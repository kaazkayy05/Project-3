extends SceneTree

const MonsterAIScript = preload("res://systems/monster_ai/monster_ai.gd")
const BreathSystemScript = preload("res://systems/sanity_breath/sanity_breath_system.gd")

var checks: int = 0
var failures: int = 0
var world: Node3D
var acoustic: AcousticPulseSystem
var monster: MonsterAI
var published_monster_position: Vector3 = Vector3.INF
var published_monster_state: MonsterAI.State = MonsterAI.State.DORMANT
var seam4_publish_count: int = 0
var player_kill_count: int = 0
var forced_gasp_kill_count: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func emit_noise(origin: Vector3, intensity: float, radius: float) -> void:
	acoustic.noise_emitted.emit(origin, intensity, radius)


func on_seam4_status_published(position: Vector3, state: MonsterAI.State) -> void:
	published_monster_position = position
	published_monster_state = state
	seam4_publish_count += 1


func on_player_killed(_noise_origin: Vector3, _intensity: float) -> void:
	player_kill_count += 1


func on_forced_gasp_player_killed(_noise_origin: Vector3, _intensity: float) -> void:
	forced_gasp_kill_count += 1


func create_navigation_test_region() -> NavigationRegion3D:
	# Four connected convex polygons form a floor with a rectangular hole in the
	# middle. A left-to-right route must travel above or below that blocked area.
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.vertices = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(6, 0, 0), Vector3(10, 0, 0),
		Vector3(0, 0, 3), Vector3(4, 0, 3), Vector3(6, 0, 3), Vector3(10, 0, 3),
		Vector3(0, 0, 7), Vector3(4, 0, 7), Vector3(6, 0, 7), Vector3(10, 0, 7),
		Vector3(0, 0, 10), Vector3(4, 0, 10), Vector3(6, 0, 10), Vector3(10, 0, 10),
	])
	# Split the side strips at every adjoining edge. Navigation polygons only
	# connect across identical full edges; a T-junction would form separate maps.
	navigation_mesh.add_polygon(PackedInt32Array([0, 4, 5, 1]))
	navigation_mesh.add_polygon(PackedInt32Array([4, 8, 9, 5]))
	navigation_mesh.add_polygon(PackedInt32Array([8, 12, 13, 9]))
	navigation_mesh.add_polygon(PackedInt32Array([2, 6, 7, 3]))
	navigation_mesh.add_polygon(PackedInt32Array([6, 10, 11, 7]))
	navigation_mesh.add_polygon(PackedInt32Array([10, 14, 15, 11]))
	navigation_mesh.add_polygon(PackedInt32Array([1, 5, 6, 2]))
	navigation_mesh.add_polygon(PackedInt32Array([9, 13, 14, 10]))

	var region := NavigationRegion3D.new()
	region.navigation_mesh = navigation_mesh
	world.add_child(region)
	return region


func run() -> void:
	world = Node3D.new()
	root.add_child(world)

	var monster_scene := load("res://systems/monster_ai/monster.tscn") as PackedScene
	var scene_monster := monster_scene.instantiate() as CharacterBody3D
	check(scene_monster != null, "Monster scene root is a CharacterBody3D")
	check(scene_monster.get_node_or_null("CollisionShape3D") is CollisionShape3D, "Monster scene has a collision shape")
	check(scene_monster.get_node_or_null("NavigationAgent3D") is NavigationAgent3D, "Monster scene has a NavigationAgent3D")
	var scene_shape := scene_monster.get_node("CollisionShape3D") as CollisionShape3D
	check(scene_shape.shape is CapsuleShape3D, "Monster collision uses a capsule")
	var scene_visual := scene_monster.get_node_or_null("EchoVisual") as Node3D
	check(scene_visual != null, "Monster scene has an acoustic echo visual")
	check(scene_visual.get_child_count() == 6, "Monster echo visual is a recognizable six-part humanoid")
	var visual_parts_have_meshes := true
	for part in scene_visual.get_children():
		visual_parts_have_meshes = visual_parts_have_meshes and part is MeshInstance3D
	check(visual_parts_have_meshes, "Every humanoid visual part is renderable geometry")
	check(not scene_visual.visible, "Monster echo visual starts hidden in darkness")
	scene_monster.queue_free()

	acoustic = AcousticPulseSystem.new()
	acoustic.set_process(false)
	world.add_child(acoustic)

	var visual_monster := monster_scene.instantiate() as MonsterAI
	visual_monster.use_house_patrol_route = false
	visual_monster.set_process(false)
	visual_monster.set_physics_process(false)
	world.add_child(visual_monster)
	visual_monster.global_position = Vector3(5, 0, 0)
	visual_monster.bind_acoustic_system(acoustic)
	var echo_visual := visual_monster.get_node("EchoVisual") as MonsterEchoVisual
	echo_visual.reveal_sample_offset = Vector3.ZERO
	acoustic.pulse_origin = Vector3.ZERO
	acoustic.is_pulse_active = true
	acoustic.pulse_radius = 4.99
	echo_visual.update_reveal()
	check(not echo_visual.visible, "Monster stays hidden before the echo reaches it")
	acoustic.pulse_radius = 5.0
	echo_visual.update_reveal()
	check(echo_visual.visible, "Monster appears when the echo reaches it")
	acoustic.pulse_radius = 5.0 + echo_visual.reveal_trail_distance + 0.01
	echo_visual.update_reveal()
	check(not echo_visual.visible, "Monster hides after the echo trail passes")
	acoustic.is_pulse_active = false
	acoustic.pulse_radius = 5.0
	echo_visual.update_reveal()
	check(not echo_visual.visible, "Monster stays hidden when no pulse is active")
	visual_monster.queue_free()

	monster = MonsterAIScript.new()
	var navigation_agent := NavigationAgent3D.new()
	navigation_agent.name = "NavigationAgent3D"
	monster.add_child(navigation_agent)
	monster.acoustic_system = acoustic
	monster.gravity_acceleration = 0.0
	monster.set_process(false)
	monster.set_physics_process(false)
	world.add_child(monster)
	monster.global_position = Vector3.ZERO

	check(monster.monster_state == MonsterAI.State.DORMANT, "Monster starts dormant")
	check(MonsterAI.State.size() == 4, "Monster exposes all four required states")

	emit_noise(Vector3(1, 0, 0), 0.2, 10.0)
	check(monster.monster_state == MonsterAI.State.DORMANT, "Noise below hearing threshold is ignored")

	emit_noise(Vector3(5, 0, 0), 1.0, 4.0)
	check(monster.monster_state == MonsterAI.State.DORMANT, "Noise outside its radius is ignored")

	var first_origin := Vector3(3, 0, -2)
	emit_noise(first_origin, 0.6, 8.0)
	check(monster.monster_state == MonsterAI.State.INVESTIGATING, "Audible noise begins investigation")
	check(monster.investigation_target == first_origin, "Investigation target is the exact noise origin")
	var moderate_aggro := monster.aggro_level
	var moderate_speed := monster.current_speed

	# Time does not count down until navigation has brought the monster to the
	# fixed event origin.
	monster._process(3.0)
	check(monster.monster_state == MonsterAI.State.INVESTIGATING, "Investigation wait does not start before arrival")
	monster.global_position = first_origin
	monster._process(2.49)
	check(monster.monster_state == MonsterAI.State.INVESTIGATING, "Monster waits at the origin for 2.5 seconds")
	monster._process(0.02)
	check(monster.monster_state == MonsterAI.State.DORMANT, "Monster returns to its default state after waiting")

	monster.global_position = Vector3.ZERO
	var strong_origin := Vector3(2, 0, 0)
	emit_noise(strong_origin, 1.4, 8.0)
	check(monster.monster_state == MonsterAI.State.HUNTING, "Strong audible noise enters hunting state")
	check(monster.aggro_level > moderate_aggro, "Stronger sound increases aggression")
	check(monster.current_speed > moderate_speed, "Stronger sound increases current speed")
	check(monster.investigation_target == strong_origin, "Hunting remains anchored to the sound origin")

	monster.update_kill_proximity(Vector3(1.9, 0, 0))
	check(monster.kill_proximity_active, "Kill proximity activates within two meters")
	monster.update_kill_proximity(Vector3(2.1, 0, 0))
	check(not monster.kill_proximity_active, "Kill proximity clears outside two meters")

	# Direct movement is an explicit test-only fallback. Production house movement
	# stays stopped until a NavigationRegion3D is added to the level.
	monster.reset_to_default()
	monster.allow_direct_movement_without_navigation = true
	monster.global_position = Vector3.ZERO
	emit_noise(Vector3(3, 0, 0), 0.6, 8.0)
	monster.set_physics_process(true)
	for frame in 12:
		await physics_frame
	monster.set_physics_process(false)
	check(monster.global_position.x > 0.1, "Monster moves toward a fixed investigation target")
	check(monster.investigation_target == Vector3(3, 0, 0), "Movement does not replace the fixed noise target")

	monster.clear_patrol_points()
	monster.global_position = Vector3.ZERO
	var route: Array[Vector3] = [Vector3(1, 0, 0), Vector3(2, 0, 0)]
	monster.set_patrol_points(route)
	check(monster.monster_state == MonsterAI.State.STALKING, "Patrol route enters stalking state")
	check(is_equal_approx(monster.current_speed, monster.stalking_speed), "Stalking uses patrol speed")
	monster.set_physics_process(true)
	for frame in 12:
		await physics_frame
	monster.set_physics_process(false)
	check(monster.global_position.x > 0.1, "Stalking moves toward the current patrol point")

	monster.global_position = route[0]
	monster._physics_process(monster.patrol_wait_duration + 0.01)
	check(monster._get_behavior_target() == route[1], "Patrol advances after waiting at a point")

	monster.clear_patrol_points()
	monster.allow_direct_movement_without_navigation = false
	monster.global_position = Vector3(2, 0, 5)
	var navigation_region := create_navigation_test_region()
	await physics_frame
	await physics_frame
	check(monster._has_navigation_region(), "Monster detects an available NavigationRegion3D")

	var routed_target := Vector3(8, 0, 5)
	emit_noise(routed_target, 1.4, 20.0)
	monster.set_physics_process(true)
	for frame in 20:
		await physics_frame
	monster.set_physics_process(false)
	var routed_path := monster.navigation_agent.get_current_navigation_path()
	check(routed_path.size() >= 3, "NavigationAgent3D builds a multi-point path around blocked space")
	check(absf(monster.global_position.z - 5.0) > 0.05, "Monster follows the routed path instead of moving straight through the hole")
	check(monster.global_position.distance_to(Vector3(2, 0, 5)) > 0.1, "Navigation movement advances along the generated path")
	navigation_region.queue_free()

	# Seam 4 uses Kayla's real script unchanged. Its automatic processing is
	# disabled so each near/far assertion advances it by an exact test interval.
	var breath_system := Node.new()
	breath_system.set_script(BreathSystemScript)
	breath_system.set_process(false)
	world.add_child(breath_system)
	var player := Node3D.new()
	world.add_child(player)
	player.global_position = Vector3.ZERO
	monster.seam4_status_published.connect(on_seam4_status_published)
	check(monster.bind_breath_system(breath_system, player), "Seam 4 binds to the existing breath distance API")

	monster.clear_patrol_points()
	monster.global_position = Vector3(10, 0, 0)
	monster.publish_seam4_status()
	check(published_monster_position == Vector3(10, 0, 0), "Seam 4 publishes monster world position")
	check(published_monster_state == MonsterAI.State.DORMANT, "Seam 4 publishes the current monster state")
	check(monster.get_monster_world_position() == published_monster_position, "Read-only position interface matches the signal")
	check(monster.get_monster_state() == published_monster_state, "Read-only state interface matches the signal")
	check(is_equal_approx(breath_system.monster_distance, 10.0), "Far monster distance reaches the breath system")

	var publications_before_state_change := seam4_publish_count
	emit_noise(Vector3(11, 0, 0), 0.6, 4.0)
	check(seam4_publish_count > publications_before_state_change, "Monster state changes publish a Seam 4 snapshot")
	check(published_monster_state == MonsterAI.State.INVESTIGATING, "Published state reflects investigation")

	breath_system.lung_capacity = 100.0
	breath_system.release_breath()
	breath_system.hold_breath()
	monster.global_position = Vector3(10, 0, 0)
	monster.publish_seam4_status()
	breath_system.update_breath(1.0)
	check(is_equal_approx(breath_system.lung_capacity, 85.0), "Far distance preserves baseline breath drain")

	breath_system.lung_capacity = 100.0
	breath_system.release_breath()
	breath_system.hold_breath()
	monster.global_position = Vector3(2, 0, 0)
	monster.publish_seam4_status()
	breath_system.update_breath(1.0)
	check(is_equal_approx(breath_system.lung_capacity, 70.0), "Near distance preserves doubled breath drain")
	breath_system.panic_level = 0.0
	breath_system.update_panic(1.0)
	check(is_equal_approx(breath_system.panic_level, 0.4), "Monster within four meters raises panic")

	monster.global_position = Vector3(10, 0, 0)
	monster.publish_seam4_status()
	breath_system.panic_level = 0.5
	breath_system.update_panic(1.0)
	check(is_equal_approx(breath_system.panic_level, 0.3), "Monster beyond four meters lowers panic")

	# Seam 4 freeze test: keep the published monster position far away while time
	# advances. Breath must remain at the relaxed single-drain rate.
	monster.global_position = Vector3(100, 0, 0)
	breath_system.lung_capacity = 100.0
	breath_system.release_breath()
	breath_system.hold_breath()
	for second in 3:
		monster.publish_seam4_status()
		breath_system.update_breath(1.0)
	check(monster.global_position == Vector3(100, 0, 0), "Freeze test keeps monster position far away")
	check(is_equal_approx(breath_system.monster_distance, 100.0), "Freeze test keeps far distance in the breath system")
	check(is_equal_approx(breath_system.lung_capacity, 55.0), "Frozen-far position keeps relaxed breath drain for three seconds")

	# GDD kill rule: proximity/overlap only arms the monster. A player-originated
	# acoustic event must occur while the current distance is strictly under 2 m.
	monster.player_killed.connect(on_player_killed)
	monster.global_position = Vector3(1.5, 0, 0)
	monster.publish_seam4_status()
	check(monster.kill_proximity_active, "Silent close proximity arms the kill rule")
	check(player_kill_count == 0, "Silent close proximity does not kill")

	monster.global_position = player.global_position
	monster.publish_seam4_status()
	check(player_kill_count == 0, "Physical overlap alone does not kill")

	monster.global_position = Vector3(3, 0, 0)
	emit_noise(player.global_position, 1.0, 12.0)
	check(player_kill_count == 0, "Player noise outside two meters does not kill")

	monster.global_position = Vector3(2, 0, 0)
	emit_noise(player.global_position, 1.0, 12.0)
	check(player_kill_count == 0, "Exact two-meter boundary does not kill")

	monster.global_position = Vector3(1.5, 0, 0)
	emit_noise(Vector3(8, 0, 0), 1.0, 12.0)
	check(player_kill_count == 0, "Non-player noise does not kill at close range")

	monster.global_position = Vector3(1.5, 0, 0)
	var target_before_kill := monster.investigation_target
	emit_noise(player.global_position, 1.0, 12.0)
	check(player_kill_count == 1, "Close-range player noise triggers one kill")
	check(monster.has_killed_player(), "Monster records its terminal kill state")
	check(is_zero_approx(monster.current_speed) and monster.velocity == Vector3.ZERO, "Kill immediately stops monster movement")

	emit_noise(player.global_position, 1.4, 12.0)
	check(player_kill_count == 1, "Kill signal fires only once")
	check(monster.investigation_target == target_before_kill, "Monster ignores noise after death")
	var stopped_position := monster.global_position
	monster.velocity = Vector3(5, 0, 0)
	monster._physics_process(0.5)
	check(monster.global_position == stopped_position and monster.velocity == Vector3.ZERO, "Monster remains stopped after death")

	# Forced gasp uses the real unchanged breath and acoustic systems. It must
	# travel through gasp_triggered -> trigger_involuntary_gasp -> noise_emitted.
	var gasp_acoustic := AcousticPulseSystem.new()
	gasp_acoustic.set_process(false)
	world.add_child(gasp_acoustic)
	var gasp_breath := Node.new()
	gasp_breath.set_script(BreathSystemScript)
	gasp_breath.set_process(false)
	world.add_child(gasp_breath)
	var gasp_player := Node3D.new()
	world.add_child(gasp_player)
	gasp_player.global_position = Vector3(20, 0, 0)
	var gasp_monster := MonsterAIScript.new()
	var gasp_navigation_agent := NavigationAgent3D.new()
	gasp_navigation_agent.name = "NavigationAgent3D"
	gasp_monster.add_child(gasp_navigation_agent)
	gasp_monster.acoustic_system = gasp_acoustic
	gasp_monster.gravity_acceleration = 0.0
	gasp_monster.set_process(false)
	gasp_monster.set_physics_process(false)
	world.add_child(gasp_monster)
	gasp_monster.global_position = Vector3(21.5, 0, 0)
	check(gasp_monster.bind_breath_system(gasp_breath, gasp_player), "Forced-gasp monster binds Seam 4")
	gasp_monster.player_killed.connect(on_forced_gasp_player_killed)
	gasp_breath.gasp_triggered.connect(func():
		gasp_acoustic.trigger_involuntary_gasp(gasp_player.global_position))
	gasp_breath.lung_capacity = 1.0
	gasp_breath.hold_breath()
	gasp_breath.update_breath(1.0)
	check(forced_gasp_kill_count == 1, "Forced gasp kills when the monster is under two meters away")

	world.queue_free()
	await process_frame
	print("MONSTER AI RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
