class_name SupplyHandler
extends RefCounted

## 整備補給處理。對應 程式規格書.md §3.14。


## 套用補給規格。
## 回傳:套用結果摘要(供 UI / 紀錄使用)。
static func apply(phase: SupplyPhase, deck: Array[DeckEntry], starting_deck_dict: Dictionary) -> Dictionary:
	var summary := {
		"phase_id": phase.id,
		"supply_type": phase.supply_type,
		"narrative": phase.narrative,
		"changes": {},
	}
	match phase.supply_type:
		"full_restore":
			var before := DeckManager.snapshot(deck)
			DeckManager.restore_to_starting(deck, starting_deck_dict)
			summary["changes"] = _diff(before, deck)
		"add_cards":
			var before := DeckManager.snapshot(deck)
			DeckManager.add_cards(deck, phase.cards_to_add)
			summary["changes"] = _diff(before, deck)
		_:
			push_warning("未知的 supply_type:" + phase.supply_type)
	EventBus.emit_signal("supply_applied", phase.id)
	return summary


static func _diff(before_snap: Dictionary, after_deck: Array[DeckEntry]) -> Dictionary:
	var d: Dictionary = {}
	for entry in after_deck:
		var before_remain: int = 0
		if before_snap.has(entry.card_id):
			before_remain = before_snap[entry.card_id].get("count_remaining", 0)
		var delta := entry.count_remaining - before_remain
		if delta != 0:
			d[entry.card_id] = delta
	return d
