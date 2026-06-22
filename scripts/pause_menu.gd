extends CanvasLayer

signal resume_requested
signal settings_requested
signal tutorial_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Root/LeftPanel/ButtonList/ResumeButton.pressed.connect(_on_resume_pressed)
	$Root/LeftPanel/ButtonList/SettingsButton.pressed.connect(_on_settings_pressed)
	$Root/LeftPanel/ButtonList/TitleButton.pressed.connect(_on_title_pressed)
	var tutorial_button := Button.new()
	tutorial_button.name = "TutorialButton"
	tutorial_button.custom_minimum_size = Vector2(0, 56)
	tutorial_button.add_theme_font_size_override("font_size", 24)
	tutorial_button.pressed.connect(func() -> void: tutorial_requested.emit())
	$Root/LeftPanel/ButtonList.add_child(tutorial_button)
	$Root/LeftPanel/ButtonList.move_child(tutorial_button, 2)
	GameConfig.language_changed.connect(_update_text)
	_update_text()


func _update_text() -> void:
	$Root/LeftPanel/ButtonList/ResumeButton.text = GameConfig.text("resume")
	$Root/LeftPanel/ButtonList/SettingsButton.text = GameConfig.text("settings")
	$Root/LeftPanel/ButtonList/TutorialButton.text = GameConfig.text("tutorial")
	$Root/LeftPanel/ButtonList/TitleButton.text = GameConfig.text("title")


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_title_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Title.tscn")
