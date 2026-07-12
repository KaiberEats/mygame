extends CanvasLayer

signal hand_reordered(cards: Array[Dictionary])
signal debug_return_requested

const CARD_VIEW_SCENE := preload("res://scenes/CardView.tscn")
const ITEM_SLOT_SCRIPT := preload("res://scripts/item_slot.gd")
const EDGE_STATUS_EFFECT_SCRIPT := preload("res://scripts/edge_status_effect.gd")

@onready var deck_count_label: Label = $Root/DeckCountLabel
@onready var hand_container: HBoxContainer = $Root/HandContainer
@onready var kill_button: Button = $Root/KillButton
@onready var change_button: Button = $Root/ChangeButton
@onready var item_slot: Control = $Root/ItemSlot
@onready var minimap: Control = $Root/Minimap
@onready var viewed_hand: HBoxContainer = $Root/ViewedHandPanel/Content/ViewedHand
@onready var viewed_name: Label = $Root/ViewedHandPanel/Content/ViewedName
@onready var viewed_panel: PanelContainer = $Root/ViewedHandPanel
@onready var hand_editor: PanelContainer = $Root/HandEditor
@onready var editor_hand_container: HBoxContainer = $Root/HandEditor/Content/EditorHandContainer

var _editor_cards: Array[Dictionary] = []
var _viewed_hand_signature := ""
var _time_label: Label
var _end_label: Label
var _exchange_panel: PanelContainer
var _exchange_bar: ProgressBar
var _exchange_label: Label
var _kill_cooldown_clock: Control
var _change_complete_visible := false
var _notification_label: Label
var _notification_time_left := 0.0
var _stun_panel: PanelContainer
var _stun_label: Label
var _stun_bar: ProgressBar
var _change_preview_layer: Control
var _change_preview_from: HBoxContainer
var _change_preview_to: HBoxContainer
var _change_preview_tween: Tween
var _debug_return_button: Button
var _ability_cooldown_panel: PanelContainer
var _ability_cooldown_bar: ProgressBar
var _exposure_panel: PanelContainer
var _exposure_list: VBoxContainer
var _edge_status_effect: Control
var _crosshair: Control
var _hud_scale := 1.0
var _last_hand: Array[Dictionary] = []
var _last_viewed_cards: Array[Dictionary] = []
var _last_viewed_name := ""


func _ready() -> void:
	_edge_status_effect = Control.new()
	_edge_status_effect.name = "EdgeStatusEffect"
	_edge_status_effect.set_script(EDGE_STATUS_EFFECT_SCRIPT)
	$Root.add_child(_edge_status_effect)
	$Root.move_child(_edge_status_effect, 0)

	_build_crosshair()

	_time_label = Label.new()
	_time_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_time_label.position = Vector2(24, -70)
	_time_label.size = Vector2(220, 50)
	_time_label.add_theme_font_size_override("font_size", 32)
	_time_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_time_label.add_theme_constant_override("shadow_offset_x", 2)
	_time_label.add_theme_constant_override("shadow_offset_y", 2)
	$Root.add_child(_time_label)

	_end_label = Label.new()
	_end_label.set_anchors_preset(Control.PRESET_CENTER)
	_end_label.position = Vector2(-300, -70)
	_end_label.size = Vector2(600, 140)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_size_override("font_size", 72)
	_end_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_end_label.add_theme_constant_override("shadow_offset_x", 4)
	_end_label.add_theme_constant_override("shadow_offset_y", 4)
	_end_label.hide()
	$Root.add_child(_end_label)

	_exchange_panel = PanelContainer.new()
	_exchange_panel.name = "ExchangePanel"
	_exchange_panel.set_anchors_preset(Control.PRESET_CENTER)
	_exchange_panel.position = Vector2(-240, 80)
	_exchange_panel.size = Vector2(480, 100)
	var exchange_content := VBoxContainer.new()
	exchange_content.add_theme_constant_override("separation", 10)
	_exchange_panel.add_child(exchange_content)
	_exchange_label = Label.new()
	_exchange_label.text = "HOLD CHANGE"
	_exchange_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exchange_label.add_theme_font_size_override("font_size", 28)
	exchange_content.add_child(_exchange_label)
	_exchange_bar = ProgressBar.new()
	_exchange_bar.custom_minimum_size = Vector2(440, 30)
	_exchange_bar.max_value = 1.0
	_exchange_bar.show_percentage = false
	exchange_content.add_child(_exchange_bar)
	_exchange_panel.hide()
	$Root.add_child(_exchange_panel)

	_kill_cooldown_clock = Control.new()
	_kill_cooldown_clock.set_script(ITEM_SLOT_SCRIPT)
	_kill_cooldown_clock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_kill_cooldown_clock.position = Vector2(-144, -100)
	_kill_cooldown_clock.size = Vector2(104, 72)
	_kill_cooldown_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_cooldown_clock.hide()
	$Root.add_child(_kill_cooldown_clock)

	_notification_label = Label.new()
	_notification_label.name = "NotificationLabel"
	_notification_label.set_anchors_preset(Control.PRESET_CENTER)
	_notification_label.position = Vector2(-400, -90)
	_notification_label.size = Vector2(800, 180)
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notification_label.add_theme_font_size_override("font_size", 54)
	_notification_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_notification_label.add_theme_constant_override("shadow_offset_x", 4)
	_notification_label.add_theme_constant_override("shadow_offset_y", 4)
	_notification_label.hide()
	$Root.add_child(_notification_label)

	_stun_panel = PanelContainer.new()
	_stun_panel.name = "StunPanel"
	_stun_panel.set_anchors_preset(Control.PRESET_CENTER)
	_stun_panel.position = Vector2(-240, 80)
	_stun_panel.size = Vector2(480, 100)
	var stun_content := VBoxContainer.new()
	stun_content.add_theme_constant_override("separation", 10)
	_stun_panel.add_child(stun_content)
	_stun_label = Label.new()
	_stun_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stun_label.add_theme_font_size_override("font_size", 28)
	stun_content.add_child(_stun_label)
	_stun_bar = ProgressBar.new()
	_stun_bar.custom_minimum_size = Vector2(440, 30)
	_stun_bar.max_value = 1.0
	_stun_bar.show_percentage = false
	stun_content.add_child(_stun_bar)
	_stun_panel.hide()
	$Root.add_child(_stun_panel)

	_change_preview_layer = Control.new()
	_change_preview_layer.name = "ChangePreviewLayer"
	_change_preview_layer.set_anchors_preset(Control.PRESET_CENTER)
	_change_preview_layer.position = Vector2(-150, -90)
	_change_preview_layer.size = Vector2(300, 180)
	_change_preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview_row := HBoxContainer.new()
	preview_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_theme_constant_override("separation", 18)
	_change_preview_layer.add_child(preview_row)
	_change_preview_from = HBoxContainer.new()
	_change_preview_from.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_child(_change_preview_from)
	var arrow := Label.new()
	arrow.text = ">"
	arrow.add_theme_font_size_override("font_size", 42)
	arrow.add_theme_color_override("font_shadow_color", Color.BLACK)
	arrow.add_theme_constant_override("shadow_offset_x", 3)
	arrow.add_theme_constant_override("shadow_offset_y", 3)
	preview_row.add_child(arrow)
	_change_preview_to = HBoxContainer.new()
	_change_preview_to.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_child(_change_preview_to)
	_change_preview_layer.hide()
	$Root.add_child(_change_preview_layer)

	_debug_return_button = Button.new()
	_debug_return_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_debug_return_button.position = Vector2(24, -132)
	_debug_return_button.size = Vector2(230, 48)
	_debug_return_button.add_theme_font_size_override("font_size", 18)
	_debug_return_button.pressed.connect(func() -> void: debug_return_requested.emit())
	$Root.add_child(_debug_return_button)

	_ability_cooldown_panel = PanelContainer.new()
	_ability_cooldown_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ability_cooldown_panel.position = Vector2(-656, 138)
	_ability_cooldown_panel.size = Vector2(632, 26)
	_ability_cooldown_bar = ProgressBar.new()
	_ability_cooldown_bar.max_value = 1.0
	_ability_cooldown_bar.show_percentage = false
	_ability_cooldown_panel.add_child(_ability_cooldown_bar)
	_ability_cooldown_panel.hide()
	$Root.add_child(_ability_cooldown_panel)

	_exposure_panel = PanelContainer.new()
	_exposure_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_exposure_panel.position = Vector2(24, 244)
	_exposure_panel.size = Vector2(260, 92)
	_exposure_list = VBoxContainer.new()
	_exposure_list.add_theme_constant_override("separation", 6)
	_exposure_panel.add_child(_exposure_list)
	_exposure_panel.hide()
	$Root.add_child(_exposure_panel)
	GameConfig.language_changed.connect(_update_language)
	GameConfig.ui_scale_changed.connect(_apply_responsive_layout)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_update_language()
	_apply_responsive_layout()


func _build_crosshair() -> void:
	var crosshair := Control.new()
	_crosshair = crosshair
	crosshair.name = "Crosshair"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-12, -12)
	crosshair.size = Vector2(24, 24)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(crosshair)

	var horizontal := ColorRect.new()
	horizontal.position = Vector2(2, 11)
	horizontal.size = Vector2(20, 2)
	horizontal.color = Color.WHITE
	horizontal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_child(horizontal)

	var vertical := ColorRect.new()
	vertical.position = Vector2(11, 2)
	vertical.size = Vector2(2, 20)
	vertical.color = Color.WHITE
	vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_child(vertical)


func _set_control_rect(control: Control, top_left: Vector2, rect_size: Vector2) -> void:
	control.offset_left = top_left.x
	control.offset_top = top_left.y
	control.offset_right = top_left.x + rect_size.x
	control.offset_bottom = top_left.y + rect_size.y


func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	_edge_status_effect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge_status_effect.offset_left = 0.0
	_edge_status_effect.offset_top = 0.0
	_edge_status_effect.offset_right = 0.0
	_edge_status_effect.offset_bottom = 0.0
	var viewport_scale := clampf(viewport_size.y / 720.0, 0.7, 2.2)
	var user_scale := lerpf(0.65, 1.35, float(GameConfig.ui_size_percent) / 100.0)
	_hud_scale = viewport_scale * user_scale
	var margin := roundf(24.0 * _hud_scale)
	var small_gap := roundf(8.0 * _hud_scale)

	var minimap_size := clampf(150.0 * _hud_scale, 96.0, minf(viewport_size.x, viewport_size.y) * 0.28)
	_set_control_rect(minimap, Vector2(margin, margin), Vector2.ONE * minimap_size)
	minimap.custom_minimum_size = minimap.size

	_set_control_rect(
		deck_count_label,
		Vector2(margin, margin + minimap_size + 12.0 * _hud_scale),
		Vector2(240.0 * _hud_scale, 40.0 * _hud_scale)
	)
	deck_count_label.add_theme_font_size_override("font_size", roundi(26.0 * _hud_scale))

	var card_size := Vector2(72.0, 104.0) * _hud_scale
	var hand_width := minf(card_size.x * 8.0 + small_gap * 7.0, viewport_size.x * 0.58)
	hand_container.offset_left = -margin - hand_width
	hand_container.offset_top = margin
	hand_container.offset_right = -margin
	hand_container.offset_bottom = margin + card_size.y + 10.0 * _hud_scale
	hand_container.add_theme_constant_override("separation", roundi(small_gap))

	_ability_cooldown_panel.offset_left = hand_container.offset_left
	_ability_cooldown_panel.offset_top = hand_container.offset_bottom + 6.0 * _hud_scale
	_ability_cooldown_panel.offset_right = hand_container.offset_right
	_ability_cooldown_panel.offset_bottom = _ability_cooldown_panel.offset_top + 26.0 * _hud_scale

	var button_size := Vector2(140.0, 58.0) * _hud_scale
	kill_button.offset_left = -margin - button_size.x
	kill_button.offset_top = -margin - button_size.y
	kill_button.offset_right = -margin
	kill_button.offset_bottom = -margin
	kill_button.add_theme_font_size_override("font_size", roundi(28.0 * _hud_scale))

	var change_size := Vector2(158.0, 58.0) * _hud_scale
	change_button.offset_left = kill_button.offset_left - 12.0 * _hud_scale - change_size.x
	change_button.offset_top = kill_button.offset_top
	change_button.offset_right = kill_button.offset_left - 12.0 * _hud_scale
	change_button.offset_bottom = kill_button.offset_bottom
	change_button.add_theme_font_size_override("font_size", roundi(28.0 * _hud_scale))

	var item_size := Vector2.ONE * (92.0 * _hud_scale)
	item_slot.offset_left = -margin - item_size.x
	item_slot.offset_top = kill_button.offset_top - 16.0 * _hud_scale - item_size.y
	item_slot.offset_right = -margin
	item_slot.offset_bottom = kill_button.offset_top - 16.0 * _hud_scale

	_kill_cooldown_clock.offset_left = item_slot.offset_left - 116.0 * _hud_scale
	_kill_cooldown_clock.offset_top = item_slot.offset_top + 10.0 * _hud_scale
	_kill_cooldown_clock.offset_right = _kill_cooldown_clock.offset_left + 104.0 * _hud_scale
	_kill_cooldown_clock.offset_bottom = _kill_cooldown_clock.offset_top + 72.0 * _hud_scale

	_set_control_rect(_time_label, Vector2(margin, -70.0 * _hud_scale), Vector2(220.0, 50.0) * _hud_scale)
	_time_label.add_theme_font_size_override("font_size", roundi(32.0 * _hud_scale))

	_set_control_rect(
		_debug_return_button,
		Vector2(margin, -132.0 * _hud_scale),
		Vector2(230.0, 48.0) * _hud_scale
	)
	_debug_return_button.add_theme_font_size_override("font_size", roundi(18.0 * _hud_scale))

	_set_control_rect(
		_exposure_panel,
		Vector2(margin, margin + minimap_size + 72.0 * _hud_scale),
		Vector2(280.0, 92.0) * _hud_scale
	)

	var panel_size := Vector2(480.0, 100.0) * _hud_scale
	for panel in [_exchange_panel, _stun_panel]:
		_set_control_rect(panel, Vector2(-panel_size.x * 0.5, 80.0 * _hud_scale), panel_size)
	_exchange_label.add_theme_font_size_override("font_size", roundi(28.0 * _hud_scale))
	_exchange_bar.custom_minimum_size = Vector2(440.0, 30.0) * _hud_scale
	_stun_label.add_theme_font_size_override("font_size", roundi(28.0 * _hud_scale))
	_stun_bar.custom_minimum_size = Vector2(440.0, 30.0) * _hud_scale

	_set_control_rect(
		_notification_label,
		Vector2(-400.0, -90.0) * _hud_scale,
		Vector2(800.0, 180.0) * _hud_scale
	)
	_notification_label.add_theme_font_size_override("font_size", roundi(54.0 * _hud_scale))
	_set_control_rect(
		_end_label,
		Vector2(-300.0, -70.0) * _hud_scale,
		Vector2(600.0, 140.0) * _hud_scale
	)
	_end_label.add_theme_font_size_override("font_size", roundi(72.0 * _hud_scale))

	_set_control_rect(
		_change_preview_layer,
		Vector2(-150.0, -90.0) * _hud_scale,
		Vector2(300.0, 180.0) * _hud_scale
	)

	viewed_panel.offset_left = -380.0 * _hud_scale
	viewed_panel.offset_top = 142.0 * _hud_scale
	viewed_panel.offset_right = 380.0 * _hud_scale
	viewed_panel.offset_bottom = 284.0 * _hud_scale

	if _crosshair != null:
		_set_control_rect(_crosshair, Vector2(-12.0, -12.0) * _hud_scale, Vector2(24.0, 24.0) * _hud_scale)
		var horizontal := _crosshair.get_child(0) as Control
		var vertical := _crosshair.get_child(1) as Control
		_set_control_rect(horizontal, Vector2(2.0, 11.0) * _hud_scale, Vector2(20.0, 2.0) * _hud_scale)
		_set_control_rect(vertical, Vector2(11.0, 2.0) * _hud_scale, Vector2(2.0, 20.0) * _hud_scale)

	if not _last_hand.is_empty():
		_render_cards(hand_container, _last_hand, false)
	if hand_editor.visible:
		_render_cards(editor_hand_container, _editor_cards, true)
	if viewed_panel.visible and not _last_viewed_name.is_empty():
		_viewed_hand_signature = ""
		set_viewed_hand(_last_viewed_name, _last_viewed_cards)


func _process(delta: float) -> void:
	if _notification_time_left <= 0.0:
		return
	_notification_time_left = maxf(_notification_time_left - delta, 0.0)
	if _notification_time_left <= 0.0:
		_notification_label.hide()


func set_deck_count(remaining: int, total: int) -> void:
	deck_count_label.text = "%s %d/%d" % [GameConfig.text("deck"), remaining, total]


func set_time_left(seconds: float) -> void:
	var whole_seconds := maxi(ceili(seconds), 0)
	var minutes := floori(float(whole_seconds) / 60.0)
	_time_label.text = "%02d:%02d" % [minutes, whole_seconds % 60]


func show_end_message(message: String) -> void:
	_end_label.text = message
	_end_label.show()


func set_exchange_progress(progress: float, should_show: bool) -> void:
	if not _change_complete_visible:
		_exchange_panel.visible = should_show
	_exchange_label.text = GameConfig.text("hold_change")
	_exchange_bar.value = clampf(progress, 0.0, 1.0)


func show_change_complete() -> void:
	_change_complete_visible = true
	_exchange_panel.show()
	_exchange_label.text = GameConfig.text("changed")
	_exchange_bar.value = 1.0
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_callback(func() -> void:
		_change_complete_visible = false
		_exchange_panel.hide()
	)


func show_change_preview(before_card: Dictionary, after_card: Dictionary) -> void:
	if before_card.is_empty() or after_card.is_empty():
		return
	_render_cards(_change_preview_from, [before_card], false)
	_render_cards(_change_preview_to, [after_card], false)
	_change_preview_layer.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_change_preview_layer.show()
	if _change_preview_tween != null:
		_change_preview_tween.kill()
	_change_preview_tween = create_tween()
	_change_preview_tween.tween_interval(1.1)
	_change_preview_tween.tween_property(_change_preview_layer, "modulate:a", 0.0, 0.25)
	_change_preview_tween.tween_callback(func() -> void:
		_change_preview_layer.hide()
		_change_preview_layer.modulate = Color(1.0, 1.0, 1.0, 1.0)
	)


func set_kill_cooldown(time_left: float, duration: float) -> void:
	_kill_cooldown_clock.visible = time_left > 0.0
	_kill_cooldown_clock.call("set_item", GameConfig.text("kill").to_upper(), time_left, duration)


func set_ability_cooldown(time_left: float, duration: float) -> void:
	_ability_cooldown_panel.visible = time_left > 0.0
	_ability_cooldown_bar.value = clampf(time_left / duration, 0.0, 1.0) if duration > 0.0 else 0.0


func set_exposure_status(is_location_revealed: bool, is_hand_viewed: bool) -> void:
	for child in _exposure_list.get_children():
		child.queue_free()
	if is_location_revealed:
		_exposure_list.add_child(_make_exposure_label(GameConfig.text("location_revealed")))
	if is_hand_viewed:
		_exposure_list.add_child(_make_exposure_label(GameConfig.text("hand_viewed")))
	_exposure_panel.visible = is_location_revealed or is_hand_viewed


func set_edge_status_effects(has_joker: bool, is_invincible: bool, has_barrier: bool) -> void:
	_edge_status_effect.call("set_statuses", has_joker, is_invincible, has_barrier)


func show_notification(message: String, duration: float = 3.0) -> void:
	_notification_label.text = message
	_notification_label.show()
	_notification_time_left = duration


func set_stun_status(time_left: float, duration: float) -> void:
	var should_show := time_left > 0.0 and _notification_time_left <= 0.0
	_stun_panel.visible = should_show
	if not should_show:
		return
	_stun_label.text = "%s  %.1f s" % [GameConfig.text("stun"), time_left]
	_stun_bar.value = clampf(time_left / duration, 0.0, 1.0)


func set_hand(cards: Array[Dictionary]) -> void:
	_last_hand = cards.duplicate()
	_render_cards(hand_container, cards, false)
	if hand_editor.visible:
		_editor_cards = cards.duplicate()
		_render_cards(editor_hand_container, _editor_cards, true)


func open_hand_editor(cards: Array[Dictionary]) -> void:
	_editor_cards = cards.duplicate()
	_render_cards(editor_hand_container, _editor_cards, true)
	hand_editor.show()


func close_hand_editor() -> void:
	hand_editor.hide()


func is_hand_editor_open() -> bool:
	return hand_editor.visible


func set_kill_available(is_available: bool) -> void:
	kill_button.disabled = not is_available
	kill_button.modulate = Color(1.0, 1.0, 0.35, 1.0) if is_available else Color(0.45, 0.45, 0.45, 0.75)


func set_change_available(is_available: bool) -> void:
	change_button.disabled = not is_available
	change_button.modulate = Color(1.0, 1.0, 0.35, 1.0) if is_available else Color(0.45, 0.45, 0.45, 0.75)


func set_item(item_name: String, time_left: float = 0.0, duration: float = 0.0, icon: Texture2D = null) -> void:
	item_slot.set_item(item_name, time_left, duration, icon)


func set_minimap_data(player_position: Vector3, revealed_positions: Array[Vector3]) -> void:
	minimap.set_data(player_position, revealed_positions)


func set_minimap_world_half_extent(world_half_extent: float) -> void:
	minimap.set_world_half_extent(world_half_extent)


func set_viewed_hand(participant_name: String, cards: Array[Dictionary]) -> void:
	_last_viewed_name = participant_name
	_last_viewed_cards = cards.duplicate()
	viewed_panel.visible = not participant_name.is_empty()
	if participant_name.is_empty():
		_viewed_hand_signature = ""
		return

	var signature := participant_name
	for card in cards:
		signature += "|%s:%s" % [card.get("suit", ""), card.get("rank", 0)]
	if signature == _viewed_hand_signature:
		return
	_viewed_hand_signature = signature
	viewed_name.text = participant_name
	_render_cards(viewed_hand, cards, false)


func _update_language() -> void:
	kill_button.text = GameConfig.text("kill")
	change_button.text = GameConfig.text("change")
	_debug_return_button.text = GameConfig.text("debug_return")
	$Root/HandEditor/Content/InstructionLabel.text = GameConfig.text("drag_cards")


func _make_exposure_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _render_cards(container: HBoxContainer, cards: Array[Dictionary], is_draggable: bool) -> void:
	for child in container.get_children():
		child.queue_free()

	for index in cards.size():
		var card_view := CARD_VIEW_SCENE.instantiate()
		container.add_child(card_view)
		if container == viewed_hand:
			card_view.set_compact(true)
		card_view.set_ui_scale(_hud_scale)
		card_view.set_card(cards[index])
		card_view.set_drag_index(index if is_draggable else -1)
		if is_draggable:
			card_view.card_dropped.connect(_on_card_dropped)


func _on_card_dropped(from_index: int, to_index: int) -> void:
	if (
		from_index == to_index
		or from_index < 0
		or from_index >= _editor_cards.size()
		or to_index < 0
		or to_index >= _editor_cards.size()
	):
		return

	var moved_card: Dictionary = _editor_cards.pop_at(from_index)
	_editor_cards.insert(to_index, moved_card)
	_render_cards(editor_hand_container, _editor_cards, true)
	_render_cards(hand_container, _editor_cards, false)
	hand_reordered.emit(_editor_cards.duplicate())
