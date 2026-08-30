class_name NetGateway
extends RefCounted

## System から試合のネット入口（通知・アクション送信・ミサイル）へアクセスする窓口。
## @rpc 本体は peer 間で NodePath を一致させる必要があるため match(main) 側に置く。
## System が main 全体へ依存しないよう、その呼び出しだけをここに集約して注入する。

var _match: Node


func setup(match_node: Node) -> void:
	_match = match_node


func notify(participant: Node3D, message: String) -> void:
	_match.notify_participant(participant, message)


func notify_exchange_complete(participant: Node3D) -> void:
	_match.notify_exchange_complete(participant)


func show_change_preview(participant: Node3D, before_card: Dictionary, after_card: Dictionary) -> void:
	_match._show_change_preview_for_participant(participant, before_card, after_card)


func broadcast_game_finished(network_standings: Dictionary) -> void:
	_match.broadcast_game_finished(network_standings)


func launch_missile(shooter: Node3D, target: Node3D) -> void:
	_match._launch_missile(shooter, target)


func report_missile_hit(target: Node3D) -> void:
	_match.on_missile_hit(target)


func request_action(action: String, value: int = 0, target_name: String = "") -> void:
	_match.request_action_remote(action, value, target_name)


func request_exchange(station_index: int, card_index: int) -> void:
	_match.request_exchange_remote(station_index, card_index)
