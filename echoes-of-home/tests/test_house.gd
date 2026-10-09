extends SceneTree
var failures: int = 0
var demo: Node3D
var player: CharacterBody3D
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1
func walk(direction: Vector3, frames: int) -> void:
	for frame in frames:
		await physics_frame
		player.velocity.x = direction.x * 2.4
		player.velocity.z = direction.z * 2.4
		player.velocity.y -= 18.0 / 60.0
		player.move_and_slide()
func place(pos: Vector3) -> void:
	player.position = pos
	player.velocity = Vector3.ZERO
	await walk(Vector3.ZERO, 15)

func path_reaches_target(path: PackedVector3Array, navigation_map: RID, target: Vector3) -> bool:
	if path.is_empty():
		return false
	var snapped_target := NavigationServer3D.map_get_closest_point(navigation_map, target)
	return path[-1].distance_to(snapped_target) < 0.05

func path_spans_heights(path: PackedVector3Array, low_height: float, high_height: float) -> bool:
	var reaches_low := false
	var reaches_high := false
	for point in path:
		reaches_low = reaches_low or point.y < low_height
		reaches_high = reaches_high or point.y > high_height
	return reaches_low and reaches_high

func run() -> void:
	demo = load("res://demo/house_demo.tscn").instantiate()
	root.add_child(demo)
	player = demo.player
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Let the runtime navigation bake and NavigationServer map synchronization
	# finish before inspecting the playable integration.
	for frame in 6:
		await physics_frame
	check(is_instance_valid(demo.navigation_region), "Playable house creates a navigation region")
	check(demo.navigation_region.navigation_mesh.get_polygon_count() > 0, "Runtime bake creates walkable navigation polygons")
	check(is_instance_valid(demo.monster), "Playable house spawns monster.tscn")
	check(demo.monster.acoustic_system == demo.acoustic, "Seam 1 binds the house acoustic system to Monster AI")
	check(player.breath_system == demo.breath_system, "Player and Monster AI share the house breath system")
	var navigation_map: RID = demo.monster.navigation_agent.get_navigation_map()
	var ground_start := Vector3(0, 0.1, 4)
	var ramp_bottom := Vector3(6, 0.4, 6.6)
	var ramp_top := Vector3(6, 2.8, 2.6)
	var upper_finish := Vector3(0, 3.1, 0)
	# Validate each baked island transition independently before the complete
	# query so a regression identifies which part of the stair route broke.
	var ground_to_ramp := NavigationServer3D.map_get_path(
		navigation_map, ground_start, ramp_bottom, true)
	var ramp_traversal := NavigationServer3D.map_get_path(
		navigation_map, ramp_bottom, ramp_top, true)
	var ramp_to_upper := NavigationServer3D.map_get_path(
		navigation_map, ramp_top, upper_finish, true)
	var stair_path := NavigationServer3D.map_get_path(
		navigation_map, ground_start, upper_finish, true)
	var ground_to_ramp_ok := path_reaches_target(ground_to_ramp, navigation_map, ramp_bottom)
	var ramp_traversal_ok := (
		path_reaches_target(ramp_traversal, navigation_map, ramp_top)
		and path_spans_heights(ramp_traversal, 1.0, 2.5))
	var ramp_to_upper_ok := path_reaches_target(ramp_to_upper, navigation_map, upper_finish)
	var complete_route_ok := (
		path_reaches_target(stair_path, navigation_map, upper_finish)
		and path_spans_heights(stair_path, 1.0, 2.5))
	if not (ground_to_ramp_ok and ramp_traversal_ok and ramp_to_upper_ok and complete_route_ok):
		print("Navigation segment status: ground/ramp=", ground_to_ramp_ok,
			" ramp=", ramp_traversal_ok, " ramp/upper=", ramp_to_upper_ok,
			" complete=", complete_route_ok)
	check(ground_to_ramp_ok and ramp_traversal_ok and ramp_to_upper_ok and complete_route_ok,
		"Navigation connects the ground floor to the upper floor through the stairs")
	var prior_noise_count: int = demo.acoustic.active_noise_events.size()
	demo.breath_system.call("trigger_gasp")
	check(demo.acoustic.active_noise_events.size() == prior_noise_count + 1,
		"Forced gasp is forwarded into the acoustic system")
	check(demo.acoustic.active_noise_events.back().position.is_equal_approx(player.global_position),
		"Forced gasp acoustic event uses the player's world position")
	demo.monster.publish_seam4_status()
	check(is_equal_approx(demo.breath_system.monster_distance,
		demo.monster.global_position.distance_to(player.global_position)),
		"Seam 4 publishes live monster-to-player distance to breath control")
	# The remaining legacy geometry checks move the player manually. Freeze the
	# monster so it cannot interfere with those deterministic collision checks.
	demo.monster.set_process(false)
	demo.monster.set_physics_process(false)
	await place(Vector3(0, 0.1, 6))
	demo.environment_system.sample_surface(player)
	check(demo.environment_system.current_surface_type == 0, "Foyer spawn rests on carpet")
	await walk(Vector3.RIGHT, 55)
	demo.environment_system.sample_surface(player)
	check(demo.environment_system.current_surface_type == 1, "Walking off runner reaches hardwood")
	await walk(Vector3.LEFT, 55)
	demo.environment_system.sample_surface(player)
	check(demo.environment_system.current_surface_type == 0, "Walking onto rug works without jump")
	await place(Vector3(6, 0.1, 7.5))
	await walk(Vector3.FORWARD, 230)
	print("Stair landing position: ", player.position)
	check(player.position.y >= 2.95 and player.position.z < 2, "Stair ramp reaches upstairs landing")
	await walk(Vector3.BACK, 230)
	print("Stair descent position: ", player.position)
	check(player.position.y < 0.3 and player.position.z > 7, "Stair ramp descends to foyer")
	await place(Vector3(-4.7, 0.1, -3))
	player.camera.look_at(demo.key.global_position)
	check(player.aimed_interaction() == &"brass_key", "Key can be targeted with existing demo interaction ray")
	await place(Vector3(-3, 0.1, -3))
	player.camera.look_at(demo.key.global_position)
	check(player.aimed_interaction() == &"", "Out-of-reach key cannot be targeted")
	await place(Vector3(0, 0.1, 6.5))
	await walk(Vector3.BACK, 70)
	check(player.position.z < 8 and not demo.environment_system.has_escaped, "Locked front door physically blocks escape")
	demo.environment_system.interact(&"brass_key")
	demo.environment_system.interact(&"deadbolt")
	demo.environment_system.interact(&"exit")
	check(demo.front_navigation_link.enabled, "Opening the front door enables its navigation link")
	await walk(Vector3.BACK, 60)
	check(demo.environment_system.has_escaped, "Open front door permits crossing exit area")
	check(not demo.key.visible and demo.key.get_child(0).disabled, "Collected key disappears and stops blocking rays")
	await place(Vector3(-1, 3.1, -0.5))
	await walk(Vector3.FORWARD, 60)
	check(player.position.z > -2, "Bedroom door physically blocks entry")
	demo.environment_system.interact(&"bedroom_door")
	check(demo.bedroom_navigation_link.enabled, "Opening the bedroom door enables its navigation link")
	await walk(Vector3.FORWARD, 65)
	check(player.position.z < -2.5, "Bedroom door opens into master bedroom")
	# Proximity remains harmless until a player-originated acoustic event occurs.
	demo.monster.global_position = player.global_position + Vector3(1.5, 0, 0)
	demo.monster.publish_seam4_status()
	check(not demo.game_over, "Close monster proximity alone does not end the game")
	demo.acoustic.noise_emitted.emit(player.global_position, 1.0, 12.0)
	check(demo.game_over, "Monster player_killed signal enters the game-over state")
	check(not player.controls_enabled and not demo.breath_system.is_processing(),
		"Game over disables player controls and breath processing")
	demo._process(0.0)
	check("Press R to restart" in demo.hud.text, "Game-over HUD presents the restart control")
	print("HOUSE RESULT: ", failures, " failures")
	demo.queue_free()
	await process_frame
	quit(1 if failures else 0)
