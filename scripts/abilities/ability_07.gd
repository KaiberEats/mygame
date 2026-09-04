class_name Ability07
extends Ability

## rank7: 透明（強化時20秒/通常10秒）。

func apply(ctx: AbilityContext) -> void:
	ctx.effects["invisible_until"] = ctx.now + (20.0 if ctx.is_enhanced else 10.0)
	ctx.caster.set_invisible(true)
