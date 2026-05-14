class_name BattleEngine
extends RefCounted

## 戰鬥引擎 — 管理 Place/Lock 狀態 + 結算 + 卡組消耗 + 揭露資訊。
## 對應 遊戲核心系統機制.md §1。
## M1:支援 Place + 動態 Lock(none/optional)+ 結算 + 揭露追蹤。
## 不支援(待 M2+):required lock、flexible 分配、戰鬥狀態變體、追擊。

enum Phase { PLACE, RESOLVED }

## 2026-05-14 暫時停用本擊上限(便於 M1 測試混合路徑)。M2 或後續可重新啟用。
const STRIKE_LIMIT_ENABLED := false

var phase: int = Phase.PLACE
var strike: Strike
var enemy_instance: EnemyInstance
var enemy_template: EnemyTemplate
var deck: Array[DeckEntry] = []  ## 當前卡組(共享參考)
var card_library: Dictionary = {}  ## { card_id: CardDefinition }
var result: Dictionary = {}

## 揭露資訊。M1 用單一敵人;M2+ 擴展為連戰範圍。
## { "enemy_weakness_type": "pierce", "enemy_class_revealed": true, ... }
var revealed_info: Dictionary = {}


func _init(enemy: EnemyInstance, template: EnemyTemplate, deck_ref: Array[DeckEntry], lib: Dictionary) -> void:
	enemy_instance = enemy
	enemy_template = template
	deck = deck_ref
	card_library = lib
	strike = Strike.new()


## ====================
##  Place 階段
## ====================

func place_card(card_id: String) -> bool:
	if phase != Phase.PLACE:
		return false
	if STRIKE_LIMIT_ENABLED and strike.size() >= enemy_instance.strike_limit:
		return false
	var entry := _find_entry(card_id)
	if entry == null:
		return false
	## Place 階段不消耗,但要追蹤「已 place + locked 的張數」不能超過卡組張數
	var in_strike_of_this_card := _count_in_strike(card_id)
	if in_strike_of_this_card >= entry.count_remaining:
		return false
	var card_def: CardDefinition = card_library.get(card_id, null)
	if card_def == null:
		return false
	strike.place(card_def)
	EventBus.emit_card_placed(card_id)
	return true


func unplace_card_at(index: int) -> bool:
	if phase != Phase.PLACE:
		return false
	var removed := strike.unplace_at(index)
	return removed != null


## 便利方法:依 card_id 反置最後一張該類卡。
func unplace_card(card_id: String) -> bool:
	if phase != Phase.PLACE:
		return false
	for i in range(strike.placed_cards.size() - 1, -1, -1):
		if strike.placed_cards[i].id == card_id:
			return unplace_card_at(i)
	return false


## 鎖定 placed_cards 中指定索引的卡 → 立即觸發 spec_locked 效果(若有)。
func lock_card_at(index: int) -> bool:
	if phase != Phase.PLACE:
		return false
	if index < 0 or index >= strike.placed_cards.size():
		return false
	var card := strike.placed_cards[index]
	if card.lock_class == "none":
		## none 卡 lock 與否無差;為求一致允許 lock,但不觸發特效
		strike.lock_at(index)
		return true
	## optional / required:觸發 spec_locked
	strike.lock_at(index)
	_apply_special_effect(card, true)
	return true


## ====================
##  結束本擊 + 結算
## ====================

func commit_strike() -> Dictionary:
	if phase != Phase.PLACE:
		return result
	if strike.has_unlocked_required_cards():
		return {}  ## required 卡未 lock,不允許 commit
	## 對剩餘 placed 的 optional 卡觸發 spec_unlocked
	for card in strike.placed_cards:
		if card.lock_class == "optional":
			_apply_special_effect(card, false)
	## 全部 lock
	strike.finalize_lock_all()
	## 消耗卡組
	for c in strike.locked_cards:
		var entry := _find_entry(c.id)
		if entry != null:
			entry.consume(1)
	## 結算
	result = Resolution.resolve(strike, enemy_instance)
	result["revealed_info"] = revealed_info.duplicate()
	phase = Phase.RESOLVED
	EventBus.emit_strike_committed()
	EventBus.emit_resolution_complete(result)
	return result


## ====================
##  揭露機制
## ====================

func _apply_special_effect(card: CardDefinition, is_locked_mode: bool) -> void:
	var spec_key := "spec_locked" if is_locked_mode else "spec_unlocked"
	var spec: Dictionary = card.special_effect.get(spec_key, {})
	if spec.is_empty():
		return
	var action: String = spec.get("action", "")
	match action:
		"reveal_weakness_type":
			## 揭露當前敵人弱點類型(深度)
			revealed_info["enemy_weakness_types"] = enemy_template.weakness_range.duplicate()
			revealed_info["weakness_reveal_mode"] = "depth"
		"reveal_remaining_weakness_types":
			## 揭露此連戰所有剩餘敵人弱點類型(廣度)
			## M1 單一敵人 = 同一結果,但標記為廣度模式
			revealed_info["enemy_weakness_types"] = enemy_template.weakness_range.duplicate()
			revealed_info["weakness_reveal_mode"] = "breadth"
		"reveal_full_requirements":
			revealed_info["full_requirements"] = enemy_instance.requirements.duplicate()
		"reveal_enemy_class":
			revealed_info["enemy_class"] = enemy_template.enemy_class
		_:
			pass  ## 未實作的 action 暫忽略


## ====================
##  輔助查詢
## ====================

func _find_entry(card_id: String) -> DeckEntry:
	for e in deck:
		if e.card_id == card_id:
			return e
	return null


func _count_in_strike(card_id: String) -> int:
	var n := 0
	for c in strike.placed_cards:
		if c.id == card_id:
			n += 1
	for c in strike.locked_cards:
		if c.id == card_id:
			n += 1
	return n


func can_commit() -> bool:
	if phase != Phase.PLACE:
		return false
	if strike.size() == 0:
		return false
	if strike.has_unlocked_required_cards():
		return false
	return true
