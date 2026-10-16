extends SceneTree

## Optional visual QA helper. Run without --headless so the compatibility
## renderer can capture the persistent monster and the close-camera scare rig.


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	var demo = load("res://demo/house_demo.tscn").instantiate()
	root.add_child(demo)
	demo.player.set_physics_process(false)
	demo.monster.set_process(false)
	demo.monster.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for frame in 4:
		await process_frame

	demo.player.position = Vector3(0.0, 0.1, 6.0)
	demo.monster.position = Vector3(0.0, 0.1, 3.0)
	demo.monster.look_at(demo.player.global_position, Vector3.UP)
	demo.player.camera.look_at(demo.monster.global_position + Vector3.UP * 1.05)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/monster_presentation.png")

	demo.monster.jumpscare.play(demo.player)
	await create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tmp/monster_jumpscare.png")
	print("Monster presentation captures saved under res://tmp/.")
	quit()
