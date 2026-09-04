class_name Ability05
extends Ability

## rank5: 相手の手札を覗く（15秒）。強化時は全員、通常は最も近い相手。

func apply(ctx: AbilityContext) -> void:
	if ctx.is_enhanced:
		var targets: Array[Node3D] = []
		for target in ctx.participants.all:
			if target != ctx.caster:
				targets.append(target)
		ctx.caster.vision().card_view = {"targets": targets, "until": ctx.now + 15.0}
	else:
		var nearest: Node3D = ctx.participants.nearest(ctx.caster)
		if nearest != null:
			ctx.caster.vision().card_view = {"target": nearest, "until": ctx.now + 15.0}
