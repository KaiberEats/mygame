class_name CombatSystem
extends Node

## kill / change / scythe / sword / barrier / counter / invincible / 自動kill の判定と適用。
## 状態は StatusComponent / CooldownComponent（_game 経由）。通知は _game.notify_participant。
## ミサイルの発射・生成・命中コールバックは RPC / self 参照の都合で match(_game) 側に残す。

var _game: Node


func setup(game: Node) -> void:
	_game = game


func try_computer_kills() -> void:
	for participant in _game._participants:
		if (
			not _game._is_computer(participant)
			or participant.is_stunned()
			or _game._get_kill_cooldown_left(participant) > 0.0
			or (not participant.has_joker() and not _game._status_system.has_extra_kill(participant))
		):
			continue

		var target: Node3D = participant.get_chase_target()
		if target != null and participant.global_position.distance_to(target.global_position) <= GameConfig.KILL_DISTANCE:
			perform_kill(participant, target)
			if randf() < 0.5:
				perform_change(participant, target)
			else:
				_game._change_killers.erase(target)


func update_automatic_kills() -> void:
	for attacker in _game._participants:
		if attacker.is_stunned() or not _game._status_system.is_effect_active(attacker, "automatic_kill_until"):
			continue
		var effects: Dictionary = _game._status(attacker).data
		var previous_targets: Dictionary = effects.get("automatic_kill_targets", {})
		var current_targets: Dictionary = {}
		for target in _game._participants:
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
	if _game._get_kill_cooldown_left(attacker) > 0.0:
		return
	_game._cooldown(attacker).kill_until = Clock.now() + GameConfig.KILL_COOLDOWN_SECONDS
	perform_kill_with_options(attacker, target, true, true)


func perform_kill_with_options(attacker: Node3D, target: Node3D, allow_change: bool, consume_extra_kill: bool) -> void:
	var effects: Dictionary = _game._status(target).data
	if _game._status_system.is_effect_active(target, "invincible_until"):
		return
	if _game._status_system.is_effect_active(target, "counter_until"):
		stun_without_change(attacker)
		effects.erase("counter_until")
		effects.erase("counter_duration")
		_game._item_system.sync_player_slot()
		return
	if int(effects.get("barrier_charges", 0)) > 0:
		effects["barrier_charges"] = int(effects["barrier_charges"]) - 1
		set_barrier_visual(target, int(effects.get("barrier_charges", 0)) > 0)
		_game._item_system.sync_player_slot()
		return

	var used_extra_kill: bool = consume_extra_kill and not attacker.has_joker() and _game._status_system.has_extra_kill(attacker)
	if used_extra_kill:
		var attacker_effects: Dictionary = _game._status(attacker).data
		attacker_effects["extra_kill_available"] = false
		if attacker.has_method("set_can_kill_without_joker"):
			attacker.set_can_kill_without_joker(false)
		_game._item_system.sync_player_slot()
	target.stun(GameConfig.STUN_SECONDS)
	show_kill_notifications(attacker, target)
	if allow_change and not used_extra_kill:
		_game._change_killers[target] = attacker
	else:
		_game._change_killers.erase(target)
	_game._player_kill_target = null
	_game._player_change_target = null
	_game.game_hud.set_kill_available(false)
	_game.game_hud.set_change_available(false)


func perform_change(attacker: Node3D, target: Node3D, forced_free_change: bool = false) -> void:
	var free_change: bool = _game._status_system.has_free_change(attacker) or forced_free_change
	if (
		(not free_change and (_game._change_killers.get(target) != attacker or not target.is_stunned()))
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
	_game._show_change_preview_for_participant(attacker, attacker_card, target_card)
	_game._show_change_preview_for_participant(target, target_card, attacker_card)
	_game._change_killers.erase(target)
	if free_change:
		var effects: Dictionary = _game._status(attacker).data
		if forced_free_change:
			effects["coin_count"] = maxi(int(effects.get("coin_count", 0)) - 1, 0)
			if int(effects.get("coin_count", 0)) <= 0:
				effects.erase("coin_until")
				effects.erase("coin_duration")
		else:
			effects["free_change_count"] = maxi(int(effects.get("free_change_count", 0)) - 1, 0)
		_game._item_system.sync_player_slot()

	_game._player_change_target = null
	_game.game_hud.set_change_available(false)


func clear_expired_change_rights() -> void:
	for target in _game._change_killers.keys():
		if not is_instance_valid(target) or (not target.is_stunned() and not target.is_stun_pending()):
			_game._change_killers.erase(target)


func use_scythe(attacker: Node3D, target: Node3D) -> void:
	var effects: Dictionary = _game._status(attacker).data
	if not _game._status_system.has_ready_scythe(attacker):
		return
	var remaining: float = maxf(float(effects.get("scythe_until", 0.0)) - Clock.now(), 0.0)
	var is_enhanced := bool(effects.get("scythe_enhanced", false))
	effects.erase("scythe_until")
	effects.erase("scythe_enhanced")
	if is_enhanced:
		effects["automatic_kill_until"] = Clock.now() + remaining
		effects["automatic_kill_targets"] = {}
		_game._item_system.sync_player_slot()
		return
	if target == null or _game._get_kill_cooldown_left(attacker) > 0.0:
		_game._item_system.sync_player_slot()
		return
	_game._cooldown(attacker).kill_until = Clock.now() + GameConfig.KILL_COOLDOWN_SECONDS
	perform_kill_with_options(attacker, target, false, false)
	_game._item_system.sync_player_slot()


func use_sword(attacker: Node3D) -> void:
	for target in _game._participants:
		if target == attacker or attacker.global_position.distance_to(target.global_position) > GameConfig.KILL_DISTANCE:
			continue

		# Sword hits intentionally bypass invincibility, barriers, counters, and other defenses.
		target.stun(GameConfig.STUN_SECONDS)
		show_kill_notifications(attacker, target)
		_game._change_killers[target] = attacker

	_game._player_kill_target = null
	_game._player_change_target = null
	_game.game_hud.set_kill_available(false)
	_game.game_hud.set_change_available(false)


func stun_without_change(target: Node3D) -> void:
	if _game._status_system.is_effect_active(target, "invincible_until"):
		return
	target.stun(GameConfig.STUN_SECONDS)
	_game._change_killers.erase(target)


func set_barrier_visual(participant: Node3D, is_active: bool) -> void:
	if participant != null and participant.has_method("set_barrier_active"):
		participant.set_barrier_active(is_active)


func show_kill_notifications(attacker: Node3D, target: Node3D) -> void:
	_game.notify_participant(target, GameConfig.text("killed"))
	_game.notify_participant(attacker, GameConfig.text("kill_notice") % _game._participant_name(target))


# --- 行動可否ゲート付きの照準（純幾何は TargetingService、ここは可否条件を足す）----------
func find_kill_target(attacker: Node3D) -> Node3D:
	if not attacker.has_joker() or attacker.is_stunned() or _game._get_kill_cooldown_left(attacker) > 0.0:
		return null
	return _game._find_aimed_target(attacker, false)


func find_change_target(attacker: Node3D) -> Node3D:
	if attacker.is_stunned() or attacker.hand.is_empty():
		return null
	if _game._status_system.has_free_change(attacker):
		return _game._find_aimed_target(attacker, false)
	return _game._find_aimed_target(attacker, true)


func find_scythe_target(attacker: Node3D) -> Node3D:
	if not _game._status_system.has_ready_scythe(attacker) or attacker.is_stunned() or _game._get_kill_cooldown_left(attacker) > 0.0:
		return null
	return _game._find_aimed_target(attacker, false)


func find_coin_change_target(attacker: Node3D) -> Node3D:
	if not _game._status_system.has_ready_coin(attacker) or attacker.is_stunned() or attacker.hand.is_empty():
		return null
	return _game._find_aimed_target(attacker, false)
