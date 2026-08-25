class_name Ability06
extends Ability

## rank6: 状態回復。強化時は一定時間の自動回復、通常は即時回復。

func apply(ctx: AbilityContext) -> void:
	if ctx.is_enhanced:
		ctx.effects["auto_cleanse_until"] = ctx.now + 30.0
		ctx.effects.erase("auto_cleanse_at")
	else:
		ctx.game._clear_negative_statuses(ctx.caster)
