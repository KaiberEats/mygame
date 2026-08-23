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
var _eos_status_label: Label
var _eos_credential_edit: LineEdit
var _eos_login_button: Button
var _open_lobby_button: Button
var _port_spin: SpinBox
var _host_button: Button
var _address_edit: LineEdit
var _join_button: Button
var _mode_back_button: Button
var _lobby_menu: VBoxContainer
var _lobby_title: Label
var _room_name_edit: LineEdit
var _create_lobby_button: Button
var _lobby_results: OptionButton
var _search_lobby_button: Button
var _join_lobby_button: Button
var _leave_lobby_button: Button
var _lobby_status_label: Label
var _lobby_back_button: Button
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
	_build_lobby_menu()
	_connect_eos_signals()
	_connect_lobby_signals()
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
	if _lobby_menu != null:
		_lobby_menu.add_theme_constant_override("separation", roundi(14.0 * layout_scale))
	for button in [_game_start_button, _tutorial_button, _settings_button, _quit_button]:
		if button != null:
			button.custom_minimum_size = Vector2(240.0, 56.0) * layout_scale
			button.add_theme_font_size_override("font_size", roundi(28.0 * layout_scale))
	if _single_button != null:
		for control in [_single_button, _eos_login_button, _host_button, _join_button, _mode_back_button]:
			control.custom_minimum_size = Vector2(300.0, 56.0) * layout_scale
			control.add_theme_font_size_override("font_size", roundi(24.0 * layout_scale))
		_eos_credential_edit.custom_minimum_size = Vector2(300.0, 44.0) * layout_scale
		_eos_status_label.add_theme_font_size_override("font_size", roundi(18.0 * layout_scale))
		_open_lobby_button.custom_minimum_size = Vector2(300.0, 56.0) * layout_scale
		_port_spin.custom_minimum_size = Vector2(300.0, 44.0) * layout_scale
		_address_edit.custom_minimum_size = Vector2(300.0, 44.0) * layout_scale
		_mode_title.add_theme_font_size_override("font_size", roundi(42.0 * layout_scale))
	if _lobby_menu != null:
		_lobby_title.add_theme_font_size_override("font_size", roundi(38.0 * layout_scale))
		_room_name_edit.custom_minimum_size = Vector2(320.0, 44.0) * layout_scale
		_lobby_results.custom_minimum_size = Vector2(320.0, 44.0) * layout_scale
		for control in [_create_lobby_button, _search_lobby_button, _join_lobby_button, _leave_lobby_button, _lobby_back_button]:
			control.custom_minimum_size = Vector2(320.0, 50.0) * layout_scale
			control.add_theme_font_size_override("font_size", roundi(22.0 * layout_scale))
		_lobby_status_label.add_theme_font_size_override("font_size", roundi(17.0 * layout_scale))


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

	_eos_status_label = Label.new()
	_eos_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eos_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_eos_status_label.custom_minimum_size = Vector2(300, 44)
	_eos_status_label.add_theme_font_size_override("font_size", 18)
	_mode_menu.add_child(_eos_status_label)

	_eos_credential_edit = LineEdit.new()
	_eos_credential_edit.custom_minimum_size = Vector2(300, 44)
	_eos_credential_edit.placeholder_text = "Credential Name"
	_eos_credential_edit.text = "joker_test_1"
	_eos_credential_edit.text_submitted.connect(func(_value: String) -> void: _login_with_eos_devtool())
	_mode_menu.add_child(_eos_credential_edit)

	_eos_login_button = Button.new()
	_eos_login_button.custom_minimum_size = Vector2(300, 56)
	_eos_login_button.pressed.connect(_login_with_eos_devtool)
	_mode_menu.add_child(_eos_login_button)
	_open_lobby_button = Button.new()
	_open_lobby_button.custom_minimum_size = Vector2(300, 56)
	_open_lobby_button.pressed.connect(_show_lobby_menu)
	_mode_menu.add_child(_open_lobby_button)
	_refresh_eos_status()

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


func _build_lobby_menu() -> void:
	_lobby_menu = VBoxContainer.new()
	_lobby_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	_lobby_menu.add_theme_constant_override("separation", 14)
	_menu_host.add_child(_lobby_menu)

	_lobby_title = Label.new()
	_lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_title.add_theme_font_size_override("font_size", 38)
	_lobby_menu.add_child(_lobby_title)

	_lobby_status_label = Label.new()
	_lobby_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_status_label.custom_minimum_size = Vector2(320, 54)
	_lobby_menu.add_child(_lobby_status_label)

	_room_name_edit = LineEdit.new()
	_room_name_edit.text = "Joker Room"
	_room_name_edit.max_length = 32
	_room_name_edit.custom_minimum_size = Vector2(320, 44)
	_lobby_menu.add_child(_room_name_edit)

	_create_lobby_button = Button.new()
	_create_lobby_button.custom_minimum_size = Vector2(320, 50)
	_create_lobby_button.pressed.connect(_create_eos_lobby)
	_lobby_menu.add_child(_create_lobby_button)

	_search_lobby_button = Button.new()
	_search_lobby_button.custom_minimum_size = Vector2(320, 50)
	_search_lobby_button.pressed.connect(_search_eos_lobbies)
	_lobby_menu.add_child(_search_lobby_button)

	_lobby_results = OptionButton.new()
	_lobby_results.custom_minimum_size = Vector2(320, 44)
	_lobby_menu.add_child(_lobby_results)

	_join_lobby_button = Button.new()
	_join_lobby_button.custom_minimum_size = Vector2(320, 50)
	_join_lobby_button.pressed.connect(_join_selected_eos_lobby)
	_lobby_menu.add_child(_join_lobby_button)

	_leave_lobby_button = Button.new()
	_leave_lobby_button.custom_minimum_size = Vector2(320, 50)
	_leave_lobby_button.pressed.connect(_leave_eos_lobby)
	_lobby_menu.add_child(_leave_lobby_button)

	_lobby_back_button = Button.new()
	_lobby_back_button.custom_minimum_size = Vector2(320, 50)
	_lobby_back_button.pressed.connect(_show_mode_menu)
	_lobby_menu.add_child(_lobby_back_button)
	_lobby_menu.hide()
	_refresh_lobby_ui()


func _connect_lobby_signals() -> void:
	EOSLobbyManager.lobby_changed.connect(_refresh_lobby_ui)
	EOSLobbyManager.search_completed.connect(_on_lobby_search_completed)
	EOSLobbyManager.operation_failed.connect(_on_lobby_operation_failed)
	_refresh_lobby_ui()


func _create_eos_lobby() -> void:
	_set_lobby_controls_enabled(false)
	_lobby_status_label.text = _eos_text("Lobbyを作成中...", "Creating lobby...")
	var succeeded := await EOSLobbyManager.create_lobby_async(_room_name_edit.text)
	if not succeeded:
		_set_lobby_controls_enabled(true)
	_refresh_lobby_ui()


func _search_eos_lobbies() -> void:
	_set_lobby_controls_enabled(false)
	_lobby_status_label.text = _eos_text("Lobbyを検索中...", "Searching for lobbies...")
	await EOSLobbyManager.search_lobbies_async()
	_set_lobby_controls_enabled(true)
	_refresh_lobby_ui()


func _join_selected_eos_lobby() -> void:
	if _lobby_results.item_count == 0:
		_on_lobby_operation_failed(_eos_text("参加できるLobbyがありません。", "No lobby is available to join."))
		return
	_set_lobby_controls_enabled(false)
	_lobby_status_label.text = _eos_text("Lobbyへ参加中...", "Joining lobby...")
	var succeeded := await EOSLobbyManager.join_lobby_async(_lobby_results.selected)
	if not succeeded:
		_set_lobby_controls_enabled(true)
	_refresh_lobby_ui()


func _leave_eos_lobby() -> void:
	_set_lobby_controls_enabled(false)
	_lobby_status_label.text = _eos_text("Lobbyから退出中...", "Leaving lobby...")
	var succeeded := await EOSLobbyManager.leave_lobby_async()
	if not succeeded:
		_set_lobby_controls_enabled(true)
	_refresh_lobby_ui()


func _on_lobby_search_completed(lobbies: Array[HLobby]) -> void:
	_lobby_results.clear()
	for lobby in lobbies:
		_lobby_results.add_item(EOSLobbyManager.lobby_summary(lobby))
	if lobbies.is_empty():
		_lobby_status_label.text = _eos_text("公開Lobbyは見つかりませんでした。", "No public lobby found.")
	else:
		_lobby_status_label.text = _eos_text(
			"%d件のLobbyが見つかりました。" % lobbies.size(),
			"Found %d lobby/lobbies." % lobbies.size()
		)


func _on_lobby_operation_failed(message: String) -> void:
	if _lobby_status_label == null:
		return
	_lobby_status_label.text = message
	_lobby_status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_set_lobby_controls_enabled(true)


func _refresh_lobby_ui() -> void:
	if _lobby_status_label == null:
		return
	var in_lobby := EOSLobbyManager.is_in_lobby()
	if in_lobby:
		_lobby_status_label.text = _eos_text(
			"参加中: %s (%d人)" % [EOSLobbyManager.current_room_name(), EOSLobbyManager.current_member_count()],
			"Joined: %s (%d members)" % [EOSLobbyManager.current_room_name(), EOSLobbyManager.current_member_count()]
		)
		_lobby_status_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
	else:
		_lobby_status_label.text = _eos_text("Lobby未参加", "Not in a lobby")
		_lobby_status_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	_set_lobby_controls_enabled(not EOSLobbyManager.is_busy)
	_create_lobby_button.disabled = in_lobby or EOSLobbyManager.is_busy
	_join_lobby_button.disabled = in_lobby or EOSLobbyManager.is_busy or _lobby_results.item_count == 0
	_leave_lobby_button.disabled = not in_lobby or EOSLobbyManager.is_busy


func _set_lobby_controls_enabled(is_enabled: bool) -> void:
	_room_name_edit.editable = is_enabled
	_create_lobby_button.disabled = not is_enabled
	_search_lobby_button.disabled = not is_enabled
	_lobby_results.disabled = not is_enabled
	_join_lobby_button.disabled = not is_enabled
	_leave_lobby_button.disabled = not is_enabled


func _connect_eos_signals() -> void:
	EOSManager.initialization_completed.connect(_on_eos_initialization_completed)
	EOSManager.initialization_failed.connect(_on_eos_initialization_failed)
	EOSManager.login_completed.connect(_on_eos_login_completed)
	EOSManager.login_failed.connect(_on_eos_login_failed)
	_refresh_eos_status()


func _login_with_eos_devtool() -> void:
	if EOSManager.is_logged_in:
		_refresh_eos_status()
		return
	var credential_name := _eos_credential_edit.text.strip_edges()
	if credential_name.is_empty():
		_eos_status_label.text = _eos_text(
			"Credential Nameを入力してください。",
			"Enter a Credential Name."
		)
		return
	_set_eos_controls_enabled(false)
	_eos_status_label.text = _eos_text("EOSへログイン中...", "Logging in to EOS...")
	var succeeded := await EOSManager.login_with_devtool_async(credential_name)
	if not succeeded:
		_set_eos_controls_enabled(true)


func _refresh_eos_status() -> void:
	if _eos_status_label == null:
		return
	if EOSManager.is_logged_in:
		_eos_status_label.text = _eos_text("EOS: ログイン済み", "EOS: Logged in")
		_eos_status_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
		_set_eos_controls_enabled(false)
	elif EOSManager.is_initialized:
		_eos_status_label.text = _eos_text("EOS: 初期化完了", "EOS: Ready")
		_eos_status_label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		_set_eos_controls_enabled(true)
	elif EOSManager.initialization_has_failed:
		_eos_status_label.text = _eos_text("EOS初期化失敗", "EOS initialization failed") + ": " + EOSManager.last_error
		_eos_status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		_set_eos_controls_enabled(false)
	else:
		_eos_status_label.text = _eos_text("EOS: 初期化中...", "EOS: Initializing...")
		_eos_status_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		_set_eos_controls_enabled(false)


func _set_eos_controls_enabled(is_enabled: bool) -> void:
	if _eos_credential_edit != null:
		_eos_credential_edit.editable = not EOSManager.is_logged_in
	if _eos_login_button != null:
		_eos_login_button.disabled = not is_enabled
	if _open_lobby_button != null:
		_open_lobby_button.disabled = not EOSManager.is_logged_in


func _on_eos_initialization_completed() -> void:
	_refresh_eos_status()


func _on_eos_initialization_failed(message: String) -> void:
	_eos_status_label.text = _eos_text("EOS初期化失敗", "EOS initialization failed") + ": " + message
	_eos_status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_set_eos_controls_enabled(false)


func _on_eos_login_completed(_product_user_id: String) -> void:
	_refresh_eos_status()
	_refresh_lobby_ui()


func _on_eos_login_failed(message: String) -> void:
	_eos_status_label.text = _eos_text("EOSログイン失敗", "EOS login failed") + ": " + message
	_eos_status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_set_eos_controls_enabled(true)


func _eos_text(japanese: String, english: String) -> String:
	return japanese if GameConfig.language == "ja" else english


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
	_lobby_menu.hide()
	_mode_menu.show()
	_refresh_lobby_ui()


func _show_lobby_menu() -> void:
	if not EOSManager.is_logged_in:
		return
	_main_menu.hide()
	_mode_menu.hide()
	_lobby_menu.show()
	_refresh_lobby_ui()


func _show_main_menu() -> void:
	_mode_menu.hide()
	_lobby_menu.hide()
	_main_menu.show()


func _update_language() -> void:
	_game_start_button.text = GameConfig.text("game_start")
	_tutorial_button.text = GameConfig.text("tutorial")
	_settings_button.text = GameConfig.text("settings")
	_quit_button.text = GameConfig.text("quit_game")
	_mode_title.text = GameConfig.text("select_mode")
	_single_button.text = GameConfig.text("single_play")
	_eos_login_button.text = _eos_text("EOS開発ログイン", "EOS Developer Login")
	_open_lobby_button.text = _eos_text("EOS Lobbyテスト", "EOS Lobby Test")
	_eos_credential_edit.placeholder_text = "Credential Name"
	_port_spin.prefix = GameConfig.text("port")
	_host_button.text = GameConfig.text("host_server")
	_address_edit.placeholder_text = GameConfig.text("server_ip")
	_join_button.text = GameConfig.text("join_server")
	_mode_back_button.text = GameConfig.text("back")
	_lobby_title.text = _eos_text("EOS Lobby", "EOS Lobby")
	_room_name_edit.placeholder_text = _eos_text("部屋名", "Room name")
	_create_lobby_button.text = _eos_text("部屋を作る", "Create Lobby")
	_search_lobby_button.text = _eos_text("部屋を探す", "Search Lobbies")
	_join_lobby_button.text = _eos_text("選択した部屋に参加", "Join Selected Lobby")
	_leave_lobby_button.text = _eos_text("退出 / 部屋を解散", "Leave / Destroy Lobby")
	_lobby_back_button.text = GameConfig.text("back")
	_refresh_eos_status()
	_refresh_lobby_ui()
