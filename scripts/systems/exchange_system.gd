class_name ExchangeSystem
extends Node

## 交換ステーション（手札の最後のカードを場のカードと交換）の生成・照準・実行。
## ローカルの長押し進行(hold)を本 System が所有。通知/送信は NetGateway 経由。

const EXCHANGE_STATION_SCENE := preload("res://scenes/entities/ExchangeStation.tscn")

var _hold_time := 0.0
var _hold_target: StaticBody3D = null
var _hold_card_index := -1
var _locked_until_release := false
var _aimed_station: StaticBody3D = null
var _aimed_card_index := -1

var _participants: Participants
var _deck: Node
var _net: NetSync
var _net_gateway: NetGateway
var _game_hud: CanvasLayer
var _world: Node


func setup(participants: Participants, deck: Node, net: NetSync, net_gateway: NetGateway,
		game_hud: CanvasLayer, world: Node) -> void:
	_participants = participants
	_deck = deck
	_net = net
	_net_gateway = net_gateway
	_game_hud = game_hud
	_world = world


func setup_stations() -> void:
	for station_position in [Vector3(0.0, 0.0, -40.0), Vector3(0.0, 0.0, 40.0)]:
		var station: StaticBody3D = EXCHANGE_STATION_SCENE.instantiate()
		station.position = station_position
		if station_position.z > 0.0:
			# 中央側から文字が読めるよう、対面側のステーションはラベルだけ反転させる。
			for card_index in GameConfig.EXCHANGE_CARD_COUNT:
				var label := station.get_node_or_null("CardLabel_%d" % card_index) as Label3D
				if label != null:
					label.rotation_degrees.y = 180.0
		_world.add_child(station)


func deal_cards() -> void:
	for station in stations():
		var station_cards: Array[Dictionary] = _deck.draw_cards(GameConfig.EXCHANGE_CARD_COUNT)
		set_station_cards(station, station_cards)


func card_local_position(card_index: int) -> Vector3:
	var centered_index: float = float(card_index) - float(GameConfig.EXCHANGE_CARD_COUNT - 1) * 0.5
	return Vector3(centered_index * GameConfig.EXCHANGE_CARD_SPACING, 1.56, 0.0)


func station_cards(station: StaticBody3D) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for card in station.get_meta("cards", []):
		if card is Dictionary:
			cards.append(card)
	if cards.is_empty() and station.has_meta("card"):
		var old_card = station.get_meta("card")
		if old_card is Dictionary:
			cards.append(old_card)
	return cards


func set_station_cards(station: StaticBody3D, cards: Array) -> void:
	var typed_cards: Array[Dictionary] = []
	for card in cards:
		if card is Dictionary:
			typed_cards.append(card)
	station.set_meta("cards", typed_cards)
	if typed_cards.is_empty():
		station.remove_meta("card")
	else:
		station.set_meta("card", typed_cards[0])
	for card_index in GameConfig.EXCHANGE_CARD_COUNT:
		var mesh := station.get_node_or_null("CardSlot_%d" % card_index) as MeshInstance3D
		var label := station.get_node_or_null("CardLabel_%d" % card_index) as Label3D
		var has_card: bool = card_index < typed_cards.size()
		if mesh != null:
			mesh.visible = has_card
			if has_card:
				var material := mesh.material_override as StandardMaterial3D
				if material != null:
					material.albedo_color = Color(0.04, 0.04, 0.05)
					material.emission = Color(0.28, 0.18, 0.04)
		if label != null:
			label.visible = has_card
			if has_card:
				label.text = "?"
				label.modulate = Color.WHITE


func find_aimed_station() -> StaticBody3D:
	_aimed_card_index = -1
	_aimed_station = null
	var local_player := _participants.local_player
	if local_player.is_stunned() or local_player.hand.is_empty() or _game_hud.is_hand_editor_open():
		return null
	var best_station: StaticBody3D = null
	var best_dot: float = GameConfig.KILL_CENTER_DOT
	for station_node in get_tree().get_nodes_in_group("exchange_stations"):
		var station := station_node as StaticBody3D
		if station == null:
			continue
		var found_cards := station_cards(station)
		for card_index in found_cards.size():
			var card_position := station.to_global(card_local_position(card_index))
			var to_card: Vector3 = card_position - local_player.get_view_origin()
			if to_card.length() > GameConfig.KILL_DISTANCE + 1.5:
				continue
			var center_dot: float = local_player.get_view_forward().dot(to_card.normalized())
			if center_dot > best_dot:
				best_dot = center_dot
				best_station = station
				_aimed_card_index = card_index
	_aimed_station = best_station
	return best_station


func update_hold(delta: float) -> void:
	var is_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _locked_until_release:
		if not is_pressed:
			_locked_until_release = false
		return

	if not is_pressed or _aimed_station == null:
		_hold_time = 0.0
		_hold_target = null
		_hold_card_index = -1
		_game_hud.set_exchange_progress(0.0, false)
		return

	if _hold_target != _aimed_station or _hold_card_index != _aimed_card_index:
		_hold_target = _aimed_station
		_hold_card_index = _aimed_card_index
		_hold_time = 0.0
	_hold_time = minf(_hold_time + delta, GameConfig.EXCHANGE_HOLD_SECONDS)
	_game_hud.set_exchange_progress(_hold_time / GameConfig.EXCHANGE_HOLD_SECONDS, true)
	if _hold_time >= GameConfig.EXCHANGE_HOLD_SECONDS:
		var station_index := stations().find(_hold_target)
		if _net.is_game_authority():
			exchange_with_station(_participants.local_player, station_index, _hold_card_index)
		else:
			_net_gateway.request_exchange(station_index, _hold_card_index)
		_hold_time = 0.0
		_hold_target = null
		_hold_card_index = -1
		_locked_until_release = true


func exchange_with_station(participant: Node3D, station_index: int, card_index: int) -> void:
	var all_stations := stations()
	if station_index < 0 or station_index >= all_stations.size():
		return
	var station: StaticBody3D = all_stations[station_index]
	var found_cards := station_cards(station)
	if card_index < 0 or card_index >= found_cards.size() or participant.hand.is_empty():
		return
	var hand: Array[Dictionary] = participant.hand.duplicate()
	var hand_index := hand.size() - 1
	var player_card: Dictionary = hand[hand_index]
	if player_card.get("suit", "") == "joker":
		_net_gateway.notify(participant, GameConfig.text("joker_exchange"))
		return
	var station_card: Dictionary = found_cards[card_index]
	hand[hand_index] = station_card
	found_cards[card_index] = player_card
	set_station_cards(station, found_cards)
	participant.set_hand(hand, true)
	_net_gateway.show_change_preview(participant, player_card, station_card)
	_net_gateway.notify_exchange_complete(participant)


func stations() -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	for station_node in get_tree().get_nodes_in_group("exchange_stations"):
		var station := station_node as StaticBody3D
		if station != null:
			result.append(station)
	result.sort_custom(func(a: StaticBody3D, b: StaticBody3D) -> bool:
		return a.global_position.z < b.global_position.z
	)
	return result
