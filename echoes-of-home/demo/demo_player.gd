extends CharacterBody3D
## Demo adapter only. Replace with the team's controller when it is available.
var environment_system: HouseEnvironmentSystem
var acoustic: AcousticPulseSystem
var sanity_breath: Node
var breath_label: Label
var breath_bar: ProgressBar
var breath_locked: bool = false
var creak: AudioStreamPlayer3D
var camera: Camera3D
var step_distance: float = 0.0
var pulse_requested: bool = false
var interaction_requested: bool = false
var interaction_hint: String = ""
var message: String = "Find the brass key downstairs."

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
	floor_snap_length = 0.3
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Create the breathing system
	sanity_breath = preload(
		"res://systems/sanity_breath/sanity_breath_system.gd"
	).new()

	sanity_breath.name = "SanityBreath"
	add_child(sanity_breath)

	sanity_breath.gasp_triggered.connect(on_player_gasp)

	# Create the breathing HUD
	var hud = CanvasLayer.new()
	add_child(hud)

	breath_label = Label.new()
	breath_label.position = Vector2(20, 115)
	breath_label.text = "BREATH: 100%"
	hud.add_child(breath_label)

	breath_bar = ProgressBar.new()
	breath_bar.position = Vector2(20, 140)
	breath_bar.size = Vector2(200, 20)
	breath_bar.min_value = 0
	breath_bar.max_value = 100
	breath_bar.value = 100
	breath_bar.show_percentage = false
	hud.add_child(breath_bar)

func _unhandled_input(event: InputEvent) -> void:
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
	if environment_system.has_escaped:
		return
			# Hold right-click to hold breath
	var right_click_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	if not right_click_pressed:
		breath_locked = false
		sanity_breath.release_breath()
	elif not breath_locked:
		sanity_breath.hold_breath()
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
	if grounded:
		step_distance += Vector2(global_position.x - previous.x, global_position.z - previous.z).length()
		if step_distance >= 0.9:
			step_distance = 0.0
			acoustic.emit_footstep_noise(global_position, sprinting)
			if environment_system.current_surface_type == HouseEnvironmentSystem.Surface.CLUTTER:
				creak.play()
	else:
		step_distance = 0.0
	if pulse_requested:
		acoustic.trigger_player_pulse(global_position)
		pulse_requested = false
	var action := aimed_interaction()
	interaction_hint = "E: " + String(action).replace("_", " ") if action != &"" else ""
	if interaction_requested:
		interaction_requested = false
		if action != &"":
			message = environment_system.interact(action)

func aimed_interaction() -> StringName:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * 2.2, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_meta("interaction"):
		return hit.collider.get_meta("interaction")
	return &""
	
func on_player_gasp() -> void:
	breath_locked = true

	print("PLAYER GASPED!")

	if acoustic != null:
		acoustic.trigger_involuntary_gasp(global_position)
		
func _process(_delta: float) -> void:
	if sanity_breath == null:
		return

	breath_label.text = "BREATH: " + str(
		int(sanity_breath.lung_capacity)
	) + "%"

	breath_bar.value = sanity_breath.lung_capacity
