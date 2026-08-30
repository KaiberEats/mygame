class_name GameFlow
extends Node

## 試合進行: 終了条件・順位計算・リザルト表示。
## 制限時間・終了フラグは GameStateManager が保持し、終了の一斉通知は NetGateway 経由。

const RESULTS_SCENE := preload("res://scenes/ui/Results.tscn")

var _participants: Participants
var _game_state: GameStateManager
var _net_gateway: NetGateway
var _game_hud: CanvasLayer
var _world: Node


func setup(participants: Participants, game_state: GameStateManager, net_gateway: NetGateway,
		game_hud: CanvasLayer, world: Node) -> void:
	_participants = participants
	_game_state = game_state
	_net_gateway = net_gateway
	_game_hud = game_hud
	_world = world


func has_empty_hand() -> bool:
	for participant in _participants.all:
		if participant.hand.is_empty():
			return true
	return false


func finish_game() -> void:
	if _game_state.is_ending:
		return
	_game_state.is_ending = true
	var standings := calculate_standings()
	if NetworkManager.is_online and multiplayer.is_server():
		var network_standings: Dictionary = {}
		for participant in standings:
			network_standings[participant.name] = standings[participant]
		_net_gateway.broadcast_game_finished(network_standings)
	var player_rank := int(standings[_participants.local_player])
	_game_hud.show_end_message(GameConfig.text("win") if player_rank == 1 else GameConfig.text("place") % player_rank)
	Engine.time_scale = 0.2
	await get_tree().create_timer(5.0, true, false, true).timeout
	Engine.time_scale = 1.0
	show_results(standings)


func receive_game_finished(network_standings: Dictionary) -> void:
	if _game_state.is_ending:
		return
	_game_state.is_ending = true
	var standings: Dictionary = {}
	for participant_name in network_standings:
		var participant: Node3D = _participants.by_name(String(participant_name))
		if participant != null:
			standings[participant] = int(network_standings[participant_name])
	var player_rank := int(standings.get(_participants.local_player, _participants.all.size()))
	_game_hud.show_end_message(GameConfig.text("win") if player_rank == 1 else GameConfig.text("place") % player_rank)
	Engine.time_scale = 0.2
	await get_tree().create_timer(5.0, true, false, true).timeout
	Engine.time_scale = 1.0
	show_results(standings)


func calculate_standings() -> Dictionary:
	var sorted_participants: Array = _participants.all.duplicate()
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
	_game_hud.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var results: CanvasLayer = RESULTS_SCENE.instantiate()
	_world.add_child(results)
	var content := results.get_node(^"Center/Content") as VBoxContainer
	var title := content.get_node(^"Title") as Label
	title.text = GameConfig.text("result")
	var return_button := content.get_node(^"ReturnButton") as Button
	return_button.text = "Classic Roomに戻る" if GameConfig.language == "ja" else "Return to Classic Room"
	return_button.pressed.connect(func() -> void:
		get_tree().paused = false
		NetworkManager.return_to_waiting_room()
	)

	var sorted_participants: Array = _participants.all.duplicate()
	sorted_participants.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return int(standings[a]) < int(standings[b])
	)
	for participant in sorted_participants:
		var row := Label.new()
		row.text = "%d  %s  -  %s%s" % [
			int(standings[participant]),
			participant.get_display_name(),
			GameConfig.text("cards") % participant.hand.size(),
			("  ジョーカー" if GameConfig.language == "ja" else "  JOKER") if participant.has_joker() else "",
		]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 26)
		content.add_child(row)
	content.move_child(return_button, -1)
