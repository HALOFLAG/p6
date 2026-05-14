class_name Strike
extends RefCounted

## 本擊 — 玩家在單場戰鬥中組成的卡牌集合。
## 對應 遊戲核心系統機制.md §1。
## M1 擴充:placed_cards 與 locked_cards 分開追蹤,支援個別 lock。

var placed_cards: Array[CardDefinition] = []  ## Place 階段,可移除
var locked_cards: Array[CardDefinition] = []  ## 已 Lock,不可撤回


func place(card: CardDefinition) -> bool:
	placed_cards.append(card)
	return true


func unplace_at(index: int) -> CardDefinition:
	if index < 0 or index >= placed_cards.size():
		return null
	var card := placed_cards[index]
	placed_cards.remove_at(index)
	return card


## 鎖定 placed_cards 中指定索引的卡片 → 移到 locked_cards。
func lock_at(index: int) -> CardDefinition:
	if index < 0 or index >= placed_cards.size():
		return null
	var card := placed_cards[index]
	placed_cards.remove_at(index)
	locked_cards.append(card)
	return card


func size() -> int:
	return placed_cards.size() + locked_cards.size()


func clear() -> void:
	placed_cards.clear()
	locked_cards.clear()


## 結束本擊時呼叫:把所有剩餘 placed 移到 locked。
func finalize_lock_all() -> Array[CardDefinition]:
	var newly_locked: Array[CardDefinition] = []
	for c in placed_cards:
		locked_cards.append(c)
		newly_locked.append(c)
	placed_cards.clear()
	return newly_locked


## 計算本擊的類型次數總和。
func get_type_counts() -> Dictionary:
	var counts: Dictionary = {}
	var all_cards := locked_cards + placed_cards
	for c in all_cards:
		for type_key in c.contribution:
			var val: int = c.contribution[type_key]
			counts[type_key] = counts.get(type_key, 0) + val
	return counts


## 計算混合任意路徑的張數(=所有有貢獻的卡的總張數)。
## 情報卡(contribution 為空)不計入。
func get_mixed_count() -> int:
	var total := 0
	var all_cards := locked_cards + placed_cards
	for c in all_cards:
		if not c.contribution.is_empty():
			total += 1
	return total


## 是否還有 required 類卡尚未 lock(用於決定「結束本擊」是否可用)。
func has_unlocked_required_cards() -> bool:
	for c in placed_cards:
		if c.lock_class == "required":
			return true
	return false
