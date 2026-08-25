class_name Ability08
extends Ability

## rank8: コイン（強制チェンジ権）。強化時は所持時間延長＋2回。速度上昇。

func apply(ctx: AbilityContext) -> void:
	ctx.effects["coin_duration"] = 30.0 if ctx.is_enhanced else 20.0
	ctx.effects["coin_until"] = ctx.now + float(ctx.effects["coin_duration"])
	ctx.effects["coin_count"] = 2 if ctx.is_enhanced else 1
	ctx.game._refresh_speed_multiplier(ctx.caster)
	ctx.game._sync_player_item_slot()
