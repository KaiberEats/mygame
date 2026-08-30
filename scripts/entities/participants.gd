class_name Participants
extends RefCounted

## 参加者（Player + Computer/NetworkPlayer）のレジストリ。
## 一覧(all)・ローカルプレイヤー(local_player)・スポーン地点を所有し、生成/配置/リスポーンを担う。
## リモートへのリスポーン反映は remote_respawn_requested シグナルで上位（main の @rpc）へ委ねる。

signal remote_respawn_requested(peer_id: int, participant_name: String, spawn_position: Vector3)

const SPAWN_POINTS := [
	Vector3(-34.0, 0.0, 34.0), Vector3(34.0, 0.0, 34.0), Vector3(34.0, 0.0, -34.0), Vector3(-34.0, 0.0, -34.0),
	Vector3(0.0, 0.0, 34.0), Vector3(34.0, 0.0, 0.0), Vector3(0.0, 0.0, -34.0), Vector3(-34.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 0.0),
]

var all: Array[Node3D] = []
var local_player: Node3D = null

var _root: Node3D
var _net: NetSync
var _player_scene: PackedScene
var _computer_scene: PackedScene
var _spawn_positions: Dictionary = {}


func setup(root: Node3D, net: NetSync, player_scene: PackedScene, computer_scene: PackedScene) -> void:
	_root = root
	_net = net
	_player_scene = player_scene
	_computer_scene = computer_scene


## local_player と生成済み参加者から一覧を作る。
func collect() -> void:
	all = [local_player]
	for child in _root.get_children():
		if child is CharacterBody3D and child != local_player:
			all.append(child)


func by_name(participant_name: String) -> Node3D:
	for participant in all:
		if participant.name == participant_name:
			return participant
	return null


func configure_computers() -> void:
	var computers: Array = []
	for child in _root.get_children():
		if child is CharacterBody3D and child != local_player:
			computers.append(child)

	while computers.size() > GameConfig.computer_count:
		var computer: Node3D = computers.pop_back()
		computer.free()
	while computers.size() < GameConfig.computer_count:
		var computer: Node3D = _computer_scene.instantiate()
		_root.add_child(computer)
		computers.append(computer)

	for index in computers.size():
		computers[index].name = ("%s %d" % ["コンピューター" if GameConfig.language == "ja" else "Computer", index + 1])
		computers[index].global_position = spawn_position_for_index(index + 1)
	local_player.display_name = GameConfig.player_name
	local_player.global_position = spawn_position_for_index(0)
	if local_player.has_method("set_body_color"):
		local_player.set_body_color(GameConfig.player_color())


func spawn_network_players() -> void:
	var local_peer: int = _root.multiplayer.get_unique_id()
	local_player.set_multiplayer_authority(1)
	local_player.display_name = NetworkManager.get_player_name(1) if NetworkManager.is_online else GameConfig.player_name
	if local_player.has_method("set_body_color"):
		local_player.set_body_color(NetworkManager.get_player_color(1) if NetworkManager.is_online else GameConfig.player_color())
	for peer_id in NetworkManager.players:
		if int(peer_id) == 1:
			continue
		var remote_player: CharacterBody3D = _player_scene.instantiate()
		remote_player.name = "NetworkPlayer_%d" % int(peer_id)
		remote_player.display_name = NetworkManager.get_player_name(int(peer_id))
		remote_player.set_multiplayer_authority(int(peer_id))
		_root.add_child(remote_player)
		remote_player.set_body_color(NetworkManager.get_player_color(int(peer_id)))
		remote_player.global_position = spawn_position_for_peer(int(peer_id))
		if int(peer_id) == local_peer:
			local_player = remote_player
			local_player.ensure_local_camera()


func refresh_network_player_profiles() -> void:
	if not NetworkManager.is_online:
		if local_player != null:
			local_player.display_name = GameConfig.player_name
			if local_player.has_method("set_body_color"):
				local_player.set_body_color(GameConfig.player_color())
		return
	for participant in all:
		if not is_instance_valid(participant):
			continue
		var peer_id: int = _net.peer_for_participant(participant)
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
	_spawn_positions.clear()
	for participant in all:
		_spawn_positions[participant] = default_spawn_for(participant)


func default_spawn_for(participant: Node3D) -> Vector3:
	var peer_id: int = _net.peer_for_participant(participant)
	if peer_id > 0:
		return spawn_position_for_peer(peer_id)
	var index: int = maxi(all.find(participant), 0)
	return spawn_position_for_index(index)


func respawn_out_of_bounds() -> void:
	for participant in all:
		if not is_instance_valid(participant):
			continue
		var horizontal := Vector2(participant.global_position.x, participant.global_position.z)
		if participant.global_position.y >= GameConfig.FALL_RESPAWN_Y and horizontal.length() <= GameConfig.MAP_RESPAWN_DISTANCE:
			continue
		var spawn_position: Vector3 = _spawn_positions.get(participant, default_spawn_for(participant))
		participant.global_position = spawn_position
		if participant is CharacterBody3D:
			participant.velocity = Vector3.ZERO
		var peer_id: int = _net.peer_for_participant(participant)
		if NetworkManager.is_online and peer_id > 1:
			remote_respawn_requested.emit(peer_id, participant.name, spawn_position)
