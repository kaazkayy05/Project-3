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
	print("Visual captures: ", OS.get_user_data_dir())
	quit()
