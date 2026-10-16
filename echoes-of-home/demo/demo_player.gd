extends CharacterBody3D
## Demo adapter only. Replace with the team's controller when it is available.
var environment_system: HouseEnvironmentSystem
var acoustic: AcousticPulseSystem
var sanity_breath: Node
var breath_locked: bool = false
var breath_system: Node
var creak: AudioStreamPlayer3D
var footsteps: AudioStreamPlayer
var camera: Camera3D
var step_distance: float = 0.0
var pulse_requested: bool = false
var interaction_requested: bool = false
var interaction_hint: String = ""
var message: String = "Find the brass key downstairs."
var controls_enabled: bool = true

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 1.55
	camera.fov = 75
	add_child(camera)
	camera.make_current()
	creak = AudioStreamPlayer3D.new()
	creak.stream = preload("res://demo/audio/floor_creak.wav")
	add_child(creak)
	footsteps = AudioStreamPlayer.new()
	footsteps.stream = preload("res://demo/audio/footsteps.wav")
	footsteps.volume_db = -6.0
	footsteps.max_polyphony = 1
	add_child(footsteps)
	floor_snap_length = 0.3
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.002)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.002, -1.4, 1.4)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_SPACE: pulse_requested = true
			KEY_E: interaction_requested = true
			KEY_F6: environment_system.freeze_resonance = not environment_system.freeze_resonance
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not controls_enabled or environment_system.has_escaped:
		velocity = Vector3.ZERO
		footsteps.stop()
		if is_instance_valid(breath_system):
			breath_system.call("release_breath")
		return
	_update_breath_input()
	var direction := Vector3(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		0.0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	direction = basis * direction.normalized()
	var sprinting := Input.is_physical_key_pressed(KEY_SHIFT)
	var speed := 4.0 if sprinting else 2.4
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y -= 18.0 * delta
	var previous := global_position
	move_and_slide()
	var grounded := environment_system.sample_surface(self)
	if not is_on_floor():
		footsteps.stop()
	if grounded:
		step_distance += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
		if step_distance >= 0.9:
			step_distance = 0.0
			var quiet_walk := (
				is_instance_valid(breath_system)
				and bool(breath_system.get("is_holding_breath"))
				and not sprinting
			)
			if not quiet_walk:
				acoustic.emit_footstep_noise(global_position, sprinting)
			if is_on_floor():
				footsteps.play()
			if environment_system.current_surface_type == HouseEnvironmentSystem.Surface.CLUTTER:
				creak.play()
	else:
		step_distance = 0.0
	if pulse_requested:
		acoustic.trigger_player_pulse(global_position)
		pulse_requested = false
	var action := aimed_interaction()
	interaction_hint = environment_system.interaction_prompt(action)
	if interaction_requested:
		interaction_requested = false
		if action != &"":
			message = environment_system.interact(action)


func _update_breath_input() -> void:
	if not is_instance_valid(breath_system):
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		breath_system.call("hold_breath")
	else:
		breath_system.call("release_breath")


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not controls_enabled:
		footsteps.stop()
		velocity = Vector3.ZERO
		pulse_requested = false
		interaction_requested = false
		if is_instance_valid(breath_system):
			breath_system.call("release_breath")

func aimed_interaction() -> StringName:
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var best: StringName = &""
	var best_score := -INF
	for target in get_tree().get_nodes_in_group("house_interactables"):
		if not target is StaticBody3D or not target.visible:
			continue
		var offset: Vector3 = target.global_position - origin
		var distance := offset.length()
		if distance > 2.2 or distance < 0.01:
			continue
		var alignment := forward.dot(offset.normalized())
		if alignment < cos(deg_to_rad(24.0)):
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, target.global_position, 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider != target:
			continue
		var action: StringName = target.get_meta("interaction")
		if action == &"deadbolt" and environment_system.objective_progress.bolt_unlocked:
			continue
		var score := alignment - distance * 0.025
		if action in [&"brass_key", &"deadbolt", &"chain"]:
			score += 0.12
		if score > best_score:
			best_score = score
			best = action
	return best

func on_player_gasp() -> void:
	breath_locked = true

	print("PLAYER GASPED!")
