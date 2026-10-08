extends Node

## Standalone Test Runner for AcousticPulseSystem
## Verifies signal dispatch, surface resonance multiplier, and involuntary gasps.

var pulse_system: AcousticPulseSystem

func _ready() -> void:
	print("\n==========================================")
	print("--- STARTING ACOUSTIC PULSE SEAM TESTS ---")
	print("==========================================")
	
	# Instantiate and attach Kai's system
	pulse_system = AcousticPulseSystem.new()
	add_child(pulse_system)
	
	# Wire up a mock listener (mimicking Daryl's Monster AI listening to Seam 1)
	pulse_system.noise_emitted.connect(_on_mock_monster_heard)
	
	# TEST 1: Default Baseline Pulse
	print("\n[TEST 1] Triggering Baseline Pulse from (0, 0, 0)...")
	var success_1: bool = pulse_system.trigger_player_pulse(Vector3.ZERO)
	print("  Pulse triggered: ", success_1)
	print("  Remaining charges: ", pulse_system.pulse_charges, "/", pulse_system.max_pulse_charges)
	
	# TEST 2: Seam 2 with Samaii (Hardwood Floor Resonance = 1.8x)
	print("\n[TEST 2] Samaii's Seam: Setting Hardwood Resonance (1.8x)...")
	pulse_system.set_surface_resonance(1.8)
	var success_2: bool = pulse_system.trigger_player_pulse(Vector3(5, 0, 5))
	print("  Pulse triggered on hardwood: ", success_2)
	print("  Remaining charges: ", pulse_system.pulse_charges, "/", pulse_system.max_pulse_charges)
	
	# TEST 3: Seam 3 with Kayla (Involuntary Gasp at zero lung capacity)
	print("\n[TEST 3] Kayla's Seam: Triggering Involuntary Gasp at (10, 0, 10)...")
	pulse_system.trigger_involuntary_gasp(Vector3(10, 0, 10))
	
	print("\n==========================================")
	print("--- ALL ACOUSTIC TESTS COMPLETED ---")
	print("==========================================\n")


func _on_mock_monster_heard(origin: Vector3, intensity: float, radius: float) -> void:
	print("  -> [MOCK MONSTER HEARD NOISE]")
	print("     Origin Coordinates : ", origin)
	print("     Calculated Intensity: ", intensity)
	print("     Acoustic Radius     : ", radius, "m")
