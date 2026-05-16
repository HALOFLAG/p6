extends Node

## 冒險手記 / 戰鬥紀錄資料層。
## 對應 戰鬥紀錄系統設計.md §6 + 程式規格書.md §3.7。
##
## 設計合約:
## - 跟 SaveSystem 獨立(存檔回滾不影響紀錄)
## - 失敗紀錄永久保留,即使重新挑戰成功也不抹除(append-only)
## - 唯一清除方式:clear_all()(僅供 [DEV] 重置使用)

const SAVE_PATH := "user://battle_records.json"
const VERSION := 1

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
func get_battles_by_campaign(campaign_id: String) -> Array[BattleRecord]:
	var result: Array[BattleRecord] = []
	var indices: Array = _battles_by_campaign.get(campaign_id, [])
	for i in indices:
		result.append(battles[i])
	return result


## 該戰役的所有整備節點紀錄。
func get_prep_nodes_by_campaign(campaign_id: String) -> Array[PrepNodeRecord]:
	var result: Array[PrepNodeRecord] = []
	for r in prep_nodes:
		if r.campaign_id == campaign_id:
			result.append(r)
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

	if not rec.ohk:
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
	for d in data.get("battles", []):
		if d is Dictionary:
			battles.append(BattleRecord.from_dict(d))
	for d in data.get("prep_nodes", []):
		if d is Dictionary:
			prep_nodes.append(PrepNodeRecord.from_dict(d))
	for i in battles.size():
		_update_indices_for_battle(i, battles[i])
