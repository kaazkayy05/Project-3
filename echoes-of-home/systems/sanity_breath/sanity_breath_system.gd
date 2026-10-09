extends Node

signal gasp_triggered
signal panic_changed(new_panic: float)

# Breath variables
var lung_capacity: float = 100.0
var is_holding_breath: bool = false
var is_gasps_active: bool = false

# Panic variables
var panic_level: float = 0.0
var heart_rate_bpm: int = 60

# Settings
var breath_drain_rate: float = 15.0
var breath_recovery_rate: float = 10.0
var monster_distance: float = 100.0

var heartbeat_sound: AudioStreamPlayer
var gasp_sound: AudioStreamPlayer

func _ready() -> void:
	# Heartbeat audio
	heartbeat_sound = AudioStreamPlayer.new()
	heartbeat_sound.stream = preload("res://demo/audio/347326__newagesoup__heartbeat-fast.wav")
	heartbeat_sound.volume_db = -20.0
	add_child(heartbeat_sound)

	# Gasp audio
	gasp_sound = AudioStreamPlayer.new()
	gasp_sound.stream = preload("res://demo/audio/508391__douglas6969__gasp.mp3")
	gasp_sound.volume_db = -8.0
	add_child(gasp_sound)
	

func _process(delta):
	update_breath(delta)
	update_panic(delta)
	update_audio()

func update_audio():
	# Heartbeat becomes faster and louder with panic
	heartbeat_sound.pitch_scale = clamp(
		heart_rate_bpm / 60.0, 1.0, 2.0
	)

	heartbeat_sound.volume_db = lerp(
		-28.0, -9.0, panic_level
	)

	if panic_level > 0.05:
		if not heartbeat_sound.playing:
			heartbeat_sound.play()
	else:
		heartbeat_sound.stop()

func update_breath(delta):
	if is_holding_breath:
		lung_capacity -= breath_drain_rate * delta

		if monster_distance < 4.0:
			lung_capacity -= breath_drain_rate * delta

		if lung_capacity <= 0:
			lung_capacity = 0
			is_holding_breath = false
			trigger_gasp()
	else:
		lung_capacity += breath_recovery_rate * delta

	lung_capacity = clamp(lung_capacity, 0.0, 100.0)


func update_panic(delta):
	if monster_distance < 4.0:
		panic_level += 0.4 * delta
	else:
		panic_level -= 0.2 * delta

	panic_level = clamp(panic_level, 0.0, 1.0)
	heart_rate_bpm = int(60 + panic_level * 120)

	panic_changed.emit(panic_level)


func hold_breath():
	if lung_capacity > 0:
		is_holding_breath = true


func release_breath():
	is_holding_breath = false


func trigger_gasp():
	is_gasps_active = true

	gasp_sound.play()
	gasp_triggered.emit()

	is_gasps_active = false


func set_monster_distance(distance: float):
	monster_distance = distance
