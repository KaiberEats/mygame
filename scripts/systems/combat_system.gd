class_name CombatSystem
extends Node

## kill / change / scythe / sword / barrier / counter / invincible / 自動kill の判定と適用。
## 状態は各参加者の StatusComponent / CooldownComponent。チェンジ権(change_killers)は本 System が所有。
## 通知・変更プレビューは NetGateway 経由。ミサイルは RPC の都合で match 側に残す。

var _change_killers: Dictionary = {}

var _participants: Participants
var _status_system: StatusSystem
var _item_system: ItemSystem
var _targeting: TargetingService
var _net_gateway: NetGateway
var _game_hud: CanvasLayer


func setup(participants: Participants, status_system: StatusSystem, item_system: ItemSystem,
		targeting: TargetingService, net_gateway: NetGateway, game_hud: CanvasLayer) -> void:
	_participants = participants
	_status_system = status_system
	_item_system = item_system
	_targeting = targeting
	_net_gateway = net_gateway
	_game_hud = game_hud


## チェンジ権テーブル(target -> 直近killer)。ネット直列化/検証から参照・更新される。
func change_rights() -> Dictionary:
	return _change_killers


func try_computer_kills() -> void:
	for participant in _participants.all:
		if (
			not participant.is_computer()
			or participant.is_stunned()
			or participant.cooldown().kill_left(Clock.now()) > 0.0
			or (not participant.has_joker() and not _status_system.has_extra_kill(participant))
		):
			continue

		var target: Node3D = participant.get_chase_target()
		if target != null and participant.global_position.distance_to(target.global_position) <= GameConfig.KILL_DISTANCE:
			perform_kill(participant, target)
			if randf() < 0.5:
				perform_change(participant, target)
			else:
				_change_killers.erase(target)


func try_computer_free_changes() -> void:
	for participant in _participants.all:
		if not participant.is_computer() or participant.is_stunned() or not _status_system.has_free_change(participant):
			continue
		var target := _participants.nearest(participant)
		if target != null and participant.global_position.distance_to(target.global_position) <= GameConfig.KILL_DISTANCE:
			perform_change(participant, target)


func update_automatic_kills() -> void:
	for attacker in _participants.all:
		if attacker.is_stunned() or not _status_system.is_effect_active(attacker, "automatic_kill_until"):
			continue
		var effects: Dictionary = attacker.status().data
		var previous_targets: Dictionary = effects.get("automatic_kill_targets", {})
		var current_targets: Dictionary = {}
		for target in _participants.all:
			if (
				target == attacker
				or attacker.global_position.distance_to(target.global_position) > GameConfig.KILL_DISTANCE
			):
				continue
			current_targets[target] = true
			if previous_targets.has(target) or target.is_stunned():
				continue
			perform_kill_with_options(attacker, target, false, false)
			if attacker.is_stunned():
				break
		effects["automatic_kill_targets"] = current_targets


func perform_kill(attacker: Node3D, target: Node3D) -> void:
	if attacker.cooldown().kill_left(Clock.now()) > 0.0:
		return
	attacker.cooldown().kill_until = Clock.now() + GameConfig.KILL_COOLDOWN_SECONDS
	perform_kill_with_options(attacker, target, true, true)


func perform_kill_with_options(attacker: Node3D, target: Node3D, allow_change: bool, consume_extra_kill: bool) -> void:
	var effects: Dictionary = target.status().data
	if _status_system.is_effect_active(target, "invincible_until"):
		return
	if _status_system.is_effect_active(target, "counter_until"):
		stun_without_change(attacker)
		effects.erase("counter_until")
		effects.erase("counter_duration")
		_item_system.sync_player_slot()
		return
	if int(effects.get("barrier_charges", 0)) > 0:
		effects["barrier_charges"] = int(effects["barrier_charges"]) - 1
		set_barrier_visual(target, int(effects.get("barrier_charges", 0)) > 0)
		_item_system.sync_player_slot()
		return

	var used_extra_kill: bool = consume_extra_kill and not attacker.has_joker() and _status_system.has_extra_kill(attacker)
	if used_extra_kill:
		var attacker_effects: Dictionary = attacker.status().data
		attacker_effects["extra_kill_available"] = false
		if attacker.has_method("set_can_kill_without_joker"):
			attacker.set_can_kill_without_joker(false)
		_item_system.sync_player_slot()
	target.stun(GameConfig.STUN_SECONDS)
	show_kill_notifications(attacker, target)
	if allow_change and not used_extra_kill:
		_change_killers[target] = attacker
	else:
		_change_killers.erase(target)
	_game_hud.set_kill_available(false)
	_game_hud.set_change_available(false)


func perform_change(attacker: Node3D, target: Node3D, forced_free_change: bool = false) -> void:
	var free_change: bool = _status_system.has_free_change(attacker) or forced_free_change
	if (
		(not free_change and (_change_killers.get(target) != attacker or not target.is_stunned()))
		or attacker.hand.is_empty()
		or target.hand.is_empty()
	):
		return

	var attacker_hand: Array[Dictionary] = attacker.hand.duplicate()
	var target_hand: Array[Dictionary] = target.hand.duplicate()
	var attacker_index := attacker_hand.size() - 1
	var target_index := randi_range(0, target_hand.size() - 1)
	var attacker_card: Dictionary = attacker_hand[attacker_index]
	var target_card: Dictionary = target_hand[target_index]
	attacker_hand[attacker_index] = target_hand[target_index]
	target_hand[target_index] = attacker_card
	attacker.set_hand(attacker_hand, true)
	target.set_hand(target_hand, true)
	_net_gateway.show_change_preview(attacker, attacker_card, target_card)
	_net_gateway.show_change_preview(target, target_card, attacker_card)
	_change_killers.erase(target)
	if free_change:
		var effects: Dictionary = attacker.status().data
		if forced_free_change:
			effects["coin_count"] = maxi(int(effects.get("coin_count", 0)) - 1, 0)
			if int(effects.get("coin_count", 0)) <= 0:
				effects.erase("coin_until")
				effects.erase("coin_duration")
		else:
			effects["free_change_count"] = maxi(int(effects.get("free_change_count", 0)) - 1, 0)
		_item_system.sync_player_slot()

	_game_hud.set_change_available(false)


func clear_expired_change_rights() -> void:
	for target in _change_killers.keys():
		if not is_instance_valid(target) or (not target.is_stunned() and not target.is_stun_pending()):
			_change_killers.erase(target)


func use_scythe(attacker: Node3D, target: Node3D) -> void:
	var effects: Dictionary = attacker.status().data
	if not _status_system.has_ready_scythe(attacker):
		return
	var remaining: float = maxf(float(effects.get("scythe_until", 0.0)) - Clock.now(), 0.0)
	var is_enhanced := bool(effects.get("scythe_enhanced", false))
	effects.erase("scythe_until")
	effects.erase("scythe_enhanced")
	if is_enhanced:
		effects["automatic_kill_until"] = Clock.now() + remaining
		effects["automatic_kill_targets"] = {}
		_item_system.sync_player_slot()
		return
	if target == null or attacker.cooldown().kill_left(Clock.now()) > 0.0:
		_item_system.sync_player_slot()
		return
	attacker.cooldown().kill_until = Clock.now() + GameConfig.KILL_COOLDOWN_SECONDS
	perform_kill_with_options(attacker, target, false, false)
	_item_system.sync_player_slot()


func use_sword(attacker: Node3D) -> void:
	for target in _participants.all:
		if target == attacker or attacker.global_position.distance_to(target.global_position) > GameConfig.KILL_DISTANCE:
			continue

		# Sword hits intentionally bypass invincibility, barriers, counters, and other defenses.
		target.stun(GameConfig.STUN_SECONDS)
		show_kill_notifications(attacker, target)
		_change_killers[target] = attacker

	_game_hud.set_kill_available(false)
	_game_hud.set_change_available(false)


func stun_without_change(target: Node3D) -> void:
	if _status_system.is_effect_active(target, "invincible_until"):
		return
	target.stun(GameConfig.STUN_SECONDS)
	_change_killers.erase(target)


func set_barrier_visual(participant: Node3D, is_active: bool) -> void:
	if participant != null and participant.has_method("set_barrier_active"):
		participant.set_barrier_active(is_active)


func show_kill_notifications(attacker: Node3D, target: Node3D) -> void:
	_net_gateway.notify(target, GameConfig.text("killed"))
	_net_gateway.notify(attacker, GameConfig.text("kill_notice") % target.get_display_name())


# --- 行動可否ゲート付きの照準（純幾何は TargetingService、ここは可否条件を足す）----------
func find_kill_target(attacker: Node3D) -> Node3D:
	if not attacker.has_joker() or attacker.is_stunned() or attacker.cooldown().kill_left(Clock.now()) > 0.0:
		return null
	return _targeting.find_aimed(attacker, _participants.all, _change_killers, false, GameConfig.KILL_DISTANCE, GameConfig.KILL_CENTER_DOT)


func find_change_target(attacker: Node3D) -> Node3D:
	if attacker.is_stunned() or attacker.hand.is_empty():
		return null
	if _status_system.has_free_change(attacker):
		return _targeting.find_aimed(attacker, _participants.all, _change_killers, false, GameConfig.KILL_DISTANCE, GameConfig.KILL_CENTER_DOT)
	return _targeting.find_aimed(attacker, _participants.all, _change_killers, true, GameConfig.KILL_DISTANCE, GameConfig.KILL_CENTER_DOT)


func find_scythe_target(attacker: Node3D) -> Node3D:
	if not _status_system.has_ready_scythe(attacker) or attacker.is_stunned() or attacker.cooldown().kill_left(Clock.now()) > 0.0:
		return null
	return _targeting.find_aimed(attacker, _participants.all, _change_killers, false, GameConfig.KILL_DISTANCE, GameConfig.KILL_CENTER_DOT)


func find_coin_change_target(attacker: Node3D) -> Node3D:
	if not _status_system.has_ready_coin(attacker) or attacker.is_stunned() or attacker.hand.is_empty():
		return null
	return _targeting.find_aimed(attacker, _participants.all, _change_killers, false, GameConfig.KILL_DISTANCE, GameConfig.KILL_CENTER_DOT)
