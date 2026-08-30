class_name Ability11
extends Ability

## rank11: 他参加者の位置をマップ表示（強化時20秒/通常10秒）。

func apply(ctx: AbilityContext) -> void:
	var positions: Dictionary = {}
	for target in ctx.game._participants:
		if target != ctx.caster:
			positions[target] = target.global_position
	ctx.ctx.caster.vision().map_reveal = {
		"positions": positions,
		"until": ctx.now + (20.0 if ctx.is_enhanced else 10.0),
	}
