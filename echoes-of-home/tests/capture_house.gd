extends SceneTree
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	var demo = load("res://demo/house_demo.tscn").instantiate()
	root.add_child(demo)
	demo.player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	demo.acoustic.set_process(false)
	demo.player.camera.rotation.x = -0.25
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://environment_dark.png")
	demo.acoustic.trigger_player_pulse(demo.player.global_position)
	demo.acoustic.pulse_radius = 5.5
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://environment_pulse.png")
	demo.monster.set_physics_process(false)
	var views := [
		["living", Vector3(-0.8, 1.65, 5.8), Vector3(-5, 1.2, 2)],
		["family", Vector3(-9, 1.65, 5), Vector3(-10, 1.0, -2)],
		["kitchen", Vector3(0, 1.65, -1.2), Vector3(4, 1, -5)],
		["childhood", Vector3(-1.8, 4.65, -3), Vector3(-5, 4.3, -6)],
		["key", Vector3(-4.5, 1.65, -2.5), demo.key.global_position],
		["deadbolt", Vector3(0, 1.65, 6.5), demo.deadbolt.global_position],
	]
	for view in views:
		demo.player.position = view[1] - Vector3.UP * 1.55
		demo.player.camera.look_at(view[2])
		demo.player.interaction_hint = demo.environment_system.interaction_prompt(demo.player.aimed_interaction())
		demo.acoustic.pulse_origin = demo.player.position
		demo.acoustic.is_pulse_active = true
		demo.acoustic.pulse_radius = 12.0
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://environment_" + view[0] + ".png")
	demo.environment_system.interact(&"brass_key")
	demo.environment_system.interact(&"deadbolt")
	demo.environment_system.interact(&"exit")
	demo.environment_system.try_escape()
	demo.acoustic.is_pulse_active = false
	demo.pulse_afterglow = 0.0
	var exterior_views := [
		["porch_arrival", Vector3(0, 1.65, 9.8), Vector3(0, 1.8, 40)],
		["porch_chairs", Vector3(0.7, 1.65, 12), Vector3(-3.8, 1.1, 10)],
		["garden_neighborhood", Vector3(-1, 1.65, 18), Vector3(1, 2.5, 42)],
		["porch_from_garden", Vector3(3, 1.65, 19), Vector3(0, 1.4, 10)],
	]
	for view in exterior_views:
		demo.player.position = view[1] - Vector3.UP * 1.55
		demo.player.camera.look_at(view[2])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://environment_" + view[0] + ".png")
	print("Visual captures: ", OS.get_user_data_dir())
	quit()
