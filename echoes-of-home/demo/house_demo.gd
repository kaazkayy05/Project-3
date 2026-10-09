extends Node3D
## Fixed authored blockout, no procedural generation or room shifting.
@export var require_chain: bool = false
const S = HouseEnvironmentSystem.Surface
const MONSTER_SCENE := preload("res://systems/monster_ai/monster.tscn")
const BREATH_SYSTEM_SCRIPT := preload("res://systems/sanity_breath/sanity_breath_system.gd")
var acoustic: AcousticPulseSystem
var environment_system: HouseEnvironmentSystem
var player: CharacterBody3D
var monster: MonsterAI
var breath_system: Node
var navigation_region: NavigationRegion3D
var front_navigation_link: NavigationLink3D
var bedroom_navigation_link: NavigationLink3D
var materials: Array[ShaderMaterial] = []
var key: StaticBody3D
var front_door: StaticBody3D
var bedroom_door: StaticBody3D
var pulse_afterglow: float = 0.0
var hud: Label
var game_over: bool = false

func _ready() -> void:
	acoustic = AcousticPulseSystem.new()
	acoustic.name = "AcousticPulseSystem"
	add_child(acoustic)
	environment_system = HouseEnvironmentSystem.new()
	environment_system.acoustic_system = acoustic
	environment_system.require_chain = require_chain
	environment_system.name = "EnvironmentSystem"
	add_child(environment_system)
	_build_house()
	_build_navigation()
	player = CharacterBody3D.new()
	player.set_script(preload("res://demo/demo_player.gd"))
	player.environment_system = environment_system
	player.acoustic = acoustic
	player.position = Vector3(0, 0.1, 6)
	add_child(player)
	breath_system = Node.new()
	breath_system.name = "SanityBreathSystem"
	breath_system.set_script(BREATH_SYSTEM_SCRIPT)
	add_child(breath_system)
	player.breath_system = breath_system
	breath_system.connect(&"gasp_triggered", Callable(self, "_on_gasp_triggered"))
	monster = MONSTER_SCENE.instantiate() as MonsterAI
	monster.name = "Monster"
	monster.position = Vector3(4, 3.1, 0)
	add_child(monster)
	monster.bind_acoustic_system(acoustic)
	monster.bind_breath_system(breath_system, player)
	monster.player_killed.connect(_on_player_killed)
	environment_system.objectives_changed.connect(_sync_objectives)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(24, 20)
	canvas.add_child(hud)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("0a0a0c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	world.environment.ambient_light_energy = 0.0
	world.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	add_child(world)


func _build_navigation() -> void:
	# The authored house is created at runtime, so its navigation data must be
	# baked after _build_house(). Static collider parsing also works headlessly.
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "HouseNavigationRegion"
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_collision_mask = 1
	navigation_mesh.agent_radius = 0.3
	navigation_mesh.agent_height = 1.7
	navigation_mesh.agent_max_climb = 0.25
	navigation_mesh.agent_max_slope = 40.0
	# A 0.25 m grid rounds the 0.3 m monster radius up to 0.5 m, which closes
	# the one-meter passage around the bottom of the stair rail. These horizontal
	# and vertical resolutions represent radius, height, and climb exactly.
	navigation_mesh.cell_size = 0.1
	navigation_mesh.cell_height = 0.05
	var navigation_map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(navigation_map, navigation_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(navigation_map, navigation_mesh.cell_height)
	# The runtime-built house nodes are siblings of the region, not its children.
	# Parse this demo root explicitly so both floors, the stair ramp, walls, and
	# closed doors all participate in one connected bake.
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	navigation_region.navigation_mesh = navigation_mesh
	add_child(navigation_region)
	NavigationServer3D.parse_source_geometry_data(navigation_mesh, source_geometry, self)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source_geometry)
	# NavigationServer applies region changes on a physics synchronization pass.
	# Upload the completed resource on the next pass, after the new region has
	# joined the World3D map.
	get_tree().physics_frame.connect(
		Callable(self, "_activate_baked_navigation").bind(navigation_mesh),
		CONNECT_ONE_SHOT)

	# Closed doors are included in the bake. Links bridge the resulting gaps only
	# while the corresponding physical door is open.
	front_navigation_link = _make_navigation_link(
		"FrontDoorNavigationLink", Vector3(0, 0.1, 7.6), Vector3(0, 0.1, 8.4))
	bedroom_navigation_link = _make_navigation_link(
		"BedroomDoorNavigationLink", Vector3(-1, 3.1, -1.6), Vector3(-1, 3.1, -2.4))


func _activate_baked_navigation(baked_mesh: NavigationMesh) -> void:
	# Give the just-added region one full physics pass to register its RID before
	# replacing the placeholder mesh with the completed bake.
	await get_tree().physics_frame
	if not is_instance_valid(navigation_region):
		return
	# Reassign after the server finishes mutating the resource so the region
	# uploads the completed polygons instead of the initially empty mesh.
	navigation_region.navigation_mesh = null
	navigation_region.navigation_mesh = baked_mesh


func _make_navigation_link(
		label: String, start: Vector3, finish: Vector3,
		starts_enabled: bool = false) -> NavigationLink3D:
	var link := NavigationLink3D.new()
	link.name = label
	link.start_position = start
	link.end_position = finish
	link.bidirectional = true
	link.enabled = starts_enabled
	add_child(link)
	return link

func box(label: String, pos: Vector3, size: Vector3, surface: int = -1, action: StringName = &"") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	if surface >= 0:
		body.set_meta("surface_type", surface)
	if action != &"":
		body.set_meta("interaction", action)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	# Physics-only runners do not need meshes in the dummy renderer.
	if DisplayServer.get_name() == "headless":
		add_child(body)
		return body
	var mesh := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = size
	mesh.mesh = geometry
	var material := ShaderMaterial.new()
	material.shader = preload("res://systems/environment/echo_surface.gdshader")
	if surface == S.CARPET:
		material.set_shader_parameter("echo_color", Color("3d4852"))
	elif surface >= S.HARDWOOD or action == &"brass_key":
		material.set_shader_parameter("echo_color", Color("c98a2c"))
	mesh.material_override = material
	materials.append(material)
	body.add_child(mesh)
	add_child(body)
	return body

func _build_house() -> void:
	box("GroundFloor", Vector3(0, -0.15, 0), Vector3(16, 0.3, 16), S.HARDWOOD)
	box("KitchenTile", Vector3(4, 0.015, -4), Vector3(7.8, 0.03, 7.8), S.TILE)
	box("LivingRoomRug", Vector3(-4, 0.025, 2), Vector3(5, 0.05, 5), S.CARPET)
	box("FoyerRunner", Vector3(0, 0.025, 4), Vector3(1.6, 0.05, 6), S.CARPET)
	box("KitchenClutter", Vector3(3, 0.04, -2), Vector3(2, 0.08, 1.2), S.CLUTTER)
	box("WestWall", Vector3(-8, 3, 0), Vector3(0.2, 6, 16))
	box("EastWall", Vector3(8, 3, 0), Vector3(0.2, 6, 16))
	box("NorthWall", Vector3(0, 3, -8), Vector3(16, 6, 0.2))
	box("FrontLeft", Vector3(-4.5, 1.5, 8), Vector3(7, 3, 0.2))
	box("FrontRight", Vector3(4.5, 1.5, 8), Vector3(7, 3, 0.2))
	box("FrontLintel", Vector3(0, 2.7, 8), Vector3(2, 0.6, 0.2))
	front_door = box("FrontDoor", Vector3(0, 1.2, 8), Vector3(2, 2.4, 0.16), -1, &"exit")
	box("Deadbolt", Vector3(-1.2, 1.2, 7.8), Vector3(0.2, 0.3, 0.18), -1, &"deadbolt")
	if require_chain:
		box("Chain", Vector3(1.2, 1.5, 7.8), Vector3(0.2, 0.3, 0.18), -1, &"chain")
	box("Porch", Vector3(0, -0.15, 9.5), Vector3(3, 0.3, 3), S.HARDWOOD)
	box("KitchenDividerLeft", Vector3(-5, 1.5, -0.5), Vector3(6, 3, 0.2))
	box("KitchenDividerRight", Vector3(5, 1.5, -0.5), Vector3(6, 3, 0.2))
	box("Sofa", Vector3(-6, 0.5, 3), Vector3(1.3, 1, 3))
	box("Sideboard", Vector3(-6, 0.45, -3), Vector3(1.2, 0.9, 2))
	key = box("HiddenBrassKey", Vector3(-6, 0.98, -3), Vector3(0.3, 0.12, 0.12), -1, &"brass_key")
	box("KitchenCounter", Vector3(6, 0.5, -6), Vector3(3, 1, 1))
	# Upper floor ends at z=2; ramp rises from z=7 to z=2 in the open stairwell.
	box("UpperFloor", Vector3(0, 2.85, -3), Vector3(16, 0.3, 10), S.HARDWOOD)
	var ramp := box("StairRamp", Vector3(6, 1.4, 4.5), Vector3(2, 0.2, 5.83), S.HARDWOOD)
	ramp.rotation.x = atan(3.0 / 5.0)
	box("StairRail", Vector3(4.9, 2, 4.5), Vector3(0.1, 4, 5))
	box("HallRunner", Vector3(0, 3.025, 0), Vector3(13, 0.05, 1.5), S.CARPET)
	box("CreakyBoard", Vector3(-2, 3.04, -1.5), Vector3(1.5, 0.08, 1), S.CLUTTER)
	box("BedroomPartitionLeft", Vector3(-5, 4.5, -2), Vector3(6, 3, 0.15))
	box("BedroomPartitionRight", Vector3(4, 4.5, -2), Vector3(8, 3, 0.15))
	bedroom_door = box("BedroomDoor", Vector3(-1, 4.2, -2), Vector3(2, 2.4, 0.15), -1, &"bedroom_door")
	box("BedroomDoorHandle", Vector3(0.2, 4.2, -1.8), Vector3(0.2, 0.3, 0.2), -1, &"bedroom_door")
	box("BedroomRug", Vector3(-4, 3.025, -5), Vector3(5, 0.05, 4), S.CARPET)
	box("Bed", Vector3(-5, 3.4, -6), Vector3(2, 0.8, 3))
	box("Roof", Vector3(0, 6.1, 0), Vector3(16, 0.2, 16))
	box("UpperFrontWall", Vector3(0, 4.5, 8), Vector3(16, 3, 0.2))
	box("LandingRail", Vector3(-2, 3.5, 2), Vector3(12, 1, 0.1))
	var exit_zone := Area3D.new()
	exit_zone.position = Vector3(0, 1, 9)
	var exit_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 2, 1)
	exit_shape.shape = shape
	exit_zone.add_child(exit_shape)
	add_child(exit_zone)
	exit_zone.body_entered.connect(func(body: Node3D):
		if body == player:
			environment_system.try_escape())

func _sync_objectives(_progress: Dictionary) -> void:
	key.visible = not environment_system.objective_progress.key_found
	key.get_child(0).set_deferred("disabled", environment_system.objective_progress.key_found)
	front_door.visible = not environment_system.room_layout_state.front_door.open
	front_door.get_child(0).set_deferred("disabled", environment_system.room_layout_state.front_door.open)
	bedroom_door.visible = not environment_system.room_layout_state.bedroom_door.open
	bedroom_door.get_child(0).set_deferred("disabled", environment_system.room_layout_state.bedroom_door.open)
	front_navigation_link.enabled = environment_system.room_layout_state.front_door.open
	bedroom_navigation_link.enabled = environment_system.room_layout_state.bedroom_door.open


func _on_gasp_triggered() -> void:
	if not game_over:
		acoustic.trigger_involuntary_gasp(player.global_position)


func _on_player_killed(_noise_origin: Vector3, _intensity: float) -> void:
	if game_over:
		return
	game_over = true
	player.set_controls_enabled(false)
	breath_system.call("release_breath")
	breath_system.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if game_over and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			get_tree().reload_current_scene()

func _process(delta: float) -> void:
	pulse_afterglow = 0.6 if acoustic.is_pulse_active else maxf(0.0, pulse_afterglow - delta)
	for material in materials:
		material.set_shader_parameter("pulse_origin", acoustic.pulse_origin)
		material.set_shader_parameter("pulse_radius", acoustic.pulse_radius)
		material.set_shader_parameter("pulse_active", pulse_afterglow > 0.0)
		material.set_shader_parameter("fade", pulse_afterglow / 0.6)
	hud.text = "ECHOES OF HOME\nWASD move | Mouse look | Space echo | E interact | Shift sprint | Left Ctrl hold breath | Esc cursor\nPulses: %d / 5\n%s" % [acoustic.pulse_charges, player.message]
	hud.text += "\n" + player.interaction_hint
	if is_instance_valid(breath_system):
		hud.text += "\nBreath: %.0f%% | Panic: %.0f%% | Heart: %d BPM" % [
			float(breath_system.get("lung_capacity")),
			float(breath_system.get("panic_level")) * 100.0,
			int(breath_system.get("heart_rate_bpm"))]
	if environment_system.freeze_resonance:
		hud.text += "\nF6: resonance freeze ON (1.0)"
	if game_over:
		hud.text = "THE LISTENER HEARD YOU\nPress R to restart."
	elif environment_system.has_escaped:
		hud.text = "You escaped the house."
