extends Node3D

const HAND_SIZE := 8
const KILL_DISTANCE := 5.0
const KILL_CENTER_DOT := 0.985
const STUN_SECONDS := 10.0
const POST_STUN_BUFF_SECONDS := 5.0
const KILL_COOLDOWN_SECONDS := 10.0
const ABILITY_COOLDOWN_SECONDS := 10.0
const EXCHANGE_HOLD_SECONDS := 5.0
const EXCHANGE_CARD_COUNT := 3
const EXCHANGE_CARD_SPACING := 1.05
const MAP_RESPAWN_DISTANCE := 64.0
const FALL_RESPAWN_Y := -8.0
const COMPUTER_PAIR_ACTION_MIN_SECONDS := 2.0
const COMPUTER_PAIR_ACTION_MAX_SECONDS := 5.0
const COMPUTER_PAIR_ACTION_CHANCE := 0.35
const NETWORK_SNAPSHOT_INTERVAL := 0.1
const HOMING_MISSILE_SCENE := preload("res://scenes/HomingMissile.tscn")
const COMPUTER_SCENE := preload("res://scenes/Computer.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const TUTORIAL_SCENE := preload("res://scenes/Tutorial.tscn")

@export var minimap_world_half_extent := 20.0

@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var settings_menu: Control = $Settings
@onready var deck: Node = $Deck
@onready var game_hud: CanvasLayer = $GameHud
@onready var player: CharacterBody3D = $Player

var _participants: Array[Node3D] = []
var _player_kill_target: Node3D = null
var _player_change_target: Node3D = null
var _player_exchange_target: StaticBody3D = null
var _change_killers: Dictionary = {}
var _kill_cooldown_until: Dictionary = {}
var _ability_cooldown_until: Dictionary = {}
var _computer_pair_action_time_left := 0.0
var _items: Dictionary = {}
var _effects: Dictionary = {}
var _card_views: Dictionary = {}
var _map_reveals: Dictionary = {}
var _time_left := 600.0
var _game_ending := false
var _exchange_hold_time := 0.0
var _exchange_hold_target: StaticBody3D = null
var _exchange_hold_card_index := -1
var _exchange_locked_until_release := false
var _network_snapshot_time_left := 0.0
var _was_stunned: Dictionary = {}
var _tutorial_overlay: Control = null
var _player_exchange_card_index := -1
var _participant_spawn_positions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	randomize()
	pause_menu.hide()
	settings_menu.hide()
	pause_menu.resume_requested.connect(_resume_game)
	pause_menu.settings_requested.connect(_show_settings_menu)
	pause_menu.tutorial_requested.connect(_show_tutorial)
	settings_menu.back_requested.connect(_show_pause_menu)
	game_hud.hand_reordered.connect(_on_hand_reordered)
	game_hud.debug_return_requested.connect(_force_return_to_waiting_room)
	_configure_computers()
	_spawn_network_players()
	player.ensure_local_camera()
	player.hand_changed.connect(_on_player_hand_changed)
	_participants = [player]
	for child in get_children():
		if child is CharacterBody3D and child != player:
			_participants.append(child)
	_cache_participant_spawn_positions()
	for participant in _participants:
		_effects[participant] = {}
		_kill_cooldown_until[participant] = 0.0
		_ability_cooldown_until[participant] = 0.0
		_was_stunned[participant] = participant.is_stunned()
	_setup_exchange_stations()
	if _is_game_authority():
		deck.reset_and_shuffle(GameConfig.deck_size)
		deck.ensure_joker_in_next_draws(HAND_SIZE * _participants.size())
		for participant in _participants:
			participant.set_hand(deck.draw_cards(HAND_SIZE))
		_deal_exchange_station_cards()
	elif NetworkManager.is_online:
		_request_full_state.rpc_id(1)

	game_hud.set_deck_count(deck.remaining_count(), deck.total_count())
	game_hud.set_hand(player.hand)
	game_hud.set_kill_available(false)
	game_hud.set_change_available(false)
	game_hud.set_item("")
	game_hud.set_minimap_world_half_extent(minimap_world_half_extent)
	_time_left = GameConfig.time_limit_minutes * 60.0
	game_hud.set_time_left(_time_left)
	_reset_computer_pair_action_timer()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	if get_tree().paused and _should_pause_game():
		return
	if _game_ending:
		return

	if _is_game_authority():
		_time_left = maxf(_time_left - delta, 0.0)
	game_hud.set_time_left(_time_left)
	game_hud.set_stun_status(player.get_stun_time_left(), STUN_SECONDS)
	_update_player_information_hud()
	_update_player_exposure_hud()
	_update_player_edge_status_effects()
	_player_kill_target = _find_kill_target(player)
	_player_change_target = _find_change_target(player)
	_player_exchange_target = _find_aimed_exchange_station()
	_update_exchange_hold(delta)
	game_hud.set_kill_available(_player_kill_target != null)
	game_hud.set_change_available(_player_change_target != null or _player_exchange_target != null)
	game_hud.set_kill_cooldown(_get_kill_cooldown_left(player), KILL_COOLDOWN_SECONDS)
	game_hud.set_ability_cooldown(_get_ability_cooldown_left(player), ABILITY_COOLDOWN_SECONDS)
	if not _is_game_authority():
		return
	_update_items(delta)
	_respawn_out_of_bounds_participants()
	_update_post_stun_buffs()
	_update_effects()
	_update_automatic_kills()
	_update_computer_pair_actions(delta)
	_update_computer_items()
	_clear_expired_change_rights()
	_try_computer_kills()
	_try_computer_free_changes()
	_network_snapshot_time_left -= delta
	if NetworkManager.is_online and _network_snapshot_time_left <= 0.0:
		_network_snapshot_time_left = NETWORK_SNAPSHOT_INTERVAL
		_receive_game_state.rpc(_build_game_state())
	if _time_left <= 0.0 or _has_empty_hand():
		_finish_game()


func _unhandled_input(event: InputEvent) -> void:
	if _game_ending:
		return

	if event.is_action_pressed("ui_cancel"):
		if pause_menu.visible or settings_menu.visible:
			_resume_game()
		else:
			_show_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if get_tree().paused or _is_local_ui_blocking_gameplay():
		return

	if event.is_action_pressed("hand_editor"):
		_set_hand_editor_open(not game_hud.is_hand_editor_open())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_item"):
		_request_use_button_action()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var pair_slot := _get_pair_slot_from_event(event)
		if pair_slot >= 0:
			_request_local_action("pair", pair_slot)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not game_hud.is_hand_editor_open() and _player_kill_target != null:
			_request_local_action("kill", 0, _player_kill_target.name)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not game_hud.is_hand_editor_open() and _player_change_target != null:
			_request_local_action("change", 0, _player_change_target.name)
			get_viewport().set_input_as_handled()


func _show_pause_menu() -> void:
	game_hud.close_hand_editor()
	get_tree().paused = _should_pause_game()
	_set_local_player_input_enabled(false)
	settings_menu.hide()
	pause_menu.show()
	game_hud.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _show_settings_menu() -> void:
	game_hud.close_hand_editor()
	get_tree().paused = _should_pause_game()
	_set_local_player_input_enabled(false)
	pause_menu.hide()
	settings_menu.show()
	game_hud.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _resume_game() -> void:
	game_hud.close_hand_editor()
	pause_menu.hide()
	settings_menu.hide()
	game_hud.show()
	get_tree().paused = false
	_set_local_player_input_enabled(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _show_tutorial() -> void:
	if _tutorial_overlay != null and is_instance_valid(_tutorial_overlay):
		return
	game_hud.close_hand_editor()
	pause_menu.hide()
	settings_menu.hide()
	get_tree().paused = _should_pause_game()
	_set_local_player_input_enabled(false)
	_tutorial_overlay = TUTORIAL_SCENE.instantiate()
	_tutorial_overlay.set_meta("overlay", true)
	_tutorial_overlay.tree_exited.connect(func() -> void:
		_tutorial_overlay = null
		if not _game_ending and get_tree().current_scene == self:
			_show_pause_menu()
	)
	game_hud.add_child(_tutorial_overlay)


func _force_return_to_waiting_room() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	NetworkManager.return_to_waiting_room()


func _should_pause_game() -> bool:
	return not NetworkManager.is_online


func _is_local_ui_blocking_gameplay() -> bool:
	return pause_menu.visible or settings_menu.visible or (_tutorial_overlay != null and is_instance_valid(_tutorial_overlay))


func _set_local_player_input_enabled(is_enabled: bool) -> void:
	if player != null and player.has_method("set_input_enabled"):
		player.set_input_enabled(is_enabled)


func _find_kill_target(attacker: Node3D) -> Node3D:
	if (
		not attacker.has_joker()
		or attacker.is_stunned()
		or _get_kill_cooldown_left(attacker) > 0.0
	):
		return null

	return _find_aimed_target(attacker, false)


func _find_change_target(attacker: Node3D) -> Node3D:
	if attacker.is_stunned() or attacker.hand.is_empty():
		return null

	if _has_free_change(attacker):
		return _find_aimed_target(attacker, false)
	return _find_aimed_target(attacker, true)


func _find_scythe_target(attacker: Node3D) -> Node3D:
	if not _has_ready_scythe(attacker) or attacker.is_stunned() or _get_kill_cooldown_left(attacker) > 0.0:
		return null
	return _find_aimed_target(attacker, false)


func _find_coin_change_target(attacker: Node3D) -> Node3D:
	if not _has_ready_coin(attacker) or attacker.is_stunned() or attacker.hand.is_empty():
		return null
	return _find_aimed_target(attacker, false)


func _find_aimed_target(attacker: Node3D, for_change: bool) -> Node3D:
	var view_origin: Vector3 = attacker.get_view_origin()
	var view_forward: Vector3 = attacker.get_view_forward()
	var best_target: Node3D = null
	var best_dot := KILL_CENTER_DOT

	for target in _participants:
		if target == attacker:
			continue
		if for_change:
			if not target.is_stunned() or _change_killers.get(target) != attacker or target.hand.is_empty():
				continue
		elif target.is_stunned():
			continue

		var to_target := target.global_position + Vector3(0.0, 1.0, 0.0) - view_origin
		var distance := to_target.length()
		if distance > KILL_DISTANCE:
			continue

		var center_dot := view_forward.dot(to_target.normalized())
		if center_dot > best_dot:
			best_dot = center_dot
			best_target = target

	return best_target


func _try_computer_kills() -> void:
	for participant in _participants:
		if (
			not _is_computer(participant)
			or participant.is_stunned()
			or _get_kill_cooldown_left(participant) > 0.0
			or (not participant.has_joker() and not _has_extra_kill(participant))
		):
			continue

		var target: Node3D = participant.get_chase_target()
		if target != null and participant.global_position.distance_to(target.global_position) <= KILL_DISTANCE:
			_perform_kill(participant, target)
			if randf() < 0.5:
				_perform_change(participant, target)
			else:
				_change_killers.erase(target)


func _update_automatic_kills() -> void:
	for attacker in _participants:
		if attacker.is_stunned() or not _is_effect_active(attacker, "automatic_kill_until"):
			continue
		var effects: Dictionary = _effects[attacker]
		var previous_targets: Dictionary = effects.get("automatic_kill_targets", {})
		var current_targets: Dictionary = {}
		for target in _participants:
			if (
				target == attacker
				or attacker.global_position.distance_to(target.global_position) > KILL_DISTANCE
			):
				continue
			current_targets[target] = true
			if previous_targets.has(target) or target.is_stunned():
				continue
			_perform_kill_with_options(attacker, target, false, false)
			if attacker.is_stunned():
				break
		effects["automatic_kill_targets"] = current_targets


func _perform_kill(attacker: Node3D, target: Node3D) -> void:
	if _get_kill_cooldown_left(attacker) > 0.0:
		return
	_kill_cooldown_until[attacker] = _now() + KILL_COOLDOWN_SECONDS
	_perform_kill_with_options(attacker, target, true, true)


func _perform_kill_with_options(attacker: Node3D, target: Node3D, allow_change: bool, consume_extra_kill: bool) -> void:
	var effects: Dictionary = _effects[target]
	if _is_effect_active(target, "invincible_until"):
		return
	if _is_effect_active(target, "counter_until"):
		_stun_without_change(attacker)
		effects.erase("counter_until")
		effects.erase("counter_duration")
		_sync_player_item_slot()
		return
	if int(effects.get("barrier_charges", 0)) > 0:
		effects["barrier_charges"] = int(effects["barrier_charges"]) - 1
		_set_barrier_visual(target, int(effects.get("barrier_charges", 0)) > 0)
		_sync_player_item_slot()
		return

	var used_extra_kill: bool = consume_extra_kill and not attacker.has_joker() and _has_extra_kill(attacker)
	if used_extra_kill:
		var attacker_effects: Dictionary = _effects[attacker]
		attacker_effects["extra_kill_available"] = false
		if attacker.has_method("set_can_kill_without_joker"):
			attacker.set_can_kill_without_joker(false)
		_sync_player_item_slot()
	target.stun(STUN_SECONDS)
	_show_kill_notifications(attacker, target)
	if allow_change and not used_extra_kill:
		_change_killers[target] = attacker
	else:
		_change_killers.erase(target)
	_player_kill_target = null
	_player_change_target = null
	game_hud.set_kill_available(false)
	game_hud.set_change_available(false)


func _perform_change(attacker: Node3D, target: Node3D, forced_free_change: bool = false) -> void:
	var free_change := _has_free_change(attacker) or forced_free_change
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
	_show_change_preview_for_participant(attacker, attacker_card, target_card)
	_show_change_preview_for_participant(target, target_card, attacker_card)
	_change_killers.erase(target)
	if free_change:
		var effects: Dictionary = _effects[attacker]
		if forced_free_change:
			effects["coin_count"] = maxi(int(effects.get("coin_count", 0)) - 1, 0)
			if int(effects.get("coin_count", 0)) <= 0:
				effects.erase("coin_until")
				effects.erase("coin_duration")
		else:
			effects["free_change_count"] = maxi(int(effects.get("free_change_count", 0)) - 1, 0)
		_sync_player_item_slot()

	_player_change_target = null
	game_hud.set_change_available(false)


func _clear_expired_change_rights() -> void:
	for target in _change_killers.keys():
		if not is_instance_valid(target) or (not target.is_stunned() and not target.is_stun_pending()):
			_change_killers.erase(target)


func _set_hand_editor_open(is_open: bool) -> void:
	if is_open:
		game_hud.open_hand_editor(player.hand)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		game_hud.close_hand_editor()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _request_use_button_action() -> void:
	var scythe_target := _find_scythe_target(player)
	var player_effects: Dictionary = _effects.get(player, {})
	if _has_ready_scythe(player) and (scythe_target != null or bool(player_effects.get("scythe_enhanced", false))):
		var target_name := ""
		if scythe_target != null:
			target_name = scythe_target.name
		_request_local_action("scythe", 0, target_name)
		return
	var coin_target := _find_coin_change_target(player)
	if coin_target != null:
		_request_local_action("coin", 0, coin_target.name)
		return
	_request_local_action("item")


func _on_hand_reordered(cards: Array[Dictionary]) -> void:
	if _is_game_authority():
		player.set_hand(cards)
	else:
		_request_reorder.rpc_id(1, cards)


func _on_player_hand_changed(cards: Array[Dictionary]) -> void:
	game_hud.set_hand(cards)


func grant_item(participant: Node3D, item_name: String, duration: float = 0.0, icon: Texture2D = null) -> void:
	_items[participant] = {
		"name": item_name,
		"duration": maxf(duration, 0.0),
		"time_left": maxf(duration, 0.0),
		"icon": icon,
	}
	_sync_player_item_slot()


func _try_use_pair(participant: Node3D, pair_slot: int) -> bool:
	if _get_ability_cooldown_left(participant) > 0.0:
		_show_ability_not_ready(participant)
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

	_activate_pair_ability(participant, ability_rank)
	_ability_cooldown_until[participant] = _now() + ABILITY_COOLDOWN_SECONDS

	_refill_hand(participant)

	game_hud.set_deck_count(deck.remaining_count(), deck.total_count())
	return true


func _activate_pair_ability(participant: Node3D, ability_rank: int) -> void:
	var now: float = _now()
	var effects: Dictionary = _effects[participant]
	var is_enhanced := bool(effects.get("enhance_next_ability", false))
	if is_enhanced:
		effects["enhance_next_ability"] = false
	match ability_rank:
		1:
			var kept_cards: Array[Dictionary] = []
			var returned_cards: Array[Dictionary] = []
			for card in participant.hand:
				if card.get("suit", "") == "joker":
					kept_cards.append(card)
				else:
					returned_cards.append(card)
			deck.return_cards(returned_cards)
			participant.set_hand(kept_cards)
			if is_enhanced:
				var missing_count: int = maxi(HAND_SIZE - kept_cards.size(), 0)
				var paired_cards: Array[Dictionary] = deck.draw_pair_focused_cards(missing_count)
				var enhanced_hand: Array[Dictionary] = kept_cards.duplicate()
				enhanced_hand.append_array(paired_cards)
				participant.set_hand(enhanced_hand, true)
		2:
			grant_item(participant, "MISSILE", 20.0 if is_enhanced else 10.0)
			_items[participant]["charges"] = 2 if is_enhanced else 1
		3:
			effects["invincible_until"] = now + (10.0 if is_enhanced else 5.0)
			participant.set_gold_outline(true)
		4:
			effects["scythe_until"] = now + 15.0
			effects["scythe_enhanced"] = is_enhanced
			_sync_player_item_slot()
		5:
			if is_enhanced:
				var targets: Array[Node3D] = []
				for target in _participants:
					if target != participant:
						targets.append(target)
				_card_views[participant] = {"targets": targets, "until": now + 15.0}
			else:
				var nearest := _find_nearest_participant(participant)
				if nearest != null:
					_card_views[participant] = {"target": nearest, "until": now + 15.0}
		6:
			if is_enhanced:
				effects["auto_cleanse_until"] = now + 30.0
				effects.erase("auto_cleanse_at")
			else:
				_clear_negative_statuses(participant)
		7:
			effects["invisible_until"] = now + (20.0 if is_enhanced else 10.0)
			participant.set_invisible(true)
		8:
			effects["coin_duration"] = 30.0 if is_enhanced else 20.0
			effects["coin_until"] = now + float(effects["coin_duration"])
			effects["coin_count"] = 2 if is_enhanced else 1
			_refresh_speed_multiplier(participant)
			_sync_player_item_slot()
		9:
			effects["counter_duration"] = 6.0 if is_enhanced else 3.0
			effects["counter_until"] = now + float(effects["counter_duration"])
			_sync_player_item_slot()
		10:
			var copies_left := 2 if is_enhanced else 1
			var source_hand: Array[Dictionary] = participant.hand.duplicate()
			for card in source_hand:
				if card.get("suit", "") != "joker" and copies_left > 0:
					participant.add_card(card.duplicate())
					copies_left -= 1
		11:
			var positions: Dictionary = {}
			for target in _participants:
				if target != participant:
					positions[target] = target.global_position
			_map_reveals[participant] = {
				"positions": positions,
				"until": now + (20.0 if is_enhanced else 10.0),
			}
		12:
			effects["barrier_charges"] = 2 if is_enhanced else 1
			_set_barrier_visual(participant, true)
			_sync_player_item_slot()
		13:
			if is_enhanced:
				grant_item(participant, "SWORD")
			else:
				effects["enhance_next_ability"] = true
	if participant == player:
		game_hud.show_notification("%d  %s" % [ability_rank, _get_ability_message(ability_rank, is_enhanced)])
	elif NetworkManager.is_online and _peer_for_participant(participant) > 0:
		_show_remote_notification.rpc_id(
			_peer_for_participant(participant),
			"%d  %s" % [ability_rank, _get_ability_message(ability_rank, is_enhanced)]
		)


func _update_computer_pair_actions(delta: float) -> void:
	_computer_pair_action_time_left -= delta
	if _computer_pair_action_time_left > 0.0:
		return

	_reset_computer_pair_action_timer()
	for participant in _participants:
		if not _is_computer(participant) or participant.is_stunned() or randf() > COMPUTER_PAIR_ACTION_CHANCE:
			continue

		var valid_pair_slots: Array[int] = []
		for pair_slot in range(4):
			if _is_valid_pair_slot(participant, pair_slot):
				valid_pair_slots.append(pair_slot)
		if not valid_pair_slots.is_empty():
			_try_use_pair(participant, valid_pair_slots.pick_random())


func _is_valid_pair_slot(participant: Node3D, pair_slot: int) -> bool:
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


func _reset_computer_pair_action_timer() -> void:
	_computer_pair_action_time_left = randf_range(
		COMPUTER_PAIR_ACTION_MIN_SECONDS,
		COMPUTER_PAIR_ACTION_MAX_SECONDS
	)


func _get_pair_slot_from_event(event: InputEvent) -> int:
	for index in range(4):
		if event.is_action_pressed("pair_%d" % (index + 1)):
			return index
	return -1


func _update_items(delta: float) -> void:
	for participant in _items.keys():
		if not is_instance_valid(participant):
			_items.erase(participant)
			continue

		var item: Dictionary = _items[participant]
		var duration: float = float(item.get("duration", 0.0))
		if duration <= 0.0:
			continue

		var time_left: float = maxf(float(item.get("time_left", 0.0)) - delta, 0.0)
		if time_left <= 0.0:
			_items.erase(participant)
		else:
			item["time_left"] = time_left
			_items[participant] = item

	_sync_player_item_slot()


func _use_item(participant: Node3D) -> void:
	if not _items.has(participant):
		_use_passive_item(participant, "")
		return

	var item: Dictionary = _items[participant]
	var item_name := String(item.get("name", ""))
	if item_name == "MISSILE":
		var target: Node3D = _find_visible_missile_target(participant)
		if target == null:
			return
		_launch_missile(participant, target)
	elif item_name == "SWORD":
		_use_sword(participant)
	var charges_left := int(item.get("charges", 1)) - 1
	if charges_left > 0:
		item["charges"] = charges_left
		_items[participant] = item
	else:
		_items.erase(participant)
	_activate_item(participant, item_name)
	_sync_player_item_slot()


func _activate_item(_participant: Node3D, _item_name: String) -> void:
	pass


func _use_passive_item(participant: Node3D, target_name: String) -> void:
	if _has_ready_scythe(participant):
		var target := _participant_by_name(target_name)
		_use_scythe(participant, target)
	elif _has_ready_coin(participant):
		var target := _participant_by_name(target_name)
		if target != null:
			_perform_change(participant, target, true)


func _use_scythe(attacker: Node3D, target: Node3D) -> void:
	var effects: Dictionary = _effects[attacker]
	if not _has_ready_scythe(attacker):
		return
	var remaining := maxf(float(effects.get("scythe_until", 0.0)) - _now(), 0.0)
	var is_enhanced := bool(effects.get("scythe_enhanced", false))
	effects.erase("scythe_until")
	effects.erase("scythe_enhanced")
	if is_enhanced:
		effects["automatic_kill_until"] = _now() + remaining
		effects["automatic_kill_targets"] = {}
		_sync_player_item_slot()
		return
	if target == null or _get_kill_cooldown_left(attacker) > 0.0:
		_sync_player_item_slot()
		return
	_kill_cooldown_until[attacker] = _now() + KILL_COOLDOWN_SECONDS
	_perform_kill_with_options(attacker, target, false, false)
	_sync_player_item_slot()


func _use_sword(attacker: Node3D) -> void:
	for target in _participants:
		if target == attacker or attacker.global_position.distance_to(target.global_position) > KILL_DISTANCE:
			continue

		# Sword hits intentionally bypass invincibility, barriers, counters, and other defenses.
		target.stun(STUN_SECONDS)
		_show_kill_notifications(attacker, target)
		_change_killers[target] = attacker

	_player_kill_target = null
	_player_change_target = null
	game_hud.set_kill_available(false)
	game_hud.set_change_available(false)


func _sync_player_item_slot() -> void:
	if not _items.has(player):
		var passive_item := _passive_item_slot_for(player)
		if passive_item.is_empty():
			game_hud.set_item("")
		else:
			game_hud.set_item(
				String(passive_item.get("name", "")),
				float(passive_item.get("time_left", 0.0)),
				float(passive_item.get("duration", 0.0))
			)
		return

	var item: Dictionary = _items[player]
	game_hud.set_item(
		String(item.get("name", "")),
		float(item.get("time_left", 0.0)),
		float(item.get("duration", 0.0)),
		item.get("icon") as Texture2D
	)


func _passive_item_slot_for(participant: Node3D) -> Dictionary:
	if not _effects.has(participant):
		return {}
	var effects: Dictionary = _effects[participant]
	var now := _now()
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


func _refill_hand(participant: Node3D) -> void:
	var missing_count := maxi(HAND_SIZE - participant.hand.size(), 0)
	if missing_count <= 0:
		return
	var cards: Array[Dictionary] = deck.draw_cards(missing_count)
	if cards.is_empty():
		return
	var updated_hand: Array[Dictionary] = participant.hand.duplicate()
	updated_hand.append_array(cards)
	participant.set_hand(updated_hand, true)


func _update_effects() -> void:
	var now: float = _now()
	for participant in _participants:
		var effects: Dictionary = _effects[participant]
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
			_refresh_speed_multiplier(participant)
		if float(effects.get("coin_until", 0.0)) > 0.0 and now >= float(effects["coin_until"]):
			effects.erase("coin_until")
			effects.erase("coin_duration")
			effects["coin_count"] = 0
			_refresh_speed_multiplier(participant)
		if float(effects.get("recovery_speed_until", 0.0)) > 0.0 and now >= float(effects["recovery_speed_until"]):
			effects.erase("recovery_speed_until")
			_refresh_speed_multiplier(participant)
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
			elif _has_negative_status(participant):
				if not effects.has("auto_cleanse_at"):
					effects["auto_cleanse_at"] = now + 3.0
				elif now >= float(effects["auto_cleanse_at"]):
					_clear_negative_statuses(participant)
					effects.erase("auto_cleanse_at")
			else:
				effects.erase("auto_cleanse_at")

	for viewer in _card_views.keys():
		if now >= float(_card_views[viewer].get("until", 0.0)):
			_card_views.erase(viewer)
	for viewer in _map_reveals.keys():
		if now >= float(_map_reveals[viewer].get("until", 0.0)):
			_map_reveals.erase(viewer)
	_sync_player_item_slot()


func _update_player_information_hud() -> void:
	var revealed_positions: Array[Vector3] = []
	var empty_cards: Array[Dictionary] = []
	var reveal_data: Dictionary = _map_reveals.get(player, {})
	var revealed: Dictionary = reveal_data.get("positions", {})
	for revealed_position in revealed.values():
		revealed_positions.append(revealed_position)
	game_hud.set_minimap_data(player.global_position, revealed_positions)

	if not _card_views.has(player):
		game_hud.set_viewed_hand("", empty_cards)
		return
	var view_data: Dictionary = _card_views[player]
	if view_data.has("targets"):
		var names: Array[String] = []
		var cards: Array[Dictionary] = []
		for viewed_target in view_data["targets"]:
			if is_instance_valid(viewed_target):
				names.append(_participant_name(viewed_target))
				cards.append_array(viewed_target.hand)
		game_hud.set_viewed_hand(" / ".join(names), cards)
		return
	var target: Node3D = view_data.get("target")
	if not is_instance_valid(target):
		_card_views.erase(player)
		game_hud.set_viewed_hand("", empty_cards)
		return
	game_hud.set_viewed_hand(_participant_name(target), target.hand)


func _update_player_exposure_hud() -> void:
	game_hud.set_exposure_status(_is_location_revealed(player), _is_hand_being_viewed(player))


func _update_player_edge_status_effects() -> void:
	var effects: Dictionary = _effects.get(player, {})
	game_hud.set_edge_status_effects(
		player.has_joker(),
		float(effects.get("invincible_until", 0.0)) > _now(),
		int(effects.get("barrier_charges", 0)) > 0
	)


func _is_location_revealed(target: Node3D) -> bool:
	for reveal_data in _map_reveals.values():
		var positions: Dictionary = reveal_data.get("positions", {})
		if positions.has(target):
			return true
	return false


func _is_hand_being_viewed(target: Node3D) -> bool:
	for view_data in _card_views.values():
		if view_data.get("target") == target:
			return true
		if view_data.has("targets") and target in view_data["targets"]:
			return true
	return false


func _has_extra_kill(participant: Node3D) -> bool:
	var effects: Dictionary = _effects[participant]
	return bool(effects.get("extra_kill_available", false)) and _is_effect_active(participant, "extra_kill_until")


func _has_free_change(participant: Node3D) -> bool:
	var effects: Dictionary = _effects[participant]
	return int(effects.get("free_change_count", 0)) > 0 and _is_effect_active(participant, "free_change_until")


func _has_ready_scythe(participant: Node3D) -> bool:
	var effects: Dictionary = _effects[participant]
	return float(effects.get("scythe_until", 0.0)) > _now()


func _has_ready_coin(participant: Node3D) -> bool:
	var effects: Dictionary = _effects[participant]
	return int(effects.get("coin_count", 0)) > 0 and float(effects.get("coin_until", 0.0)) > _now()


func _is_effect_active(participant: Node3D, key: String) -> bool:
	return float(_effects[participant].get(key, 0.0)) > _now()


func _update_post_stun_buffs() -> void:
	var now := _now()
	for participant in _participants:
		var is_stunned_now: bool = participant.is_stunned()
		if bool(_was_stunned.get(participant, false)) and not is_stunned_now:
			var effects: Dictionary = _effects[participant]
			effects["invincible_until"] = maxf(
				float(effects.get("invincible_until", 0.0)),
				now + POST_STUN_BUFF_SECONDS
			)
			effects["recovery_speed_until"] = maxf(
				float(effects.get("recovery_speed_until", 0.0)),
				now + POST_STUN_BUFF_SECONDS
			)
			participant.set_gold_outline(true)
			_refresh_speed_multiplier(participant)
		_was_stunned[participant] = is_stunned_now


func _refresh_speed_multiplier(participant: Node3D) -> void:
	var has_speed_boost := (
		_is_effect_active(participant, "free_change_until")
		or _is_effect_active(participant, "coin_until")
		or _is_effect_active(participant, "recovery_speed_until")
	)
	participant.set_speed_multiplier(1.1 if has_speed_boost else 1.0)


func _clear_negative_statuses(participant: Node3D) -> void:
	participant.clear_stun()
	for viewer in _card_views.keys():
		var view_data: Dictionary = _card_views[viewer]
		if view_data.get("target") == participant:
			_card_views.erase(viewer)
		elif view_data.has("targets"):
			var targets: Array = view_data["targets"]
			targets.erase(participant)
			if targets.is_empty():
				_card_views.erase(viewer)
	for viewer in _map_reveals.keys():
		var positions: Dictionary = _map_reveals[viewer].get("positions", {})
		positions.erase(participant)


func _has_negative_status(participant: Node3D) -> bool:
	if participant.is_stunned():
		return true
	for view_data in _card_views.values():
		if view_data.get("target") == participant:
			return true
		if view_data.has("targets") and participant in view_data["targets"]:
			return true
	for reveal_data in _map_reveals.values():
		var positions: Dictionary = reveal_data.get("positions", {})
		if positions.has(participant):
			return true
	return false


func _find_nearest_participant(participant: Node3D) -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for target in _participants:
		if target == participant:
			continue
		var distance := participant.global_position.distance_squared_to(target.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = target
	return nearest


func _find_visible_missile_target(shooter: Node3D) -> Node3D:
	var candidates: Array[Node3D] = []
	if shooter == player:
		var best_dot := KILL_CENTER_DOT
		for target in _participants:
			if target == shooter:
				continue
			var direction: Vector3 = (target.global_position + Vector3.UP - shooter.get_view_origin()).normalized()
			var dot: float = shooter.get_view_forward().dot(direction)
			if dot > best_dot and _has_line_of_sight(shooter, target):
				best_dot = dot
				candidates = [target]
	else:
		for target in _participants:
			if target != shooter and _has_line_of_sight(shooter, target):
				candidates.append(target)
		candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return shooter.global_position.distance_squared_to(a.global_position) < shooter.global_position.distance_squared_to(b.global_position)
		)
	return candidates[0] if not candidates.is_empty() else null


func _has_line_of_sight(shooter: Node3D, target: Node3D) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		shooter.get_view_origin(),
		target.global_position + Vector3.UP
	)
	query.exclude = [shooter]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty() and result.get("collider") == target


func _launch_missile(shooter: Node3D, target: Node3D) -> void:
	if NetworkManager.is_online:
		_spawn_missile.rpc(shooter.name, target.name)
		return
	_spawn_missile(shooter.name, target.name)


@rpc("authority", "call_local", "reliable")
func _spawn_missile(shooter_name: String, target_name: String) -> void:
	var shooter := _participant_by_name(shooter_name)
	var target := _participant_by_name(target_name)
	if shooter == null or target == null:
		return
	var missile: CharacterBody3D = HOMING_MISSILE_SCENE.instantiate()
	add_child(missile)
	missile.global_position = shooter.get_view_origin() + shooter.get_view_forward()
	missile.look_at(target.global_position + Vector3.UP, Vector3.UP)
	missile.setup(shooter, target, self)


func on_missile_hit(target: Node3D) -> void:
	if not _is_game_authority():
		return
	_stun_without_change(target)


func _stun_without_change(target: Node3D) -> void:
	if _is_effect_active(target, "invincible_until"):
		return
	target.stun(STUN_SECONDS)
	_change_killers.erase(target)


func _update_computer_items() -> void:
	for participant in _participants:
		if not _is_computer(participant) or participant.is_stunned() or not _items.has(participant):
			continue
		if randf() < 0.005:
			_use_item(participant)


func _try_computer_free_changes() -> void:
	for participant in _participants:
		if not _is_computer(participant) or participant.is_stunned() or not _has_free_change(participant):
			continue
		var target := _find_nearest_participant(participant)
		if target != null and participant.global_position.distance_to(target.global_position) <= KILL_DISTANCE:
			_perform_change(participant, target)


func _setup_exchange_stations() -> void:
	for station_position in [Vector3(0.0, 0.0, -40.0), Vector3(0.0, 0.0, 40.0)]:
		var station := StaticBody3D.new()
		station.name = "ExchangeStation"
		station.position = station_position
		station.add_to_group("exchange_stations")
		add_child(station)

		var pedestal_mesh := BoxMesh.new()
		pedestal_mesh.size = Vector3(3.0, 1.5, 3.0)
		var pedestal := MeshInstance3D.new()
		pedestal.position.y = 0.75
		pedestal.mesh = pedestal_mesh
		var pedestal_material := StandardMaterial3D.new()
		pedestal_material.albedo_color = Color(0.16, 0.09, 0.035)
		pedestal.material_override = pedestal_material
		station.add_child(pedestal)

		for card_index in EXCHANGE_CARD_COUNT:
			var hidden_card_mesh := BoxMesh.new()
			hidden_card_mesh.size = Vector3(0.85, 0.12, 1.35)
			var hidden_card := MeshInstance3D.new()
			hidden_card.name = "CardSlot_%d" % card_index
			hidden_card.position = _exchange_card_local_position(card_index)
			hidden_card.mesh = hidden_card_mesh
			var card_material := StandardMaterial3D.new()
			card_material.albedo_color = Color(0.04, 0.04, 0.05)
			card_material.emission_enabled = true
			card_material.emission = Color(0.28, 0.18, 0.04)
			hidden_card.material_override = card_material
			station.add_child(hidden_card)

			var card_label := Label3D.new()
			card_label.name = "CardLabel_%d" % card_index
			card_label.position = hidden_card.position + Vector3(0.0, 0.09, 0.0)
			card_label.rotation_degrees.x = -90.0
			if station_position.z > 0.0:
				card_label.rotation_degrees.y = 180.0
			card_label.font_size = 42
			card_label.modulate = Color.WHITE
			card_label.outline_size = 8
			card_label.outline_modulate = Color.BLACK
			card_label.text = "?"
			station.add_child(card_label)

		var shape := BoxShape3D.new()
		shape.size = Vector3(3.0, 1.5, 3.0)
		var collision := CollisionShape3D.new()
		collision.position.y = 0.75
		collision.shape = shape
		station.add_child(collision)



func _deal_exchange_station_cards() -> void:
	for station in _exchange_stations():
		var station_cards: Array[Dictionary] = deck.draw_cards(EXCHANGE_CARD_COUNT)
		_set_station_cards(station, station_cards)


func _exchange_card_local_position(card_index: int) -> Vector3:
	var centered_index := float(card_index) - float(EXCHANGE_CARD_COUNT - 1) * 0.5
	return Vector3(centered_index * EXCHANGE_CARD_SPACING, 1.56, 0.0)


func _station_cards(station: StaticBody3D) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for card in station.get_meta("cards", []):
		if card is Dictionary:
			cards.append(card)
	if cards.is_empty() and station.has_meta("card"):
		var old_card = station.get_meta("card")
		if old_card is Dictionary:
			cards.append(old_card)
	return cards


func _set_station_cards(station: StaticBody3D, cards: Array) -> void:
	var typed_cards: Array[Dictionary] = []
	for card in cards:
		if card is Dictionary:
			typed_cards.append(card)
	station.set_meta("cards", typed_cards)
	if typed_cards.is_empty():
		station.remove_meta("card")
	else:
		station.set_meta("card", typed_cards[0])
	for card_index in EXCHANGE_CARD_COUNT:
		var mesh := station.get_node_or_null("CardSlot_%d" % card_index) as MeshInstance3D
		var label := station.get_node_or_null("CardLabel_%d" % card_index) as Label3D
		var has_card := card_index < typed_cards.size()
		if mesh != null:
			mesh.visible = has_card
			if has_card:
				var material := mesh.material_override as StandardMaterial3D
				if material != null:
					material.albedo_color = Color(0.04, 0.04, 0.05)
					material.emission = Color(0.28, 0.18, 0.04)
		if label != null:
			label.visible = has_card
			if has_card:
				label.text = "?"
				label.modulate = Color.WHITE


func _find_aimed_exchange_station() -> StaticBody3D:
	_player_exchange_card_index = -1
	if player.is_stunned() or player.hand.is_empty() or game_hud.is_hand_editor_open():
		return null
	var best_station: StaticBody3D = null
	var best_dot := KILL_CENTER_DOT
	for station_node in get_tree().get_nodes_in_group("exchange_stations"):
		var station := station_node as StaticBody3D
		if station == null:
			continue
		var station_cards := _station_cards(station)
		for card_index in station_cards.size():
			var card_position := station.to_global(_exchange_card_local_position(card_index))
			var to_card: Vector3 = card_position - player.get_view_origin()
			if to_card.length() > KILL_DISTANCE + 1.5:
				continue
			var center_dot: float = player.get_view_forward().dot(to_card.normalized())
			if center_dot > best_dot:
				best_dot = center_dot
				best_station = station
				_player_exchange_card_index = card_index
	return best_station


func _update_exchange_hold(delta: float) -> void:
	var is_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _exchange_locked_until_release:
		if not is_pressed:
			_exchange_locked_until_release = false
		return

	if not is_pressed or _player_exchange_target == null:
		_exchange_hold_time = 0.0
		_exchange_hold_target = null
		_exchange_hold_card_index = -1
		game_hud.set_exchange_progress(0.0, false)
		return

	if _exchange_hold_target != _player_exchange_target or _exchange_hold_card_index != _player_exchange_card_index:
		_exchange_hold_target = _player_exchange_target
		_exchange_hold_card_index = _player_exchange_card_index
		_exchange_hold_time = 0.0
	_exchange_hold_time = minf(_exchange_hold_time + delta, EXCHANGE_HOLD_SECONDS)
	game_hud.set_exchange_progress(_exchange_hold_time / EXCHANGE_HOLD_SECONDS, true)
	if _exchange_hold_time >= EXCHANGE_HOLD_SECONDS:
		var station_index := _exchange_stations().find(_exchange_hold_target)
		if _is_game_authority():
			_exchange_with_station(player, station_index, _exchange_hold_card_index)
		else:
			_request_exchange.rpc_id(1, station_index, _exchange_hold_card_index)
		_exchange_hold_time = 0.0
		_exchange_hold_target = null
		_exchange_hold_card_index = -1
		_exchange_locked_until_release = true


func _exchange_with_station(participant: Node3D, station_index: int, card_index: int) -> void:
	var stations := _exchange_stations()
	if station_index < 0 or station_index >= stations.size():
		return
	var station: StaticBody3D = stations[station_index]
	var station_cards := _station_cards(station)
	if card_index < 0 or card_index >= station_cards.size() or participant.hand.is_empty():
		return
	var hand: Array[Dictionary] = participant.hand.duplicate()
	var hand_index := hand.size() - 1
	var player_card: Dictionary = hand[hand_index]
	if player_card.get("suit", "") == "joker":
		if participant == player:
			game_hud.show_notification(GameConfig.text("joker_exchange"))
		elif NetworkManager.is_online and _peer_for_participant(participant) > 0:
			_show_remote_notification.rpc_id(_peer_for_participant(participant), GameConfig.text("joker_exchange"))
		return
	var station_card: Dictionary = station_cards[card_index]
	hand[hand_index] = station_card
	station_cards[card_index] = player_card
	_set_station_cards(station, station_cards)
	participant.set_hand(hand, true)
	_show_change_preview_for_participant(participant, player_card, station_card)
	if participant == player:
		game_hud.show_change_complete()
	elif NetworkManager.is_online and _peer_for_participant(participant) > 0:
		_show_remote_exchange_complete.rpc_id(_peer_for_participant(participant))


func _get_kill_cooldown_left(participant: Node3D) -> float:
	return maxf(float(_kill_cooldown_until.get(participant, 0.0)) - _now(), 0.0)


func _get_ability_cooldown_left(participant: Node3D) -> float:
	return maxf(float(_ability_cooldown_until.get(participant, 0.0)) - _now(), 0.0)


func _show_ability_not_ready(participant: Node3D) -> void:
	if participant == player:
		game_hud.show_notification(GameConfig.text("ability_not_ready"))
	elif NetworkManager.is_online and _peer_for_participant(participant) > 0:
		_show_remote_notification.rpc_id(_peer_for_participant(participant), GameConfig.text("ability_not_ready"))


func _set_barrier_visual(participant: Node3D, is_active: bool) -> void:
	if participant != null and participant.has_method("set_barrier_active"):
		participant.set_barrier_active(is_active)


func _show_kill_notifications(attacker: Node3D, target: Node3D) -> void:
	if target == player:
		game_hud.show_notification(GameConfig.text("killed"))
	elif NetworkManager.is_online and _peer_for_participant(target) > 0:
		_show_remote_notification.rpc_id(_peer_for_participant(target), GameConfig.text("killed"))
	if attacker == player:
		game_hud.show_notification(GameConfig.text("kill_notice") % _participant_name(target))
	elif NetworkManager.is_online and _peer_for_participant(attacker) > 0:
		_show_remote_notification.rpc_id(
			_peer_for_participant(attacker),
			GameConfig.text("kill_notice") % _participant_name(target)
		)


func _get_ability_message(rank: int, is_enhanced: bool) -> String:
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


func _configure_computers() -> void:
	var computers: Array[Node3D] = []
	for child in get_children():
		if child is CharacterBody3D and child != player:
			computers.append(child)

	while computers.size() > GameConfig.computer_count:
		var computer: Node3D = computers.pop_back()
		computer.free()
	while computers.size() < GameConfig.computer_count:
		var computer: Node3D = COMPUTER_SCENE.instantiate()
		add_child(computer)
		computers.append(computer)

	for index in computers.size():
		computers[index].name = ("%s %d" % ["コンピューター" if GameConfig.language == "ja" else "Computer", index + 1])
		computers[index].global_position = _spawn_position_for_index(index + 1)
	player.display_name = GameConfig.player_name
	player.global_position = _spawn_position_for_index(0)
	if player.has_method("set_body_color"):
		player.set_body_color(GameConfig.player_color())


func _spawn_network_players() -> void:
	var local_peer := multiplayer.get_unique_id()
	player.set_multiplayer_authority(1)
	player.display_name = NetworkManager.get_player_name(1) if NetworkManager.is_online else GameConfig.player_name
	if player.has_method("set_body_color"):
		player.set_body_color(NetworkManager.get_player_color(1) if NetworkManager.is_online else GameConfig.player_color())
	for peer_id in NetworkManager.players:
		if int(peer_id) == 1:
			continue
		var remote_player: CharacterBody3D = PLAYER_SCENE.instantiate()
		remote_player.name = "NetworkPlayer_%d" % int(peer_id)
		remote_player.display_name = NetworkManager.get_player_name(int(peer_id))
		remote_player.set_multiplayer_authority(int(peer_id))
		add_child(remote_player)
		remote_player.set_body_color(NetworkManager.get_player_color(int(peer_id)))
		remote_player.global_position = _spawn_position_for_peer(int(peer_id))
		if int(peer_id) == local_peer:
			player = remote_player
			player.ensure_local_camera()


func _spawn_position_for_index(index: int) -> Vector3:
	var spawn_points := [
		Vector3(-34.0, 0.0, 34.0),
		Vector3(34.0, 0.0, 34.0),
		Vector3(34.0, 0.0, -34.0),
		Vector3(-34.0, 0.0, -34.0),
		Vector3(0.0, 0.0, 34.0),
		Vector3(34.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -34.0),
		Vector3(-34.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.0),
	]
	return spawn_points[index % spawn_points.size()]


func _spawn_position_for_peer(peer_id: int) -> Vector3:
	if peer_id <= 1:
		return _spawn_position_for_index(0)
	return _spawn_position_for_index(peer_id - 1)


func _respawn_out_of_bounds_participants() -> void:
	for participant in _participants:
		if not is_instance_valid(participant):
			continue
		var horizontal := Vector2(participant.global_position.x, participant.global_position.z)
		if participant.global_position.y >= FALL_RESPAWN_Y and horizontal.length() <= MAP_RESPAWN_DISTANCE:
			continue
		var spawn_position: Vector3 = _participant_spawn_positions.get(participant, _default_spawn_for_participant(participant))
		participant.global_position = spawn_position
		if participant is CharacterBody3D:
			participant.velocity = Vector3.ZERO
		var peer_id := _peer_for_participant(participant)
		if NetworkManager.is_online and peer_id > 1:
			_receive_respawn.rpc_id(peer_id, participant.name, spawn_position)


func _default_spawn_for_participant(participant: Node3D) -> Vector3:
	var peer_id := _peer_for_participant(participant)
	if peer_id > 0:
		return _spawn_position_for_peer(peer_id)
	var index := maxi(_participants.find(participant), 0)
	return _spawn_position_for_index(index)


func _cache_participant_spawn_positions() -> void:
	_participant_spawn_positions.clear()
	for index in _participants.size():
		var participant: Node3D = _participants[index]
		_participant_spawn_positions[participant] = _default_spawn_for_participant(participant)


@rpc("authority", "call_remote", "reliable")
func _receive_respawn(participant_name: String, spawn_position: Vector3) -> void:
	var participant := _participant_by_name(participant_name)
	if participant == null:
		return
	participant.global_position = spawn_position
	if participant is CharacterBody3D:
		participant.velocity = Vector3.ZERO


func _has_empty_hand() -> bool:
	for participant in _participants:
		if participant.hand.is_empty():
			return true
	return false


func _finish_game() -> void:
	if _game_ending:
		return
	_game_ending = true
	var standings := _calculate_standings()
	if NetworkManager.is_online and multiplayer.is_server():
		var network_standings: Dictionary = {}
		for participant in standings:
			network_standings[participant.name] = standings[participant]
		_receive_game_finished.rpc(network_standings)
	var player_rank := int(standings[player])
	game_hud.show_end_message(GameConfig.text("win") if player_rank == 1 else GameConfig.text("place") % player_rank)
	Engine.time_scale = 0.2
	await get_tree().create_timer(5.0, true, false, true).timeout
	Engine.time_scale = 1.0
	_show_results(standings)


@rpc("authority", "call_remote", "reliable")
func _receive_game_finished(network_standings: Dictionary) -> void:
	if _game_ending:
		return
	_game_ending = true
	var standings: Dictionary = {}
	for participant_name in network_standings:
		var participant := _participant_by_name(String(participant_name))
		if participant != null:
			standings[participant] = int(network_standings[participant_name])
	var player_rank := int(standings.get(player, _participants.size()))
	game_hud.show_end_message(GameConfig.text("win") if player_rank == 1 else GameConfig.text("place") % player_rank)
	Engine.time_scale = 0.2
	await get_tree().create_timer(5.0, true, false, true).timeout
	Engine.time_scale = 1.0
	_show_results(standings)


func _calculate_standings() -> Dictionary:
	var sorted_participants := _participants.duplicate()
	sorted_participants.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		if a.has_joker() != b.has_joker():
			return not a.has_joker()
		return a.hand.size() < b.hand.size()
	)

	var standings: Dictionary = {}
	var previous: Node3D = null
	var current_rank := 0
	for index in sorted_participants.size():
		var participant: Node3D = sorted_participants[index]
		if previous == null or participant.has_joker() != previous.has_joker() or participant.hand.size() != previous.hand.size():
			current_rank = index + 1
		standings[participant] = current_rank
		previous = participant
	return standings


func _show_results(standings: Dictionary) -> void:
	get_tree().paused = true
	game_hud.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.025, 0.02, 0.035, 0.98)
	layer.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(650, 0)
	content.add_theme_constant_override("separation", 14)
	center.add_child(content)
	var title := Label.new()
	title.text = GameConfig.text("result")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	content.add_child(title)

	var sorted_participants := _participants.duplicate()
	sorted_participants.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return int(standings[a]) < int(standings[b])
	)
	for participant in sorted_participants:
		var row := Label.new()
		row.text = "%d  %s  -  %s%s" % [
			int(standings[participant]),
			_participant_name(participant),
			GameConfig.text("cards") % participant.hand.size(),
			("  ジョーカー" if GameConfig.language == "ja" else "  JOKER") if participant.has_joker() else "",
		]
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 26)
		content.add_child(row)

	var title_button := Button.new()
	title_button.custom_minimum_size = Vector2(0, 60)
	title_button.text = "Classic Roomに戻る" if GameConfig.language == "ja" else "Return to Classic Room"
	title_button.add_theme_font_size_override("font_size", 24)
	title_button.pressed.connect(func() -> void:
		get_tree().paused = false
		NetworkManager.return_to_waiting_room()
	)
	content.add_child(title_button)


func _participant_name(participant: Node3D) -> String:
	if participant.has_method("get_display_name"):
		return participant.get_display_name()
	return participant.name


func _is_game_authority() -> bool:
	return not NetworkManager.is_online or multiplayer.is_server()


func _is_computer(participant: Node3D) -> bool:
	return participant.has_method("get_chase_target")


func _participant_by_name(participant_name: String) -> Node3D:
	for participant in _participants:
		if participant.name == participant_name:
			return participant
	return null


func _participant_for_peer(peer_id: int) -> Node3D:
	return _participant_by_name("Player" if peer_id == 1 else "NetworkPlayer_%d" % peer_id)


func _peer_for_participant(participant: Node3D) -> int:
	if participant.name == "Player":
		return 1
	if participant.name.begins_with("NetworkPlayer_"):
		return int(participant.name.trim_prefix("NetworkPlayer_"))
	return 0


@rpc("authority", "call_remote", "reliable")
func _show_remote_notification(message: String) -> void:
	game_hud.show_notification(message)


@rpc("authority", "call_remote", "reliable")
func _show_remote_exchange_complete() -> void:
	game_hud.show_change_complete()


@rpc("authority", "call_remote", "reliable")
func _show_remote_change_preview(before_card: Dictionary, after_card: Dictionary) -> void:
	game_hud.show_change_preview(before_card, after_card)


func _show_change_preview_for_participant(participant: Node3D, before_card: Dictionary, after_card: Dictionary) -> void:
	if participant == player:
		game_hud.show_change_preview(before_card, after_card)
		return
	if NetworkManager.is_online and _peer_for_participant(participant) > 0:
		_show_remote_change_preview.rpc_id(_peer_for_participant(participant), before_card, after_card)


func _exchange_stations() -> Array[StaticBody3D]:
	var stations: Array[StaticBody3D] = []
	for node in get_tree().get_nodes_in_group("exchange_stations"):
		var station := node as StaticBody3D
		if station != null:
			stations.append(station)
	stations.sort_custom(func(a: StaticBody3D, b: StaticBody3D) -> bool:
		return a.global_position.z < b.global_position.z
	)
	return stations


func _request_local_action(action: String, value: int = 0, target_name: String = "") -> void:
	if _is_game_authority():
		_execute_player_action(player, action, value, target_name)
	else:
		_request_action.rpc_id(1, action, value, target_name)


func _execute_player_action(actor: Node3D, action: String, value: int, target_name: String) -> void:
	match action:
		"pair":
			_try_use_pair(actor, value)
		"item":
			_use_item(actor)
		"scythe":
			var target := _participant_by_name(target_name)
			if _can_server_scythe(actor, target):
				_use_scythe(actor, target)
		"coin":
			var target := _participant_by_name(target_name)
			if target != null and _can_server_coin_change(actor, target):
				_perform_change(actor, target, true)
		"kill":
			var target := _participant_by_name(target_name)
			if target != null and _can_server_kill(actor, target):
				_perform_kill(actor, target)
		"change":
			var target := _participant_by_name(target_name)
			if target != null and _can_server_change(actor, target):
				_perform_change(actor, target)


func _can_server_kill(actor: Node3D, target: Node3D) -> bool:
	return (
		actor != target
		and actor.global_position.distance_to(target.global_position) <= KILL_DISTANCE + 0.5
		and not actor.is_stunned()
		and not target.is_stunned()
		and _get_kill_cooldown_left(actor) <= 0.0
		and actor.has_joker()
	)


func _can_server_scythe(actor: Node3D, target: Node3D) -> bool:
	if actor == null or actor.is_stunned() or not _has_ready_scythe(actor):
		return false
	var effects: Dictionary = _effects[actor]
	if bool(effects.get("scythe_enhanced", false)):
		return true
	return (
		target != null
		and actor != target
		and actor.global_position.distance_to(target.global_position) <= KILL_DISTANCE + 0.5
		and not target.is_stunned()
		and _get_kill_cooldown_left(actor) <= 0.0
	)


func _can_server_change(actor: Node3D, target: Node3D) -> bool:
	return (
		actor != target
		and actor.global_position.distance_to(target.global_position) <= KILL_DISTANCE + 0.5
		and not actor.is_stunned()
		and not actor.hand.is_empty()
		and not target.hand.is_empty()
		and (_has_free_change(actor) or (_change_killers.get(target) == actor and target.is_stunned()))
	)


func _can_server_coin_change(actor: Node3D, target: Node3D) -> bool:
	return (
		actor != target
		and actor.global_position.distance_to(target.global_position) <= KILL_DISTANCE + 0.5
		and not actor.is_stunned()
		and not target.is_stunned()
		and not actor.hand.is_empty()
		and not target.hand.is_empty()
		and _has_ready_coin(actor)
	)


@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: String, value: int = 0, target_name: String = "") -> void:
	if not multiplayer.is_server():
		return
	var actor := _participant_for_peer(multiplayer.get_remote_sender_id())
	if actor != null:
		_execute_player_action(actor, action, value, target_name)


@rpc("any_peer", "call_remote", "reliable")
func _request_exchange(station_index: int, card_index: int) -> void:
	if not multiplayer.is_server():
		return
	var actor := _participant_for_peer(multiplayer.get_remote_sender_id())
	var stations := _exchange_stations()
	if actor == null or station_index < 0 or station_index >= stations.size():
		return
	if actor.global_position.distance_to(stations[station_index].global_position) <= KILL_DISTANCE + 1.5:
		_exchange_with_station(actor, station_index, card_index)


@rpc("any_peer", "call_remote", "reliable")
func _request_reorder(cards: Array) -> void:
	if not multiplayer.is_server():
		return
	var actor := _participant_for_peer(multiplayer.get_remote_sender_id())
	if actor != null and _same_cards(actor.hand, cards):
		actor.set_hand(cards)


func _same_cards(first: Array, second: Array) -> bool:
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


@rpc("any_peer", "call_remote", "reliable")
func _request_full_state() -> void:
	if multiplayer.is_server():
		_receive_game_state.rpc_id(multiplayer.get_remote_sender_id(), _build_game_state())


func _build_game_state() -> Dictionary:
	var participant_states: Dictionary = {}
	var now := _now()
	for participant in _participants:
		var effect_state: Dictionary = {}
		for key in [
			"invincible_until", "invisible_until", "free_change_until", "extra_kill_until", "scythe_until", "coin_until",
			"counter_until", "automatic_kill_until", "auto_cleanse_until", "recovery_speed_until"
		]:
			var remaining := maxf(float(_effects[participant].get(key, 0.0)) - now, 0.0)
			if remaining > 0.0:
				effect_state[key] = remaining
		for key in [
			"free_change_count", "free_change_duration", "extra_kill_available",
			"scythe_enhanced", "coin_count", "coin_duration",
			"counter_duration", "barrier_charges", "enhance_next_ability"
		]:
			if _effects[participant].has(key):
				effect_state[key] = _effects[participant][key]
		participant_states[participant.name] = {
			"transform": participant.global_transform,
			"hand": participant.hand,
			"stun": participant.get_stun_time_left(),
			"pending_stun": 0.0,
			"effects": effect_state,
			"kill_cooldown": _get_kill_cooldown_left(participant),
			"ability_cooldown": _get_ability_cooldown_left(participant),
			"item": _network_item_for(participant),
		}
	var station_cards: Array = []
	for station in _exchange_stations():
		station_cards.append(_station_cards(station))
	var change_rights: Dictionary = {}
	for target in _change_killers:
		if is_instance_valid(target) and is_instance_valid(_change_killers[target]):
			change_rights[target.name] = _change_killers[target].name
	return {
		"participants": participant_states,
		"deck_remaining": deck.remaining_count(),
		"deck_total": deck.total_count(),
		"time_left": _time_left,
		"stations": station_cards,
		"change_rights": change_rights,
		"card_views": _build_card_view_state(now),
		"map_reveals": _build_map_reveal_state(now),
	}


func _network_item_for(participant: Node3D) -> Dictionary:
	if not _items.has(participant):
		return {}
	var item: Dictionary = _items[participant]
	return {
		"name": item.get("name", ""),
		"duration": item.get("duration", 0.0),
		"time_left": item.get("time_left", 0.0),
		"charges": item.get("charges", 1),
	}


func _build_card_view_state(now: float) -> Dictionary:
	var result: Dictionary = {}
	for viewer in _card_views:
		var view: Dictionary = _card_views[viewer]
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


func _build_map_reveal_state(now: float) -> Dictionary:
	var result: Dictionary = {}
	for viewer in _map_reveals:
		var reveal: Dictionary = _map_reveals[viewer]
		result[viewer.name] = {
			"remaining": maxf(float(reveal.get("until", 0.0)) - now, 0.0),
			"positions": reveal.get("positions", {}).values(),
		}
	return result


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_game_state(state: Dictionary) -> void:
	var now := _now()
	_time_left = float(state.get("time_left", _time_left))
	game_hud.set_deck_count(int(state.get("deck_remaining", 0)), int(state.get("deck_total", 0)))
	var participant_states: Dictionary = state.get("participants", {})
	for participant_name in participant_states:
		var participant := _participant_by_name(String(participant_name))
		if participant == null:
			continue
		var data: Dictionary = participant_states[participant_name]
		if participant != player:
			participant.global_transform = data.get("transform", participant.global_transform)
		participant.set_hand(data.get("hand", []))
		participant.set_stun_state(float(data.get("stun", 0.0)), float(data.get("pending_stun", 0.0)))
		_kill_cooldown_until[participant] = now + float(data.get("kill_cooldown", 0.0))
		_ability_cooldown_until[participant] = now + float(data.get("ability_cooldown", 0.0))
		_apply_effect_state(participant, data.get("effects", {}), now)
		var item: Dictionary = data.get("item", {})
		if item.is_empty():
			_items.erase(participant)
		else:
			_items[participant] = item
	var stations := _exchange_stations()
	var station_cards: Array = state.get("stations", [])
	for index in mini(stations.size(), station_cards.size()):
		_set_station_cards(stations[index], station_cards[index])
	_change_killers.clear()
	for target_name in state.get("change_rights", {}):
		var target := _participant_by_name(String(target_name))
		var attacker := _participant_by_name(String(state["change_rights"][target_name]))
		if target != null and attacker != null:
			_change_killers[target] = attacker
	_apply_card_view_state(state.get("card_views", {}), now)
	_apply_map_reveal_state(state.get("map_reveals", {}), now)
	_sync_player_item_slot()


func _apply_effect_state(participant: Node3D, state: Dictionary, now: float) -> void:
	var effects: Dictionary = {}
	for key in state:
		if String(key).ends_with("_until"):
			effects[key] = now + float(state[key])
		else:
			effects[key] = state[key]
	_effects[participant] = effects
	participant.set_gold_outline(effects.has("invincible_until"))
	participant.set_invisible(effects.has("invisible_until"))
	_set_barrier_visual(participant, int(effects.get("barrier_charges", 0)) > 0)
	_refresh_speed_multiplier(participant)
	if participant.has_method("set_can_kill_without_joker"):
		participant.set_can_kill_without_joker(bool(effects.get("extra_kill_available", false)))


func _apply_card_view_state(state: Dictionary, now: float) -> void:
	_card_views.clear()
	for viewer_name in state:
		var viewer := _participant_by_name(String(viewer_name))
		if viewer == null:
			continue
		var source: Dictionary = state[viewer_name]
		var view := {"until": now + float(source.get("remaining", 0.0))}
		if source.has("targets"):
			var targets: Array[Node3D] = []
			for target_name in source["targets"]:
				var target := _participant_by_name(String(target_name))
				if target != null:
					targets.append(target)
			view["targets"] = targets
		elif source.has("target"):
			var target := _participant_by_name(String(source["target"]))
			if target != null:
				view["target"] = target
		_card_views[viewer] = view


func _apply_map_reveal_state(state: Dictionary, now: float) -> void:
	_map_reveals.clear()
	for viewer_name in state:
		var viewer := _participant_by_name(String(viewer_name))
		if viewer == null:
			continue
		var source: Dictionary = state[viewer_name]
		var positions: Dictionary = {}
		var index := 0
		for revealed_position in source.get("positions", []):
			positions[index] = revealed_position
			index += 1
		_map_reveals[viewer] = {
			"until": now + float(source.get("remaining", 0.0)),
			"positions": positions,
		}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
