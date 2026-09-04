class_name AbilitySystem
extends Node

## ペア（同ランク2枚）を使った能力発動。rank→Ability の表で振り分ける。
## 能力の中身は abilities/ability_NN.gd（Strategy）。テキストは get_ability_message。

var _abilities: Dictionary = {}
var _pair_action_time_left: float = 0.0

var _participants: Participants
var _combat: CombatSystem
var _status_system: StatusSystem
var _item_system: ItemSystem
var _deck: Node
var _net_gateway: NetGateway
var _game_hud: CanvasLayer


func setup(participants: Participants, combat: CombatSystem, status_system: StatusSystem,
		item_system: ItemSystem, deck: Node, net_gateway: NetGateway, game_hud: CanvasLayer) -> void:
	_participants = participants
	_combat = combat
	_status_system = status_system
	_item_system = item_system
	_deck = deck
	_net_gateway = net_gateway
	_game_hud = game_hud
	_abilities = {
		1: Ability01.new(), 2: Ability02.new(), 3: Ability03.new(), 4: Ability04.new(),
		5: Ability05.new(), 6: Ability06.new(), 7: Ability07.new(), 8: Ability08.new(),
		9: Ability09.new(), 10: Ability10.new(), 11: Ability11.new(), 12: Ability12.new(),
		13: Ability13.new(),
	}


func try_use_pair(participant: Node3D, pair_slot: int) -> bool:
	if participant.cooldown().ability_left(Clock.now()) > 0.0:
		show_ability_not_ready(participant)
		return false

	var first_index := pair_slot * 2
	var second_index := first_index + 1
	if second_index >= participant.hand.size():
		return false

	var first_card: Dictionary = participant.hand[first_index]
	var second_card: Dictionary = participant.hand[second_index]
	if (
		first_card.get("suit", "") == "joker"
		or second_card.get("suit", "") == "joker"
		or int(first_card.get("rank", 0)) != int(second_card.get("rank", 0))
	):
		return false

	var ability_rank := int(first_card.get("rank", 0))
	var updated_hand: Array[Dictionary] = participant.hand.duplicate()
	updated_hand.remove_at(second_index)
	updated_hand.remove_at(first_index)
	participant.set_hand(updated_hand)

	activate_pair_ability(participant, ability_rank)
	participant.cooldown().ability_until = Clock.now() + GameConfig.ABILITY_COOLDOWN_SECONDS

	_refill_hand(participant)

	_game_hud.set_deck_count(_deck.remaining_count(), _deck.total_count())
	return true


func _refill_hand(participant: Node3D) -> void:
	var missing_count := maxi(GameConfig.HAND_SIZE - participant.hand.size(), 0)
	if missing_count <= 0:
		return
	var cards: Array[Dictionary] = _deck.draw_cards(missing_count)
	if cards.is_empty():
		return
	var updated_hand: Array[Dictionary] = participant.hand.duplicate()
	updated_hand.append_array(cards)
	participant.set_hand(updated_hand, true)


func activate_pair_ability(participant: Node3D, ability_rank: int) -> void:
	var effects: Dictionary = participant.status().data
	var is_enhanced := bool(effects.get("enhance_next_ability", false))
	if is_enhanced:
		effects["enhance_next_ability"] = false

	var ability: Ability = _abilities.get(ability_rank)
	if ability != null:
		var ctx := AbilityContext.new()
		ctx.caster = participant
		ctx.is_enhanced = is_enhanced
		ctx.now = Clock.now()
		ctx.effects = effects
		ctx.combat = _combat
		ctx.item_system = _item_system
		ctx.status_system = _status_system
		ctx.participants = _participants
		ctx.deck = _deck
		ability.apply(ctx)

	var message := "%d  %s" % [ability_rank, get_ability_message(ability_rank, is_enhanced)]
	_net_gateway.notify(participant, message)


func update_computer_pair_actions(delta: float) -> void:
	_pair_action_time_left -= delta
	if _pair_action_time_left > 0.0:
		return

	reset_computer_pair_action_timer()
	for participant in _participants.all:
		if not participant.is_computer() or participant.is_stunned() or randf() > GameConfig.COMPUTER_PAIR_ACTION_CHANCE:
			continue

		var valid_pair_slots: Array[int] = []
		for pair_slot in range(4):
			if is_valid_pair_slot(participant, pair_slot):
				valid_pair_slots.append(pair_slot)
		if not valid_pair_slots.is_empty():
			try_use_pair(participant, valid_pair_slots.pick_random())


func is_valid_pair_slot(participant: Node3D, pair_slot: int) -> bool:
	var first_index := pair_slot * 2
	var second_index := first_index + 1
	if second_index >= participant.hand.size():
		return false

	var first_card: Dictionary = participant.hand[first_index]
	var second_card: Dictionary = participant.hand[second_index]
	return (
		first_card.get("suit", "") != "joker"
		and second_card.get("suit", "") != "joker"
		and int(first_card.get("rank", 0)) == int(second_card.get("rank", 0))
	)


func reset_computer_pair_action_timer() -> void:
	_pair_action_time_left = randf_range(
		GameConfig.COMPUTER_PAIR_ACTION_MIN_SECONDS,
		GameConfig.COMPUTER_PAIR_ACTION_MAX_SECONDS
	)


func get_pair_slot_from_event(event: InputEvent) -> int:
	for index in range(4):
		if event.is_action_pressed("pair_%d" % (index + 1)):
			return index
	return -1


func show_ability_not_ready(participant: Node3D) -> void:
	_net_gateway.notify(participant, GameConfig.text("ability_not_ready"))


func get_ability_message(rank: int, is_enhanced: bool) -> String:
	if GameConfig.language == "ja":
		var normal_ja := ["", "手札交換", "ミサイル", "5秒無敵", "鎌", "手札を見る15秒", "状態回復", "10秒透明", "コイン", "レイピア", "1枚コピー", "10秒マップ表示", "盾", "次を強化"]
		var enhanced_ja := ["", "ペアドロー", "ミサイル2発", "10秒無敵", "オート鎌", "全手札を見る15秒", "自動状態回復", "20秒透明", "コイン2回", "レイピア6秒", "2枚コピー", "20秒マップ表示", "盾2回", "ソード"]
		return enhanced_ja[rank] if is_enhanced else normal_ja[rank]
	match rank:
		1:
			return "PAIR DRAW" if is_enhanced else "REDRAW"
		2:
			return "MISSILE x2" if is_enhanced else "MISSILE"
		3:
			return "INVINCIBLE 10s" if is_enhanced else "INVINCIBLE 5s"
		4:
			return "AUTO SCYTHE" if is_enhanced else "SCYTHE"
		5:
			return "VIEW ALL HANDS 15s" if is_enhanced else "VIEW HAND 15s"
		6:
			return "AUTO CLEANSE" if is_enhanced else "CLEANSE"
		7:
			return "INVISIBLE 20s" if is_enhanced else "INVISIBLE 10s"
		8:
			return "COIN x2" if is_enhanced else "COIN"
		9:
			return "RAPIER 6s" if is_enhanced else "RAPIER"
		10:
			return "COPY x2" if is_enhanced else "COPY"
		11:
			return "MAP REVEAL 20s" if is_enhanced else "MAP REVEAL 10s"
		12:
			return "SHIELD x2" if is_enhanced else "SHIELD"
		13:
			return "SWORD" if is_enhanced else "BOOST NEXT"
	return "ABILITY"
