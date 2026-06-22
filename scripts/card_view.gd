extends Control

signal card_dropped(from_index: int, to_index: int)

@onready var rank_label: Label = $Panel/MarginContainer/VBoxContainer/RankLabel
@onready var mark_label: Label = $Panel/MarginContainer/VBoxContainer/MarkLabel
@onready var bottom_label: Label = $Panel/MarginContainer/VBoxContainer/BottomLabel

var _drag_index := -1


func set_card(card: Dictionary) -> void:
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
	if not is_compact:
		return
	custom_minimum_size = Vector2(48, 70)
	rank_label.add_theme_font_size_override("font_size", 12)
	mark_label.add_theme_font_size_override("font_size", 18)
	bottom_label.add_theme_font_size_override("font_size", 12)


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
