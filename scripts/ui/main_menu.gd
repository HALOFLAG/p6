extends Control

## 主選單 —— 新遊戲 / 繼續 / 結束。
## 「設置」入口待 M4 里程碑(雙模式 UI / 教學)。
## 對應 UI 設計指引.md §2 螢幕地圖「主選單」。

const HUB_SCENE := "res://scenes/hub.tscn"

@onready var new_game_btn: Button = $CenterStack/StackVBox/Buttons/NewGameButton
@onready var continue_btn: Button = $CenterStack/StackVBox/Buttons/ContinueButton
@onready var quit_btn: Button = $CenterStack/StackVBox/Buttons/QuitButton


func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	quit_btn.pressed.connect(_on_quit)
	continue_btn.disabled = not _has_progress()


func _has_progress() -> bool:
	return SaveSystem.has_save() or not GameState.completed_campaigns.is_empty()


func _on_new_game() -> void:
	GameState.reset_progress()
	SaveSystem.clear_save()
	get_tree().change_scene_to_file(HUB_SCENE)


func _on_continue() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)


func _on_quit() -> void:
	get_tree().quit()
