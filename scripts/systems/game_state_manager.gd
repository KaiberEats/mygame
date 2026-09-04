class_name GameStateManager
extends Node

## 試合の進行状態を所有する。残り時間・終了フラグ・ネット送信タイマー。
## 各層はここを読み書きする（状態を main に散らさない）。

var time_left: float = 0.0
var is_ending: bool = false
var network_snapshot_time_left: float = 0.0
