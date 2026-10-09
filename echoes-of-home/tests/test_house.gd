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
func run() -> void:
	demo = load("res://demo/house_demo.tscn").instantiate()
	root.add_child(demo)
	player = demo.player
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	await walk(Vector3.BACK, 60)
	check(demo.environment_system.has_escaped, "Open front door permits crossing exit area")
	check(not demo.key.visible and demo.key.get_child(0).disabled, "Collected key disappears and stops blocking rays")
	await place(Vector3(-1, 3.1, -0.5))
	await walk(Vector3.FORWARD, 60)
	check(player.position.z > -2, "Bedroom door physically blocks entry")
	demo.environment_system.interact(&"bedroom_door")
	await walk(Vector3.FORWARD, 65)
	check(player.position.z < -2.5, "Bedroom door opens into master bedroom")
	print("HOUSE RESULT: ", failures, " failures")
	demo.queue_free()
	await process_frame
	quit(1 if failures else 0)
