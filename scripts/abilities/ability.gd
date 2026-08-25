class_name Ability
extends RefCounted

## ペア能力1種の基底。rank ごとに派生し apply() で効果を適用する。
## 新しい能力を足すときは Ability を継承したファイルを作り AbilitySystem に登録する。

func apply(_ctx: AbilityContext) -> void:
	pass
