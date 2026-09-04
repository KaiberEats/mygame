class_name CooldownComponent
extends Node

## 参加者の kill / 能力 クールダウン（この時刻まで使用不可）を保持する。

var kill_until: float = 0.0
var ability_until: float = 0.0


func kill_left(now: float) -> float:
	return maxf(kill_until - now, 0.0)


func ability_left(now: float) -> float:
	return maxf(ability_until - now, 0.0)
