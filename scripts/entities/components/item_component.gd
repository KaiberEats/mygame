class_name ItemComponent
extends Node

## 参加者の所持アイテム（MISSILE / SWORD 等）を保持する。空 = 所持なし。

var data: Dictionary = {}


func has_item() -> bool:
	return not data.is_empty()


func clear() -> void:
	data = {}
