class_name DeckEntry
extends Resource

## 卡組中某類卡的動態狀態。
## 2026-05-14 新增:一張卡 = 一次使用,該類卡組張數 = count_remaining。

@export var card_id: String = ""
@export var count_remaining: int = 0
@export var count_consumed_total: int = 0


func consume(amount: int = 1) -> bool:
	if count_remaining < amount:
		return false
	count_remaining -= amount
	count_consumed_total += amount
	return true


func add(amount: int) -> void:
	count_remaining += amount


func snapshot() -> Dictionary:
	return {
		"card_id": card_id,
		"count_remaining": count_remaining,
		"count_consumed_total": count_consumed_total,
	}


func restore(snap: Dictionary) -> void:
	count_remaining = snap.get("count_remaining", 0)
	count_consumed_total = snap.get("count_consumed_total", 0)
