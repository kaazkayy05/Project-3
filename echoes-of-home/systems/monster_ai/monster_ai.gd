class_name MonsterAI
extends CharacterBody3D

## System 2: Monster AI & Behavior
## Owns hearing response, state transitions, patrol selection, and locomotion.
## A NavigationRegion3D must exist in the containing level for obstacle routing.

signal state_changed(previous_state: State, new_state: State)
signal seam4_status_published(monster_world_position: Vector3, published_state: State)
signal player_killed(noise_origin: Vector3, intensity: float)

enum State {
	DORMANT,
	INVESTIGATING,
	HUNTING,
	STALKING,
}

@export_group("Hearing")
@export var hearing_threshold: float = 0.3
@export var full_aggro_intensity: float = 1.5
@export_range(0.0, 1.0) var hunting_aggro_threshold: float = 0.65

@export_group("Investigation")
@export var investigation_duration: float = 2.5
@export var arrival_tolerance: float = 0.25
@export var investigation_speed: float = 2.0
@export var hunting_speed: float = 5.0

@export_group("Patrol and Movement")
@export var use_house_patrol_route: bool = false
@export var stalking_speed: float = 1.25
@export var patrol_wait_duration: float = 0.75
@export var gravity_acceleration: float = 18.0
@export var allow_direct_movement_without_navigation: bool = false

@export_group("Kill Proximity")
@export var kill_proximity_distance: float = 2.0
@export var player_noise_origin_tolerance: float = 0.5

@export_group("Seams")
@export var acoustic_system: AcousticPulseSystem

var monster_state: State = State.DORMANT
var investigation_target: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var aggro_level: float = 0.0
var kill_proximity_active: bool = false
var patrol_points: Array[Vector3] = []

var _investigation_time_remaining: float = 0.0
var _patrol_index: int = 0
var _patrol_time_remaining: float = 0.0
var _navigation_target: Vector3 = Vector3.INF
var _breath_system: Node
var _seam4_player: Node3D
var _player_killed: bool = false

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

## World-space points chosen from the current fixed house blockout. The route
## passes through the central kitchen opening, approaches the east stair, climbs
## to the upper hall, and ends inside the master bedroom.
const HOUSE_PATROL_POINTS := [
	Vector3(-5.5, 0.1, 4.5),
	Vector3(0.0, 0.1, 1.0),
	Vector3(0.0, 0.1, -3.5),
	Vector3(6.0, 0.1, 6.5),
	Vector3(6.0, 3.1, 1.5),
	Vector3(0.0, 3.1, 0.0),
	Vector3(-4.0, 3.1, -5.0),
]


func _ready() -> void:
	floor_snap_length = 0.35
	_connect_acoustic_system()
	if use_house_patrol_route:
		var house_route: Array[Vector3] = []
		house_route.assign(HOUSE_PATROL_POINTS)
		set_patrol_points(house_route)


func _process(delta: float) -> void:
	_update_investigation_wait(delta)


func _physics_process(delta: float) -> void:
	if _player_killed:
		velocity = Vector3.ZERO
		publish_seam4_status()
		return
	_update_patrol(delta)
	_update_movement(delta)
	move_and_slide()
	publish_seam4_status()


## Allows a coordinator to assign or replace the acoustic system after this node
## has entered the scene tree without creating duplicate signal connections.
func bind_acoustic_system(system: AcousticPulseSystem) -> void:
	if is_instance_valid(acoustic_system):
		var callback := Callable(self, "_on_noise_emitted")
		if acoustic_system.noise_emitted.is_connected(callback):
			acoustic_system.noise_emitted.disconnect(callback)

	acoustic_system = system
	_connect_acoustic_system()


## Seam 4 binding. System 2 owns the monster transform and state; Kayla's system
## continues to own all breath/panic decisions through set_monster_distance().
func bind_breath_system(system: Node, player: Node3D) -> bool:
	if not is_instance_valid(system) or not system.has_method("set_monster_distance"):
		push_warning("Seam 4 requires a breath system with set_monster_distance(distance).")
		return false
	if not is_instance_valid(player):
		push_warning("Seam 4 requires a valid player Node3D.")
		return false

	_breath_system = system
	_seam4_player = player
	publish_seam4_status()
	return true


func clear_breath_system_binding() -> void:
	_breath_system = null
	_seam4_player = null


## Read-only Seam 4 accessors for coordinators that prefer polling to signals.
func get_monster_world_position() -> Vector3:
	return global_position


func get_monster_state() -> State:
	return monster_state


func has_killed_player() -> bool:
	return _player_killed


## Publishes a consistent position/state snapshot and pushes only distance into
## the existing breath API. This is public so freeze tests and coordinators can
## request an immediate update without waiting for a physics frame.
func publish_seam4_status() -> void:
	seam4_status_published.emit(global_position, monster_state)
	if is_instance_valid(_seam4_player):
		var distance := global_position.distance_to(_seam4_player.global_position)
		# The GDD rule is strictly under two meters. This flag only arms the
		# noise-triggered rule; proximity by itself never emits player_killed.
		kill_proximity_active = distance < kill_proximity_distance
		if is_instance_valid(_breath_system):
			_breath_system.call("set_monster_distance", distance)
	else:
		kill_proximity_active = false


func reset_to_default() -> void:
	_investigation_time_remaining = 0.0
	aggro_level = 0.0
	if patrol_points.is_empty():
		current_speed = 0.0
		_set_state(State.DORMANT)
		_set_navigation_target(global_position)
	else:
		current_speed = stalking_speed
		_patrol_time_remaining = patrol_wait_duration
		_set_state(State.STALKING)
		_set_navigation_target(patrol_points[_patrol_index])


## Patrol points are world-space coordinates. Supplying at least one point starts
## stalking immediately; an empty route returns the monster to DORMANT.
func set_patrol_points(points: Array[Vector3]) -> void:
	patrol_points.clear()
	patrol_points.append_array(points)
	_patrol_index = 0
	reset_to_default()


func clear_patrol_points() -> void:
	patrol_points.clear()
	_patrol_index = 0
	reset_to_default()


## Seam 4-ready proximity state. The playable player/breath integration will call
## this once those systems are added to the shared scene.
func update_kill_proximity(player_world_position: Vector3) -> void:
	kill_proximity_active = global_position.distance_to(player_world_position) < kill_proximity_distance


func _connect_acoustic_system() -> void:
	if not is_instance_valid(acoustic_system):
		return

	var callback := Callable(self, "_on_noise_emitted")
	if not acoustic_system.noise_emitted.is_connected(callback):
		acoustic_system.noise_emitted.connect(callback)


func _on_noise_emitted(origin: Vector3, intensity: float, radius: float) -> void:
	if _player_killed:
		return
	if _should_kill_from_player_noise(origin, intensity, radius):
		_kill_player(origin, intensity)
		return
	if not _is_noise_audible(origin, intensity, radius):
		return

	# The event origin is copied at emission time. The monster deliberately does
	# not track the player's later position while investigating this sound.
	investigation_target = origin
	aggro_level = _aggression_from_intensity(intensity)
	current_speed = lerpf(investigation_speed, hunting_speed, aggro_level)
	_investigation_time_remaining = investigation_duration
	_set_navigation_target(investigation_target)

	if aggro_level >= hunting_aggro_threshold:
		_set_state(State.HUNTING)
	else:
		_set_state(State.INVESTIGATING)


func _should_kill_from_player_noise(origin: Vector3, intensity: float, radius: float) -> bool:
	if not is_instance_valid(_seam4_player) or intensity <= 0.0 or radius <= 0.0:
		return false

	# Seam 1 currently carries no source identifier. All production acoustic
	# events are player-generated, and their origin is the player's position.
	# Checking that origin prevents an unrelated future noise from causing a kill.
	if origin.distance_to(_seam4_player.global_position) > player_noise_origin_tolerance:
		return false

	# Recheck synchronously when the sound arrives instead of trusting the
	# previous physics frame's cached proximity flag.
	var current_distance := global_position.distance_to(_seam4_player.global_position)
	kill_proximity_active = current_distance < kill_proximity_distance
	return kill_proximity_active


func _kill_player(noise_origin: Vector3, intensity: float) -> void:
	if _player_killed:
		return
	_player_killed = true
	current_speed = 0.0
	velocity = Vector3.ZERO
	player_killed.emit(noise_origin, intensity)


func _is_noise_audible(origin: Vector3, intensity: float, radius: float) -> bool:
	if intensity < hearing_threshold or radius <= 0.0:
		return false
	return global_position.distance_to(origin) <= radius


func _aggression_from_intensity(intensity: float) -> float:
	if full_aggro_intensity <= hearing_threshold:
		return 1.0
	return clampf(
		inverse_lerp(hearing_threshold, full_aggro_intensity, intensity),
		0.0,
		1.0
	)


func _update_investigation_wait(delta: float) -> void:
	if monster_state != State.INVESTIGATING and monster_state != State.HUNTING:
		return
	if global_position.distance_to(investigation_target) > arrival_tolerance:
		return

	_investigation_time_remaining = maxf(0.0, _investigation_time_remaining - delta)
	if is_zero_approx(_investigation_time_remaining):
		reset_to_default()


func _update_patrol(delta: float) -> void:
	if monster_state != State.STALKING or patrol_points.is_empty():
		return

	var target := patrol_points[_patrol_index]
	if global_position.distance_to(target) > arrival_tolerance:
		_patrol_time_remaining = patrol_wait_duration
		return

	_patrol_time_remaining = maxf(0.0, _patrol_time_remaining - delta)
	if not is_zero_approx(_patrol_time_remaining):
		return

	_patrol_index = (_patrol_index + 1) % patrol_points.size()
	_patrol_time_remaining = patrol_wait_duration
	_set_navigation_target(patrol_points[_patrol_index])


func _update_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity_acceleration * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var target := _get_behavior_target()
	if target == Vector3.INF or global_position.distance_to(target) <= arrival_tolerance:
		_stop_horizontal_movement()
		return

	var next_position := _get_next_movement_position(target)
	var direction := next_position - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		_stop_horizontal_movement()
		return

	direction = direction.normalized()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed
	look_at(global_position + direction, Vector3.UP)


func _get_behavior_target() -> Vector3:
	if monster_state == State.INVESTIGATING or monster_state == State.HUNTING:
		return investigation_target
	if monster_state == State.STALKING and not patrol_points.is_empty():
		return patrol_points[_patrol_index]
	return Vector3.INF


func _get_next_movement_position(target: Vector3) -> Vector3:
	if _has_navigation_region():
		_set_navigation_target(target)
		if not navigation_agent.is_navigation_finished():
			return navigation_agent.get_next_path_position()
		return global_position
	if allow_direct_movement_without_navigation:
		return target
	return global_position


func _has_navigation_region() -> bool:
	if not is_instance_valid(navigation_agent):
		return false
	var navigation_map := navigation_agent.get_navigation_map()
	if not navigation_map.is_valid():
		return false
	return not NavigationServer3D.map_get_regions(navigation_map).is_empty()


func _set_navigation_target(target: Vector3) -> void:
	if _navigation_target.is_equal_approx(target):
		return
	_navigation_target = target
	if is_instance_valid(navigation_agent):
		navigation_agent.target_position = target


func _stop_horizontal_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _set_state(new_state: State) -> void:
	if monster_state == new_state:
		return
	var previous_state := monster_state
	monster_state = new_state
	state_changed.emit(previous_state, monster_state)
	publish_seam4_status()
