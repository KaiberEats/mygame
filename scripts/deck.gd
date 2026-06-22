extends Node

var _cards: Array[Dictionary] = []
var _total_cards := 53


func reset_and_shuffle(total_cards: int = 53) -> void:
	_total_cards = maxi(total_cards, 1)
	var full_deck := _create_full_deck()
	var joker: Dictionary = full_deck.pop_back()
	_cards = []
	while _cards.size() < _total_cards - 1:
		for card in full_deck:
			if _cards.size() >= _total_cards - 1:
				break
			_cards.append(card.duplicate())
	_cards.append(joker)
	_cards.shuffle()


func ensure_joker_in_next_draws(count: int) -> void:
	var draw_count := mini(count, _cards.size())
	if draw_count <= 0:
		return

	var joker_index := -1
	for index in _cards.size():
		if _cards[index].get("suit", "") == "joker":
			joker_index = index
			break

	var first_draw_index := _cards.size() - draw_count
	if joker_index >= first_draw_index:
		return

	var target_index := randi_range(first_draw_index, _cards.size() - 1)
	var replaced_card := _cards[target_index]
	_cards[target_index] = _cards[joker_index]
	_cards[joker_index] = replaced_card


func draw_cards(count: int) -> Array[Dictionary]:
	var drawn: Array[Dictionary] = []
	var draw_count := mini(count, _cards.size())

	for index in draw_count:
		drawn.append(_cards.pop_back())

	return drawn


func draw_pair_focused_cards(count: int) -> Array[Dictionary]:
	var drawn: Array[Dictionary] = []
	var draw_count := mini(count, _cards.size())
	var cards_by_rank: Dictionary = {}

	for card in _cards:
		var rank := int(card.get("rank", 0))
		if card.get("suit", "") == "joker":
			continue
		if not cards_by_rank.has(rank):
			cards_by_rank[rank] = []
		cards_by_rank[rank].append(card)

	var ranks: Array = cards_by_rank.keys()
	ranks.shuffle()
	for rank in ranks:
		var ranked_cards: Array = cards_by_rank[rank]
		while ranked_cards.size() >= 2 and drawn.size() + 2 <= draw_count:
			drawn.append(ranked_cards.pop_back())
			drawn.append(ranked_cards.pop_back())

	for card in drawn:
		_cards.erase(card)
	if drawn.size() < draw_count:
		drawn.append_array(draw_cards(draw_count - drawn.size()))

	return drawn


func return_cards(cards: Array[Dictionary]) -> void:
	_cards.append_array(cards)
	_cards.shuffle()


func remaining_count() -> int:
	return _cards.size()


func total_count() -> int:
	return _total_cards


func _create_full_deck() -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	var suits := [
		{"name": "spade", "mark": "♠", "color": Color.BLACK},
		{"name": "heart", "mark": "♥", "color": Color.RED},
		{"name": "diamond", "mark": "♦", "color": Color.RED},
		{"name": "club", "mark": "♣", "color": Color.BLACK},
	]

	for suit in suits:
		for rank in range(1, 14):
			deck.append({
				"suit": suit.name,
				"mark": suit.mark,
				"rank": rank,
				"label": str(rank),
				"color": suit.color,
			})

	deck.append({
		"suit": "joker",
		"mark": "JOKER",
		"rank": 0,
		"label": "J",
		"color": Color.BLACK,
	})

	return deck
