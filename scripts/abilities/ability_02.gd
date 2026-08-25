class_name Ability02
extends Ability

## rank2: ミサイルを付与。強化時は所持時間延長＋2発。

func apply(ctx: AbilityContext) -> void:
	ctx.game.grant_item(ctx.caster, "MISSILE", 20.0 if ctx.is_enhanced else 10.0)
	ctx.game._item(ctx.caster).data["charges"] = 2 if ctx.is_enhanced else 1
