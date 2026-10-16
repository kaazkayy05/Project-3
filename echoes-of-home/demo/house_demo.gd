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
var deadbolt: StaticBody3D
var bolt_thumb: StaticBody3D
var front_door: StaticBody3D
var bedroom_door: StaticBody3D
var pulse_afterglow: float = 0.0
var interaction_label: Label
var objective_label: Label
var pulse_label: Label
var controls_label: Label
var breath_label: Label
var breath_bar: ProgressBar
var status_label: Label
var game_over: bool = false
var death_overlay: CanvasLayer
var feedback_sound: AudioStreamPlayer
var previous_key_found := false
var previous_bolt_unlocked := false
var death_sound: AudioStreamPlayer
var breath_vignette: ColorRect
var breath_vignette_material: ShaderMaterial
var breath_vignette_latched: bool = false

func _ready() -> void:
	acoustic = AcousticPulseSystem.new()
	acoustic.name = "AcousticPulseSystem"
	add_child(acoustic)
	environment_system = HouseEnvironmentSystem.new()
	environment_system.acoustic_system = acoustic
	environment_system.require_chain = require_chain
	environment_system.name = "EnvironmentSystem"
	add_child(environment_system)
	_build_feedback_sound()
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
	player.sanity_breath = breath_system
	breath_system.connect(
		&"gasp_triggered", Callable(player, "on_player_gasp")
	)
	breath_system.connect(&"gasp_triggered", Callable(self, "_on_gasp_triggered"))
	monster = MONSTER_SCENE.instantiate() as MonsterAI
	monster.name = "Monster"
	monster.position = Vector3(4, 3.1, 0)
	add_child(monster)
	monster.bind_acoustic_system(acoustic)
	breath_system.bind_seam4_player(player)
	monster.seam4_status_published.connect(
		Callable(breath_system, "receive_monster_status")
	)
	monster.bind_breath_system(breath_system, player)
	monster.player_killed.connect(_on_player_killed)
	environment_system.objectives_changed.connect(_sync_objectives)
	_build_breath_vignette()
	_build_hud()
	_build_death_notification()
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("0a0a0c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	world.environment.ambient_light_energy = 0.0
	world.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	add_child(world)
	if not MusicManager.music.playing:
		MusicManager.music.play(0.0)


func _build_breath_vignette() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "BreathVignette"
	canvas.layer = 0 # Above the world, below the HUD (1), death (10), and pause (100).
	add_child(canvas)
	breath_vignette_material = ShaderMaterial.new()
	breath_vignette_material.shader = preload("res://demo/shaders/breath_vignette.gdshader")
	breath_vignette = ColorRect.new()
	breath_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	breath_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	breath_vignette.material = breath_vignette_material
	canvas.add_child(breath_vignette)


func _update_breath_vignette() -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		breath_vignette_latched = false
	elif is_instance_valid(breath_system):
		if float(breath_system.get("lung_capacity")) == 0.0:
			breath_vignette_latched = true
	breath_vignette.visible = (
		breath_vignette_latched and not game_over and not environment_system.has_escaped
	)
	breath_vignette_material.set_shader_parameter("lungs_empty", breath_vignette_latched)


func _build_death_notification() -> void:
	death_sound = AudioStreamPlayer.new()
	var stream := preload("res://demo/audio/fail-sound.wav").duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	death_sound.stream = stream
	death_sound.volume_db = -10.0
	death_sound.max_polyphony = 1
	add_child(death_sound)

	death_overlay = CanvasLayer.new()
	death_overlay.layer = 10
	add_child(death_overlay)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(center)

	var message := VBoxContainer.new()
	message.add_theme_constant_override("separation", 16)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(message)

	var lines := [
		["YOU DIED", 56],
		["The Listener heard you.", 26],
		["Press R to Restart.", 22],
	]
	for entry in lines:
		var label := Label.new()
		label.text = entry[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", entry[1])
		label.add_theme_color_override("font_color", Color("#b97979"))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		message.add_child(label)

	death_overlay.hide()


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	objective_label = _make_hud_label(
		root, Vector2(0, 0), Rect2(20, 20, 280, 180)
	)
	interaction_label = _make_hud_label(
		root, Vector2(0.5, 1), Rect2(-350, -140, 700, 60),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	pulse_label = _make_hud_label(
		root, Vector2(1, 0), Rect2(-200, 20, 180, 50),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	controls_label = _make_hud_label(
		root, Vector2(0.5, 0), Rect2(-320, 20, 640, 70),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	controls_label.add_theme_font_size_override("font_size", 14)
	controls_label.text = (
		"WASD — Move | Mouse — Look | Space — Echo | E — Interact\n"
		+ "Shift — Sprint | Right Click — Hold Breath | Esc — Pause/Resume"
	)

	breath_label = _make_hud_label(
		root, Vector2(0, 1), Rect2(20, -84, 240, 28)
	)

	breath_bar = ProgressBar.new()
	breath_bar.anchor_top = 1.0
	breath_bar.anchor_bottom = 1.0
	breath_bar.offset_left = 20
	breath_bar.offset_right = 260
	breath_bar.offset_top = -48
	breath_bar.offset_bottom = -28
	breath_bar.min_value = 0
	breath_bar.max_value = 100
	breath_bar.show_percentage = false
	breath_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var track := StyleBoxFlat.new()
	track.bg_color = Color("#17171c")
	breath_bar.add_theme_stylebox_override("background", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#8c7777")
	breath_bar.add_theme_stylebox_override("fill", fill)
	root.add_child(breath_bar)

	status_label = _make_hud_label(
		root, Vector2(1, 1), Rect2(-260, -84, 240, 56),
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _make_hud_label(
		parent: Control, anchor: Vector2, bounds: Rect2,
		alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.anchor_left = anchor.x
	label.anchor_right = anchor.x
	label.anchor_top = anchor.y
	label.anchor_bottom = anchor.y
	label.offset_left = bounds.position.x
	label.offset_top = bounds.position.y
	label.offset_right = bounds.end.x
	label.offset_bottom = bounds.end.y
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("#d8d3cc"))
	label.add_theme_color_override("font_shadow_color", Color("#09090d"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label


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
		body.add_to_group("house_interactables")
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
	if action == &"deadbolt" or action == &"brass_key":
		material.set_shader_parameter("echo_color", Color("e9ba63"))
		material.set_shader_parameter("ambient_floor", 0.012)
		material.set_shader_parameter("surface_fill_boost", 0.65)
	elif surface == S.CARPET:
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
	box("FamilyRoomFloor", Vector3(-10, -0.15, 2), Vector3(4, 0.3, 12), S.HARDWOOD)
	box("FamilyRoomWest", Vector3(-12, 1.5, 2), Vector3(0.2, 3, 12))
	box("FamilyRoomNorth", Vector3(-10, 1.5, -4), Vector3(4, 3, 0.2))
	box("FamilyRoomSouth", Vector3(-10, 1.5, 8), Vector3(4, 3, 0.2))
	box("FamilyRoomCeiling", Vector3(-10, 3.1, 2), Vector3(4, 0.2, 12))
	box("WestUpperWall", Vector3(-8, 4.5, 0), Vector3(0.2, 3, 16))
	box("WestBackWall", Vector3(-8, 1.5, -6), Vector3(0.2, 3, 4))
	box("WestPierNorth", Vector3(-8, 1.5, -0.5), Vector3(0.2, 3, 3))
	box("WestPierSouth", Vector3(-8, 1.5, 7), Vector3(0.2, 3, 2))
	box("EastWall", Vector3(8, 3, 0), Vector3(0.2, 6, 16))
	box("NorthWall", Vector3(0, 3, -8), Vector3(16, 6, 0.2))
	box("FrontLeft", Vector3(-4.5, 1.5, 8), Vector3(7, 3, 0.2))
	box("FrontRight", Vector3(4.5, 1.5, 8), Vector3(7, 3, 0.2))
	box("FrontLintel", Vector3(0, 2.7, 8), Vector3(2, 0.6, 0.2))
	front_door = box("FrontDoor", Vector3(0, 1.2, 8), Vector3(2, 2.4, 0.16), -1, &"exit")
	deadbolt = box("Deadbolt", Vector3(-0.66, 1.35, 7.78), Vector3(0.32, 0.44, 0.16), -1, &"deadbolt")
	if DisplayServer.get_name() != "headless":
		var plate := CylinderMesh.new()
		plate.top_radius = 0.2
		plate.bottom_radius = 0.2
		plate.height = 0.14
		plate.radial_segments = 16
		var plate_mesh := deadbolt.get_child(1) as MeshInstance3D
		plate_mesh.mesh = plate
		plate_mesh.rotation.x = PI / 2.0
	bolt_thumb = box("DeadboltThumbTurn", Vector3(-0.66, 1.35, 7.65), Vector3(0.10, 0.28, 0.12), -1, &"deadbolt")
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
	_furnish_home()
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
	if (environment_system.objective_progress.key_found and not previous_key_found
			or environment_system.objective_progress.bolt_unlocked and not previous_bolt_unlocked):
		feedback_sound.play()
	previous_key_found = environment_system.objective_progress.key_found
	previous_bolt_unlocked = environment_system.objective_progress.bolt_unlocked
	deadbolt.visible = not environment_system.room_layout_state.front_door.open
	bolt_thumb.visible = deadbolt.visible
	deadbolt.get_child(0).set_deferred("disabled", not deadbolt.visible)
	bolt_thumb.get_child(0).set_deferred("disabled", not bolt_thumb.visible)
	bolt_thumb.rotation.z = PI / 2.0 if environment_system.objective_progress.bolt_unlocked else 0.0
	key.visible = not environment_system.objective_progress.key_found
	key.get_child(0).set_deferred("disabled", environment_system.objective_progress.key_found)
	front_door.visible = not environment_system.room_layout_state.front_door.open
	front_door.get_child(0).set_deferred("disabled", environment_system.room_layout_state.front_door.open)
	bedroom_door.visible = not environment_system.room_layout_state.bedroom_door.open
	bedroom_door.get_child(0).set_deferred("disabled", environment_system.room_layout_state.bedroom_door.open)
	front_navigation_link.enabled = environment_system.room_layout_state.front_door.open
	bedroom_navigation_link.enabled = environment_system.room_layout_state.bedroom_door.open


func _on_gasp_triggered() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
			and float(breath_system.get("lung_capacity")) == 0.0:
		breath_vignette_latched = true
	if not game_over:
		acoustic.trigger_involuntary_gasp(player.global_position)


func _on_player_killed(_noise_origin: Vector3, _intensity: float) -> void:
	if game_over or environment_system.has_escaped:
		return
	game_over = true
	MusicManager.music.stop()
	player.set_controls_enabled(false)
	breath_system.call("release_breath")
	breath_system.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	death_overlay.show()
	death_sound.play()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT \
			and not event.pressed:
		breath_vignette_latched = false
		breath_vignette.hide()
		breath_vignette_material.set_shader_parameter("lungs_empty", false)


func _unhandled_input(event: InputEvent) -> void:
	if game_over and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			get_tree().reload_current_scene()

func _process(delta: float) -> void:
	_update_breath_vignette()
	pulse_afterglow = 0.6 if acoustic.is_pulse_active else maxf(0.0, pulse_afterglow - delta)
	for material in materials:
		material.set_shader_parameter("pulse_origin", acoustic.pulse_origin)
		material.set_shader_parameter("pulse_radius", acoustic.pulse_radius)
		material.set_shader_parameter("pulse_active", pulse_afterglow > 0.0)
		material.set_shader_parameter("fade", pulse_afterglow / 0.6)
	objective_label.text = "OBJECTIVE\n" + player.message
	interaction_label.text = player.interaction_hint if not game_over and not environment_system.has_escaped else ""

	pulse_label.text = "ECHO PULSES\n%d / %d" % [
		acoustic.pulse_charges, acoustic.max_pulse_charges
	]

	if is_instance_valid(breath_system):
		var capacity := float(breath_system.get("lung_capacity"))
		breath_label.text = "BREATH  %.0f%%" % capacity
		breath_bar.value = capacity
		status_label.text = "PANIC  %.0f%%\nHEART  %d BPM" % [
			float(breath_system.get("panic_level")) * 100.0,
			int(breath_system.get("heart_rate_bpm"))
		]

	if environment_system.freeze_resonance:
		objective_label.text += "\nF6: resonance freeze ON (1.0)"
	if game_over:
		objective_label.text = "THE LISTENER HEARD YOU\nPress R to restart."
	elif environment_system.has_escaped:
		objective_label.text = "You escaped the house."

# Details share the pulse shader without creating snagging collision geometry.
func detail(label: String, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var prop := box(label, pos, size)
	prop.collision_layer = 0
	if DisplayServer.get_name() != "headless":
		var material := (prop.get_child(1) as MeshInstance3D).material_override as ShaderMaterial
		material.set_shader_parameter("echo_color", color)
		material.set_shader_parameter("ambient_floor", 0.012)
	return prop

func _picture(label: String, pos: Vector3, crooked: bool = false) -> void:
	var frame := detail(label, pos, Vector3(0.7, 0.55, 0.06), Color("9d7953"))
	if crooked:
		frame.rotation.z = 0.14
	for i in 3:
		var figure := detail(label + "Figure", pos + Vector3((i - 1) * 0.18, -0.04, 0.04), Vector3(0.10, 0.24 - i * 0.04, 0.02), Color("b2a18b"))
		figure.reparent(frame, true)
		var head := detail(label + "Head", pos + Vector3((i - 1) * 0.18, 0.14 - i * 0.02, 0.04), Vector3(0.09, 0.09, 0.02), Color("b2a18b"))
		head.reparent(frame, true)

func _furnish_home() -> void:
	box("CouchBack", Vector3(-6.5, 0.85, 3), Vector3(0.25, 0.8, 3.1))
	for z in [1.65, 4.35]:
		box("CouchArm", Vector3(-6, 0.65, z), Vector3(1.4, 0.3, 0.25))
	_table("CoffeeTable", Vector3(-3.8, 0.3, 3), Vector3(1.1, 0.6, 1.8))
	box("TelevisionCabinet", Vector3(-2, 0.4, 0.5), Vector3(1.8, 0.8, 0.6))
	box("OldTelevision", Vector3(-2, 1.1, 0.5), Vector3(1.05, 0.65, 0.55))
	detail("GlassScreen", Vector3(-2, 1.1, 0.8), Vector3(0.85, 0.45, 0.03), Color("687e7b"))
	for z in [2.1, 3.0, 3.9]:
		detail("WornCushion", Vector3(-5.9, 1.01, z), Vector3(0.9, 0.05, 0.8), Color("858879"))
	box("FamilyRoomRug", Vector3(-10, 0.025, 2), Vector3(2.6, 0.05, 4), S.CARPET)
	box("ReadingBench", Vector3(-11.3, 0.45, 2), Vector3(0.7, 0.9, 2))
	box("FamilyBookshelf", Vector3(-10, 0.9, -3.5), Vector3(2, 1.8, 0.4))
	box("Refrigerator", Vector3(7.1, 1, -3.2), Vector3(1.2, 2, 1.1))
	box("CounterReturn", Vector3(7.2, 0.5, -5.6), Vector3(1.1, 1, 3.2))
	for x in [5.2, 6.5]:
		box("WallCabinet", Vector3(x, 2.1, -7.4), Vector3(1.15, 0.7, 0.6))
	_table("DiningTable", Vector3(2.8, 0.4, -4.8), Vector3(1.5, 0.8, 2.2))
	for z in [-6.3, -3.3]:
		box("DiningChair", Vector3(2.8, 0.25, z), Vector3(0.6, 0.5, 0.6))
		detail("ChairBack", Vector3(2.8, 0.8, z), Vector3(0.6, 0.6, 0.12), Color("927452"))
	for x in [2.4, 3.2]:
		detail("DinnerPlate", Vector3(x, 0.82, -4.8), Vector3(0.3, 0.025, 0.3), Color("c6bba2"))
	box("ChildDresser", Vector3(-6.8, 3.5, -3.4), Vector3(1.4, 1, 0.7))
	box("ChildBookshelf", Vector3(-2.8, 3.8, -7.4), Vector3(1.5, 1.6, 0.4))
	detail("BedPillow", Vector3(-5, 3.88, -7), Vector3(1.5, 0.15, 0.5), Color("9192ab"))
	detail("BedQuilt", Vector3(-5, 3.83, -5.6), Vector3(2.02, 0.08, 1.8), Color("7b839c"))
	for i in 5:
		detail("ToyBlock", Vector3(-3.2 + i * 0.22, 3.12, -4.5), Vector3(0.18, 0.18, 0.18), Color("ac796c"))
	box("StudyRug", Vector3(4, 3.025, -5), Vector3(4, 0.05, 3), S.CARPET)
	_table("HomeworkDesk", Vector3(6.5, 3.4, -6.8), Vector3(2, 0.8, 1))
	box("CornerFacingChair", Vector3(7.2, 3.45, -4.6), Vector3(0.6, 0.9, 0.6))
	var partition := get_node("BedroomPartitionRight") as StaticBody3D
	partition.position.x = 1.5
	(partition.get_child(0).shape as BoxShape3D).size.x = 3.0
	if DisplayServer.get_name() != "headless":
		((partition.get_child(1) as MeshInstance3D).mesh as BoxMesh).size.x = 3.0
	box("StudyDoorPier", Vector3(6.5, 4.5, -2), Vector3(3, 3, 0.15))
	box("StudyDoorLintel", Vector3(4, 5.75, -2), Vector3(2, 0.5, 0.15))
	for i in 4:
		_picture("FamilyPhoto", Vector3(-5.8 + i * 1.1, 1.9, -0.35), i == 2)
		_picture("ChildDrawing", Vector3(-5.5 + i * 1.4, 4.8, -7.85), i == 1)
	for i in 8:
		detail("OldBook", Vector3(-10.8 + i * 0.22, 1.1, -3.22), Vector3(0.15, 0.45, 0.16), Color("8f9d87"))
	for i in 15:
		var z := 6.85 - i * (5.0 / 15.0)
		var y := 1.4 + (4.5 - z) * 0.6 + 0.12
		detail("StairTread", Vector3(6, y, z), Vector3(1.95, 0.025, 0.045), Color("9c8469"))
	detail("CornerChairBack", Vector3(7.2, 4.1, -4.3), Vector3(0.6, 0.6, 0.12), Color("927452"))
	for y in [3.25, 3.55, 3.85]:
		detail("DresserDrawer", Vector3(-6.8, y, -3.02), Vector3(1.2, 0.2, 0.04), Color("917456"))
	# Original low-poly brass key silhouette, parented for atomic pickup visibility.
	for entry in [[Vector3(-0.12, 0, 0), Vector3(0.14, 0.14, 0.22)], [Vector3(0.1, 0, 0), Vector3(0.3, 0.06, 0.06)], [Vector3(0.18, 0, 0.06), Vector3(0.05, 0.06, 0.1)]]:
		var part := detail("KeyDetail", key.position + entry[0], entry[1], Color("e9ba63"))
		part.reparent(key, true)
		if DisplayServer.get_name() != "headless":
			var key_mesh := part.get_child(1) as MeshInstance3D
			(key_mesh.material_override as ShaderMaterial).set_shader_parameter("surface_fill_boost", 0.65)
			if entry[0].x < 0:
				var bow := TorusMesh.new()
				bow.inner_radius = 0.045
				bow.outer_radius = 0.11
				bow.rings = 16
				bow.ring_segments = 8
				key_mesh.mesh = bow
	if DisplayServer.get_name() != "headless":
		(key.get_child(1) as MeshInstance3D).hide()

func _build_feedback_sound() -> void:
	# Original short mechanical click. Presentation only; existing noise contracts stay intact.
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	var samples := PackedByteArray()
	for i in 2205:
		var t := float(i) / 22050.0
		var sample := sin(TAU * 730.0 * t) * exp(-t * 65.0) * 70.0
		samples.append(int(sample) & 255)
	stream.data = samples
	feedback_sound = AudioStreamPlayer.new()
	feedback_sound.stream = stream
	feedback_sound.volume_db = -16.0
	add_child(feedback_sound)

func _table(label: String, pos: Vector3, size: Vector3) -> void:
	var body := box(label, pos, size)
	if DisplayServer.get_name() != "headless":
		var mesh := body.get_child(1) as MeshInstance3D
		(mesh.mesh as BoxMesh).size.y = 0.12
		mesh.position.y = size.y / 2.0 - 0.06
	for x in [-1, 1]:
		for z in [-1, 1]:
			detail(label + "Leg", pos + Vector3(x * (size.x / 2.0 - 0.12), -0.06, z * (size.z / 2.0 - 0.12)), Vector3(0.12, size.y - 0.12, 0.12), Color("927452"))
