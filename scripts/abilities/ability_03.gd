class_name Ability03
extends Ability

## rank3: 無敵（強化時10秒/通常5秒）。金アウトライン表示。

func apply(ctx: AbilityContext) -> void:
	ctx.effects["invincible_until"] = ctx.now + (10.0 if ctx.is_enhanced else 5.0)
	ctx.caster.set_gold_outline(true)
