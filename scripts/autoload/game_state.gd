extends Node

## 跨場景持久狀態。對應 程式規格書.md §2 autoload。
## M3 範圍:已完成戰役、已解鎖紀念品。

const PROGRESS_PATH := "user://progress.cfg"

var completed_campaigns: Array = []
var unlocked_souvenirs: Array = []


func _ready() -> void:
	load_progress()


func mark_campaign_complete(campaign_id: String) -> void:
	if not completed_campaigns.has(campaign_id):
		completed_campaigns.append(campaign_id)
	save_progress()


func is_campaign_complete(campaign_id: String) -> bool:
	return completed_campaigns.has(campaign_id)


func unlock_souvenir(souvenir_id: String) -> void:
	if not unlocked_souvenirs.has(souvenir_id):
		unlocked_souvenirs.append(souvenir_id)
	save_progress()


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "completed_campaigns", completed_campaigns)
	config.set_value("progress", "unlocked_souvenirs", unlocked_souvenirs)
	var err := config.save(PROGRESS_PATH)
	if err != OK:
		push_error("進度存檔失敗:" + str(err))


func load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_PATH):
		return
	var config := ConfigFile.new()
	if config.load(PROGRESS_PATH) != OK:
		push_error("進度讀檔失敗")
		return
	completed_campaigns = config.get_value("progress", "completed_campaigns", [])
	unlocked_souvenirs = config.get_value("progress", "unlocked_souvenirs", [])


## 開發測試用:清除所有進度。
func reset_progress() -> void:
	completed_campaigns.clear()
	unlocked_souvenirs.clear()
	if FileAccess.file_exists(PROGRESS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))
