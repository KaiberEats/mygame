extends Control
signal card_dropped(from_index: int, to_index: int)

const JOKER_TEXTURE := preload("res://assets/seprite/joker_only1.png")

@onready var panel: PanelContainer = $Panel
@onready var margin_container: MarginContainer = $Panel/MarginContainer
@onready var rank_label: Label = $Panel/MarginContainer/VBoxContainer/RankLabel
@onready var mark_label: Label = $Panel/MarginContainer/VBoxContainer/MarkLabel
@onready var bottom_label: Label = $Panel/MarginContainer/VBoxContainer/BottomLabel

var _drag_index := -1
var _is_compact := false
var _ui_scale := 1.0
var _joker_image: TextureRect


func set_card(card: Dictionary) -> void:
	var is_joker := String(card.get("suit", "")) == "joker"
	_ensure_joker_image()
	panel.visible = not is_joker
	_joker_image.visible = is_joker
	if is_joker:
		return

	var card_color: Color = card.get("color", Color.BLACK)
	rank_label.text = card.get("label", "?")
	mark_label.text = card.get("mark", "?")
	bottom_label.text = card.get("label", "?")

	rank_label.add_theme_color_override("font_color", card_color)
	mark_label.add_theme_color_override("font_color", card_color)
	bottom_label.add_theme_color_override("font_color", card_color)


func set_drag_index(index: int) -> void:
	_drag_index = index
	mouse_filter = Control.MOUSE_FILTER_STOP if index >= 0 else Control.MOUSE_FILTER_IGNORE


func set_compact(is_compact: bool) -> void:
	_is_compact = is_compact
	_apply_ui_scale()


func set_ui_scale(value: float) -> void:
	_ui_scale = maxf(value, 0.1)
	_apply_ui_scale()


func _apply_ui_scale() -> void:
	var base_size := Vector2(48, 70) if _is_compact else Vector2(72, 104)
	var rank_size := 12 if _is_compact else 18
	var mark_size := 18 if _is_compact else 28
	var bottom_size := 12 if _is_compact else 18
	custom_minimum_size = base_size * _ui_scale
	rank_label.add_theme_font_size_override("font_size", roundi(rank_size * _ui_scale))
	mark_label.add_theme_font_size_override("font_size", roundi(mark_size * _ui_scale))
	bottom_label.add_theme_font_size_override("font_size", roundi(bottom_size * _ui_scale))


func _ensure_joker_image() -> void:
	if _joker_image != null:
		return
	_joker_image = TextureRect.new()
	_joker_image.name = "JokerImage"
	_joker_image.texture = JOKER_TEXTURE
	_joker_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_joker_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_joker_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joker_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_joker_image.visible = false
	add_child(_joker_image)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if _drag_index < 0:
		return null

	var preview := duplicate()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return {"from_index": _drag_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return _drag_index >= 0 and data is Dictionary and data.has("from_index")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	card_dropped.emit(int(data["from_index"]), _drag_index)
