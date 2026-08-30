extends Node3D

## 試合(Match.tscn)のエントリ / Composition Root。
## 各 System/コンポーネントを構築・結線し、_process で tick を発火する。
## ネットの @rpc 入口(NodePath一致のため)を持つ。ルール/状態/表示は各層が担う。

const HOMING_MISSILE_SCENE := preload("res://scenes/entities/HomingMissile.tscn")
const COMPUTER_SCENE := preload("res://scenes/entities/Computer.tscn")
const PLAYER_SCENE := preload("res://scenes/entities/Player.tscn")
const TUTORIAL_SCENE := preload("res://scenes/ui/Tutorial.tscn")

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
var _status_system: StatusSystem = null
var _controls: PlayerController = null
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
	_status_system = StatusSystem.new()
	_status_system.name = "StatusSystem"
	add_child(_status_system)
	_status_system.setup(self)
	_hud = HudPresenter.new(self, game_hud)
	_participants_mgr = Participants.new()
	_participants_mgr.setup(self)
	_controls = PlayerController.new()
	_controls.name = "PlayerController"
	add_child(_controls)
	_controls.setup(self)
	pause_menu.hide()
	settings_menu.hide()
	pause_menu.resume_requested.connect(_controls.resume_game)
	pause_menu.settings_requested.connect(_controls.show_settings_menu)
	pause_menu.tutorial_requested.connect(_controls.show_tutorial)
	settings_menu.back_requested.connect(_controls.show_pause_menu)
	game_hud.hand_reordered.connect(_on_hand_reordered)
	game_hud.debug_return_requested.connect(_controls.force_return_to_waiting_room)
	if not NetworkManager.peers_changed.is_connected(_participants_mgr.refresh_network_player_profiles):
		NetworkManager.peers_changed.connect(_participants_mgr.refresh_network_player_profiles)
	_participants_mgr.configure_computers()
	_participants_mgr.spawn_network_players()
	player.ensure_local_camera()
	player.hand_changed.connect(_on_player_hand_changed)
	_participants = [player]
	for child in _participants_root.get_children():
		if child is CharacterBody3D and child != player:
			_participants.append(child)
	_participants_mgr.cache_spawn_positions()
	for participant in _participants:
		_was_stunned[participant] = participant.is_stunned()
	_exchange.setup_stations()
	if _net.is_game_authority():
		deck.reset_and_shuffle(GameConfig.deck_size)
		deck.ensure_joker_in_next_draws(GameConfig.HAND_SIZE * _participants.size())
		for participant in _participants:
			participant.set_hand(deck.draw_cards(GameConfig.HAND_SIZE))
		_exchange.deal_cards()
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
	_ability.reset_computer_pair_action_timer()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	if get_tree().paused and _controls.should_pause_game():
		return
	if _game_ending:
		return

	if _net.is_game_authority():
		_time_left = maxf(_time_left - delta, 0.0)
	_hud.refresh_status()
	_player_kill_target = _combat.find_kill_target(player)
	_player_change_target = _combat.find_change_target(player)
	_player_exchange_target = _exchange.find_aimed_station()
	_exchange.update_hold(delta)
	_hud.refresh_actions()
	if not _net.is_game_authority():
		return
	_item_system.update(delta)
	_participants_mgr.respawn_out_of_bounds()
	_status_system.update_post_stun_buffs()
	_status_system.update_effects()
	_combat.update_automatic_kills()
	_ability.update_computer_pair_actions(delta)
	_item_system.update_computer_items()
	_combat.clear_expired_change_rights()
	_combat.try_computer_kills()
	_try_computer_free_changes()
	_network_snapshot_time_left -= delta
	if NetworkManager.is_online and _network_snapshot_time_left <= 0.0:
		_network_snapshot_time_left = GameConfig.NETWORK_SNAPSHOT_INTERVAL
		_receive_game_state.rpc(_codec.build_state(self))
	if _time_left <= 0.0 or _flow.has_empty_hand():
		_flow.finish_game()


func _find_aimed_target(attacker: Node3D, for_change: bool) -> Node3D:
	return _targeting.find_aimed(attacker, _participants, _change_killers, for_change, GameConfig.KILL_DISTANCE, GameConfig.KILL_CENTER_DOT)


func _on_hand_reordered(cards: Array[Dictionary]) -> void:
	if _net.is_game_authority():
		player.set_hand(cards)
	else:
		_request_reorder.rpc_id(1, cards)


func _on_player_hand_changed(cards: Array[Dictionary]) -> void:
	game_hud.set_hand(cards)


func _refill_hand(participant: Node3D) -> void:
	var missing_count := maxi(GameConfig.HAND_SIZE - participant.hand.size(), 0)
	if missing_count <= 0:
		return
	var cards: Array[Dictionary] = deck.draw_cards(missing_count)
	if cards.is_empty():
		return
	var updated_hand: Array[Dictionary] = participant.hand.duplicate()
	updated_hand.append_array(cards)
	participant.set_hand(updated_hand, true)


func _find_nearest_participant(participant: Node3D) -> Node3D:
	return _targeting.find_nearest(participant, _participants)


func _find_visible_missile_target(shooter: Node3D) -> Node3D:
	return _targeting.find_visible_missile(shooter, _participants, player, GameConfig.KILL_CENTER_DOT)


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
	if not _net.is_game_authority():
		return
	_combat.stun_without_change(target)


func _try_computer_free_changes() -> void:
	for participant in _participants:
		if not participant.is_computer() or participant.is_stunned() or not _status_system.has_free_change(participant):
			continue
		var target := _find_nearest_participant(participant)
		if target != null and participant.global_position.distance_to(target.global_position) <= GameConfig.KILL_DISTANCE:
			_combat.perform_change(participant, target)


func _get_kill_cooldown_left(participant: Node3D) -> float:
	return maxf(float(participant.cooldown().kill_until) - Clock.now(), 0.0)


func _get_ability_cooldown_left(participant: Node3D) -> float:
	return maxf(float(participant.cooldown().ability_until) - Clock.now(), 0.0)


func respawn_remote(peer_id: int, participant_name: String, spawn_position: Vector3) -> void:
	_receive_respawn.rpc_id(peer_id, participant_name, spawn_position)


@rpc("authority", "call_remote", "reliable")
func _receive_respawn(participant_name: String, spawn_position: Vector3) -> void:
	var participant := _participant_by_name(participant_name)
	if participant == null:
		return
	participant.global_position = spawn_position
	if participant is CharacterBody3D:
		participant.velocity = Vector3.ZERO


func broadcast_game_finished(network_standings: Dictionary) -> void:
	_receive_game_finished.rpc(network_standings)


@rpc("authority", "call_remote", "reliable")
func _receive_game_finished(network_standings: Dictionary) -> void:
	_flow.receive_game_finished(network_standings)


func _participant_by_name(participant_name: String) -> Node3D:
	for participant in _participants:
		if participant.name == participant_name:
			return participant
	return null


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
	if NetworkManager.is_online and _net.peer_for_participant(participant) > 0:
		_show_remote_change_preview.rpc_id(_net.peer_for_participant(participant), before_card, after_card)


func request_exchange_remote(station_index: int, card_index: int) -> void:
	_request_exchange.rpc_id(1, station_index, card_index)


func notify_participant(participant: Node3D, message: String) -> void:
	if participant == player:
		game_hud.show_notification(message)
	elif NetworkManager.is_online and _net.peer_for_participant(participant) > 0:
		_show_remote_notification.rpc_id(_net.peer_for_participant(participant), message)


func notify_exchange_complete(participant: Node3D) -> void:
	if participant == player:
		game_hud.show_change_complete()
	elif NetworkManager.is_online and _net.peer_for_participant(participant) > 0:
		_show_remote_exchange_complete.rpc_id(_net.peer_for_participant(participant))


func request_action_remote(action: String, value: int = 0, target_name: String = "") -> void:
	_request_action.rpc_id(1, action, value, target_name)


@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: String, value: int = 0, target_name: String = "") -> void:
	if not multiplayer.is_server():
		return
	var actor := _net.participant_for_peer(multiplayer.get_remote_sender_id())
	if actor != null:
		_net.execute_player_action(actor, action, value, target_name)


@rpc("any_peer", "call_remote", "reliable")
func _request_exchange(station_index: int, card_index: int) -> void:
	if not multiplayer.is_server():
		return
	var actor := _net.participant_for_peer(multiplayer.get_remote_sender_id())
	var stations := _exchange.stations()
	if actor == null or station_index < 0 or station_index >= stations.size():
		return
	if actor.global_position.distance_to(stations[station_index].global_position) <= GameConfig.KILL_DISTANCE + 1.5:
		_exchange.exchange_with_station(actor, station_index, card_index)


@rpc("any_peer", "call_remote", "reliable")
func _request_reorder(cards: Array) -> void:
	if not multiplayer.is_server():
		return
	var actor := _net.participant_for_peer(multiplayer.get_remote_sender_id())
	if actor != null and _codec.same_cards(actor.hand, cards):
		actor.set_hand(cards)


@rpc("any_peer", "call_remote", "reliable")
func _request_full_state() -> void:
	if multiplayer.is_server():
		_receive_game_state.rpc_id(multiplayer.get_remote_sender_id(), _codec.build_state(self))


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_game_state(state: Dictionary) -> void:
	_codec.apply_state(self, state)


