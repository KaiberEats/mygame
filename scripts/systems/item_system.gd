class_name ItemSystem
extends Node

## アイテム（MISSILE/SWORD 等の能動、SCYTHE/COIN/RAPIER/SHIELD のパッシブ表示）の付与・使用・更新。
## 状態は ItemComponent / StatusComponent（_game 経由）。scythe/sword 等の戦闘実体は CombatSystem 側。

var _game: Node


func setup(game: Node) -> void:
	_game = game


func grant(participant: Node3D, item_name: String, duration: float = 0.0, icon: Texture2D = null) -> void:
	_game._item(participant).data = {
		"name": item_name,
		"duration": maxf(duration, 0.0),
		"time_left": maxf(duration, 0.0),
		"icon": icon,
	}
	sync_player_slot()


func update(delta: float) -> void:
	for participant in _game._participants:
		if not is_instance_valid(participant) or not _game._item(participant).has_item():
			continue

		var item: Dictionary = _game._item(participant).data
		var duration: float = float(item.get("duration", 0.0))
		if duration <= 0.0:
			continue

		var time_left: float = maxf(float(item.get("time_left", 0.0)) - delta, 0.0)
		if time_left <= 0.0:
			_game._item(participant).clear()
		else:
			item["time_left"] = time_left
			_game._item(participant).data = item

	sync_player_slot()


func use(participant: Node3D) -> void:
	if not _game._item(participant).has_item():
		use_passive(participant, "")
		return

	var item: Dictionary = _game._item(participant).data
	var item_name := String(item.get("name", ""))
	if item_name == "MISSILE":
		var target: Node3D = _game._find_visible_missile_target(participant)
		if target == null:
			return
		_game._launch_missile(participant, target)
	elif item_name == "SWORD":
		_game._combat.use_sword(participant)
	var charges_left := int(item.get("charges", 1)) - 1
	if charges_left > 0:
		item["charges"] = charges_left
		_game._item(participant).data = item
	else:
		_game._item(participant).clear()
	activate(participant, item_name)
	sync_player_slot()


func activate(_participant: Node3D, _item_name: String) -> void:
	pass


func use_passive(participant: Node3D, target_name: String) -> void:
	if _game._status_system.has_ready_scythe(participant):
		var target: Node3D = _game._participant_by_name(target_name)
		_game._combat.use_scythe(participant, target)
	elif _game._status_system.has_ready_coin(participant):
		var target: Node3D = _game._participant_by_name(target_name)
		if target != null:
			_game._combat.perform_change(participant, target, true)


func sync_player_slot() -> void:
	if not _game._item(_game.player).has_item():
		var passive_item := passive_slot_for(_game.player)
		if passive_item.is_empty():
			_game.game_hud.set_item("")
		else:
			_game.game_hud.set_item(
				String(passive_item.get("name", "")),
				float(passive_item.get("time_left", 0.0)),
				float(passive_item.get("duration", 0.0))
			)
		return

	var item: Dictionary = _game._item(_game.player).data
	_game.game_hud.set_item(
		String(item.get("name", "")),
		float(item.get("time_left", 0.0)),
		float(item.get("duration", 0.0)),
		item.get("icon") as Texture2D
	)


func passive_slot_for(participant: Node3D) -> Dictionary:
	if not is_instance_valid(participant):
		return {}
	var effects: Dictionary = _game._status(participant).data
	var now: float = _game._now()
	var scythe_until := maxf(
		float(effects.get("scythe_until", 0.0)),
		float(effects.get("automatic_kill_until", 0.0))
	)
	if scythe_until > now:
		return {
			"name": "SCYTHE",
			"time_left": scythe_until - now,
			"duration": 15.0,
		}
	var coin_until := float(effects.get("coin_until", 0.0))
	if int(effects.get("coin_count", 0)) > 0 and coin_until > now:
		return {
			"name": "COIN",
			"time_left": coin_until - now,
			"duration": float(effects.get("coin_duration", 20.0)),
		}
	var rapier_until := float(effects.get("counter_until", 0.0))
	if rapier_until > now:
		return {
			"name": "RAPIER",
			"time_left": rapier_until - now,
			"duration": float(effects.get("counter_duration", 3.0)),
		}
	if int(effects.get("barrier_charges", 0)) > 0:
		return {
			"name": "SHIELD",
			"time_left": 0.0,
			"duration": 0.0,
		}
	return {}


func update_computer_items() -> void:
	for participant in _game._participants:
		if not _game._is_computer(participant) or participant.is_stunned() or not _game._item(participant).has_item():
			continue
		if randf() < 0.005:
			use(participant)
