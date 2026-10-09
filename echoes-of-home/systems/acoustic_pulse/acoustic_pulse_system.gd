class_name AcousticPulseSystem
extends Node

## System 1: Acoustic Pulse & Perception System
## Owner: Kai
## Responsibilities: Pulse charge economy, wave expansion, and noise dispatch.

# --- SEAM SIGNALS ---
## Seam 1 -> Daryl's Monster AI listens to this
signal noise_emitted(origin: Vector3, intensity: float, radius: float)

## UI and local state signals
signal charges_updated(current_charges: int, max_charges: int)
signal pulse_started(origin: Vector3, max_radius: float, duration: float)
signal pulse_ended()

# --- OWNED STATE ---
@export_group("Pulse Tuning")
@export var max_pulse_charges: int = 5
@export var pulse_recharge_time: float = 6.0
@export var base_pulse_radius: float = 24.0
@export var base_pulse_speed: float = 14.0

var pulse_charges: int = 5
var is_pulse_active: bool = false
var pulse_origin: Vector3 = Vector3.ZERO
var pulse_radius: float = 0.0
var active_noise_events: Array[Dictionary] = []

# --- INBOUND SEAM STATE CACHE ---
## Seam 2 <- Samaii writes this via set_surface_resonance()
var current_surface_resonance: float = 1.0

var _recharge_timer: float = 0.0
var _current_target_radius: float = 0.0


func _ready() -> void:
	pulse_charges = max_pulse_charges
	charges_updated.emit(pulse_charges, max_pulse_charges)


func _process(delta: float) -> void:
	_handle_pulse_expansion(delta)
	_handle_recharge(delta)


# ==============================================================================
# PLAYER ACTIONS & EXPANSION
# ==============================================================================

func trigger_player_pulse(player_global_pos: Vector3) -> bool:
	if pulse_charges <= 0:
		return false
	
	pulse_charges -= 1
	charges_updated.emit(pulse_charges, max_pulse_charges)
	
	var effective_radius: float = base_pulse_radius * current_surface_resonance
	var duration: float = effective_radius / base_pulse_speed
	
	pulse_origin = player_global_pos
	pulse_radius = 0.0
	_current_target_radius = effective_radius
	is_pulse_active = true
	
	pulse_started.emit(pulse_origin, effective_radius, duration)
	
	# Rule 1 / Seam 1: broadcast sound event
	_dispatch_noise_event(pulse_origin, 1.0 * current_surface_resonance, effective_radius)
	return true


func _handle_pulse_expansion(delta: float) -> void:
	if not is_pulse_active:
		return
	
	pulse_radius += base_pulse_speed * delta
	if pulse_radius >= _current_target_radius:
		pulse_radius = _current_target_radius
		is_pulse_active = false
		pulse_ended.emit()


func _handle_recharge(delta: float) -> void:
	if pulse_charges < max_pulse_charges:
		_recharge_timer += delta
		if _recharge_timer >= pulse_recharge_time:
			pulse_charges += 1
			_recharge_timer = 0.0
			charges_updated.emit(pulse_charges, max_pulse_charges)


# ==============================================================================
# SEAM METHODS (Used by Samaii & Kayla)
# ==============================================================================

## Seam 2 (Samaii): Carpet = 0.5, Hardwood = 1.8
func set_surface_resonance(multiplier: float) -> void:
	current_surface_resonance = clampf(multiplier, 0.1, 3.0)


## Seam 3 (Kayla): Involuntary gasp when lung stamina hits 0
func trigger_involuntary_gasp(player_global_pos: Vector3) -> void:
	var gasp_intensity: float = 1.5 * current_surface_resonance
	var gasp_radius: float = base_pulse_radius * 1.2
	_dispatch_noise_event(player_global_pos, gasp_intensity, gasp_radius)


func emit_footstep_noise(step_global_pos: Vector3, is_sprinting: bool) -> void:
	var base_intensity: float = 0.7 if is_sprinting else 0.25
	var effective_intensity: float = base_intensity * current_surface_resonance
	var effective_radius: float = (base_pulse_radius * 0.6) * current_surface_resonance
	_dispatch_noise_event(step_global_pos, effective_intensity, effective_radius)


# ==============================================================================
# INTERNAL DISPATCH
# ==============================================================================

func _dispatch_noise_event(pos: Vector3, intensity: float, radius: float) -> void:
	var event: Dictionary = {
		"position": pos,
		"intensity": intensity,
		"radius": radius,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	active_noise_events.append(event)
	if active_noise_events.size() > 5:
		active_noise_events.pop_front()
	
	noise_emitted.emit(pos, intensity, radius)
