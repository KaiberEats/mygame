class_name ExchangeSystem
extends Node

## 交換ステーション（手札の最後のカードを場のカードと交換）の生成・照準・実行。
## RPC と通知の発火は _game（match）側のヘルパーを経由する。

var _game: Node


func setup(game: Node) -> void:
	_game = game


func setup_stations() -> void:
	for station_position in [Vector3(0.0, 0.0, -40.0), Vector3(0.0, 0.0, 40.0)]:
		var station := StaticBody3D.new()
		station.name = "ExchangeStation"
		station.position = station_position
		station.add_to_group("exchange_stations")
		_game.add_child(station)

		var pedestal_mesh := BoxMesh.new()
		pedestal_mesh.size = Vector3(3.0, 1.5, 3.0)
		var pedestal := MeshInstance3D.new()
		pedestal.position.y = 0.75
		pedestal.mesh = pedestal_mesh
		var pedestal_material := StandardMaterial3D.new()
		pedestal_material.albedo_color = Color(0.16, 0.09, 0.035)
		pedestal.material_override = pedestal_material
		station.add_child(pedestal)

		for card_index in _game.EXCHANGE_CARD_COUNT:
			var hidden_card_mesh := BoxMesh.new()
			hidden_card_mesh.size = Vector3(0.85, 0.12, 1.35)
			var hidden_card := MeshInstance3D.new()
			hidden_card.name = "CardSlot_%d" % card_index
			hidden_card.position = card_local_position(card_index)
			hidden_card.mesh = hidden_card_mesh
			var card_material := StandardMaterial3D.new()
			card_material.albedo_color = Color(0.04, 0.04, 0.05)
			card_material.emission_enabled = true
			card_material.emission = Color(0.28, 0.18, 0.04)
			hidden_card.material_override = card_material
			station.add_child(hidden_card)

			var card_label := Label3D.new()
			card_label.name = "CardLabel_%d" % card_index
			card_label.position = hidden_card.position + Vector3(0.0, 0.09, 0.0)
			card_label.rotation_degrees.x = -90.0
			if station_position.z > 0.0:
				card_label.rotation_degrees.y = 180.0
			card_label.font_size = 42
			card_label.modulate = Color.WHITE
			card_label.outline_size = 8
			card_label.outline_modulate = Color.BLACK
			card_label.text = "?"
			station.add_child(card_label)

		var shape := BoxShape3D.new()
		shape.size = Vector3(3.0, 1.5, 3.0)
		var collision := CollisionShape3D.new()
		collision.position.y = 0.75
		collision.shape = shape
		station.add_child(collision)


func deal_cards() -> void:
	for station in stations():
		var station_cards: Array[Dictionary] = _game.deck.draw_cards(_game.EXCHANGE_CARD_COUNT)
		set_station_cards(station, station_cards)


func card_local_position(card_index: int) -> Vector3:
	var centered_index: float = float(card_index) - float(_game.EXCHANGE_CARD_COUNT - 1) * 0.5
	return Vector3(centered_index * _game.EXCHANGE_CARD_SPACING, 1.56, 0.0)


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
	for card_index in _game.EXCHANGE_CARD_COUNT:
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
	_game._player_exchange_card_index = -1
	if _game.player.is_stunned() or _game.player.hand.is_empty() or _game.game_hud.is_hand_editor_open():
		return null
	var best_station: StaticBody3D = null
	var best_dot: float = _game.KILL_CENTER_DOT
	for station_node in get_tree().get_nodes_in_group("exchange_stations"):
		var station := station_node as StaticBody3D
		if station == null:
			continue
		var found_cards := station_cards(station)
		for card_index in found_cards.size():
			var card_position := station.to_global(card_local_position(card_index))
			var to_card: Vector3 = card_position - _game.player.get_view_origin()
			if to_card.length() > _game.KILL_DISTANCE + 1.5:
				continue
			var center_dot: float = _game.player.get_view_forward().dot(to_card.normalized())
			if center_dot > best_dot:
				best_dot = center_dot
				best_station = station
				_game._player_exchange_card_index = card_index
	return best_station


func update_hold(delta: float) -> void:
	var is_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _game._exchange_locked_until_release:
		if not is_pressed:
			_game._exchange_locked_until_release = false
		return

	if not is_pressed or _game._player_exchange_target == null:
		_game._exchange_hold_time = 0.0
		_game._exchange_hold_target = null
		_game._exchange_hold_card_index = -1
		_game.game_hud.set_exchange_progress(0.0, false)
		return

	if _game._exchange_hold_target != _game._player_exchange_target or _game._exchange_hold_card_index != _game._player_exchange_card_index:
		_game._exchange_hold_target = _game._player_exchange_target
		_game._exchange_hold_card_index = _game._player_exchange_card_index
		_game._exchange_hold_time = 0.0
	_game._exchange_hold_time = minf(_game._exchange_hold_time + delta, _game.EXCHANGE_HOLD_SECONDS)
	_game.game_hud.set_exchange_progress(_game._exchange_hold_time / _game.EXCHANGE_HOLD_SECONDS, true)
	if _game._exchange_hold_time >= _game.EXCHANGE_HOLD_SECONDS:
		var station_index := stations().find(_game._exchange_hold_target)
		if _game._is_game_authority():
			exchange_with_station(_game.player, station_index, _game._exchange_hold_card_index)
		else:
			_game.request_exchange_remote(station_index, _game._exchange_hold_card_index)
		_game._exchange_hold_time = 0.0
		_game._exchange_hold_target = null
		_game._exchange_hold_card_index = -1
		_game._exchange_locked_until_release = true


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
		_game.notify_participant(participant, GameConfig.text("joker_exchange"))
		return
	var station_card: Dictionary = found_cards[card_index]
	hand[hand_index] = station_card
	found_cards[card_index] = player_card
	set_station_cards(station, found_cards)
	participant.set_hand(hand, true)
	_game._show_change_preview_for_participant(participant, player_card, station_card)
	_game.notify_exchange_complete(participant)


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
