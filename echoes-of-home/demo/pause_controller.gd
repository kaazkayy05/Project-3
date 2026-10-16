extends Node

var overlay: CanvasLayer
var unpause_button: Button
var click_sound: AudioStreamPlayer
var previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	click_sound = AudioStreamPlayer.new()
	click_sound.stream = preload("res://demo/audio/menu-click.mp3")
	add_child(click_sound)
	overlay = CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.7)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	unpause_button = Button.new()
	unpause_button.text = "Unpause"
	unpause_button.custom_minimum_size = Vector2(200, 60)
	center.add_child(unpause_button)
	unpause_button.pressed.connect(_on_unpause_pressed)
	overlay.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			var scene := get_tree().current_scene
			if scene == null or scene.scene_file_path != "res://demo/house_demo.tscn":
				return
			get_viewport().set_input_as_handled()
			_set_paused(not get_tree().paused)

func _set_paused(paused: bool) -> void:
	if paused:
		previous_mouse_mode = Input.mouse_mode
	get_tree().paused = paused
	overlay.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else previous_mouse_mode
	if paused:
		unpause_button.grab_focus()

func _on_unpause_pressed() -> void:
	click_sound.play()
	_set_paused(false)
