class_name StatusComponent
extends Node

## 参加者の時限効果状態（無敵/バリア/透明/鎌/coin/counter 等）を保持する。
## データは時刻ベースのキー（例: "invincible_until"）を持つ Dictionary。
## 移行中は main / System が data を参照で読み書きする。

var data: Dictionary = {}


## 時刻キー（*_until）が now を超えているか。
func is_active(key: String, now: float) -> bool:
	return float(data.get(key, 0.0)) > now
