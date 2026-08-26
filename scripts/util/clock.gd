class_name Clock
extends RefCounted

## 時限効果の期限判定に使う経過秒。各層はこれを参照する（main に _now を置かない）。
static func now() -> float:
	return Time.get_ticks_msec() / 1000.0
