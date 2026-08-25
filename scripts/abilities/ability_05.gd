class_name Ability05
extends Ability

## rank5: 相手の手札を覗く（15秒）。強化時は全員、通常は最も近い相手。

func apply(ctx: AbilityContext) -> void:
	if ctx.is_enhanced:
		var targets: Array[Node3D] = []
		for target in ctx.game._participants:
			if target != ctx.caster:
				targets.append(target)
		ctx.game._vision(ctx.caster).card_view = {"targets": targets, "until": ctx.now + 15.0}
	else:
		var nearest: Node3D = ctx.game._find_nearest_participant(ctx.caster)
		if nearest != null:
			ctx.game._vision(ctx.caster).card_view = {"target": nearest, "until": ctx.now + 15.0}
