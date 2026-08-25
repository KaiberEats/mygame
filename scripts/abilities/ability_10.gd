class_name Ability10
extends Ability

## rank10: 非jokerカードを複製（強化時2枚/通常1枚）。

func apply(ctx: AbilityContext) -> void:
	var copies_left := 2 if ctx.is_enhanced else 1
	var source_hand: Array[Dictionary] = ctx.caster.hand.duplicate()
	for card in source_hand:
		if card.get("suit", "") != "joker" and copies_left > 0:
			ctx.caster.add_card(card.duplicate())
			copies_left -= 1
