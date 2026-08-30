class_name ItemSystem
extends Node

## アイテム（MISSILE/SWORD 等の能動、SCYTHE/COIN/RAPIER/SHIELD のパッシブ表示）の付与・使用・更新。
## 状態は各参加者の ItemComponent / StatusComponent。scythe/sword 等の戦闘実体は CombatSystem 側。

var _participants: Participants
var _combat: CombatSystem
var _status_system: StatusSystem
var _targeting: TargetingService
var _net_gateway: NetGateway
var _game_hud: CanvasLayer


func setup(participants: Participants, combat: CombatSystem, status_system: StatusSystem,
		targeting: TargetingService, net_gateway: NetGateway, game_hud: CanvasLayer) -> void:
	_participants = participants
	_combat = combat
	_status_system = status_system
	_targeting = targeting
	_net_gateway = net_gateway
	_game_hud = game_hud


func grant(participant: Node3D, item_name: String, duration: float = 0.0, icon: Texture2D = null) -> void:
	participant.item().data = {
		"name": item_name,
		"duration": maxf(duration, 0.0),
		"time_left": maxf(duration, 0.0),
		"icon": icon,
	}
	sync_player_slot()


func update(delta: float) -> void:
	for participant in _participants.all:
		if not is_instance_valid(participant) or not participant.item().has_item():
			continue

		var item: Dictionary = participant.item().data
		var duration: float = float(item.get("duration", 0.0))
		if duration <= 0.0:
			continue

		var time_left: float = maxf(float(item.get("time_left", 0.0)) - delta, 0.0)
		if time_left <= 0.0:
			participant.item().clear()
		else:
			item["time_left"] = time_left
			participant.item().data = item

	sync_player_slot()


func use(participant: Node3D) -> void:
	if not participant.item().has_item():
		use_passive(participant, "")
		return

	var item: Dictionary = participant.item().data
	var item_name := String(item.get("name", ""))
	if item_name == "MISSILE":
		var target: Node3D = _targeting.find_visible_missile(participant, _participants.all, _participants.local_player, GameConfig.KILL_CENTER_DOT)
		if target == null:
			return
		_net_gateway.launch_missile(participant, target)
	elif item_name == "SWORD":
		_combat.use_sword(participant)
	var charges_left := int(item.get("charges", 1)) - 1
	if charges_left > 0:
		item["charges"] = charges_left
		participant.item().data = item
	else:
		participant.item().clear()
	activate(participant, item_name)
	sync_player_slot()


func activate(_participant: Node3D, _item_name: String) -> void:
	pass


func use_passive(participant: Node3D, target_name: String) -> void:
	if _status_system.has_ready_scythe(participant):
		var target: Node3D = _participants.by_name(target_name)
		_combat.use_scythe(participant, target)
	elif _status_system.has_ready_coin(participant):
		var target: Node3D = _participants.by_name(target_name)
		if target != null:
			_combat.perform_change(participant, target, true)


func sync_player_slot() -> void:
	if not _participants.local_player.item().has_item():
		var passive_item := passive_slot_for(_participants.local_player)
		if passive_item.is_empty():
			_game_hud.set_item("")
		else:
			_game_hud.set_item(
				String(passive_item.get("name", "")),
				float(passive_item.get("time_left", 0.0)),
				float(passive_item.get("duration", 0.0))
			)
		return

	var item: Dictionary = _participants.local_player.item().data
	_game_hud.set_item(
		String(item.get("name", "")),
		float(item.get("time_left", 0.0)),
		float(item.get("duration", 0.0)),
		item.get("icon") as Texture2D
	)


func passive_slot_for(participant: Node3D) -> Dictionary:
	if not is_instance_valid(participant):
		return {}
	var effects: Dictionary = participant.status().data
	var now: float = Clock.now()
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
	for participant in _participants.all:
		if not participant.is_computer() or participant.is_stunned() or not participant.item().has_item():
			continue
		if randf() < 0.005:
			use(participant)
