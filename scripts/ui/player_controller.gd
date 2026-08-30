class_name PlayerController
extends Node

## ローカルプレイヤーの入力受付とメニュー(ポーズ/設定/チュートリアル)制御。
## 入力→行動要求(request_local_action)への変換もここが担う。状態/RPCは _game 経由。

var _game: Node


func setup(game: Node) -> void:
	_game = game


func _unhandled_input(event: InputEvent) -> void:
	if _game._game_ending:
		return

	if event.is_action_pressed("ui_cancel"):
		if _game.pause_menu.visible or _game.settings_menu.visible:
			resume_game()
		else:
			show_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if get_tree().paused or is_local_ui_blocking_gameplay():
		return

	if event.is_action_pressed("hand_editor"):
		set_hand_editor_open(not _game.game_hud.is_hand_editor_open())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_item"):
		request_use_button_action()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var pair_slot: int = _game._ability.get_pair_slot_from_event(event)
		if pair_slot >= 0:
			request_local_action("pair", pair_slot)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not _game.game_hud.is_hand_editor_open() and _game._player_kill_target != null:
			request_local_action("kill", 0, _game._player_kill_target.name)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _game.game_hud.is_hand_editor_open() and _game._player_change_target != null:
			request_local_action("change", 0, _game._player_change_target.name)
			get_viewport().set_input_as_handled()


func show_pause_menu() -> void:
	_game.game_hud.close_hand_editor()
	get_tree().paused = should_pause_game()
	set_local_player_input_enabled(false)
	_game.settings_menu.hide()
	_game.pause_menu.show()
	_game.game_hud.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func show_settings_menu() -> void:
	_game.game_hud.close_hand_editor()
	get_tree().paused = should_pause_game()
	set_local_player_input_enabled(false)
	_game.pause_menu.hide()
	_game.settings_menu.show()
	_game.game_hud.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func resume_game() -> void:
	_game.game_hud.close_hand_editor()
	_game.pause_menu.hide()
	_game.settings_menu.hide()
	_game.game_hud.show()
	get_tree().paused = false
	set_local_player_input_enabled(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func show_tutorial() -> void:
	if _game._tutorial_overlay != null and is_instance_valid(_game._tutorial_overlay):
		return
	_game.game_hud.close_hand_editor()
	_game.pause_menu.hide()
	_game.settings_menu.hide()
	get_tree().paused = should_pause_game()
	set_local_player_input_enabled(false)
	_game._tutorial_overlay = _game.TUTORIAL_SCENE.instantiate()
	_game._tutorial_overlay.set_meta("overlay", true)
	_game._tutorial_overlay.tree_exited.connect(func() -> void:
		_game._tutorial_overlay = null
		if not _game._game_ending and get_tree().current_scene == _game:
			show_pause_menu()
	)
	_game.game_hud.add_child(_game._tutorial_overlay)


func force_return_to_waiting_room() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	NetworkManager.return_to_waiting_room()


func should_pause_game() -> bool:
	return not NetworkManager.is_online


func is_local_ui_blocking_gameplay() -> bool:
	return _game.pause_menu.visible or _game.settings_menu.visible or (_game._tutorial_overlay != null and is_instance_valid(_game._tutorial_overlay))


func set_local_player_input_enabled(is_enabled: bool) -> void:
	if _game.player != null and _game.player.has_method("set_input_enabled"):
		_game.player.set_input_enabled(is_enabled)


func set_hand_editor_open(is_open: bool) -> void:
	if is_open:
		_game.game_hud.open_hand_editor(_game.player.hand)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_game.game_hud.close_hand_editor()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func request_use_button_action() -> void:
	var scythe_target: Node3D = _game._combat.find_scythe_target(_game.player)
	var player_effects: Dictionary = _game.player.status().data
	if _game._status_system.has_ready_scythe(_game.player) and (scythe_target != null or bool(player_effects.get("scythe_enhanced", false))):
		var target_name := ""
		if scythe_target != null:
			target_name = scythe_target.name
		request_local_action("scythe", 0, target_name)
		return
	var coin_target: Node3D = _game._combat.find_coin_change_target(_game.player)
	if coin_target != null:
		request_local_action("coin", 0, coin_target.name)
		return
	request_local_action("item")


func request_local_action(action: String, value: int = 0, target_name: String = "") -> void:
	if _game._net.is_game_authority():
		_game._net.execute_player_action(_game.player, action, value, target_name)
	else:
		_game.request_action_remote(action, value, target_name)
