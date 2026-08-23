extends Node3D

const PLAYER_SCENE := preload("res://scenes/Player.tscn")

var _settings_layer: CanvasLayer
var _computer_spin: SpinBox
var _deck_spin: SpinBox
var _time_option: OptionButton
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _system_settings: Control = $Settings


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for node_name in ["Computer1", "Computer2", "Computer3", "Deck", "GameHud"]:
		var node := get_node_or_null(node_name)
		if node != null:
			node.queue_free()
	_pause_menu.hide()
	_system_settings.hide()
	_pause_menu.resume_requested.connect(_resume_waiting)
	_pause_menu.settings_requested.connect(_show_system_settings)
	_pause_menu.tutorial_requested.connect(_show_tutorial)
	_system_settings.back_requested.connect(_show_pause_menu)
	GameConfig.language_changed.connect(_reload_language)
	NetworkManager.peers_changed.connect(_sync_network_players)
	_build_prompt()
	_build_settings()
	_sync_network_players()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _settings_layer.visible:
			_set_settings_visible(false)
		elif _pause_menu.visible or _system_settings.visible:
			_resume_waiting()
		else:
			_show_pause_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_game_settings") and not _pause_menu.visible and not _system_settings.visible:
		_set_settings_visible(not _settings_layer.visible)
		get_viewport().set_input_as_handled()


func _build_settings() -> void:
	_settings_layer = CanvasLayer.new()
	_settings_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_settings_layer)

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.02, 0.02, 0.03, 0.9)
	_settings_layer.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 500)
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)
	content.add_child(_make_label(GameConfig.text("game_settings"), 40))
	var map_option := OptionButton.new()
	map_option.custom_minimum_size = Vector2(220, 48)
	map_option.add_item("Mansion")
	content.add_child(_make_row(GameConfig.text("map"), map_option))

	_computer_spin = _make_spin(0, 9, GameConfig.computer_count)
	content.add_child(_make_row(GameConfig.text("computers"), _computer_spin))
	_computer_spin.value_changed.connect(_on_computer_count_changed)

	_deck_spin = _make_spin(1, 300, GameConfig.deck_size)
	content.add_child(_make_row(GameConfig.text("deck_cards"), _deck_spin))

	_time_option = OptionButton.new()
	_time_option.custom_minimum_size = Vector2(220, 48)
	for minutes in GameConfig.TIME_OPTIONS:
		_time_option.add_item(GameConfig.text("minutes") % minutes, minutes)
		if minutes == GameConfig.time_limit_minutes:
			_time_option.select(_time_option.item_count - 1)
	content.add_child(_make_row(GameConfig.text("time_limit"), _time_option))

	var start_button := Button.new()
	start_button.custom_minimum_size = Vector2(0, 64)
	start_button.text = GameConfig.text("start_mansion")
	start_button.add_theme_font_size_override("font_size", 26)
	start_button.pressed.connect(_start_game)
	content.add_child(start_button)

	var close_label := _make_label("%s / Esc: %s" % [GameConfig.text("open_settings"), GameConfig.text("close_settings")], 18)
	content.add_child(close_label)
	_settings_layer.hide()


func _build_prompt() -> void:
	var prompt_layer := CanvasLayer.new()
	add_child(prompt_layer)
	var prompt := Label.new()
	prompt.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	prompt.position = Vector2(24, -64)
	prompt.size = Vector2(420, 44)
	prompt.text = "T: %s" % GameConfig.text("open_settings")
	prompt.add_theme_font_size_override("font_size", 24)
	prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt.add_theme_constant_override("shadow_offset_x", 2)
	prompt.add_theme_constant_override("shadow_offset_y", 2)
	prompt_layer.add_child(prompt)


func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	return label


func _make_spin(minimum: float, maximum: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.custom_minimum_size = Vector2(220, 48)
	return spin


func _make_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220, 48)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	row.add_child(label)
	row.add_child(control)
	return row


func _on_computer_count_changed(value: float) -> void:
	_deck_spin.value = GameConfig.default_deck_size_for_computers(int(value))


func _set_settings_visible(should_show: bool) -> void:
	if NetworkManager.is_online and not multiplayer.is_server():
		return
	_settings_layer.visible = should_show
	get_tree().paused = should_show
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if should_show else Input.MOUSE_MODE_CAPTURED)


func _show_pause_menu() -> void:
	get_tree().paused = true
	_system_settings.hide()
	_pause_menu.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _show_system_settings() -> void:
	_pause_menu.hide()
	_system_settings.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _resume_waiting() -> void:
	_pause_menu.hide()
	_system_settings.hide()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _show_tutorial() -> void:
	get_tree().paused = false
	GameConfig.tutorial_return_scene = scene_file_path
	get_tree().change_scene_to_file("res://scenes/Tutorial.tscn")


func _reload_language() -> void:
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")


func _start_game() -> void:
	if NetworkManager.is_online and not multiplayer.is_server():
		return
	GameConfig.computer_count = int(_computer_spin.value)
	GameConfig.deck_size = int(_deck_spin.value)
	GameConfig.time_limit_minutes = _time_option.get_item_id(_time_option.selected)
	get_tree().paused = false
	NetworkManager.start_game()


func _sync_network_players() -> void:
	$Player.set_multiplayer_authority(1)
	$Player.display_name = NetworkManager.get_player_name(1) if NetworkManager.is_online else GameConfig.player_name
	if $Player.has_method("set_body_color"):
		$Player.set_body_color(NetworkManager.get_player_color(1) if NetworkManager.is_online else GameConfig.player_color())
	for child in get_children():
		if child.name.begins_with("NetworkPlayer_"):
			var peer_id := int(child.name.trim_prefix("NetworkPlayer_"))
			if not NetworkManager.players.has(peer_id):
				child.queue_free()
	for peer_id in NetworkManager.players:
		if int(peer_id) == 1:
			continue
		var node_name := "NetworkPlayer_%d" % int(peer_id)
		if has_node(node_name):
			continue
		var remote_player: CharacterBody3D = PLAYER_SCENE.instantiate()
		remote_player.name = node_name
		remote_player.display_name = NetworkManager.get_player_name(int(peer_id))
		remote_player.set_multiplayer_authority(int(peer_id))
		add_child(remote_player)
		remote_player.set_body_color(NetworkManager.get_player_color(int(peer_id)))
		remote_player.global_position = Vector3((int(peer_id) % 5) * 3.0 - 6.0, 0.0, 4.0)

