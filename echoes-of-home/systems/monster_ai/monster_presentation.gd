class_name MonsterPresentation
extends Node3D

## Presentation-only animation. This node reads the owning Monster AI state but
## never writes behavior, movement, collision, navigation, or hearing values.

@export var body_material: ShaderMaterial
@export var idle_bob_height := 0.025
@export var idle_bob_speed := 1.7

@onready var body_root: Node3D = get_node("BodyRoot")
@onready var head: MeshInstance3D = get_node("BodyRoot/Head")
@onready var left_arm: MeshInstance3D = get_node("BodyRoot/LeftArm")
@onready var right_arm: MeshInstance3D = get_node("BodyRoot/RightArm")
@onready var eyes: Node3D = get_node("BodyRoot/Eyes")

var _elapsed := 0.0
var _left_arm_base := Vector3.ZERO
var _right_arm_base := Vector3.ZERO


func _ready() -> void:
	_left_arm_base = left_arm.rotation
	_right_arm_base = right_arm.rotation


func _process(delta: float) -> void:
	_elapsed += delta
	var monster := get_parent() as MonsterAI
	var threat := 0.0
	if is_instance_valid(monster):
		match monster.monster_state:
			MonsterAI.State.HUNTING:
				threat = 1.0
			MonsterAI.State.INVESTIGATING:
				threat = 0.45
			_:
				threat = 0.12

	body_root.position.y = sin(_elapsed * idle_bob_speed) * idle_bob_height
	head.rotation.z = sin(_elapsed * 1.13) * 0.035
	left_arm.rotation = _left_arm_base + Vector3(0.0, 0.0, sin(_elapsed * 1.4) * 0.035)
	right_arm.rotation = _right_arm_base + Vector3(0.0, 0.0, -sin(_elapsed * 1.4) * 0.035)
	var eye_pulse := 0.92 + sin(_elapsed * (5.0 + threat * 4.0)) * 0.08
	eyes.scale = Vector3.ONE * eye_pulse
	if is_instance_valid(body_material):
		body_material.set_shader_parameter("threat", threat)

