extends SceneTree

## Standalone gameplay bot for the playable house. It never changes production
## state or reads the monster transform for decisions. Headless Godot cannot
## synthesize Input.is_physical_key_pressed(), so movement is applied to the real
## player CharacterBody3D with the exact controller constants and seam calls.

const HOUSE_SCENE_PATH := "res://demo/house_demo.tscn"
const STRATEGIES: Array[String] = [
	"normal_walk",
	"breath_stealth",
	"run_on_warning",
	"combined",
]
const RUNS_PER_STRATEGY := 5
const RUN_TIMEOUT_SECONDS := 60.0
const TIME_SCALE := 4.0
const PHYSICS_TICKS := 60.0
const SIMULATION_DELTA := TIME_SCALE / PHYSICS_TICKS
const WALK_SPEED := 2.4
const SPRINT_SPEED := 4.0
const GRAVITY := 18.0
const STEP_DISTANCE := 0.9
const PATH_REFRESH_SECONDS := 0.6
const INTERACTION_RETRY_SECONDS := 0.35
const KEY_APPROACHES: Array[Vector3] = [
	Vector3(-4.6, 0.1, -2.3),
	Vector3(-4.6, 0.1, -3.7),
	Vector3(-6.0, 0.1, -1.3),
]
const DOOR_APPROACH := Vector3(0.0, 0.1, 6.5)
const ESCAPE_TARGET := Vector3(0.0, 0.1, 10.0)

var _demo: Node3D
var _player: CharacterBody3D
var _monster: MonsterAI
var _environment: HouseEnvironmentSystem
var _acoustic: AcousticPulseSystem
var _breath: Node
var _navigation_map: RID

var _results: Array[Dictionary] = []
var _metrics: Dictionary = {}
var _sim_time := 0.0
var _pending_noise := ""
var _last_noise_label := "none"
var _last_noise_time := -INF
var _path: PackedVector3Array = PackedVector3Array()
var _path_index := 0
var _path_refresh_remaining := 0.0
var _interaction_retry_remaining := 0.0
var _current_target := Vector3.INF
var _recovering_breath := false
var _initial_hesitation_remaining := 0.0
var _last_progress_position := Vector3.ZERO
var _progress_check_remaining := 2.0
var _last_desired_direction := Vector3.ZERO
var _unstick_remaining := 0.0
var _unstick_direction := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	call_deferred("_run_suite")


func _run_suite() -> void:
	Engine.time_scale = TIME_SCALE
	Engine.physics_ticks_per_second = int(PHYSICS_TICKS)
	var attempt := 0
	for strategy in STRATEGIES:
		for strategy_run in RUNS_PER_STRATEGY:
			attempt += 1
			var result := await _run_attempt(attempt, strategy, strategy_run)
			_results.append(result)
			print("AI_PLAYTEST_RUN:", JSON.stringify(result))

	var summary := _summarize_results()
	_write_results(summary)
	print("AI_PLAYTEST_SUMMARY:", JSON.stringify(summary))
	Engine.time_scale = 1.0
	quit(0)


func _run_attempt(attempt: int, strategy: String, strategy_run: int) -> Dictionary:
	_rng.seed = 440_000 + attempt * 7919
	_sim_time = 0.0
	_pending_noise = ""
	_last_noise_label = "none"
	_last_noise_time = -INF
	_path = PackedVector3Array()
	_path_index = 0
	_path_refresh_remaining = 0.0
	_interaction_retry_remaining = 0.0
	_current_target = Vector3.INF
	_recovering_breath = false
	_initial_hesitation_remaining = _rng.randf_range(0.0, 1.5)
	_progress_check_remaining = 2.0
	_last_desired_direction = Vector3.ZERO
	_unstick_remaining = 0.0
	_unstick_direction = Vector3.ZERO

	var house_scene := load(HOUSE_SCENE_PATH) as PackedScene
	_demo = house_scene.instantiate()
	root.add_child(_demo)
	_player = _demo.player
	_monster = _demo.monster
	_environment = _demo.environment_system
	_acoustic = _demo.acoustic
	_breath = _demo.breath_system
	_player.set_physics_process(false)

	_metrics = {
		"attempt": attempt,
		"strategy": strategy,
		"strategy_run": strategy_run + 1,
		"result": "timeout",
		"duration_seconds": 0.0,
		"key_collected": false,
		"door_unlocked": false,
		"door_opened": false,
		"escaped": false,
		"death_position": [],
		"final_position": [],
		"death_cause": "none",
		"breath_hold_seconds": 0.0,
		"hiding_seconds": 0.0,
		"sprinting_seconds": 0.0,
		"minimum_lung_capacity": 100.0,
		"noise_counts": {},
		"detection_counts": {},
		"state_changes": [],
		"interaction_failures": 0,
		"stuck_replans": 0,
		"key_approach": [],
	}

	_acoustic.noise_emitted.connect(_on_noise_emitted)
	_monster.state_changed.connect(_on_monster_state_changed)
	_monster.player_killed.connect(_on_player_killed)

	# Allow the runtime navigation bake and physics map to settle normally.
	for frame in 8:
		await physics_frame
	_navigation_map = _monster.navigation_agent.get_navigation_map()
	_last_progress_position = _player.global_position
	var key_approach := KEY_APPROACHES[_rng.randi_range(0, KEY_APPROACHES.size() - 1)]
	_metrics.key_approach = _vector_to_array(key_approach)

	while _sim_time < RUN_TIMEOUT_SECONDS:
		await physics_frame
		_sim_time += SIMULATION_DELTA
		_interaction_retry_remaining = maxf(0.0, _interaction_retry_remaining - SIMULATION_DELTA)
		_path_refresh_remaining = maxf(0.0, _path_refresh_remaining - SIMULATION_DELTA)
		_progress_check_remaining = maxf(0.0, _progress_check_remaining - SIMULATION_DELTA)
		_unstick_remaining = maxf(0.0, _unstick_remaining - SIMULATION_DELTA)

		_metrics.key_collected = bool(_environment.objective_progress.key_found)
		_metrics.door_unlocked = bool(_environment.objective_progress.bolt_unlocked)
		_metrics.door_opened = bool(_environment.room_layout_state.front_door.open)
		_metrics.escaped = bool(_environment.has_escaped)
		_metrics.minimum_lung_capacity = minf(
			float(_metrics.minimum_lung_capacity), float(_breath.lung_capacity)
		)

		if _demo.game_over or _monster.has_killed_player():
			_metrics.result = "death"
			break
		if _environment.has_escaped:
			_metrics.result = "escaped"
			break

		var target := _objective_target(key_approach)
		if target != _current_target:
			_current_target = target
			_refresh_path(target)

		var decision := _strategy_decision(strategy)
		var hold_breath: bool = decision.hold_breath
		var sprinting: bool = decision.sprinting
		var should_move: bool = decision.should_move

		if _initial_hesitation_remaining > 0.0:
			_initial_hesitation_remaining = maxf(
				0.0, _initial_hesitation_remaining - SIMULATION_DELTA
			)
			should_move = false

		_apply_breath_choice(hold_breath)
		if hold_breath:
			_metrics.breath_hold_seconds += SIMULATION_DELTA
		if not should_move and bool(decision.hiding):
			_metrics.hiding_seconds += SIMULATION_DELTA
		if sprinting and should_move:
			_metrics.sprinting_seconds += SIMULATION_DELTA

		if _is_at_objective(target):
			_stop_player()
			_try_current_interaction()
		elif should_move:
			if is_zero_approx(_path_refresh_remaining):
				_refresh_path(target)
			var direction := _next_path_direction(target)
			_move_player(direction, sprinting)
		else:
			_stop_player()
			_environment.sample_surface(_player)

		_check_progress(target, should_move)

	_metrics.duration_seconds = snappedf(_sim_time, 0.01)
	_metrics.final_position = _vector_to_array(_player.global_position)
	if _metrics.result == "death" and _metrics.death_position.is_empty():
		_metrics.death_position = _vector_to_array(_player.global_position)
	if _metrics.result == "timeout":
		_metrics.death_cause = "timeout_before_escape"

	await _dispose_attempt()
	return _metrics.duplicate(true)


func _objective_target(key_approach: Vector3) -> Vector3:
	if not bool(_environment.objective_progress.key_found):
		return key_approach
	if not bool(_environment.objective_progress.bolt_unlocked):
		return DOOR_APPROACH
	if not bool(_environment.room_layout_state.front_door.open):
		return DOOR_APPROACH
	return ESCAPE_TARGET


func _strategy_decision(strategy: String) -> Dictionary:
	var warning_is_audible := (
		is_instance_valid(_monster.approach_warning)
		and _monster.approach_warning.playing
	)
	var lung := float(_breath.lung_capacity)
	var surface := int(_environment.current_surface_type)
	var on_carpet := surface == HouseEnvironmentSystem.Surface.CARPET
	var hold_breath := false
	var sprinting := false
	var should_move := true
	var hiding := false

	match strategy:
		"normal_walk":
			pass
		"breath_stealth":
			if lung <= 28.0:
				_recovering_breath = true
			elif lung >= 82.0:
				_recovering_breath = false
			hold_breath = not _recovering_breath and not on_carpet
			if warning_is_audible and lung > 20.0:
				hold_breath = true
				should_move = false
				hiding = true
		"run_on_warning":
			sprinting = warning_is_audible
		"combined":
			if lung <= 25.0:
				_recovering_breath = true
			elif lung >= 75.0:
				_recovering_breath = false
			if warning_is_audible and lung > 25.0:
				hold_breath = true
				should_move = false
				hiding = true
			elif warning_is_audible:
				sprinting = true
			else:
				hold_breath = not _recovering_breath and not on_carpet

	return {
		"hold_breath": hold_breath,
		"sprinting": sprinting,
		"should_move": should_move,
		"hiding": hiding,
	}


func _apply_breath_choice(hold_breath: bool) -> void:
	if hold_breath:
		_breath.call("hold_breath")
	else:
		_breath.call("release_breath")


func _move_player(direction: Vector3, sprinting: bool) -> void:
	if not _player.controls_enabled or _environment.has_escaped:
		_stop_player()
		return

	direction.y = 0.0
	if not direction.is_zero_approx():
		direction = direction.normalized()
		_player.look_at(_player.global_position + direction, Vector3.UP)
	_last_desired_direction = direction
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	_player.velocity.x = direction.x * speed
	_player.velocity.z = direction.z * speed
	_player.velocity.y -= GRAVITY * SIMULATION_DELTA
	var previous := _player.global_position
	_player.move_and_slide()
	var grounded := _environment.sample_surface(_player)
	if not _player.is_on_floor():
		_player.footsteps.stop()
	if grounded:
		_player.step_distance += Vector2(
			_player.global_position.x - previous.x,
			_player.global_position.z - previous.z
		).length()
		if _player.step_distance >= STEP_DISTANCE:
			_player.step_distance = 0.0
			var quiet_walk := (
				bool(_breath.is_holding_breath)
				and not sprinting
			)
			if not quiet_walk:
				_pending_noise = "sprint_footstep" if sprinting else "walk_footstep"
				_acoustic.emit_footstep_noise(_player.global_position, sprinting)
				_pending_noise = ""
			if _player.is_on_floor():
				_player.footsteps.play()
			if _environment.current_surface_type == HouseEnvironmentSystem.Surface.CLUTTER:
				_player.creak.play()
	else:
		_player.step_distance = 0.0


func _stop_player() -> void:
	_player.velocity.x = 0.0
	_player.velocity.z = 0.0
	if is_instance_valid(_player.footsteps):
		_player.footsteps.stop()


func _refresh_path(target: Vector3) -> void:
	_path_refresh_remaining = PATH_REFRESH_SECONDS
	_path_index = 0
	if not _navigation_map.is_valid():
		_path = PackedVector3Array()
		return
	_path = NavigationServer3D.map_get_path(
		_navigation_map, _player.global_position, target, true
	)
	if _path.size() > 1:
		_path_index = 1


func _next_path_direction(target: Vector3) -> Vector3:
	if _unstick_remaining > 0.0:
		return _unstick_direction
	while _path_index < _path.size():
		var waypoint := _path[_path_index]
		var flat_offset := Vector2(
			waypoint.x - _player.global_position.x,
			waypoint.z - _player.global_position.z
		)
		if flat_offset.length() > 0.3:
			return Vector3(flat_offset.x, 0.0, flat_offset.y)
		_path_index += 1
	var direct := target - _player.global_position
	direct.y = 0.0
	return direct


func _is_at_objective(target: Vector3) -> bool:
	var flat_distance := Vector2(
		target.x - _player.global_position.x,
		target.z - _player.global_position.z
	).length()
	return flat_distance <= 0.45


func _try_current_interaction() -> void:
	if not is_zero_approx(_interaction_retry_remaining):
		return
	_interaction_retry_remaining = INTERACTION_RETRY_SECONDS

	var expected: StringName
	var target_node: Node3D
	if not bool(_environment.objective_progress.key_found):
		expected = &"brass_key"
		target_node = _demo.key
	elif not bool(_environment.objective_progress.bolt_unlocked):
		expected = &"deadbolt"
		target_node = _demo.deadbolt
	elif not bool(_environment.room_layout_state.front_door.open):
		expected = &"exit"
		target_node = _demo.front_door
	else:
		return

	_player.camera.look_at(target_node.global_position)
	var aimed_action: StringName = _player.aimed_interaction()
	if aimed_action != expected:
		_metrics.interaction_failures += 1
		return

	# Feed the normal E handler and let the player's existing interaction branch
	# consume it. Velocity is zero so this extra controller tick cannot double-move.
	var held_before := bool(_breath.is_holding_breath)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	_player._unhandled_input(event)
	_player.velocity = Vector3.ZERO
	_player._physics_process(0.0)
	if held_before:
		_breath.call("hold_breath")


func _check_progress(target: Vector3, should_move: bool) -> void:
	if not is_zero_approx(_progress_check_remaining):
		return
	_progress_check_remaining = 2.0
	var moved := _player.global_position.distance_to(_last_progress_position)
	var target_distance := _player.global_position.distance_to(target)
	if should_move and moved < 0.2 and target_distance > 0.8:
		_metrics.stuck_replans += 1
		var basis_direction := _last_desired_direction
		if basis_direction.is_zero_approx():
			basis_direction = target - _player.global_position
			basis_direction.y = 0.0
			basis_direction = basis_direction.normalized()
		var side_sign := -1.0 if _rng.randi_range(0, 1) == 0 else 1.0
		_unstick_direction = Vector3(
			-basis_direction.z * side_sign, 0.0, basis_direction.x * side_sign
		)
		_unstick_remaining = 0.8
		_refresh_path(target)
	_last_progress_position = _player.global_position


func _on_noise_emitted(origin: Vector3, intensity: float, radius: float) -> void:
	var label := _pending_noise
	if label.is_empty():
		if bool(_breath.is_gasps_active):
			label = "forced_gasp"
		else:
			label = "external_acoustic"
	_last_noise_label = label
	_last_noise_time = _sim_time
	_increment_count(_metrics.noise_counts, label)
	var heard := (
		intensity >= _monster.hearing_threshold
		and radius > 0.0
		and _monster.global_position.distance_to(origin) <= radius
	)
	if heard:
		_increment_count(_metrics.detection_counts, label)


func _on_monster_state_changed(previous_state: MonsterAI.State, new_state: MonsterAI.State) -> void:
	var cause := _pending_noise
	if cause.is_empty() and _sim_time - _last_noise_time <= 0.11:
		cause = _last_noise_label
	if cause.is_empty():
		cause = "passive_breathing_or_patrol"
	_metrics.state_changes.append({
		"time": snappedf(_sim_time, 0.01),
		"from": MonsterAI.State.keys()[previous_state],
		"to": MonsterAI.State.keys()[new_state],
		"cause": cause,
	})


func _on_player_killed(_origin: Vector3, _intensity: float) -> void:
	_metrics.death_position = _vector_to_array(_player.global_position)
	var cause := _pending_noise
	if cause.is_empty():
		cause = _last_noise_label
	_metrics.death_cause = cause if not cause.is_empty() else "unknown_acoustic_event"


func _increment_count(counts: Dictionary, label: String) -> void:
	counts[label] = int(counts.get(label, 0)) + 1


func _vector_to_array(value: Vector3) -> Array[float]:
	return [
		snappedf(value.x, 0.01),
		snappedf(value.y, 0.01),
		snappedf(value.z, 0.01),
	]


func _dispose_attempt() -> void:
	if is_instance_valid(_demo):
		for audio in _demo.find_children("*", "AudioStreamPlayer", true, false):
			audio.stop()
		for audio in _demo.find_children("*", "AudioStreamPlayer3D", true, false):
			audio.stop()
		_demo.queue_free()
	for frame in 3:
		await process_frame


func _summarize_results() -> Dictionary:
	var summary := {
		"attempts": _results.size(),
		"escapes": 0,
		"deaths": 0,
		"timeouts": 0,
		"success_rate_percent": 0.0,
		"average_escape_seconds": null,
		"most_common_death_cause": "none",
		"strategies": {},
	}
	var successful_time := 0.0
	var death_causes := {}
	for strategy in STRATEGIES:
		summary.strategies[strategy] = {
			"attempts": 0,
			"escapes": 0,
			"deaths": 0,
			"timeouts": 0,
			"average_escape_seconds": null,
			"average_breath_hold_seconds": 0.0,
		}

	for result in _results:
		var strategy_data: Dictionary = summary.strategies[result.strategy]
		strategy_data.attempts += 1
		strategy_data.average_breath_hold_seconds += float(result.breath_hold_seconds)
		match result.result:
			"escaped":
				summary.escapes += 1
				strategy_data.escapes += 1
				successful_time += float(result.duration_seconds)
				strategy_data.average_escape_seconds = (
					float(strategy_data.get("escape_time_total", 0.0))
					+ float(result.duration_seconds)
				)
				strategy_data.escape_time_total = strategy_data.average_escape_seconds
			"death":
				summary.deaths += 1
				strategy_data.deaths += 1
				_increment_count(death_causes, str(result.death_cause))
			_:
				summary.timeouts += 1
				strategy_data.timeouts += 1

	for strategy in STRATEGIES:
		var strategy_data: Dictionary = summary.strategies[strategy]
		strategy_data.average_breath_hold_seconds = snappedf(
			float(strategy_data.average_breath_hold_seconds) / float(strategy_data.attempts),
			0.01
		)
		if strategy_data.escapes > 0:
			strategy_data.average_escape_seconds = snappedf(
				float(strategy_data.escape_time_total) / float(strategy_data.escapes),
				0.01
			)
		strategy_data.erase("escape_time_total")

	if summary.escapes > 0:
		summary.average_escape_seconds = snappedf(
			successful_time / float(summary.escapes), 0.01
		)
	summary.success_rate_percent = snappedf(
		100.0 * float(summary.escapes) / float(summary.attempts), 0.01
	)
	var highest_count := 0
	for cause in death_causes:
		var count: int = death_causes[cause]
		if count > highest_count:
			highest_count = count
			summary.most_common_death_cause = cause
	return summary


func _write_results(summary: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	var payload := {
		"method": {
			"engine_target": "Godot 4.3 headless",
			"headless_input_limitation": (
				"Raw physical keyboard and mouse state cannot be synthesized headlessly; "
				+ "the bot drives the real CharacterBody3D with the production controller's "
				+ "movement, collision, surface, footstep, interaction, and breath rules."
			),
			"time_scale": TIME_SCALE,
			"timeout_seconds": RUN_TIMEOUT_SECONDS,
		},
		"summary": summary,
		"runs": _results,
	}
	var file := FileAccess.open("res://tmp/ai_playtest_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "\t"))
