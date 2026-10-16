extends Control

var click_sound: AudioStreamPlayer
var play_button: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	click_sound = AudioStreamPlayer.new()
	click_sound.stream = preload("res://demo/audio/menu-click.mp3")
	add_child(click_sound)
	var background := ColorRect.new()
	background.color = Color("#090a0d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# Keep the complete menu in one reference frame, including its input areas.
	var menu := Control.new()
	menu.size = Vector2(1280, 720)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu)

	var content := VBoxContainer.new()
	content.position = Vector2(64, 140)
	content.size = Vector2(680, 440)
	content.add_theme_constant_override("separation", 24)
	menu.add_child(content)

	var title := Label.new()
	title.position = Vector2(64, 40)
	title.size = Vector2(1152, 60)
	title.text = "ECHOES OF HOME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("#b97979"))
	menu.add_child(title)

	var story := Label.new()
	story.text = "You're trapped inside your childhood home. The rooms are familiar, but something feels terribly wrong.\n\nSomething followed you inside.\n\nStay quiet. Find a way out."
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.add_theme_font_size_override("font_size", 20)
	story.add_theme_color_override("font_color", Color("#d8d3cc"))
	story.add_theme_constant_override("line_spacing", 2)
	content.add_child(story)

	var how_to_see := VBoxContainer.new()
	how_to_see.add_theme_constant_override("separation", 8)
	content.add_child(how_to_see)

	var see_heading := Label.new()
	see_heading.text = "HOW TO SEE"
	see_heading.add_theme_font_size_override("font_size", 22)
	see_heading.add_theme_color_override("font_color", Color("#b97979"))
	how_to_see.add_child(see_heading)

	var explanation := Label.new()
	explanation.text = "You're surrounded by darkness. Press Space to send out an echo pulse that briefly reveals nearby walls and objects, helping you navigate your childhood home.\n\nYour echo pulses have limited charges that replenish over time. Use them wisely."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_font_size_override("font_size", 20)
	explanation.add_theme_color_override("font_color", Color("#d8d3cc"))
	explanation.add_theme_constant_override("line_spacing", 2)
	how_to_see.add_child(explanation)

	var controls := VBoxContainer.new()
	controls.position = Vector2(800, 140)
	controls.size = Vector2(416, 440)
	controls.add_theme_constant_override("separation", 16)
	menu.add_child(controls)

	var heading := Label.new()
	heading.text = "CONTROLS"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color("#b97979"))
	controls.add_child(heading)

	for text in [
		"WASD — Move",
		"Mouse — Look around",
		"Space — Echo pulse",
		"E — Interact",
		"Shift — Sprint",
		"Right Click — Hold Breath",
		"Esc — Pause / Resume",
	]:
		var row := Label.new()
		row.text = text
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 20)
		row.add_theme_color_override("font_color", Color("#bcb8b2"))
		controls.add_child(row)

	var center := CenterContainer.new()
	center.position = Vector2(64, 604)
	center.size = Vector2(1152, 60)
	menu.add_child(center)
	play_button = Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = Vector2(200, 60)
	play_button.add_theme_font_size_override("font_size", 22)
	center.add_child(play_button)

	resized.connect(_resize_menu.bind(menu))
	_resize_menu(menu)
	play_button.pressed.connect(_on_play_pressed)
	play_button.grab_focus()

func _resize_menu(menu: Control) -> void:
	var reference_size := Vector2(1280, 720)
	var fit_scale := minf(
		size.x / reference_size.x,
		size.y / reference_size.y
	)
	menu.scale = Vector2.ONE * fit_scale
	menu.position = (size - reference_size * fit_scale) * 0.5

func _on_play_pressed() -> void:
	play_button.disabled = true
	click_sound.play()
	await click_sound.finished
	var error := get_tree().change_scene_to_file("res://demo/house_demo.tscn")
	if error != OK:
		push_error("Could not load house_demo.tscn: %s" % error_string(error))
		play_button.disabled = false
