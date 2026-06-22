class_name HandSorter
extends RefCounted


static func sort(cards: Array[Dictionary]) -> Array[Dictionary]:
	var sorted_cards: Array[Dictionary] = cards.duplicate()
	sorted_cards.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_rank: int = 99 if left.get("suit", "") == "joker" else int(left.get("rank", 0))
		var right_rank: int = 99 if right.get("suit", "") == "joker" else int(right.get("rank", 0))
		return left_rank < right_rank
	)

	var pair_cards: Array[Dictionary] = []
	var remaining_cards: Array[Dictionary] = []
	var jokers: Array[Dictionary] = []
	var cards_by_rank: Dictionary = {}

	for card in sorted_cards:
		if card.get("suit", "") == "joker":
			jokers.append(card)
			continue

		var rank: int = int(card.get("rank", 0))
		if not cards_by_rank.has(rank):
			cards_by_rank[rank] = []
		cards_by_rank[rank].append(card)

	for rank in range(1, 14):
		var ranked_cards: Array = cards_by_rank.get(rank, [])
		if ranked_cards.size() >= 2:
			pair_cards.append(ranked_cards[0])
			pair_cards.append(ranked_cards[1])
			for index in range(2, ranked_cards.size()):
				remaining_cards.append(ranked_cards[index])
		else:
			for card in ranked_cards:
				remaining_cards.append(card)

	pair_cards.append_array(remaining_cards)
	pair_cards.append_array(jokers)
	return pair_cards
