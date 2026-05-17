extends Node

## 冒險手記 / 戰鬥紀錄資料層。
## 對應 戰鬥紀錄系統設計.md §6 + 程式規格書.md §3.7。
##
## 設計合約:
## - 跟 SaveSystem 獨立(存檔回滾不影響紀錄)
## - 失敗紀錄永久保留,即使重新挑戰成功也不抹除(append-only)
## - 唯一清除方式:clear_all()(僅供 [DEV] 重置使用)

const SAVE_PATH := "user://battle_records.json"
## v2(2026-05-16,ADR-0003):BattleRecord 內嵌 StrikeResult(原 6 個結算欄位移進 record.result)。
## v3(2026-05-17,ADR-0006):BattleRecord / PrepNodeRecord 加 campaign_attempt 欄位。
## 舊 disk file 版本不符 → 自動清檔 + push_warning。
const VERSION := 3

var battles: Array[BattleRecord] = []
var prep_nodes: Array[PrepNodeRecord] = []

## 索引(載入 / 寫入時重建)
var _battles_by_enemy_template: Dictionary = {}   ## { enemy_template_id: Array[int] }
var _last_failure_by_enemy: Dictionary = {}       ## { enemy_template_id: int(index) }
var _battles_by_campaign: Dictionary = {}         ## { campaign_id: Array[int] }


func _ready() -> void:
	_load_from_disk()


# ============ 對外 API ============

## 存一筆戰鬥紀錄,自動更新索引並寫入磁碟。
func save_battle(rec: BattleRecord) -> void:
	battles.append(rec)
	_update_indices_for_battle(battles.size() - 1, rec)
	_save_to_disk()


## 存一筆整備節點紀錄。
func save_prep_node(rec: PrepNodeRecord) -> void:
	prep_nodes.append(rec)
	_save_to_disk()


## 該模板敵人所有相關紀錄(供精英對戰前查閱 / 索引用)。
func query_battles_by_enemy(enemy_template_id: String) -> Array[BattleRecord]:
	var result: Array[BattleRecord] = []
	var indices: Array = _battles_by_enemy_template.get(enemy_template_id, [])
	for i in indices:
		result.append(battles[i])
	return result


## 該模板敵人最近一次的失敗紀錄(沒有則 null)。
func get_last_failure(enemy_template_id: String) -> BattleRecord:
	if not _last_failure_by_enemy.has(enemy_template_id):
		return null
	return battles[_last_failure_by_enemy[enemy_template_id]]


## 該戰役的所有戰鬥紀錄(地圖視圖用)。
## attempt: -1(預設)= 所有 attempt;指定 int = 只回該 attempt 的記錄(M5-S4 chip switcher 用)。
func get_battles_by_campaign(campaign_id: String, attempt: int = -1) -> Array[BattleRecord]:
	var result: Array[BattleRecord] = []
	var indices: Array = _battles_by_campaign.get(campaign_id, [])
	for i in indices:
		if attempt != -1 and battles[i].campaign_attempt != attempt:
			continue
		result.append(battles[i])
	return result


## 該戰役的所有整備節點紀錄。
## attempt: -1(預設)= 所有 attempt;指定 int = 只回該 attempt(M5-S4)。
func get_prep_nodes_by_campaign(campaign_id: String, attempt: int = -1) -> Array[PrepNodeRecord]:
	var result: Array[PrepNodeRecord] = []
	for r in prep_nodes:
		if r.campaign_id != campaign_id:
			continue
		if attempt != -1 and r.campaign_attempt != attempt:
			continue
		result.append(r)
	return result


## 該戰役中是否曾發生 GAME_OVER(供 SouvenirConditions / ADR-0005 用)。
## 跨 attempt 累計:由於 BattleRecord append-only 且跟 SaveSystem 獨立,
## 即使玩家「接受失敗」回 Hub 再重來戰役,先前 attempt 的 GAME_OVER 仍計入。
## 對應「失敗的疤痕永久保留」設計合約(戰鬥紀錄系統設計.md §6.5)。
## ADR-0006 維持此 Any-attempt 行為(不加 attempt 篩選),跟 ADR-0005 的 broken_bow 邏輯一致。
func had_game_over_in_campaign(campaign_id: String) -> bool:
	var indices: Array = _battles_by_campaign.get(campaign_id, [])
	for i in indices:
		if battles[i].failure_outcome == FailureHandler.FailureOutcome.GAME_OVER:
			return true
	return false


## 該戰役下一個 attempt 號(M5-S4 / ADR-0006)。
## 用法:m2_campaign._start_campaign 開頭呼叫,assign 進 current_campaign_attempt 並寫入後續 records。
## Derive 自現有 records max campaign_attempt + 1(無記錄 → 回 1)。
## 對應 ADR-0005「derive over store」原則 — GameState 不另存 counter。
func next_attempt_index_for(campaign_id: String) -> int:
	var max_idx: int = 0
	var indices: Array = _battles_by_campaign.get(campaign_id, [])
	for i in indices:
		if battles[i].campaign_attempt > max_idx:
			max_idx = battles[i].campaign_attempt
	return max_idx + 1


## 該戰役有 records 的 attempt 號集合(升序去重,M5-S4 / ADR-0006)。
## 用法:adventure_journal MapHeader chip switcher 動態 build chip。
## 無記錄 → 回空陣列(caller 顯示「(此戰役尚無紀錄)」)。
func get_attempts_for_campaign(campaign_id: String) -> Array[int]:
	var seen: Dictionary = {}
	var indices: Array = _battles_by_campaign.get(campaign_id, [])
	for i in indices:
		seen[battles[i].campaign_attempt] = true
	## 整備節點也算 attempt 痕跡(M5-S4 跑空紀錄連戰但有過整備不存在,但結構對稱)
	for r in prep_nodes:
		if r.campaign_id == campaign_id:
			seen[r.campaign_attempt] = true
	var result: Array[int] = []
	for k in seen.keys():
		result.append(int(k))
	result.sort()
	return result


## 全部清除 —— 僅供 [DEV] 重置 / 測試用。一般遊戲流程絕對不該呼叫。
func clear_all() -> void:
	battles.clear()
	prep_nodes.clear()
	_battles_by_enemy_template.clear()
	_last_failure_by_enemy.clear()
	_battles_by_campaign.clear()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ============ 內部:索引維護 + 磁碟 I/O ============

func _update_indices_for_battle(idx: int, rec: BattleRecord) -> void:
	if not _battles_by_enemy_template.has(rec.enemy_template_id):
		_battles_by_enemy_template[rec.enemy_template_id] = []
	(_battles_by_enemy_template[rec.enemy_template_id] as Array).append(idx)

	## ohk 經 ADR-0003 後位於 rec.result 內;result 可能為 null(理論不該發生,防爆)
	var is_ohk: bool = rec.result != null and rec.result.ohk
	if not is_ohk:
		_last_failure_by_enemy[rec.enemy_template_id] = idx

	if not _battles_by_campaign.has(rec.campaign_id):
		_battles_by_campaign[rec.campaign_id] = []
	(_battles_by_campaign[rec.campaign_id] as Array).append(idx)


func _save_to_disk() -> void:
	var battles_data: Array = []
	for r in battles:
		battles_data.append(r.to_dict())
	var prep_data: Array = []
	for r in prep_nodes:
		prep_data.append(r.to_dict())
	var data := {
		"version": VERSION,
		"battles": battles_data,
		"prep_nodes": prep_data,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("無法寫入戰鬥紀錄:" + SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()


func _load_from_disk() -> void:
	battles.clear()
	prep_nodes.clear()
	_battles_by_enemy_template.clear()
	_last_failure_by_enemy.clear()
	_battles_by_campaign.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("戰鬥紀錄 JSON 解析失敗")
		return
	var data: Dictionary = parsed
	## Schema version check(ADR-0003):version 不符 → 自動清檔。
	## v1→v2 是 BattleRecord 結算欄位重構,from_dict 形狀不相容。
	var disk_version: int = int(data.get("version", 0))
	if disk_version != VERSION:
		push_warning("戰鬥紀錄 schema 版本不相容(disk=%d, code=%d),已重置紀錄。" % [disk_version, VERSION])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	for d in data.get("battles", []):
		if d is Dictionary:
			battles.append(BattleRecord.from_dict(d))
	for d in data.get("prep_nodes", []):
		if d is Dictionary:
			prep_nodes.append(PrepNodeRecord.from_dict(d))
	for i in battles.size():
		_update_indices_for_battle(i, battles[i])
