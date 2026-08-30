class_name Ability13
extends Ability

## rank13: 強化時はソードを付与、通常は「次の能力を強化」する。

func apply(ctx: AbilityContext) -> void:
	if ctx.is_enhanced:
		ctx.item_system.grant(ctx.caster, "SWORD")
	else:
		ctx.effects["enhance_next_ability"] = true
