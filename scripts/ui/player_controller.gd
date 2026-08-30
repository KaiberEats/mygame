class_name PlayerController
extends Node

## ローカルプレイヤーの入力受付とメニュー(ポーズ/設定/チュートリアル)制御。
## 入力→行動要求(request_local_action)への変換もここが担う。ローカルの照準対象も本 Node が所有する。

const TUTORIAL_SCENE := preload("res://scenes/ui/Tutorial.tscn")

var kill_target: Node3D = null
var change_target: Node3D = null
var exchange_target: StaticBody3D = null

var _participants: Participants
var _ability: AbilitySystem
var _combat: CombatSystem
var _status_system: StatusSystem
var _net: NetSync
var _net_gateway: NetGateway
var _game_state: GameStateManager
var _game_hud: CanvasLayer
var _pause_menu: CanvasLayer
var _settings_menu: Control
var _world: Node
var _tutorial_overlay: Control = null


func setup(participants: Participants, ability: AbilitySystem, combat: CombatSystem,
		status_system: StatusSystem, net: NetSync, net_gateway: NetGateway, game_state: GameStateManager,
		game_hud: CanvasLayer, pause_menu: CanvasLayer, settings_menu: Control, world: Node) -> void:
	_participants = participants
	_ability = ability
	_combat = combat
	_status_system = status_system
	_net = net
	_net_gateway = net_gateway
	_game_state = game_state
	_game_hud = game_hud
	_pause_menu = pause_menu
	_settings_menu = settings_menu
	_world = world


func _unhandled_input(event: InputEvent) -> void:
	if _game_state.is_ending:
		return

	if event.is_action_pressed("ui_cancel"):
		if _pause_menu.visible or _settings_menu.visible:
			resume_game()
		else:
			show_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if get_tree().paused or is_local_ui_blocking_gameplay():
		return

	if event.is_action_pressed("hand_editor"):
		set_hand_editor_open(not _game_hud.is_hand_editor_open())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_item"):
		request_use_button_action()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var pair_slot: int = _ability.get_pair_slot_from_event(event)
		if pair_slot >= 0:
			request_local_action("pair", pair_slot)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not _game_hud.is_hand_editor_open() and kill_target != null:
			request_local_action("kill", 0, kill_target.name)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _game_hud.is_hand_editor_open() and change_target != null:
			request_local_action("change", 0, change_target.name)
			get_viewport().set_input_as_handled()


func show_pause_menu() -> void:
	_game_hud.close_hand_editor()
	get_tree().paused = should_pause_game()
	set_local_player_input_enabled(false)
	_settings_menu.hide()
	_pause_menu.show()
	_game_hud.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func show_settings_menu() -> void:
	_game_hud.close_hand_editor()
	get_tree().paused = should_pause_game()
	set_local_player_input_enabled(false)
	_pause_menu.hide()
	_settings_menu.show()
	_game_hud.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func resume_game() -> void:
	_game_hud.close_hand_editor()
	_pause_menu.hide()
	_settings_menu.hide()
	_game_hud.show()
	get_tree().paused = false
	set_local_player_input_enabled(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func show_tutorial() -> void:
	if _tutorial_overlay != null and is_instance_valid(_tutorial_overlay):
		return
	_game_hud.close_hand_editor()
	_pause_menu.hide()
	_settings_menu.hide()
	get_tree().paused = should_pause_game()
	set_local_player_input_enabled(false)
	_tutorial_overlay = TUTORIAL_SCENE.instantiate()
	_tutorial_overlay.set_meta("overlay", true)
	_tutorial_overlay.tree_exited.connect(func() -> void:
		_tutorial_overlay = null
		if not _game_state.is_ending and get_tree().current_scene == _world:
			show_pause_menu()
	)
	_game_hud.add_child(_tutorial_overlay)


func force_return_to_waiting_room() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	NetworkManager.return_to_waiting_room()


func should_pause_game() -> bool:
	return not NetworkManager.is_online


func is_local_ui_blocking_gameplay() -> bool:
	return _pause_menu.visible or _settings_menu.visible or (_tutorial_overlay != null and is_instance_valid(_tutorial_overlay))


func set_local_player_input_enabled(is_enabled: bool) -> void:
	var local_player := _participants.local_player
	if local_player != null and local_player.has_method("set_input_enabled"):
		local_player.set_input_enabled(is_enabled)


func set_hand_editor_open(is_open: bool) -> void:
	if is_open:
		_game_hud.open_hand_editor(_participants.local_player.hand)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_game_hud.close_hand_editor()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func request_use_button_action() -> void:
	var local_player := _participants.local_player
	var scythe_target: Node3D = _combat.find_scythe_target(local_player)
	var player_effects: Dictionary = local_player.status().data
	if _status_system.has_ready_scythe(local_player) and (scythe_target != null or bool(player_effects.get("scythe_enhanced", false))):
		var target_name := ""
		if scythe_target != null:
			target_name = scythe_target.name
		request_local_action("scythe", 0, target_name)
		return
	var coin_target: Node3D = _combat.find_coin_change_target(local_player)
	if coin_target != null:
		request_local_action("coin", 0, coin_target.name)
		return
	request_local_action("item")


func request_local_action(action: String, value: int = 0, target_name: String = "") -> void:
	if _net.is_game_authority():
		_net.execute_player_action(_participants.local_player, action, value, target_name)
	else:
		_net_gateway.request_action(action, value, target_name)
