class_name Participants
extends RefCounted

## 参加者（Player + Computer/NetworkPlayer）の生成・配置・リスポーンを担う。
## 参加者ノードの親付けは現状 Match 直下のまま（コンテナ化は今後）。RPC 発火は _game 経由。

const SPAWN_POINTS := [
	Vector3(-34.0, 0.0, 34.0), Vector3(34.0, 0.0, 34.0), Vector3(34.0, 0.0, -34.0), Vector3(-34.0, 0.0, -34.0),
	Vector3(0.0, 0.0, 34.0), Vector3(34.0, 0.0, 0.0), Vector3(0.0, 0.0, -34.0), Vector3(-34.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 0.0),
]

var _game: Node


func setup(game: Node) -> void:
	_game = game


func configure_computers() -> void:
	var computers: Array = []
	for child in _game._participants_root.get_children():
		if child is CharacterBody3D and child != _game.player:
			computers.append(child)

	while computers.size() > GameConfig.computer_count:
		var computer: Node3D = computers.pop_back()
		computer.free()
	while computers.size() < GameConfig.computer_count:
		var computer: Node3D = _game.COMPUTER_SCENE.instantiate()
		_game._participants_root.add_child(computer)
		computers.append(computer)

	for index in computers.size():
		computers[index].name = ("%s %d" % ["コンピューター" if GameConfig.language == "ja" else "Computer", index + 1])
		computers[index].global_position = spawn_position_for_index(index + 1)
	_game.player.display_name = GameConfig.player_name
	_game.player.global_position = spawn_position_for_index(0)
	if _game.player.has_method("set_body_color"):
		_game.player.set_body_color(GameConfig.player_color())


func spawn_network_players() -> void:
	var local_peer: int = _game.multiplayer.get_unique_id()
	_game.player.set_multiplayer_authority(1)
	_game.player.display_name = NetworkManager.get_player_name(1) if NetworkManager.is_online else GameConfig.player_name
	if _game.player.has_method("set_body_color"):
		_game.player.set_body_color(NetworkManager.get_player_color(1) if NetworkManager.is_online else GameConfig.player_color())
	for peer_id in NetworkManager.players:
		if int(peer_id) == 1:
			continue
		var remote_player: CharacterBody3D = _game.PLAYER_SCENE.instantiate()
		remote_player.name = "NetworkPlayer_%d" % int(peer_id)
		remote_player.display_name = NetworkManager.get_player_name(int(peer_id))
		remote_player.set_multiplayer_authority(int(peer_id))
		_game._participants_root.add_child(remote_player)
		remote_player.set_body_color(NetworkManager.get_player_color(int(peer_id)))
		remote_player.global_position = spawn_position_for_peer(int(peer_id))
		if int(peer_id) == local_peer:
			_game.player = remote_player
			_game.player.ensure_local_camera()


func refresh_network_player_profiles() -> void:
	if not NetworkManager.is_online:
		if _game.player != null:
			_game.player.display_name = GameConfig.player_name
			if _game.player.has_method("set_body_color"):
				_game.player.set_body_color(GameConfig.player_color())
		return
	for participant in _game._participants:
		if not is_instance_valid(participant):
			continue
		var peer_id: int = _game._net.peer_for_participant(participant)
		if peer_id <= 0:
			continue
		participant.display_name = NetworkManager.get_player_name(peer_id)
		if participant.has_method("set_body_color"):
			participant.set_body_color(NetworkManager.get_player_color(peer_id))


func spawn_position_for_index(index: int) -> Vector3:
	return SPAWN_POINTS[index % SPAWN_POINTS.size()]


func spawn_position_for_peer(peer_id: int) -> Vector3:
	if peer_id <= 1:
		return spawn_position_for_index(0)
	return spawn_position_for_index(peer_id - 1)


func cache_spawn_positions() -> void:
	_game._participant_spawn_positions.clear()
	for index in _game._participants.size():
		var participant: Node3D = _game._participants[index]
		_game._participant_spawn_positions[participant] = default_spawn_for(participant)


func default_spawn_for(participant: Node3D) -> Vector3:
	var peer_id: int = _game._net.peer_for_participant(participant)
	if peer_id > 0:
		return spawn_position_for_peer(peer_id)
	var index: int = maxi(_game._participants.find(participant), 0)
	return spawn_position_for_index(index)


func respawn_out_of_bounds() -> void:
	for participant in _game._participants:
		if not is_instance_valid(participant):
			continue
		var horizontal := Vector2(participant.global_position.x, participant.global_position.z)
		if participant.global_position.y >= GameConfig.FALL_RESPAWN_Y and horizontal.length() <= GameConfig.MAP_RESPAWN_DISTANCE:
			continue
		var spawn_position: Vector3 = _game._participant_spawn_positions.get(participant, default_spawn_for(participant))
		participant.global_position = spawn_position
		if participant is CharacterBody3D:
			participant.velocity = Vector3.ZERO
		var peer_id: int = _game._net.peer_for_participant(participant)
		if NetworkManager.is_online and peer_id > 1:
			_game.respawn_remote(peer_id, participant.name, spawn_position)
