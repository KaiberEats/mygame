extends Control

signal back_requested

const WINDOWED_SIZE := Vector2i(1280, 720)
const SCREEN_OPTIONS := ["Windowed", "Fullscreen", "Borderless"]
const REBINDABLE_ACTIONS := {
	"move_forward": "Move Forward",
	"move_back": "Move Back",
	"move_left": "Move Left",
	"move_right": "Move Right",
	"jump": "Jump",
	"open_game_settings": "Game Settings",
	"hand_editor": "Hand Editor",
	"use_item": "Use Item",
	"pair_1": "Pair 1",
	"pair_2": "Pair 2",
	"pair_3": "Pair 3",
	"pair_4": "Pair 4",
}

@onready var content: VBoxContainer = $CenterContainer/Panel/VBoxContainer
@onready var title_label: Label = $CenterContainer/Panel/VBoxContainer/TitleLabel
@onready var screen_row: HBoxContainer = $CenterContainer/Panel/VBoxContainer/ScreenRow
@onready var screen_label: Label = $CenterContainer/Panel/VBoxContainer/ScreenRow/ScreenLabel
@onready var screen_value: Label = $CenterContainer/Panel/VBoxContainer/ScreenRow/Selector/ScreenValue
@onready var left_button: Button = $CenterContainer/Panel/VBoxContainer/ScreenRow/Selector/LeftButton
@onready var right_button: Button = $CenterContainer/Panel/VBoxContainer/ScreenRow/Selector/RightButton
@onready var back_button: Button = $CenterContainer/Panel/VBoxContainer/BackButton

var _screen_index := 0
var _saved_screen_index := 0
var _display_button: Button
var _controls_button: Button
var _controls_scroll: ScrollContainer
var _language_row: HBoxContainer
var _binding_buttons: Dictionary = {}
var _pending_bindings: Dictionary = {}
var _waiting_action := ""
var _language_option: OptionButton
var _name_edit: LineEdit
var _color_row: HBoxContainer
var _color_option: OptionButton
var _ui_size_row: HBoxContainer
var _ui_size_slider: HSlider
var _ui_size_value: Label
var _save_button: Button
var _pending_language := ""
var _pending_player_name := ""
var _pending_player_color_name := ""
var _pending_ui_size_percent := 50


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	content.add_theme_constant_override("separation", 12)
	title_label.add_theme_font_size_override("font_size", 36)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_sync_screen_index()
	_saved_screen_index = _screen_index
	_pending_language = GameConfig.language
	_pending_player_name = GameConfig.player_name
	_pending_player_color_name = GameConfig.player_color_name
	_pending_ui_size_percent = GameConfig.ui_size_percent
	_capture_pending_bindings()
	_update_screen_label()
	_build_page_tabs()
	_build_language_row()
	_build_name_row()
	_build_color_row()
	_build_ui_size_row()
	_build_controls_page()
	_build_save_button()
	left_button.pressed.connect(_change_screen_option.bind(-1))
	right_button.pressed.connect(_change_screen_option.bind(1))
	back_button.pressed.connect(_on_back_pressed)
	GameConfig.language_changed.connect(_update_language)
	_update_language()
	_show_display_page()


func _unhandled_input(event: InputEvent) -> void:
	if not _waiting_action.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				_waiting_action = ""
				_refresh_binding_labels()
			else:
				_apply_binding(_waiting_action, event)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left") and screen_row.visible:
		_change_screen_option(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") and screen_row.visible:
		_change_screen_option(1)
		get_viewport().set_input_as_handled()


func _build_page_tabs() -> void:
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 16)
	content.add_child(tabs)
	content.move_child(tabs, 1)
	_display_button = Button.new()
	_display_button.text = "Display"
	_display_button.custom_minimum_size = Vector2(180, 48)
	_display_button.pressed.connect(_show_display_page)
	tabs.add_child(_display_button)
	_controls_button = Button.new()
	_controls_button.text = "Key Controls"
	_controls_button.custom_minimum_size = Vector2(180, 48)
	_controls_button.pressed.connect(_show_controls_page)
	tabs.add_child(_controls_button)


func _build_language_row() -> void:
	var row := HBoxContainer.new()
	row.name = "LanguageRow"
	_language_row = row
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.name = "LanguageLabel"
	label.custom_minimum_size = Vector2(220, 48)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_language_option = OptionButton.new()
	_language_option.custom_minimum_size = Vector2(260, 48)
	_language_option.add_item("English", 0)
	_language_option.add_item("日本語", 1)
	_language_option.select(1 if GameConfig.language == "ja" else 0)
	_language_option.item_selected.connect(func(index: int) -> void:
		_pending_language = "ja" if index == 1 else "en"
	)
	row.add_child(_language_option)
	content.add_child(row)
	content.move_child(row, 2)


func _build_name_row() -> void:
	var row := HBoxContainer.new()
	row.name = "NameRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.name = "NameLabel"
	label.text = "Player Name"
	label.custom_minimum_size = Vector2(220, 48)
	row.add_child(label)
	_name_edit = LineEdit.new()
	_name_edit.text = GameConfig.player_name
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(260, 48)
	_name_edit.text_changed.connect(func(value: String) -> void:
		_pending_player_name = value.strip_edges() if not value.strip_edges().is_empty() else "Player"
	)
	row.add_child(_name_edit)
	content.add_child(row)
	content.move_child(row, 3)


func _build_color_row() -> void:
	var row := HBoxContainer.new()
	row.name = "ColorRow"
	_color_row = row
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.name = "ColorLabel"
	label.custom_minimum_size = Vector2(220, 48)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_color_option = OptionButton.new()
	_color_option.custom_minimum_size = Vector2(260, 48)
	for color_name in GameConfig.PLAYER_COLOR_OPTIONS:
		_color_option.add_item(GameConfig.color_label(color_name))
		_color_option.set_item_metadata(_color_option.item_count - 1, color_name)
		if color_name == _pending_player_color_name:
			_color_option.select(_color_option.item_count - 1)
	_color_option.item_selected.connect(func(index: int) -> void:
		_pending_player_color_name = String(_color_option.get_item_metadata(index))
	)
	row.add_child(_color_option)
	content.add_child(row)
	content.move_child(row, 4)


func _build_ui_size_row() -> void:
	var row := HBoxContainer.new()
	row.name = "UiSizeRow"
	_ui_size_row = row
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.name = "UiSizeLabel"
	label.custom_minimum_size = Vector2(220, 48)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_ui_size_slider = HSlider.new()
	_ui_size_slider.min_value = 0.0
	_ui_size_slider.max_value = 100.0
	_ui_size_slider.step = 1.0
	_ui_size_slider.value = _pending_ui_size_percent
	_ui_size_slider.custom_minimum_size = Vector2(210, 48)
	_ui_size_slider.value_changed.connect(func(value: float) -> void:
		_pending_ui_size_percent = roundi(value)
		_update_ui_size_value()
	)
	row.add_child(_ui_size_slider)
	_ui_size_value = Label.new()
	_ui_size_value.custom_minimum_size = Vector2(70, 48)
	_ui_size_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui_size_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_ui_size_value)
	content.add_child(row)
	content.move_child(row, 5)
	_update_ui_size_value()


func _build_controls_page() -> void:
	_controls_scroll = ScrollContainer.new()
	_controls_scroll.custom_minimum_size = Vector2(640, 350)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_controls_scroll.add_child(rows)
	for action in REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = REBINDABLE_ACTIONS[action]
		label.custom_minimum_size = Vector2(320, 44)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(240, 44)
		button.pressed.connect(_start_binding.bind(action))
		row.add_child(button)
		rows.add_child(row)
		_binding_buttons[action] = button
	content.add_child(_controls_scroll)
	content.move_child(_controls_scroll, content.get_child_count() - 2)
	_refresh_binding_labels()


func _build_save_button() -> void:
	_save_button = Button.new()
	_save_button.custom_minimum_size = Vector2(220, 56)
	_save_button.add_theme_font_size_override("font_size", 24)
	_save_button.pressed.connect(_save_changes)
	content.add_child(_save_button)
	content.move_child(_save_button, content.get_child_count() - 2)


func _show_display_page() -> void:
	_waiting_action = ""
	_language_row.show()
	content.get_node("NameRow").show()
	_color_row.show()
	_ui_size_row.show()
	screen_row.show()
	_controls_scroll.hide()
	_display_button.disabled = true
	_controls_button.disabled = false


func _show_controls_page() -> void:
	_language_row.hide()
	content.get_node("NameRow").hide()
	_color_row.hide()
	_ui_size_row.hide()
	screen_row.hide()
	_controls_scroll.show()
	_display_button.disabled = false
	_controls_button.disabled = true
	_refresh_binding_labels()


func _start_binding(action: String) -> void:
	_waiting_action = action
	var button: Button = _binding_buttons[action]
	button.text = "Press a key..."


func _apply_binding(action: String, event: InputEventKey) -> void:
	var binding := InputEventKey.new()
	binding.keycode = event.keycode
	binding.physical_keycode = event.physical_keycode
	_pending_bindings[action] = [binding]
	_waiting_action = ""
	_refresh_binding_labels()


func _refresh_binding_labels() -> void:
	for action in REBINDABLE_ACTIONS:
		var button: Button = _binding_buttons[action]
		var events: Array = _pending_bindings.get(action, [])
		button.text = events[0].as_text() if not events.is_empty() else GameConfig.text("unbound")


func _update_language() -> void:
	title_label.text = GameConfig.text("settings")
	screen_label.text = GameConfig.text("screen")
	_display_button.text = GameConfig.text("display")
	_controls_button.text = GameConfig.text("key_controls")
	_save_button.text = GameConfig.text("save_changes")
	back_button.text = GameConfig.text("back")
	content.get_node("LanguageRow/LanguageLabel").text = GameConfig.text("language")
	content.get_node("NameRow/NameLabel").text = GameConfig.text("player_name")
	content.get_node("ColorRow/ColorLabel").text = GameConfig.text("character_color")
	content.get_node("UiSizeRow/UiSizeLabel").text = GameConfig.text("ui_size")
	for index in _color_option.item_count:
		var color_name := String(_color_option.get_item_metadata(index))
		_color_option.set_item_text(index, GameConfig.color_label(color_name))
	var ja_actions := {
		"move_forward": "前進", "move_back": "後退", "move_left": "左移動", "move_right": "右移動",
		"jump": "ジャンプ", "open_game_settings": "ゲーム設定", "hand_editor": "手札編集",
		"use_item": "アイテム使用", "pair_1": "ペア1", "pair_2": "ペア2", "pair_3": "ペア3", "pair_4": "ペア4",
	}
	for action in REBINDABLE_ACTIONS:
		var button: Button = _binding_buttons[action]
		var row := button.get_parent()
		row.get_child(0).text = ja_actions[action] if GameConfig.language == "ja" else REBINDABLE_ACTIONS[action]
	_refresh_binding_labels()


func _sync_screen_index() -> void:
	match DisplayServer.window_get_mode():
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			_screen_index = 1
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			_screen_index = 2
		_:
			_screen_index = 0


func _change_screen_option(amount: int) -> void:
	_screen_index = wrapi(_screen_index + amount, 0, SCREEN_OPTIONS.size())
	_update_screen_label()


func _apply_screen_option() -> void:
	var screen_id := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen_id)
	match _screen_index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(WINDOWED_SIZE)
			DisplayServer.window_set_position(Vector2i(
				roundi((screen_size.x - WINDOWED_SIZE.x) * 0.5),
				roundi((screen_size.y - WINDOWED_SIZE.y) * 0.5)
			))
		1:
			DisplayServer.window_set_size(screen_size)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2:
			DisplayServer.window_set_size(screen_size)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _update_screen_label() -> void:
	screen_value.text = SCREEN_OPTIONS[_screen_index]


func _update_ui_size_value() -> void:
	if _ui_size_value != null:
		_ui_size_value.text = "%d%%" % _pending_ui_size_percent


func _on_back_pressed() -> void:
	_waiting_action = ""
	_screen_index = _saved_screen_index
	back_requested.emit()


func _capture_pending_bindings() -> void:
	_pending_bindings.clear()
	for action in REBINDABLE_ACTIONS:
		_pending_bindings[action] = InputMap.action_get_events(action).duplicate()


func _save_changes() -> void:
	_waiting_action = ""
	GameConfig.player_name = _pending_player_name
	GameConfig.player_color_name = _pending_player_color_name
	GameConfig.set_ui_size_percent(_pending_ui_size_percent)
	for action in REBINDABLE_ACTIONS:
		InputMap.action_erase_events(action)
		for event in _pending_bindings.get(action, []):
			InputMap.action_add_event(action, event)
	_apply_screen_option()
	_saved_screen_index = _screen_index
	if GameConfig.language != _pending_language:
		GameConfig.set_language(_pending_language)
	else:
		_update_language()
	back_requested.emit()

