class_name HudPresenter
extends RefCounted

## HUD の Presenter（MVP）。状態（参加者コンポーネント等）を読み、描画専用の game_hud に反映する。
## game_hud にはロジックを置かず、View からの逆参照もしない。

var _view: CanvasLayer
var _participants: Participants
var _game_state: GameStateManager
var _status_system: StatusSystem
var _controls: PlayerController


func _init(view: CanvasLayer, participants: Participants, game_state: GameStateManager,
		status_system: StatusSystem, controls: PlayerController) -> void:
	_view = view
	_participants = participants
	_game_state = game_state
	_status_system = status_system
	_controls = controls


## 毎フレーム前半: 残り時間・スタン・情報・露出・状態枠。
func refresh_status() -> void:
	_view.set_time_left(_game_state.time_left)
	_view.set_stun_status(_participants.local_player.get_stun_time_left(), GameConfig.STUN_SECONDS)
	_update_information()
	_update_exposure()
	_update_edge_status()


## 毎フレーム後半（対象確定後）: kill/change 可否・クールダウン。
func refresh_actions() -> void:
	var local_player := _participants.local_player
	_view.set_kill_available(_controls.kill_target != null)
	_view.set_change_available(_controls.change_target != null or _controls.exchange_target != null)
	_view.set_kill_cooldown(local_player.cooldown().kill_left(Clock.now()), GameConfig.KILL_COOLDOWN_SECONDS)
	_view.set_ability_cooldown(local_player.cooldown().ability_left(Clock.now()), GameConfig.ABILITY_COOLDOWN_SECONDS)


func _update_information() -> void:
	var local_player := _participants.local_player
	var revealed_positions: Array[Vector3] = []
	var empty_cards: Array[Dictionary] = []
	var reveal_data: Dictionary = local_player.vision().map_reveal
	var revealed: Dictionary = reveal_data.get("positions", {})
	for revealed_position in revealed.values():
		revealed_positions.append(revealed_position)
	_view.set_minimap_data(local_player.global_position, revealed_positions)

	if local_player.vision().card_view.is_empty():
		_view.set_viewed_hand("", empty_cards)
		return
	var view_data: Dictionary = local_player.vision().card_view
	if view_data.has("targets"):
		var names: Array[String] = []
		var cards: Array[Dictionary] = []
		for viewed_target in view_data["targets"]:
			if is_instance_valid(viewed_target):
				names.append(viewed_target.get_display_name())
				cards.append_array(viewed_target.hand)
		_view.set_viewed_hand(" / ".join(names), cards)
		return
	var target: Node3D = view_data.get("target")
	if not is_instance_valid(target):
		local_player.vision().card_view = {}
		_view.set_viewed_hand("", empty_cards)
		return
	_view.set_viewed_hand(target.get_display_name(), target.hand)


func _update_exposure() -> void:
	var local_player := _participants.local_player
	_view.set_exposure_status(_status_system.is_location_revealed(local_player), _status_system.is_hand_being_viewed(local_player))


func _update_edge_status() -> void:
	var local_player := _participants.local_player
	var effects: Dictionary = local_player.status().data
	_view.set_edge_status_effects(
		local_player.has_joker(),
		float(effects.get("invincible_until", 0.0)) > Clock.now(),
		int(effects.get("barrier_charges", 0)) > 0
	)
