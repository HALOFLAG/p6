class_name DeckManager
extends RefCounted

## 卡組管理工具方法集。對應 程式規格書.md §3.1。


## 從戰役配置建立起手卡組。
static func build_starting_deck(starting_deck_dict: Dictionary) -> Array[DeckEntry]:
	var deck: Array[DeckEntry] = []
	for card_id in starting_deck_dict:
		var entry := DeckEntry.new()
		entry.card_id = card_id
		entry.count_remaining = starting_deck_dict[card_id]
		entry.count_consumed_total = 0
		deck.append(entry)
	return deck


## 對卡組做快照(供教學重來回滾使用)。
static func snapshot(deck: Array[DeckEntry]) -> Dictionary:
	var snap: Dictionary = {}
	for entry in deck:
		snap[entry.card_id] = entry.snapshot()
	return snap


## 還原卡組到快照狀態。
static func restore(deck: Array[DeckEntry], snap: Dictionary) -> void:
	for entry in deck:
		if snap.has(entry.card_id):
			entry.restore(snap[entry.card_id])


## 查找卡組中特定 card_id 的 entry。
static func find_entry(deck: Array[DeckEntry], card_id: String) -> DeckEntry:
	for entry in deck:
		if entry.card_id == card_id:
			return entry
	return null


## 補給:新增卡片到卡組中。若該 card_id 不存在,自動建立新 entry。
static func add_cards(deck: Array[DeckEntry], cards_to_add: Dictionary) -> void:
	for card_id in cards_to_add:
		var amount: int = cards_to_add[card_id]
		var entry := find_entry(deck, card_id)
		if entry == null:
			entry = DeckEntry.new()
			entry.card_id = card_id
			entry.count_remaining = 0
			entry.count_consumed_total = 0
			deck.append(entry)
		entry.add(amount)


## 還原卡組為起手規格(整備 1 完全補給用)。
static func restore_to_starting(deck: Array[DeckEntry], starting_deck_dict: Dictionary) -> void:
	for entry in deck:
		entry.count_remaining = starting_deck_dict.get(entry.card_id, 0)


## 卡組總張數(供 UI 顯示用)。
static func total_count(deck: Array[DeckEntry]) -> int:
	var n := 0
	for entry in deck:
		n += entry.count_remaining
	return n
