extends Node

var breath_system
var acoustic_system

func _ready():
	breath_system = Node.new()
	breath_system.set_script(
		load("res://systems/sanity_breath/sanity_breath_system.gd")
	)
	add_child(breath_system)
	_test_seam4_reader()
		# Create Kai's acoustic system for testing
	acoustic_system = AcousticPulseSystem.new()
	add_child(acoustic_system)

	# Listen for noise events
	acoustic_system.noise_emitted.connect(on_noise_emitted)

	print("Starting lung capacity: ", breath_system.lung_capacity)

	# Test holding breath
	breath_system.hold_breath()
	breath_system.update_breath(1.0)
	print("After holding breath for 1 second: ", breath_system.lung_capacity)

	# Test monster proximity
	breath_system.set_monster_distance(2.0)
	breath_system.update_breath(1.0)
	print("After 1 second near monster: ", breath_system.lung_capacity)

	# Test panic
	breath_system.update_panic(1.0)
	print("Panic level: ", breath_system.panic_level)
	print("Heart rate: ", breath_system.heart_rate_bpm)

	# Test releasing breath
	breath_system.release_breath()
	breath_system.update_breath(1.0)
	print("After recovery: ", breath_system.lung_capacity)
		# Test forced gasp
	breath_system.gasp_triggered.connect(on_gasp_triggered)

	breath_system.lung_capacity = 5.0
	breath_system.hold_breath()
	breath_system.update_breath(1.0)

	print("Final lung capacity: ", breath_system.lung_capacity)
	print("Holding breath: ", breath_system.is_holding_breath)


func _test_seam4_reader() -> void:
	var reader = load(
		"res://systems/sanity_breath/sanity_breath_system.gd"
	).new()
	reader.set_process(false)
	add_child(reader)

	var player := Node3D.new()
	add_child(player)

	var monster := MonsterAI.new()
	monster.set_process(false)
	monster.set_physics_process(false)
	add_child(monster)

	reader.bind_seam4_player(player)
	monster.seam4_status_published.connect(
		Callable(reader, "receive_monster_status")
	)
	assert(monster.bind_breath_system(reader, player))

	for distance in [3.99, 4.0, 4.01]:
		player.global_position = Vector3.ZERO
		monster.global_position = Vector3(distance, 0, 0)
		monster.publish_seam4_status()

		assert(reader.monster_world_position == monster.global_position)
		assert(reader.monster_state == monster.monster_state)
		assert(is_equal_approx(reader.monster_distance, distance))

		# Legacy pushes must not override reader-owned distance.
		reader.set_monster_distance(999.0)
		assert(is_equal_approx(reader.monster_distance, distance))

		reader.lung_capacity = 100.0
		reader.hold_breath()
		reader.update_breath(1.0)

		var expected_capacity := 70.0 if distance < 4.0 else 85.0
		assert(is_equal_approx(reader.lung_capacity, expected_capacity))

		reader.panic_level = 0.5
		reader.update_panic(1.0)
		var expected_panic := 0.9 if distance < 4.0 else 0.3
		assert(is_equal_approx(reader.panic_level, expected_panic))

	# Publish once; player movement must refresh reader-owned distance.
	monster.global_position = Vector3(100, 0, 0)
	monster.publish_seam4_status()
	reader.lung_capacity = 100.0
	reader.hold_breath()

	var elapsed_seconds := 0
	for position in [
		Vector3(-4, 0.1, 2),
		Vector3(4, 0.1, -4),
		Vector3(-4, 3.1, -5),
	]:
		player.global_position = position
		reader.update_breath(1.0)
		elapsed_seconds += 1

		assert(is_equal_approx(
			reader.monster_distance,
			position.distance_to(monster.global_position)
		))
		assert(is_equal_approx(
			reader.lung_capacity, 100.0 - 15.0 * elapsed_seconds
		))

	assert(monster.global_position == Vector3(100, 0, 0))

	monster.free()
	player.free()
	reader.free()
	print("Seam 4 reader checks passed.")


func on_gasp_triggered():
	print("GASP TRIGGERED!")

	acoustic_system.trigger_involuntary_gasp(Vector3.ZERO)
	
func on_noise_emitted(origin: Vector3, intensity: float, radius: float):
	print("Noise event received!")
	print("Noise position: ", origin)
	print("Noise intensity: ", intensity)
	print("Noise radius: ", radius)
