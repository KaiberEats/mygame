extends Node

signal peers_changed
signal connection_failed

const MAX_CLIENTS := 9

var players: Dictionary = {}
var player_colors: Dictionary = {}
var is_online := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


func host(port: int) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	is_online = true
	players[1] = GameConfig.player_name
	player_colors[1] = GameConfig.player_color_name
	peers_changed.emit()
	return OK


func join(address: String, port: int) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	is_online = true
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	player_colors.clear()
	is_online = false


func start_game() -> void:
	if is_online and multiplayer.is_server():
		_load_game.rpc(GameConfig.computer_count, GameConfig.deck_size, GameConfig.time_limit_minutes)
	else:
		get_tree().change_scene_to_file("res://scenes/Mansion.tscn")


func return_to_waiting_room() -> void:
	if not is_online:
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	elif multiplayer.is_server():
		_load_scene.rpc("res://scenes/Main.tscn")
	else:
		_request_return_to_waiting_room.rpc_id(1)


func get_player_name(peer_id: int) -> String:
	return String(players.get(peer_id, "Player %d" % peer_id))


func get_player_color(peer_id: int) -> Color:
	var color_name := String(player_colors.get(peer_id, "black"))
	return GameConfig.color_for_name(color_name)


func _on_peer_connected(_peer_id: int) -> void:
	if multiplayer.is_server():
		_receive_roster.rpc_id(_peer_id, players, player_colors)


func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	player_colors.erase(peer_id)
	peers_changed.emit()


func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, GameConfig.player_name, GameConfig.player_color_name)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_connection_failed() -> void:
	close()
	connection_failed.emit()


@rpc("any_peer", "reliable")
func _register_player(player_name: String, color_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	players[peer_id] = player_name
	player_colors[peer_id] = color_name
	_receive_roster.rpc(players, player_colors)
	peers_changed.emit()


@rpc("authority", "call_local", "reliable")
func _receive_roster(roster: Dictionary, color_roster: Dictionary) -> void:
	players = roster
	players[multiplayer.get_unique_id()] = GameConfig.player_name
	player_colors = color_roster
	player_colors[multiplayer.get_unique_id()] = GameConfig.player_color_name
	peers_changed.emit()


@rpc("authority", "call_local", "reliable")
func _load_scene(scene_path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)


@rpc("any_peer", "call_remote", "reliable")
func _request_return_to_waiting_room() -> void:
	if multiplayer.is_server():
		_load_scene.rpc("res://scenes/Main.tscn")


@rpc("authority", "call_local", "reliable")
func _load_game(computer_count: int, deck_size: int, time_limit_minutes: int) -> void:
	GameConfig.computer_count = computer_count
	GameConfig.deck_size = deck_size
	GameConfig.time_limit_minutes = time_limit_minutes
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Mansion.tscn")
