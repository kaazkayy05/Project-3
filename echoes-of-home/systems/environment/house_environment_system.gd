class_name HouseEnvironmentSystem
extends Node
## Owner: Samaii. Call sample_surface before player-generated noise.
signal surface_changed(surface_type: int, multiplier: float)
signal objectives_changed(progress: Dictionary)
signal escaped

enum Surface { CARPET, HARDWOOD, TILE, CLUTTER }
const RESONANCE = [0.5, 1.8, 1.6, 2.0]
@export var acoustic_system: AcousticPulseSystem
@export var require_chain: bool = false
@export var freeze_resonance: bool = false:
	set(value):
		freeze_resonance = value
		_publish_surface()
var current_surface_type: Surface = Surface.HARDWOOD
var resonance_multiplier: float = 1.8
var objective_progress: Dictionary = {"key_found": false, "bolt_unlocked": false, "chain_cleared": false}
var room_layout_state: Dictionary = {
	"front_door": {"locked": true, "open": false},
	"bedroom_door": {"locked": false, "open": false},
	"blocked_hazard_zones": {"kitchen_clutter": false, "upstairs_creaky_board": false}
}
var has_escaped: bool = false

func _ready() -> void:
	_publish_surface()

func _publish_surface() -> void:
	resonance_multiplier = 1.0 if freeze_resonance else float(RESONANCE[current_surface_type])
	if is_instance_valid(acoustic_system):
		acoustic_system.set_surface_resonance(resonance_multiplier)
	surface_changed.emit(current_surface_type, resonance_multiplier)

func sample_surface(player: PhysicsBody3D) -> bool:
	# Feet-origin ray hits the uppermost solid floor, including rugs over wood.
	var query := PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3.UP * 0.15,
		player.global_position + Vector3.DOWN * 0.35, 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var surface: int = Surface.HARDWOOD
	if not hit.is_empty():
		surface = int(hit.collider.get_meta("surface_type", Surface.HARDWOOD))
	current_surface_type = clampi(surface, Surface.CARPET, Surface.CLUTTER) as Surface
	_publish_surface()
	return not hit.is_empty()

func can_escape() -> bool:
	return objective_progress.key_found and objective_progress.bolt_unlocked and (
		not require_chain or objective_progress.chain_cleared)

func interact(action: StringName) -> String:
	match action:
		&"brass_key":
			if objective_progress.key_found:
				return "The key is already in your pocket."
			objective_progress.key_found = true
		&"deadbolt":
			if not objective_progress.key_found:
				return "The deadbolt needs a brass key."
			objective_progress.bolt_unlocked = true
			room_layout_state.front_door.locked = false
		&"chain":
			if not require_chain:
				return "There is no chain fitted."
			objective_progress.chain_cleared = true
		&"exit":
			if not can_escape():
				return "The front door is still secured."
			room_layout_state.front_door.open = true
		&"bedroom_door":
			room_layout_state.bedroom_door.open = not room_layout_state.bedroom_door.open
		_:
			return ""
	room_layout_state.front_door.locked = not can_escape()
	objectives_changed.emit(objective_progress.duplicate(true))
	return "Brass key collected." if action == &"brass_key" else "Done."

func try_escape() -> bool:
	if has_escaped or not can_escape() or not room_layout_state.front_door.open:
		return false
	has_escaped = true
	escaped.emit()
	return true
