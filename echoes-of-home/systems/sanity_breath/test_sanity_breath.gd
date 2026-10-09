extends Node

var breath_system
var acoustic_system

func _ready():
	breath_system = Node.new()
	breath_system.set_script(
		load("res://systems/sanity_breath/sanity_breath_system.gd")
	)
	add_child(breath_system)
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


func on_gasp_triggered():
	print("GASP TRIGGERED!")

	acoustic_system.trigger_involuntary_gasp(Vector3.ZERO)
	
func on_noise_emitted(origin: Vector3, intensity: float, radius: float):
	print("Noise event received!")
	print("Noise position: ", origin)
	print("Noise intensity: ", intensity)
	print("Noise radius: ", radius)
