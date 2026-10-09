extends SceneTree
var failures: int = 0
var checks: int = 0
var environment_system: HouseEnvironmentSystem
var acoustic: AcousticPulseSystem
var actor: CharacterBody3D
var world: Node3D
var monster_state: String = "DORMANT"
var investigation_target: Vector3

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func listen(origin: Vector3, intensity: float, radius: float) -> void:
	# Contract probe only: Daryl's actual AI is not present in this repository.
	if intensity >= 0.3 and origin.distance_to(Vector3(0, 0, 5)) <= radius:
		monster_state = "INVESTIGATING"
		investigation_target = origin

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	acoustic = AcousticPulseSystem.new()
	world.add_child(acoustic)
	acoustic.set_process(false)
	environment_system = HouseEnvironmentSystem.new()
	environment_system.acoustic_system = acoustic
	world.add_child(environment_system)
	actor = CharacterBody3D.new()
	world.add_child(actor)
	for surface in range(4):
		var body := StaticBody3D.new()
		body.position = Vector3(surface * 4, -0.1, 0)
		body.set_meta("surface_type", surface)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3, 0.2, 3)
		shape.shape = box
		body.add_child(shape)
		world.add_child(body)
	await physics_frame
	await physics_frame
	acoustic.noise_emitted.connect(listen)
	for surface in range(4):
		actor.position = Vector3(surface * 4, 0.05, 0)
		check(environment_system.sample_surface(actor), "Floor collider detected %d" % surface)
		check(environment_system.current_surface_type == surface, "Floor type %d" % surface)
		var multiplier: float = HouseEnvironmentSystem.RESONANCE[surface]
		check(is_equal_approx(acoustic.current_surface_resonance, multiplier), "Acoustic setter receives %s" % multiplier)
		acoustic.emit_footstep_noise(actor.global_position, false)
		var event: Dictionary = acoustic.active_noise_events.back()
		check(is_equal_approx(event.intensity, 0.25 * multiplier), "Footstep intensity %d" % surface)
		check(is_equal_approx(event.radius, 7.2 * multiplier), "Footstep radius %d" % surface)
		check(acoustic.trigger_player_pulse(actor.global_position), "Pulse accepted %d" % surface)
		event = acoustic.active_noise_events.back()
		check(is_equal_approx(event.intensity, multiplier) and is_equal_approx(event.radius, 12.0 * multiplier), "Pulse scaling %d" % surface)
	check(acoustic.pulse_charges == 1, "Pulse charge economy preserved")
	# Same origin, alternate surfaces: only audible event changes probe state.
	actor.position = Vector3(0, 0.05, 0)
	environment_system.sample_surface(actor)
	monster_state = "DORMANT"
	acoustic.emit_footstep_noise(Vector3.ZERO, false)
	check(monster_state == "DORMANT", "Carpet step below listener threshold")
	actor.position.x = 4
	environment_system.sample_surface(actor)
	acoustic.emit_footstep_noise(Vector3.ZERO, false)
	check(monster_state == "INVESTIGATING" and investigation_target == Vector3.ZERO, "Existing noise signal changes probe behavior and anchors origin")
	environment_system.freeze_resonance = true
	for surface in range(4):
		actor.position.x = surface * 4
		environment_system.sample_surface(actor)
		acoustic.emit_footstep_noise(actor.global_position, false)
		var event: Dictionary = acoustic.active_noise_events.back()
		check(is_equal_approx(event.intensity, 0.25) and is_equal_approx(event.radius, 7.2), "Frozen footstep identical %d" % surface)
		acoustic.pulse_charges = 1
		acoustic.trigger_player_pulse(actor.global_position)
		event = acoustic.active_noise_events.back()
		check(is_equal_approx(event.intensity, 1.0) and is_equal_approx(event.radius, 12.0), "Frozen pulse identical %d" % surface)
	environment_system.freeze_resonance = false
	check(is_equal_approx(acoustic.current_surface_resonance, 2.0), "Unfreeze restores current floor")
	actor.position = Vector3(100, 0, 100)
	check(not environment_system.sample_surface(actor), "Off-floor sample reports airborne")
	check(is_equal_approx(acoustic.current_surface_resonance, 1.8), "Off-floor sample does not retain carpet")
	check(not environment_system.try_escape(), "Escape blocked without objectives")
	environment_system.interact(&"deadbolt")
	check(not environment_system.objective_progress.bolt_unlocked, "Bolt cannot unlock before key")
	environment_system.interact(&"exit")
	check(not environment_system.room_layout_state.front_door.open, "Door stays closed before objectives")
	environment_system.interact(&"brass_key")
	check(not environment_system.try_escape(), "Key alone cannot escape")
	environment_system.interact(&"deadbolt")
	check(environment_system.can_escape(), "Default key and bolt loop ready")
	check(not environment_system.try_escape(), "Must open exit before crossing")
	environment_system.require_chain = true
	environment_system.interact(&"exit")
	check(not environment_system.can_escape(), "Optional chain gates exit")
	environment_system.interact(&"chain")
	environment_system.interact(&"exit")
	check(environment_system.try_escape(), "All objectives and open door allow escape")
	check(not environment_system.try_escape(), "Escape signal cannot repeat")
	environment_system.interact(&"bedroom_door")
	check(environment_system.room_layout_state.bedroom_door.open, "Interior door opens")
	environment_system.interact(&"bedroom_door")
	check(not environment_system.room_layout_state.bedroom_door.open, "Interior door closes")
	world.queue_free()
	await process_frame
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
