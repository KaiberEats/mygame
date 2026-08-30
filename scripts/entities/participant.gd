class_name Participant
extends CharacterBody3D

## プレイヤー/コンピューター共通の基底。
## 状態を持つ4コンポーネントを自己 attach し、型付きゲッターで公開する。
## 継承側が _ready を定義する場合は super() を呼ぶこと。

func _ready() -> void:
	_attach_component(StatusComponent.new(), "StatusComponent")
	_attach_component(CooldownComponent.new(), "CooldownComponent")
	_attach_component(ItemComponent.new(), "ItemComponent")
	_attach_component(VisionComponent.new(), "VisionComponent")


func _attach_component(component: Node, node_name: String) -> void:
	component.name = node_name
	add_child(component)


func status() -> StatusComponent:
	return get_node(^"StatusComponent")


func cooldown() -> CooldownComponent:
	return get_node(^"CooldownComponent")


func item() -> ItemComponent:
	return get_node(^"ItemComponent")


func vision() -> VisionComponent:
	return get_node(^"VisionComponent")


func is_computer() -> bool:
	return false


func get_display_name() -> String:
	return name
