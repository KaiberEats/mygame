class_name StatusSystem
extends Node

## 時限効果の期限処理(tick)・状態問い合わせ・視界(覗き見/開示)横断クエリ。
## 状態データは各参加者の StatusComponent / VisionComponent。

var _participants: Participants
var _item_system: ItemSystem
var _was_stunned: Dictionary = {}


func setup(participants: Participants, item_system: ItemSystem) -> void:
	_participants = participants
	_item_system = item_system


## 気絶明けバフ判定の初期状態を、生成済み参加者から作る。
func seed_stun_state() -> void:
	for participant in _participants.all:
		_was_stunned[participant] = participant.is_stunned()


## 毎フレーム: 各効果の期限切れを処理し、視界の期限も掃除する。
func update_effects() -> void:
	var now: float = Clock.now()
	for participant in _participants.all:
		var effects: Dictionary = participant.status().data
		if float(effects.get("invincible_until", 0.0)) > 0.0 and now >= float(effects["invincible_until"]):
			effects.erase("invincible_until")
			participant.set_gold_outline(false)
		if float(effects.get("invisible_until", 0.0)) > 0.0 and now >= float(effects["invisible_until"]):
			effects.erase("invisible_until")
			participant.set_invisible(false)
		if float(effects.get("free_change_until", 0.0)) > 0.0 and now >= float(effects["free_change_until"]):
			effects.erase("free_change_until")
			effects.erase("free_change_duration")
			effects["free_change_count"] = 0
			refresh_speed_multiplier(participant)
		if float(effects.get("coin_until", 0.0)) > 0.0 and now >= float(effects["coin_until"]):
			effects.erase("coin_until")
			effects.erase("coin_duration")
			effects["coin_count"] = 0
			refresh_speed_multiplier(participant)
		if float(effects.get("recovery_speed_until", 0.0)) > 0.0 and now >= float(effects["recovery_speed_until"]):
			effects.erase("recovery_speed_until")
			refresh_speed_multiplier(participant)
		if float(effects.get("extra_kill_until", 0.0)) > 0.0 and now >= float(effects["extra_kill_until"]):
			effects.erase("extra_kill_until")
			effects["extra_kill_available"] = false
			if participant.has_method("set_can_kill_without_joker"):
				participant.set_can_kill_without_joker(false)
		if float(effects.get("scythe_until", 0.0)) > 0.0 and now >= float(effects["scythe_until"]):
			effects.erase("scythe_until")
			effects.erase("scythe_enhanced")
		if float(effects.get("counter_until", 0.0)) > 0.0 and now >= float(effects["counter_until"]):
			effects.erase("counter_until")
			effects.erase("counter_duration")
		if float(effects.get("automatic_kill_until", 0.0)) > 0.0 and now >= float(effects["automatic_kill_until"]):
			effects.erase("automatic_kill_until")
			effects.erase("automatic_kill_targets")
		if float(effects.get("auto_cleanse_until", 0.0)) > 0.0:
			if now >= float(effects["auto_cleanse_until"]):
				effects.erase("auto_cleanse_until")
				effects.erase("auto_cleanse_at")
			elif has_negative_status(participant):
				if not effects.has("auto_cleanse_at"):
					effects["auto_cleanse_at"] = now + 3.0
				elif now >= float(effects["auto_cleanse_at"]):
					clear_negative_statuses(participant)
					effects.erase("auto_cleanse_at")
			else:
				effects.erase("auto_cleanse_at")

	for viewer in _participants.all:
		var cv: Dictionary = viewer.vision().card_view
		if not cv.is_empty() and now >= float(cv.get("until", 0.0)):
			viewer.vision().card_view = {}
		var mr: Dictionary = viewer.vision().map_reveal
		if not mr.is_empty() and now >= float(mr.get("until", 0.0)):
			viewer.vision().map_reveal = {}
	_item_system.sync_player_slot()


func is_location_revealed(target: Node3D) -> bool:
	for viewer in _participants.all:
		var positions: Dictionary = viewer.vision().map_reveal.get("positions", {})
		if positions.has(target):
			return true
	return false


func is_hand_being_viewed(target: Node3D) -> bool:
	for viewer in _participants.all:
		var view_data: Dictionary = viewer.vision().card_view
		if view_data.get("target") == target:
			return true
		if view_data.has("targets") and target in view_data["targets"]:
			return true
	return false


func has_extra_kill(participant: Node3D) -> bool:
	var effects: Dictionary = participant.status().data
	return bool(effects.get("extra_kill_available", false)) and is_effect_active(participant, "extra_kill_until")


func has_free_change(participant: Node3D) -> bool:
	var effects: Dictionary = participant.status().data
	return int(effects.get("free_change_count", 0)) > 0 and is_effect_active(participant, "free_change_until")


func has_ready_scythe(participant: Node3D) -> bool:
	var effects: Dictionary = participant.status().data
	return float(effects.get("scythe_until", 0.0)) > Clock.now()


func has_ready_coin(participant: Node3D) -> bool:
	var effects: Dictionary = participant.status().data
	return int(effects.get("coin_count", 0)) > 0 and float(effects.get("coin_until", 0.0)) > Clock.now()


func is_effect_active(participant: Node3D, key: String) -> bool:
	return float(participant.status().data.get(key, 0.0)) > Clock.now()


func update_post_stun_buffs() -> void:
	var now: float = Clock.now()
	for participant in _participants.all:
		var is_stunned_now: bool = participant.is_stunned()
		if bool(_was_stunned.get(participant, false)) and not is_stunned_now:
			var effects: Dictionary = participant.status().data
			effects["invincible_until"] = maxf(
				float(effects.get("invincible_until", 0.0)),
				now + GameConfig.POST_STUN_BUFF_SECONDS
			)
			effects["recovery_speed_until"] = maxf(
				float(effects.get("recovery_speed_until", 0.0)),
				now + GameConfig.POST_STUN_BUFF_SECONDS
			)
			participant.set_gold_outline(true)
			refresh_speed_multiplier(participant)
		_was_stunned[participant] = is_stunned_now


func refresh_speed_multiplier(participant: Node3D) -> void:
	var has_speed_boost: bool = (
		is_effect_active(participant, "free_change_until")
		or is_effect_active(participant, "coin_until")
		or is_effect_active(participant, "recovery_speed_until")
	)
	participant.set_speed_multiplier(1.1 if has_speed_boost else 1.0)


func clear_negative_statuses(participant: Node3D) -> void:
	participant.clear_stun()
	for viewer in _participants.all:
		var view_data: Dictionary = viewer.vision().card_view
		if view_data.get("target") == participant:
			viewer.vision().card_view = {}
		elif view_data.has("targets"):
			var targets: Array = view_data["targets"]
			targets.erase(participant)
			if targets.is_empty():
				viewer.vision().card_view = {}
	for viewer in _participants.all:
		var positions: Dictionary = viewer.vision().map_reveal.get("positions", {})
		positions.erase(participant)


func has_negative_status(participant: Node3D) -> bool:
	if participant.is_stunned():
		return true
	for viewer in _participants.all:
		var view_data: Dictionary = viewer.vision().card_view
		if view_data.get("target") == participant:
			return true
		if view_data.has("targets") and participant in view_data["targets"]:
			return true
	for viewer in _participants.all:
		var positions: Dictionary = viewer.vision().map_reveal.get("positions", {})
		if positions.has(participant):
			return true
	return false
