extends Control

var _main_menu: VBoxContainer
var _mode_menu: VBoxContainer
var _game_start_button: Button
var _tutorial_button: Button
var _settings_button: Button
var _quit_button: Button
var _mode_title: Label
var _single_button: Button
var _port_spin: SpinBox
var _host_button: Button
var _address_edit: LineEdit
var _join_button: Button
var _mode_back_button: Button


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	NetworkManager.close()
	_main_menu = $CenterContainer/VBoxContainer
	_game_start_button = _main_menu.get_node("GameStartButton")
	_game_start_button.pressed.connect(_show_mode_menu)
	_tutorial_button = Button.new()
	_tutorial_button.custom_minimum_size = Vector2(240, 64)
	_tutorial_button.add_theme_font_size_override("font_size", 28)
	_tutorial_button.pressed.connect(func() -> void:
		GameConfig.tutorial_return_scene = "res://scenes/Title.tscn"
		get_tree().change_scene_to_file("res://scenes/Tutorial.tscn")
	)
	_main_menu.add_child(_tutorial_button)
	_build_settings_button()
	_build_mode_menu()
	GameConfig.language_changed.connect(_update_language)
	_update_language()


func _start_single_player() -> void:
	NetworkManager.close()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _build_mode_menu() -> void:
	_mode_menu = VBoxContainer.new()
	_mode_menu.add_theme_constant_override("separation", 20)
	_mode_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	$CenterContainer.add_child(_mode_menu)

	_mode_title = Label.new()
	_mode_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_title.add_theme_font_size_override("font_size", 42)
	_mode_menu.add_child(_mode_title)

	_single_button = Button.new()
	_single_button.custom_minimum_size = Vector2(300, 60)
	_single_button.pressed.connect(_start_single_player)
	_mode_menu.add_child(_single_button)

	_port_spin = SpinBox.new()
	_port_spin.name = "Port"
	_port_spin.min_value = 1024
	_port_spin.max_value = 65535
	_port_spin.value = 7000
	_port_spin.custom_minimum_size = Vector2(300, 44)
	_mode_menu.add_child(_port_spin)
	_host_button = Button.new()
	_host_button.custom_minimum_size = Vector2(300, 56)
	_host_button.pressed.connect(func() -> void:
		if NetworkManager.host(int(_port_spin.value)) == OK:
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
	)
	_mode_menu.add_child(_host_button)
	_address_edit = LineEdit.new()
	_address_edit.name = "Address"
	_address_edit.text = "127.0.0.1"
	_address_edit.custom_minimum_size = Vector2(300, 44)
	_mode_menu.add_child(_address_edit)
	_join_button = Button.new()
	_join_button.custom_minimum_size = Vector2(300, 56)
	_join_button.pressed.connect(func() -> void: NetworkManager.join(_address_edit.text, int(_port_spin.value)))
	_mode_menu.add_child(_join_button)

	_mode_back_button = Button.new()
	_mode_back_button.custom_minimum_size = Vector2(300, 52)
	_mode_back_button.pressed.connect(_show_main_menu)
	_mode_menu.add_child(_mode_back_button)
	_mode_menu.hide()


func _build_settings_button() -> void:
	_settings_button = Button.new()
	_settings_button.custom_minimum_size = Vector2(240, 56)
	_settings_button.pressed.connect(_open_settings)
	_main_menu.add_child(_settings_button)
	_quit_button = Button.new()
	_quit_button.custom_minimum_size = Vector2(240, 56)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_main_menu.add_child(_quit_button)


func _open_settings() -> void:
	var settings := preload("res://scenes/Settings.tscn").instantiate()
	add_child(settings)
	settings.back_requested.connect(settings.queue_free)


func _show_mode_menu() -> void:
	_main_menu.hide()
	_mode_menu.show()


func _show_main_menu() -> void:
	_mode_menu.hide()
	_main_menu.show()


func _update_language() -> void:
	_game_start_button.text = GameConfig.text("game_start")
	_tutorial_button.text = GameConfig.text("tutorial")
	_settings_button.text = GameConfig.text("settings")
	_quit_button.text = GameConfig.text("quit_game")
	_mode_title.text = GameConfig.text("select_mode")
	_single_button.text = GameConfig.text("single_play")
	_port_spin.prefix = GameConfig.text("port")
	_host_button.text = GameConfig.text("host_server")
	_address_edit.placeholder_text = GameConfig.text("server_ip")
	_join_button.text = GameConfig.text("join_server")
	_mode_back_button.text = GameConfig.text("back")
