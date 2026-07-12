extends Control

const JOKER_TEXTURE := preload("res://assets/seprite/baba_joker.png")
const JOKER_GIF_FRAME_COUNT := 14
const JOKER_GIF_FRAME_TEMPLATE := "res://assets/seprite/baba_joker_gif_frames/frame_%02d.png"

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
var _title_layout: BoxContainer
var _image_area: Control
var _title_label: Label
var _menu_host: VBoxContainer
var _joker_button: TextureButton
var _joker_timer: Timer
var _joker_frames: Array[Texture2D] = []
var _joker_frame_index := 0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	NetworkManager.close()
	_setup_title_layout()
	_main_menu = _menu_host.get_node("VBoxContainer")
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
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_update_language()
	_apply_responsive_layout()


func _setup_title_layout() -> void:
	$Background.color = Color.BLACK
	var center := $CenterContainer
	var existing_menu := center.get_node("VBoxContainer") as VBoxContainer
	center.remove_child(existing_menu)

	_title_layout = HBoxContainer.new()
	_title_layout.name = "TitleLayout"
	_title_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_title_layout)

	_image_area = Control.new()
	_title_layout.add_child(_image_area)

	_joker_button = TextureButton.new()
	_joker_button.texture_normal = JOKER_TEXTURE
	_joker_button.texture_hover = JOKER_TEXTURE
	_joker_button.texture_pressed = JOKER_TEXTURE
	_joker_button.ignore_texture_size = true
	_joker_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_joker_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_joker_button.pressed.connect(_play_joker_gif)
	_image_area.add_child(_joker_button)

	_menu_host = VBoxContainer.new()
	_menu_host.name = "MenuHost"
	_menu_host.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_layout.add_child(_menu_host)

	existing_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_host.add_child(existing_menu)
	_title_label = existing_menu.get_node("TitleLabel") as Label
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.add_theme_color_override("font_shadow_color", Color(0.6, 0.0, 0.0))
	_title_label.add_theme_constant_override("shadow_offset_x", 4)
	_title_label.add_theme_constant_override("shadow_offset_y", 4)

	_joker_timer = Timer.new()
	_joker_timer.wait_time = 0.14
	_joker_timer.timeout.connect(_advance_joker_gif)
	add_child(_joker_timer)


func _apply_responsive_layout() -> void:
	if _title_layout == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var layout_scale := clampf(minf(viewport_size.x / 1280.0, viewport_size.y / 720.0), 0.55, 1.65)
	var is_narrow := viewport_size.x < 820.0 or viewport_size.x < viewport_size.y
	var parent := _title_layout.get_parent()
	var old_index := _title_layout.get_index()
	var old_layout := _title_layout
	var children := _title_layout.get_children()
	for child in children:
		old_layout.remove_child(child)
	parent.remove_child(old_layout)
	if is_narrow:
		_title_layout = VBoxContainer.new()
	else:
		_title_layout = HBoxContainer.new()
	_title_layout.name = "TitleLayout"
	_title_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_layout.add_theme_constant_override("separation", roundi((28.0 if is_narrow else 72.0) * layout_scale))
	parent.add_child(_title_layout)
	parent.move_child(_title_layout, old_index)
	for child in children:
		_title_layout.add_child(child)
	old_layout.queue_free()

	var image_size := Vector2(430.0, 360.0) * layout_scale if is_narrow else Vector2(520.0, 560.0) * layout_scale
	var menu_size := Vector2(330.0, 330.0) * layout_scale if is_narrow else Vector2(360.0, 560.0) * layout_scale
	_image_area.custom_minimum_size = image_size
	_menu_host.custom_minimum_size = menu_size
	_title_label.add_theme_font_size_override("font_size", roundi((72.0 if is_narrow else 96.0) * layout_scale))
	_main_menu.add_theme_constant_override("separation", roundi(28.0 * layout_scale))
	if _mode_menu != null:
		_mode_menu.add_theme_constant_override("separation", roundi(18.0 * layout_scale))
	for button in [_game_start_button, _tutorial_button, _settings_button, _quit_button]:
		if button != null:
			button.custom_minimum_size = Vector2(240.0, 56.0) * layout_scale
			button.add_theme_font_size_override("font_size", roundi(28.0 * layout_scale))
	if _single_button != null:
		for control in [_single_button, _host_button, _join_button, _mode_back_button]:
			control.custom_minimum_size = Vector2(300.0, 56.0) * layout_scale
			control.add_theme_font_size_override("font_size", roundi(24.0 * layout_scale))
		_port_spin.custom_minimum_size = Vector2(300.0, 44.0) * layout_scale
		_address_edit.custom_minimum_size = Vector2(300.0, 44.0) * layout_scale
		_mode_title.add_theme_font_size_override("font_size", roundi(42.0 * layout_scale))


func _start_single_player() -> void:
	NetworkManager.close()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _build_mode_menu() -> void:
	_mode_menu = VBoxContainer.new()
	_mode_menu.add_theme_constant_override("separation", 20)
	_mode_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_host.add_child(_mode_menu)

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


func _load_joker_gif_frames() -> void:
	if not _joker_frames.is_empty():
		return
	for index in range(JOKER_GIF_FRAME_COUNT):
		var image := Image.new()
		if image.load(JOKER_GIF_FRAME_TEMPLATE % index) != OK:
			continue
		_joker_frames.append(ImageTexture.create_from_image(image))


func _play_joker_gif() -> void:
	_load_joker_gif_frames()
	if _joker_frames.is_empty():
		return
	_joker_frame_index = 0
	_joker_button.texture_normal = _joker_frames[_joker_frame_index]
	_joker_button.texture_hover = _joker_frames[_joker_frame_index]
	_joker_button.texture_pressed = _joker_frames[_joker_frame_index]
	_joker_timer.start()


func _advance_joker_gif() -> void:
	if _joker_frames.is_empty():
		_joker_timer.stop()
		return
	_joker_frame_index += 1
	if _joker_frame_index >= _joker_frames.size():
		_joker_timer.stop()
		_joker_button.texture_normal = JOKER_TEXTURE
		_joker_button.texture_hover = JOKER_TEXTURE
		_joker_button.texture_pressed = JOKER_TEXTURE
		return
	var texture := _joker_frames[_joker_frame_index]
	_joker_button.texture_normal = texture
	_joker_button.texture_hover = texture
	_joker_button.texture_pressed = texture


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
