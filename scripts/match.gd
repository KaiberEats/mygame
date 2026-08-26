extends Node3D

## 試合(Match.tscn)のエントリ / Composition Root（旧 main.gd）。
## ここでは各 System/コンポーネントを構築・結線し、_process で tick を発火するだけ。
## ゲームのルール・状態・表示は持たず、systems/ · abilities/ · entities/components · net/ · ui/ が担う。

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

@onready var pause_menu: CanvasLayer = $UI/PauseMenu
@onready var settings_menu: Control = $UI/Settings
@onready var deck: Node = $Services/Deck
@onready var game_hud: CanvasLayer = $UI/GameHud
@onready var player: CharacterBody3D = $Participants/Player
@onready var _participants_root: Node3D = $Participants

var _participants: Array[Node3D] = []
var _player_kill_target: Node3D = null
var _player_change_target: Node3D = null
var _player_exchange_target: StaticBody3D = null
var _change_killers: Dictionary = {}
var _targeting := TargetingService.new()
var _exchange: ExchangeSystem = null
var _item_system: ItemSystem = null
var _combat: CombatSystem = null
var _ability: AbilitySystem = null
var _codec := GameStateCodec.new()
var _net: NetSync = null
var _flow: GameFlow = null
var _hud: HudPresenter = null
var _participants_mgr: Participants = null
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
	_exchange = ExchangeSystem.new()
	_exchange.name = "ExchangeSystem"
	add_child(_exchange)
	_exchange.setup(self)
	_item_system = ItemSystem.new()
	_item_system.name = "ItemSystem"
	add_child(_item_system)
	_item_system.setup(self)
	_combat = CombatSystem.new()
	_combat.name = "CombatSystem"
	add_child(_combat)
	_combat.setup(self)
	_ability = AbilitySystem.new()
	_ability.name = "AbilitySystem"
	add_child(_ability)
	_ability.setup(self)
	_net = NetSync.new()
	_net.name = "NetSync"
	add_child(_net)
	_net.setup(self)
	_flow = GameFlow.new()
	_flow.name = "GameFlow"
	add_child(_flow)
	_flow.setup(self)
	_hud = HudPresenter.new(self, game_hud)
	_participants_mgr = Participants.new()
	_participants_mgr.setup(self)
	pause_menu.hide()
	settings_menu.hide()
	pause_menu.resume_requested.connect(_resume_game)
	pause_menu.settings_requested.connect(_show_settings_menu)
	pause_menu.tutorial_requested.connect(_show_tutorial)
	settings_menu.back_requested.connect(_show_pause_menu)
	game_hud.hand_reordered.connect(_on_hand_reordered)
	game_hud.debug_return_requested.connect(_force_return_to_waiting_room)
	if not NetworkManager.peers_changed.is_connected(_refresh_network_player_profiles):
		NetworkManager.peers_changed.connect(_refresh_network_player_profiles)
	_configure_computers()
	_spawn_network_players()
	player.ensure_local_camera()
	player.hand_changed.connect(_on_player_hand_changed)
	_participants = [player]
	for child in _participants_root.get_children():
		if child is CharacterBody3D and child != player:
			_participants.append(child)
	_cache_participant_spawn_positions()
	for participant in _participants:
		_attach_components(participant)
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
	_hud.refresh_status()
	_player_kill_target = _find_kill_target(player)
	_player_change_target = _find_change_target(player)
	_player_exchange_target = _find_aimed_exchange_station()
	_update_exchange_hold(delta)
	_hud.refresh_actions()
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
	return _targeting.find_aimed(attacker, _participants, _change_killers, for_change, KILL_DISTANCE, KILL_CENTER_DOT)


func _try_computer_kills() -> void:
	_combat.try_computer_kills()


func _update_automatic_kills() -> void:
	_combat.update_automatic_kills()


func _perform_kill(attacker: Node3D, target: Node3D) -> void:
	_combat.perform_kill(attacker, target)


func _perform_kill_with_options(attacker: Node3D, target: Node3D, allow_change: bool, consume_extra_kill: bool) -> void:
	_combat.perform_kill_with_options(attacker, target, allow_change, consume_extra_kill)


func _perform_change(attacker: Node3D, target: Node3D, forced_free_change: bool = false) -> void:
	_combat.perform_change(attacker, target, forced_free_change)


func _clear_expired_change_rights() -> void:
	_combat.clear_expired_change_rights()


func _set_hand_editor_open(is_open: bool) -> void:
	if is_open:
		game_hud.open_hand_editor(player.hand)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		game_hud.close_hand_editor()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _request_use_button_action() -> void:
	var scythe_target := _find_scythe_target(player)
	var player_effects: Dictionary = _status(player).data
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
	_item_system.grant(participant, item_name, duration, icon)


func _try_use_pair(participant: Node3D, pair_slot: int) -> bool:
	return _ability.try_use_pair(participant, pair_slot)


func _activate_pair_ability(participant: Node3D, ability_rank: int) -> void:
	_ability.activate_pair_ability(participant, ability_rank)


func _update_computer_pair_actions(delta: float) -> void:
	_ability.update_computer_pair_actions(delta)


func _is_valid_pair_slot(participant: Node3D, pair_slot: int) -> bool:
	return _ability.is_valid_pair_slot(participant, pair_slot)


func _reset_computer_pair_action_timer() -> void:
	_ability.reset_computer_pair_action_timer()


func _get_pair_slot_from_event(event: InputEvent) -> int:
	return _ability.get_pair_slot_from_event(event)


func _update_items(delta: float) -> void:
	_item_system.update(delta)


func _use_item(participant: Node3D) -> void:
	_item_system.use(participant)


func _activate_item(_participant: Node3D, _item_name: String) -> void:
	_item_system.activate(_participant, _item_name)


func _use_passive_item(participant: Node3D, target_name: String) -> void:
	_item_system.use_passive(participant, target_name)


func _use_scythe(attacker: Node3D, target: Node3D) -> void:
	_combat.use_scythe(attacker, target)


func _use_sword(attacker: Node3D) -> void:
	_combat.use_sword(attacker)


func _sync_player_item_slot() -> void:
	_item_system.sync_player_slot()


func _passive_item_slot_for(participant: Node3D) -> Dictionary:
	return _item_system.passive_slot_for(participant)


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
		var effects: Dictionary = _status(participant).data
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

	for viewer in _participants:
		var cv: Dictionary = _vision(viewer).card_view
		if not cv.is_empty() and now >= float(cv.get("until", 0.0)):
			_vision(viewer).card_view = {}
		var mr: Dictionary = _vision(viewer).map_reveal
		if not mr.is_empty() and now >= float(mr.get("until", 0.0)):
			_vision(viewer).map_reveal = {}
	_sync_player_item_slot()


func _is_location_revealed(target: Node3D) -> bool:
	for viewer in _participants:
		var positions: Dictionary = _vision(viewer).map_reveal.get("positions", {})
		if positions.has(target):
			return true
	return false


func _is_hand_being_viewed(target: Node3D) -> bool:
	for viewer in _participants:
		var view_data: Dictionary = _vision(viewer).card_view
		if view_data.get("target") == target:
			return true
		if view_data.has("targets") and target in view_data["targets"]:
			return true
	return false


func _has_extra_kill(participant: Node3D) -> bool:
	var effects: Dictionary = _status(participant).data
	return bool(effects.get("extra_kill_available", false)) and _is_effect_active(participant, "extra_kill_until")


func _has_free_change(participant: Node3D) -> bool:
	var effects: Dictionary = _status(participant).data
	return int(effects.get("free_change_count", 0)) > 0 and _is_effect_active(participant, "free_change_until")


func _has_ready_scythe(participant: Node3D) -> bool:
	var effects: Dictionary = _status(participant).data
	return float(effects.get("scythe_until", 0.0)) > _now()


func _has_ready_coin(participant: Node3D) -> bool:
	var effects: Dictionary = _status(participant).data
	return int(effects.get("coin_count", 0)) > 0 and float(effects.get("coin_until", 0.0)) > _now()


func _is_effect_active(participant: Node3D, key: String) -> bool:
	return float(_status(participant).data.get(key, 0.0)) > _now()


func _update_post_stun_buffs() -> void:
	var now := _now()
	for participant in _participants:
		var is_stunned_now: bool = participant.is_stunned()
		if bool(_was_stunned.get(participant, false)) and not is_stunned_now:
			var effects: Dictionary = _status(participant).data
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
	for viewer in _participants:
		var view_data: Dictionary = _vision(viewer).card_view
		if view_data.get("target") == participant:
			_vision(viewer).card_view = {}
		elif view_data.has("targets"):
			var targets: Array = view_data["targets"]
			targets.erase(participant)
			if targets.is_empty():
				_vision(viewer).card_view = {}
	for viewer in _participants:
		var positions: Dictionary = _vision(viewer).map_reveal.get("positions", {})
		positions.erase(participant)


func _has_negative_status(participant: Node3D) -> bool:
	if participant.is_stunned():
		return true
	for viewer in _participants:
		var view_data: Dictionary = _vision(viewer).card_view
		if view_data.get("target") == participant:
			return true
		if view_data.has("targets") and participant in view_data["targets"]:
			return true
	for viewer in _participants:
		var positions: Dictionary = _vision(viewer).map_reveal.get("positions", {})
		if positions.has(participant):
			return true
	return false


func _find_nearest_participant(participant: Node3D) -> Node3D:
	return _targeting.find_nearest(participant, _participants)


func _find_visible_missile_target(shooter: Node3D) -> Node3D:
	return _targeting.find_visible_missile(shooter, _participants, player, KILL_CENTER_DOT)


func _has_line_of_sight(shooter: Node3D, target: Node3D) -> bool:
	return _targeting.has_line_of_sight(shooter, target)


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
	_combat.stun_without_change(target)


func _update_computer_items() -> void:
	_item_system.update_computer_items()


func _try_computer_free_changes() -> void:
	for participant in _participants:
		if not _is_computer(participant) or participant.is_stunned() or not _has_free_change(participant):
			continue
		var target := _find_nearest_participant(participant)
		if target != null and participant.global_position.distance_to(target.global_position) <= KILL_DISTANCE:
			_perform_change(participant, target)


func _setup_exchange_stations() -> void:
	_exchange.setup_stations()



func _deal_exchange_station_cards() -> void:
	_exchange.deal_cards()


func _exchange_card_local_position(card_index: int) -> Vector3:
	return _exchange.card_local_position(card_index)


func _station_cards(station: StaticBody3D) -> Array[Dictionary]:
	return _exchange.station_cards(station)


func _set_station_cards(station: StaticBody3D, cards: Array) -> void:
	_exchange.set_station_cards(station, cards)


func _find_aimed_exchange_station() -> StaticBody3D:
	return _exchange.find_aimed_station()


func _update_exchange_hold(delta: float) -> void:
	_exchange.update_hold(delta)


func _exchange_with_station(participant: Node3D, station_index: int, card_index: int) -> void:
	_exchange.exchange_with_station(participant, station_index, card_index)


func _get_kill_cooldown_left(participant: Node3D) -> float:
	return maxf(float(_cooldown(participant).kill_until) - _now(), 0.0)


func _get_ability_cooldown_left(participant: Node3D) -> float:
	return maxf(float(_cooldown(participant).ability_until) - _now(), 0.0)


func _show_ability_not_ready(participant: Node3D) -> void:
	_ability.show_ability_not_ready(participant)


func _set_barrier_visual(participant: Node3D, is_active: bool) -> void:
	_combat.set_barrier_visual(participant, is_active)


func _show_kill_notifications(attacker: Node3D, target: Node3D) -> void:
	_combat.show_kill_notifications(attacker, target)


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
	_participants_mgr.configure_computers()


func _spawn_network_players() -> void:
	_participants_mgr.spawn_network_players()


func _refresh_network_player_profiles() -> void:
	_participants_mgr.refresh_network_player_profiles()


func _spawn_position_for_index(index: int) -> Vector3:
	return _participants_mgr.spawn_position_for_index(index)


func _spawn_position_for_peer(peer_id: int) -> Vector3:
	return _participants_mgr.spawn_position_for_peer(peer_id)


func respawn_remote(peer_id: int, participant_name: String, spawn_position: Vector3) -> void:
	_receive_respawn.rpc_id(peer_id, participant_name, spawn_position)


func _respawn_out_of_bounds_participants() -> void:
	_participants_mgr.respawn_out_of_bounds()


func _default_spawn_for_participant(participant: Node3D) -> Vector3:
	return _participants_mgr.default_spawn_for(participant)


func _cache_participant_spawn_positions() -> void:
	_participants_mgr.cache_spawn_positions()


@rpc("authority", "call_remote", "reliable")
func _receive_respawn(participant_name: String, spawn_position: Vector3) -> void:
	var participant := _participant_by_name(participant_name)
	if participant == null:
		return
	participant.global_position = spawn_position
	if participant is CharacterBody3D:
		participant.velocity = Vector3.ZERO


func _has_empty_hand() -> bool:
	return _flow.has_empty_hand()


func _finish_game() -> void:
	_flow.finish_game()


func broadcast_game_finished(network_standings: Dictionary) -> void:
	_receive_game_finished.rpc(network_standings)


@rpc("authority", "call_remote", "reliable")
func _receive_game_finished(network_standings: Dictionary) -> void:
	_flow.receive_game_finished(network_standings)


func _calculate_standings() -> Dictionary:
	return _flow.calculate_standings()


func _show_results(standings: Dictionary) -> void:
	_flow.show_results(standings)


func _participant_name(participant: Node3D) -> String:
	if participant.has_method("get_display_name"):
		return participant.get_display_name()
	return participant.name


func _is_game_authority() -> bool:
	return _net.is_game_authority()


func _is_computer(participant: Node3D) -> bool:
	return participant.has_method("get_chase_target")


func _participant_by_name(participant_name: String) -> Node3D:
	for participant in _participants:
		if participant.name == participant_name:
			return participant
	return null


func _participant_for_peer(peer_id: int) -> Node3D:
	return _net.participant_for_peer(peer_id)


func _peer_for_participant(participant: Node3D) -> int:
	return _net.peer_for_participant(participant)


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


func request_exchange_remote(station_index: int, card_index: int) -> void:
	_request_exchange.rpc_id(1, station_index, card_index)


func notify_participant(participant: Node3D, message: String) -> void:
	if participant == player:
		game_hud.show_notification(message)
	elif NetworkManager.is_online and _peer_for_participant(participant) > 0:
		_show_remote_notification.rpc_id(_peer_for_participant(participant), message)


func notify_exchange_complete(participant: Node3D) -> void:
	if participant == player:
		game_hud.show_change_complete()
	elif NetworkManager.is_online and _peer_for_participant(participant) > 0:
		_show_remote_exchange_complete.rpc_id(_peer_for_participant(participant))


func _exchange_stations() -> Array[StaticBody3D]:
	return _exchange.stations()


func _request_local_action(action: String, value: int = 0, target_name: String = "") -> void:
	if _is_game_authority():
		_execute_player_action(player, action, value, target_name)
	else:
		_request_action.rpc_id(1, action, value, target_name)


func _execute_player_action(actor: Node3D, action: String, value: int, target_name: String) -> void:
	_net.execute_player_action(actor, action, value, target_name)


func _can_server_kill(actor: Node3D, target: Node3D) -> bool:
	return _net.can_server_kill(actor, target)


func _can_server_scythe(actor: Node3D, target: Node3D) -> bool:
	return _net.can_server_scythe(actor, target)


func _can_server_change(actor: Node3D, target: Node3D) -> bool:
	return _net.can_server_change(actor, target)


func _can_server_coin_change(actor: Node3D, target: Node3D) -> bool:
	return _net.can_server_coin_change(actor, target)


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
	return _codec.same_cards(first, second)


@rpc("any_peer", "call_remote", "reliable")
func _request_full_state() -> void:
	if multiplayer.is_server():
		_receive_game_state.rpc_id(multiplayer.get_remote_sender_id(), _build_game_state())


func _build_game_state() -> Dictionary:
	return _codec.build_state(self)


func _network_item_for(participant: Node3D) -> Dictionary:
	return _codec.network_item_for(self, participant)


func _build_card_view_state(now: float) -> Dictionary:
	return _codec.build_card_view_state(self, now)


func _build_map_reveal_state(now: float) -> Dictionary:
	return _codec.build_map_reveal_state(self, now)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_game_state(state: Dictionary) -> void:
	_codec.apply_state(self, state)


func _apply_effect_state(participant: Node3D, state: Dictionary, now: float) -> void:
	_codec.apply_effect_state(self, participant, state, now)


func _apply_card_view_state(state: Dictionary, now: float) -> void:
	_codec.apply_card_view_state(self, state, now)


func _apply_map_reveal_state(state: Dictionary, now: float) -> void:
	_codec.apply_map_reveal_state(self, state, now)


func _attach_components(participant: Node) -> void:
	var status := StatusComponent.new()
	status.name = "StatusComponent"
	participant.add_child(status)
	var cooldown := CooldownComponent.new()
	cooldown.name = "CooldownComponent"
	participant.add_child(cooldown)
	var item := ItemComponent.new()
	item.name = "ItemComponent"
	participant.add_child(item)
	var vision := VisionComponent.new()
	vision.name = "VisionComponent"
	participant.add_child(vision)


func _status(participant: Node) -> StatusComponent:
	return participant.get_node(^"StatusComponent")


func _cooldown(participant: Node) -> CooldownComponent:
	return participant.get_node(^"CooldownComponent")


func _item(participant: Node) -> ItemComponent:
	return participant.get_node(^"ItemComponent")


func _vision(participant: Node) -> VisionComponent:
	return participant.get_node(^"VisionComponent")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
