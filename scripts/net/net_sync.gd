class_name NetSync
extends Node

## ネットの検証・ディスパッチ・peer解決。
## RPC の受け口（@rpc）は NodePath 一致のため match(_game) 側に残し、その本体からここを呼ぶ。

var _game: Node


func setup(game: Node) -> void:
	_game = game


func is_game_authority() -> bool:
	return not NetworkManager.is_online or multiplayer.is_server()


func participant_for_peer(peer_id: int) -> Node3D:
	return _game._participant_by_name("Player" if peer_id == 1 else "NetworkPlayer_%d" % peer_id)


func peer_for_participant(participant: Node3D) -> int:
	if participant.name == "Player":
		return 1
	if participant.name.begins_with("NetworkPlayer_"):
		return int(participant.name.trim_prefix("NetworkPlayer_"))
	return 0


func execute_player_action(actor: Node3D, action: String, value: int, target_name: String) -> void:
	match action:
		"pair":
			_game._ability.try_use_pair(actor, value)
		"item":
			_game._item_system.use(actor)
		"scythe":
			var target: Node3D = _game._participant_by_name(target_name)
			if can_server_scythe(actor, target):
				_game._combat.use_scythe(actor, target)
		"coin":
			var target: Node3D = _game._participant_by_name(target_name)
			if target != null and can_server_coin_change(actor, target):
				_game._combat.perform_change(actor, target, true)
		"kill":
			var target: Node3D = _game._participant_by_name(target_name)
			if target != null and can_server_kill(actor, target):
				_game._combat.perform_kill(actor, target)
		"change":
			var target: Node3D = _game._participant_by_name(target_name)
			if target != null and can_server_change(actor, target):
				_game._combat.perform_change(actor, target)


func can_server_kill(actor: Node3D, target: Node3D) -> bool:
	return (
		actor != target
		and actor.global_position.distance_to(target.global_position) <= GameConfig.KILL_DISTANCE + 0.5
		and not actor.is_stunned()
		and not target.is_stunned()
		and actor.cooldown().kill_left(Clock.now()) <= 0.0
		and actor.has_joker()
	)


func can_server_scythe(actor: Node3D, target: Node3D) -> bool:
	if actor == null or actor.is_stunned() or not _game._status_system.has_ready_scythe(actor):
		return false
	var effects: Dictionary = actor.status().data
	if bool(effects.get("scythe_enhanced", false)):
		return true
	return (
		target != null
		and actor != target
		and actor.global_position.distance_to(target.global_position) <= GameConfig.KILL_DISTANCE + 0.5
		and not target.is_stunned()
		and actor.cooldown().kill_left(Clock.now()) <= 0.0
	)


func can_server_change(actor: Node3D, target: Node3D) -> bool:
	return (
		actor != target
		and actor.global_position.distance_to(target.global_position) <= GameConfig.KILL_DISTANCE + 0.5
		and not actor.is_stunned()
		and not actor.hand.is_empty()
		and not target.hand.is_empty()
		and (_game._status_system.has_free_change(actor) or (_game._change_killers.get(target) == actor and target.is_stunned()))
	)


func can_server_coin_change(actor: Node3D, target: Node3D) -> bool:
	return (
		actor != target
		and actor.global_position.distance_to(target.global_position) <= GameConfig.KILL_DISTANCE + 0.5
		and not actor.is_stunned()
		and not target.is_stunned()
		and not actor.hand.is_empty()
		and not target.hand.is_empty()
		and _game._status_system.has_ready_coin(actor)
	)
