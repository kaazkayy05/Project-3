class_name MonsterJumpscare
extends Node

signal finished

@export var presentation_duration := 0.72

@onready var scare_rig: Node3D = get_node("ScareRig")
@onready var screen_flash: ColorRect = get_node("ScreenFlash/ColorRect")
@onready var sting: AudioStreamPlayer = get_node("Sting")

var _active := false
var _home_parent: Node


func _ready() -> void:
	_home_parent = scare_rig.get_parent()
	scare_rig.visible = false
	screen_flash.visible = false


func play(player: Node3D) -> bool:
	if _active or not is_instance_valid(player):
		return false
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if not is_instance_valid(camera):
		camera = player.get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return false

	_active = true
	scare_rig.reparent(camera, false)
	scare_rig.position = Vector3(0.0, -0.18, -1.7)
	scare_rig.rotation = Vector3(0.04, 0.0, 0.0)
	scare_rig.scale = Vector3.ONE * 0.58
	scare_rig.visible = true
	screen_flash.color = Color(0.58, 0.015, 0.01, 0.34)
	screen_flash.visible = true
	sting.play()

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_EXPO)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(scare_rig, "position", Vector3(0.0, -0.2, -0.68), 0.11)
	tween.parallel().tween_property(scare_rig, "scale", Vector3.ONE * 1.08, 0.11)
	tween.tween_property(scare_rig, "rotation", Vector3(-0.03, 0.07, 0.045), 0.045)
	tween.tween_property(scare_rig, "rotation", Vector3(0.025, -0.065, -0.04), 0.045)
	tween.tween_property(scare_rig, "rotation", Vector3(-0.015, 0.035, 0.02), 0.055)
	tween.tween_interval(0.22)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(screen_flash, "color", Color(0.0, 0.0, 0.0, 0.0), 0.18)
	await tween.finished

	sting.stop()
	scare_rig.visible = false
	scare_rig.reparent(_home_parent, false)
	screen_flash.visible = false
	_active = false
	finished.emit()
	return true


func is_active() -> bool:
	return _active


func get_duration() -> float:
	return presentation_duration
