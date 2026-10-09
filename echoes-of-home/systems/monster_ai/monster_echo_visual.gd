class_name MonsterEchoVisual
extends Node3D

## Visual-only adapter for the Monster scene. It reads the acoustic wave owned
## by System 1 and never writes to Monster AI state or behavior.

@export var reveal_trail_distance: float = 5.0
@export var reveal_sample_offset: Vector3 = Vector3(0.0, 0.9, 0.0)
@export var echo_material: ShaderMaterial


func _ready() -> void:
	visible = false
	_set_shader_pulse_active(false)


func _process(_delta: float) -> void:
	update_reveal()


## Public for deterministic visual tests. Gameplay calls this once per frame.
func update_reveal() -> void:
	var monster := get_parent() as MonsterAI
	if not is_instance_valid(monster) or not is_instance_valid(monster.acoustic_system):
		_hide_visual()
		return

	var acoustic := monster.acoustic_system
	if not acoustic.is_pulse_active:
		_hide_visual()
		return

	var sample_position := to_global(reveal_sample_offset)
	var distance_from_origin := sample_position.distance_to(acoustic.pulse_origin)
	var distance_behind_wave := acoustic.pulse_radius - distance_from_origin
	visible = distance_behind_wave >= 0.0 and distance_behind_wave <= reveal_trail_distance

	if not is_instance_valid(echo_material):
		return
	echo_material.set_shader_parameter("pulse_origin", acoustic.pulse_origin)
	echo_material.set_shader_parameter("pulse_radius", acoustic.pulse_radius)
	echo_material.set_shader_parameter("pulse_active", visible)
	echo_material.set_shader_parameter("reveal_trail_distance", reveal_trail_distance)


func _hide_visual() -> void:
	visible = false
	_set_shader_pulse_active(false)


func _set_shader_pulse_active(active: bool) -> void:
	if is_instance_valid(echo_material):
		echo_material.set_shader_parameter("pulse_active", active)
