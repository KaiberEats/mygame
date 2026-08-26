class_name GameFlow
extends Node

## 試合進行: 終了条件・順位計算・リザルト表示。
## RPC の発火は match(_game) のヘルパー経由。制限時間 `_time_left` は match が保持し _process で減算する。

var _game: Node


func setup(game: Node) -> void:
	_game = game


func has_empty_hand() -> bool:
	for participant in _game._participants:
		if participant.hand.is_empty():
			return true
	return false


func finish_game() -> void:
	if _game._game_ending:
		return
	_game._game_ending = true
	var standings := calculate_standings()
	if NetworkManager.is_online and multiplayer.is_server():
		var network_standings: Dictionary = {}
		for participant in standings:
			network_standings[participant.name] = standings[participant]
		_game.broadcast_game_finished(network_standings)
	var player_rank := int(standings[_game.player])
	_game.game_hud.show_end_message(GameConfig.text("win") if player_rank == 1 else GameConfig.text("place") % player_rank)
	Engine.time_scale = 0.2
	await get_tree().create_timer(5.0, true, false, true).timeout
	Engine.time_scale = 1.0
	show_results(standings)


func receive_game_finished(network_standings: Dictionary) -> void:
	if _game._game_ending:
		return
	_game._game_ending = true
	var standings: Dictionary = {}
	for participant_name in network_standings:
		var participant: Node3D = _game._participant_by_name(String(participant_name))
		if participant != null:
			standings[participant] = int(network_standings[participant_name])
	var player_rank := int(standings.get(_game.player, _game._participants.size()))
	_game.game_hud.show_end_message(GameConfig.text("win") if player_rank == 1 else GameConfig.text("place") % player_rank)
	Engine.time_scale = 0.2
	await get_tree().create_timer(5.0, true, false, true).timeout
	Engine.time_scale = 1.0
	show_results(standings)


func calculate_standings() -> Dictionary:
	var sorted_participants: Array = _game._participants.duplicate()
	sorted_participants.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		if a.has_joker() != b.has_joker():
			return not a.has_joker()
		return a.hand.size() < b.hand.size()
	)

	var standings: Dictionary = {}
	var previous: Node3D = null
	var current_rank := 0
	for index in sorted_participants.size():
		var participant: Node3D = sorted_participants[index]
		if previous == null or participant.has_joker() != previous.has_joker() or participant.hand.size() != previous.hand.size():
			current_rank = index + 1
		standings[participant] = current_rank
		previous = participant
	return standings


func show_results(standings: Dictionary) -> void:
	get_tree().paused = true
	_game.game_hud.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_game.add_child(layer)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.025, 0.02, 0.035, 0.98)
	layer.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(650, 0)
	content.add_theme_constant_override("separation", 14)
	center.add_child(content)
	var title := Label.new()
	title.text = GameConfig.text("result")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	content.add_child(title)

	var sorted_participants: Array = _game._participants.duplicate()
	sorted_participants.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return int(standings[a]) < int(standings[b])
	)
	for participant in sorted_participants:
		var row := Label.new()
		row.text = "%d  %s  -  %s%s" % [
			int(standings[participant]),
			_game._participant_name(participant),
			GameConfig.text("cards") % participant.hand.size(),
			("  ジョーカー" if GameConfig.language == "ja" else "  JOKER") if participant.has_joker() else "",
		]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 26)
		content.add_child(row)

	var title_button := Button.new()
	title_button.custom_minimum_size = Vector2(0, 60)
	title_button.text = "Classic Roomに戻る" if GameConfig.language == "ja" else "Return to Classic Room"
	title_button.add_theme_font_size_override("font_size", 24)
	title_button.pressed.connect(func() -> void:
		get_tree().paused = false
		NetworkManager.return_to_waiting_room()
	)
	content.add_child(title_button)
