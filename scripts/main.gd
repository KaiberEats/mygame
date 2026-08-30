extends Node3D

## 試合(Match.tscn)のエントリ / Composition Root。
## 各 System/コンポーネントを構築・結線し、_process で tick を発火する。
## ネットの @rpc 入口(NodePath一致のため)を持つ。ルール/状態/表示は各層が担う。

const HOMING_MISSILE_SCENE := preload("res://scenes/entities/HomingMissile.tscn")
const COMPUTER_SCENE := preload("res://scenes/entities/Computer.tscn")
const PLAYER_SCENE := preload("res://scenes/entities/Player.tscn")

@export var minimap_world_half_extent := 20.0

@onready var pause_menu: CanvasLayer = $UI/PauseMenu
@onready var settings_menu: Control = $UI/Settings
@onready var deck: Node = $Services/Deck
@onready var game_hud: CanvasLayer = $UI/GameHud
@onready var _participants_root: Node3D = $Participants

# System 群は Match.tscn の Systems ノードに配置。main は参照して結線・tick 発火する。
@onready var _exchange: ExchangeSystem = $Systems/ExchangeSystem
@onready var _item_system: ItemSystem = $Systems/ItemSystem
@onready var _combat: CombatSystem = $Systems/CombatSystem
@onready var _ability: AbilitySystem = $Systems/AbilitySystem
@onready var _net: NetSync = $Systems/NetSync
@onready var _flow: GameFlow = $Systems/GameFlow
@onready var _status_system: StatusSystem = $Systems/StatusSystem
@onready var _game_state: GameStateManager = $Systems/GameStateManager
@onready var _controls: PlayerController = $Systems/PlayerController

# シーンに置けない RefCounted はここで生成する。
var _targeting := TargetingService.new()
var _codec := GameStateCodec.new()
var _hud: HudPresenter = null
var _participants_mgr: Participants = null
var _net_gateway: NetGateway = null

# 参加者レジストリへのショートハンド（@rpc 入口・構築で使う）。
var player: Node3D:
	get:
		return _participants_mgr.local_player
var _participants: Array[Node3D]:
	get:
		return _participants_mgr.all


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	randomize()
	# --- シーンに置けない RefCounted を生成 ---
	_net_gateway = NetGateway.new()
	_participants_mgr = Participants.new()
	_hud = HudPresenter.new(game_hud, _participants_mgr, _game_state, _status_system, _controls)

	# --- 結線（依存注入）---
	_exchange.setup(_participants_mgr, deck, _net, _net_gateway, game_hud, self)
	_item_system.setup(_participants_mgr, _combat, _status_system, _targeting, _net_gateway, game_hud)
	_combat.setup(_participants_mgr, _status_system, _item_system, _targeting, _net_gateway, game_hud)
	_ability.setup(_participants_mgr, _combat, _status_system, _item_system, deck, _net_gateway, game_hud)
	_net.setup(_participants_mgr, _ability, _item_system, _combat, _status_system)
	_codec.setup(_participants_mgr, _exchange, _combat, _status_system, _item_system, deck, game_hud, _game_state)
	_flow.setup(_participants_mgr, _game_state, _net_gateway, game_hud, self)
	_status_system.setup(_participants_mgr, _item_system)
	_net_gateway.setup(self)
	_controls.setup(_participants_mgr, _ability, _combat, _exchange, _status_system, _net, _net_gateway, _game_state,
		game_hud, pause_menu, settings_menu, self)
	_participants_mgr.setup(_participants_root, _net, PLAYER_SCENE, COMPUTER_SCENE)
	_participants_mgr.local_player = _participants_root.get_node(^"Player")
	_participants_mgr.remote_respawn_requested.connect(respawn_remote)

	# メニュー/HUD の signal は Match.tscn で接続済み。実行時に決まる接続だけここで行う。
	pause_menu.hide()
	settings_menu.hide()
	if not NetworkManager.peers_changed.is_connected(_participants_mgr.refresh_network_player_profiles):
		NetworkManager.peers_changed.connect(_participants_mgr.refresh_network_player_profiles)

	# --- 参加者の生成・配置 ---
	_participants_mgr.configure_computers()
	_participants_mgr.spawn_network_players()
	player.ensure_local_camera()
	player.hand_changed.connect(_on_player_hand_changed)
	_participants_mgr.collect()
	_participants_mgr.cache_spawn_positions()
	_status_system.seed_stun_state()
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
	_game_state.time_left = GameConfig.time_limit_minutes * 60.0
	game_hud.set_time_left(_game_state.time_left)
	_ability.reset_computer_pair_action_timer()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	if get_tree().paused and _controls.should_pause_game():
		return
	if _game_state.is_ending:
		return

	if _net.is_game_authority():
		_game_state.time_left = maxf(_game_state.time_left - delta, 0.0)
	_hud.refresh_status()
	_controls.update_aim()
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
	_combat.try_computer_free_changes()
	_game_state.network_snapshot_time_left -= delta
	if NetworkManager.is_online and _game_state.network_snapshot_time_left <= 0.0:
		_game_state.network_snapshot_time_left = GameConfig.NETWORK_SNAPSHOT_INTERVAL
		_receive_game_state.rpc(_codec.build_state())
	if _game_state.time_left <= 0.0 or _flow.has_empty_hand():
		_flow.finish_game()


func _on_hand_reordered(cards: Array[Dictionary]) -> void:
	if _net.is_game_authority():
		player.set_hand(cards)
	else:
		_request_reorder.rpc_id(1, cards)


func _on_player_hand_changed(cards: Array[Dictionary]) -> void:
	game_hud.set_hand(cards)


func _launch_missile(shooter: Node3D, target: Node3D) -> void:
	if NetworkManager.is_online:
		_spawn_missile.rpc(shooter.name, target.name)
		return
	_spawn_missile(shooter.name, target.name)


@rpc("authority", "call_local", "reliable")
func _spawn_missile(shooter_name: String, target_name: String) -> void:
	var shooter := _participants_mgr.by_name(shooter_name)
	var target := _participants_mgr.by_name(target_name)
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


func respawn_remote(peer_id: int, participant_name: String, spawn_position: Vector3) -> void:
	_receive_respawn.rpc_id(peer_id, participant_name, spawn_position)


@rpc("authority", "call_remote", "reliable")
func _receive_respawn(participant_name: String, spawn_position: Vector3) -> void:
	var participant := _participants_mgr.by_name(participant_name)
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
		_receive_game_state.rpc_id(multiplayer.get_remote_sender_id(), _codec.build_state())


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_game_state(state: Dictionary) -> void:
	_codec.apply_state(state)


