class_name GameStateCodec
extends RefCounted

## 試合状態の直列化 / 復元。参加者コンポーネント・deck・交換ステーション等を Dictionary に写す。
## RPC の入口は match 側に残し、その本体からここを呼ぶ。

const EFFECT_TIME_KEYS := [
	"invincible_until", "invisible_until", "free_change_until", "extra_kill_until", "scythe_until", "coin_until",
	"counter_until", "automatic_kill_until", "auto_cleanse_until", "recovery_speed_until",
]
const EFFECT_VALUE_KEYS := [
	"free_change_count", "free_change_duration", "extra_kill_available",
	"scythe_enhanced", "coin_count", "coin_duration",
	"counter_duration", "barrier_charges", "enhance_next_ability",
]

var _participants: Participants
var _exchange: ExchangeSystem
var _combat: CombatSystem
var _status_system: StatusSystem
var _item_system: ItemSystem
var _deck: Node
var _game_hud: CanvasLayer
var _game_state: GameStateManager


func setup(participants: Participants, exchange: ExchangeSystem, combat: CombatSystem,
		status_system: StatusSystem, item_system: ItemSystem, deck: Node,
		game_hud: CanvasLayer, game_state: GameStateManager) -> void:
	_participants = participants
	_exchange = exchange
	_combat = combat
	_status_system = status_system
	_item_system = item_system
	_deck = deck
	_game_hud = game_hud
	_game_state = game_state


func build_state() -> Dictionary:
	var participant_states: Dictionary = {}
	var now: float = Clock.now()
	for participant in _participants.all:
		var effect_state: Dictionary = {}
		var effects: Dictionary = participant.status().data
		for key in EFFECT_TIME_KEYS:
			var remaining: float = maxf(float(effects.get(key, 0.0)) - now, 0.0)
			if remaining > 0.0:
				effect_state[key] = remaining
		for key in EFFECT_VALUE_KEYS:
			if effects.has(key):
				effect_state[key] = effects[key]
		participant_states[participant.name] = {
			"transform": participant.global_transform,
			"hand": participant.hand,
			"stun": participant.get_stun_time_left(),
			"pending_stun": 0.0,
			"effects": effect_state,
			"kill_cooldown": participant.cooldown().kill_left(now),
			"ability_cooldown": participant.cooldown().ability_left(now),
			"item": network_item_for(participant),
		}
	var station_cards: Array = []
	for station in _exchange.stations():
		station_cards.append(_exchange.station_cards(station))
	var change_rights: Dictionary = {}
	var killers: Dictionary = _combat.change_rights()
	for target in killers:
		if is_instance_valid(target) and is_instance_valid(killers[target]):
			change_rights[target.name] = killers[target].name
	return {
		"participants": participant_states,
		"deck_remaining": _deck.remaining_count(),
		"deck_total": _deck.total_count(),
		"time_left": _game_state.time_left,
		"stations": station_cards,
		"change_rights": change_rights,
		"card_views": build_card_view_state(now),
		"map_reveals": build_map_reveal_state(now),
	}


func network_item_for(participant: Node3D) -> Dictionary:
	if not participant.item().has_item():
		return {}
	var item: Dictionary = participant.item().data
	return {
		"name": item.get("name", ""),
		"duration": item.get("duration", 0.0),
		"time_left": item.get("time_left", 0.0),
		"charges": item.get("charges", 1),
	}


func build_card_view_state(now: float) -> Dictionary:
	var result: Dictionary = {}
	for viewer in _participants.all:
		var view: Dictionary = viewer.vision().card_view
		if view.is_empty():
			continue
		var data := {"remaining": maxf(float(view.get("until", 0.0)) - now, 0.0)}
		if view.has("targets"):
			var names: Array[String] = []
			for target in view["targets"]:
				if is_instance_valid(target):
					names.append(target.name)
			data["targets"] = names
		elif is_instance_valid(view.get("target")):
			data["target"] = view["target"].name
		result[viewer.name] = data
	return result


func build_map_reveal_state(now: float) -> Dictionary:
	var result: Dictionary = {}
	for viewer in _participants.all:
		var reveal: Dictionary = viewer.vision().map_reveal
		if reveal.is_empty():
			continue
		result[viewer.name] = {
			"remaining": maxf(float(reveal.get("until", 0.0)) - now, 0.0),
			"positions": reveal.get("positions", {}).values(),
		}
	return result


func apply_state(state: Dictionary) -> void:
	var now: float = Clock.now()
	_game_state.time_left = float(state.get("time_left", _game_state.time_left))
	_game_hud.set_deck_count(int(state.get("deck_remaining", 0)), int(state.get("deck_total", 0)))
	var participant_states: Dictionary = state.get("participants", {})
	for participant_name in participant_states:
		var participant: Node3D = _participants.by_name(String(participant_name))
		if participant == null:
			continue
		var data: Dictionary = participant_states[participant_name]
		if participant != _participants.local_player:
			participant.global_transform = data.get("transform", participant.global_transform)
		participant.set_hand(data.get("hand", []))
		participant.set_stun_state(float(data.get("stun", 0.0)), float(data.get("pending_stun", 0.0)))
		participant.cooldown().kill_until = now + float(data.get("kill_cooldown", 0.0))
		participant.cooldown().ability_until = now + float(data.get("ability_cooldown", 0.0))
		apply_effect_state(participant, data.get("effects", {}), now)
		var item: Dictionary = data.get("item", {})
		if item.is_empty():
			participant.item().clear()
		else:
			participant.item().data = item
	var stations: Array = _exchange.stations()
	var station_cards: Array = state.get("stations", [])
	for index in mini(stations.size(), station_cards.size()):
		_exchange.set_station_cards(stations[index], station_cards[index])
	var killers: Dictionary = _combat.change_rights()
	killers.clear()
	for target_name in state.get("change_rights", {}):
		var target: Node3D = _participants.by_name(String(target_name))
		var attacker: Node3D = _participants.by_name(String(state["change_rights"][target_name]))
		if target != null and attacker != null:
			killers[target] = attacker
	apply_card_view_state(state.get("card_views", {}), now)
	apply_map_reveal_state(state.get("map_reveals", {}), now)
	_item_system.sync_player_slot()


func apply_effect_state(participant: Node3D, state: Dictionary, now: float) -> void:
	var effects: Dictionary = {}
	for key in state:
		if String(key).ends_with("_until"):
			effects[key] = now + float(state[key])
		else:
			effects[key] = state[key]
	participant.status().data = effects
	participant.set_gold_outline(effects.has("invincible_until"))
	participant.set_invisible(effects.has("invisible_until"))
	_combat.set_barrier_visual(participant, int(effects.get("barrier_charges", 0)) > 0)
	_status_system.refresh_speed_multiplier(participant)
	if participant.has_method("set_can_kill_without_joker"):
		participant.set_can_kill_without_joker(bool(effects.get("extra_kill_available", false)))


func apply_card_view_state(state: Dictionary, now: float) -> void:
	for participant in _participants.all:
		participant.vision().card_view = {}
	for viewer_name in state:
		var viewer: Node3D = _participants.by_name(String(viewer_name))
		if viewer == null:
			continue
		var source: Dictionary = state[viewer_name]
		var view := {"until": now + float(source.get("remaining", 0.0))}
		if source.has("targets"):
			var targets: Array[Node3D] = []
			for target_name in source["targets"]:
				var target: Node3D = _participants.by_name(String(target_name))
				if target != null:
					targets.append(target)
			view["targets"] = targets
		elif source.has("target"):
			var target: Node3D = _participants.by_name(String(source["target"]))
			if target != null:
				view["target"] = target
		viewer.vision().card_view = view


func apply_map_reveal_state(state: Dictionary, now: float) -> void:
	for participant in _participants.all:
		participant.vision().map_reveal = {}
	for viewer_name in state:
		var viewer: Node3D = _participants.by_name(String(viewer_name))
		if viewer == null:
			continue
		var source: Dictionary = state[viewer_name]
		var positions: Dictionary = {}
		var index := 0
		for revealed_position in source.get("positions", []):
			positions[index] = revealed_position
			index += 1
		viewer.vision().map_reveal = {
			"until": now + float(source.get("remaining", 0.0)),
			"positions": positions,
		}


func same_cards(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	var first_signatures: Array[String] = []
	var second_signatures: Array[String] = []
	for card in first:
		first_signatures.append("%s:%d" % [card.get("suit", ""), int(card.get("rank", 0))])
	for card in second:
		second_signatures.append("%s:%d" % [card.get("suit", ""), int(card.get("rank", 0))])
	first_signatures.sort()
	second_signatures.sort()
	return first_signatures == second_signatures
