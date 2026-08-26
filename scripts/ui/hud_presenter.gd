class_name HudPresenter
extends RefCounted

## HUD の Presenter（MVP）。状態（参加者コンポーネント等）を読み、描画専用の game_hud に反映する。
## game_hud にはロジックを置かず、View からの逆参照もしない。

var _game: Node
var _view: CanvasLayer


func _init(game: Node, view: CanvasLayer) -> void:
	_game = game
	_view = view


## 毎フレーム前半: 残り時間・スタン・情報・露出・状態枠。
func refresh_status() -> void:
	_view.set_time_left(_game._time_left)
	_view.set_stun_status(_game.player.get_stun_time_left(), _game.STUN_SECONDS)
	_update_information()
	_update_exposure()
	_update_edge_status()


## 毎フレーム後半（対象確定後）: kill/change 可否・クールダウン。
func refresh_actions() -> void:
	_view.set_kill_available(_game._player_kill_target != null)
	_view.set_change_available(_game._player_change_target != null or _game._player_exchange_target != null)
	_view.set_kill_cooldown(_game._get_kill_cooldown_left(_game.player), _game.KILL_COOLDOWN_SECONDS)
	_view.set_ability_cooldown(_game._get_ability_cooldown_left(_game.player), _game.ABILITY_COOLDOWN_SECONDS)


func _update_information() -> void:
	var revealed_positions: Array[Vector3] = []
	var empty_cards: Array[Dictionary] = []
	var reveal_data: Dictionary = _game._vision(_game.player).map_reveal
	var revealed: Dictionary = reveal_data.get("positions", {})
	for revealed_position in revealed.values():
		revealed_positions.append(revealed_position)
	_view.set_minimap_data(_game.player.global_position, revealed_positions)

	if _game._vision(_game.player).card_view.is_empty():
		_view.set_viewed_hand("", empty_cards)
		return
	var view_data: Dictionary = _game._vision(_game.player).card_view
	if view_data.has("targets"):
		var names: Array[String] = []
		var cards: Array[Dictionary] = []
		for viewed_target in view_data["targets"]:
			if is_instance_valid(viewed_target):
				names.append(_game._participant_name(viewed_target))
				cards.append_array(viewed_target.hand)
		_view.set_viewed_hand(" / ".join(names), cards)
		return
	var target: Node3D = view_data.get("target")
	if not is_instance_valid(target):
		_game._vision(_game.player).card_view = {}
		_view.set_viewed_hand("", empty_cards)
		return
	_view.set_viewed_hand(_game._participant_name(target), target.hand)


func _update_exposure() -> void:
	_view.set_exposure_status(_game._is_location_revealed(_game.player), _game._is_hand_being_viewed(_game.player))


func _update_edge_status() -> void:
	var effects: Dictionary = _game._status(_game.player).data
	_view.set_edge_status_effects(
		_game.player.has_joker(),
		float(effects.get("invincible_until", 0.0)) > _game._now(),
		int(effects.get("barrier_charges", 0)) > 0
	)
