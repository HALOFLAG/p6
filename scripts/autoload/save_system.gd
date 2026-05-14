extends Node

## 自動存檔系統。對應 程式規格書.md §3.9。
## M2 範圍:整備節點時自動存檔;失敗 → 重啟時從存檔點繼續。

const SAVE_PATH := "user://savegame.tres"


## 整備節點自動存檔。
func save_at_prep_node(state: Dictionary) -> bool:
	## state 結構:
	## {
	##   "campaign_id": String,
	##   "chain_index_completed": int,   ## 已通過第 N 連戰(下次從 chain_index_completed+1 開始)
	##   "deck": Dictionary,              ## { card_id: { count_remaining, count_consumed_total } }
	##   "supply_applied_history": Array, ## 已套用過的 supply_id
	## }
	var config := ConfigFile.new()
	config.set_value("save", "version", 1)
	config.set_value("save", "campaign_id", state.get("campaign_id", ""))
	config.set_value("save", "chain_index_completed", state.get("chain_index_completed", -1))
	config.set_value("save", "deck", state.get("deck", {}))
	config.set_value("save", "supply_applied_history", state.get("supply_applied_history", []))
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_error("存檔失敗:" + str(err))
		return false
	return true


## 載入存檔。
func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		push_error("讀檔失敗:" + str(err))
		return {}
	return {
		"campaign_id": config.get_value("save", "campaign_id", ""),
		"chain_index_completed": config.get_value("save", "chain_index_completed", -1),
		"deck": config.get_value("save", "deck", {}),
		"supply_applied_history": config.get_value("save", "supply_applied_history", []),
	}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
