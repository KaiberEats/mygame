class_name Ability01
extends Ability

## rank1: 非joker手札を山札に戻して引き直す。強化時はペア寄せで引き直す。

func apply(ctx: AbilityContext) -> void:
	var kept_cards: Array[Dictionary] = []
	var returned_cards: Array[Dictionary] = []
	for card in ctx.caster.hand:
		if card.get("suit", "") == "joker":
			kept_cards.append(card)
		else:
			returned_cards.append(card)
	ctx.deck.return_cards(returned_cards)
	ctx.caster.set_hand(kept_cards)
	if ctx.is_enhanced:
		var missing_count: int = maxi(GameConfig.hand_size - kept_cards.size(), 0)
		var paired_cards: Array[Dictionary] = ctx.deck.draw_pair_focused_cards(missing_count)
		var enhanced_hand: Array[Dictionary] = kept_cards.duplicate()
		enhanced_hand.append_array(paired_cards)
		ctx.caster.set_hand(enhanced_hand, true)
