extends Control

## 啟動畫面 —— Logo + 點擊任意處 / 任意鍵進入主選單。
## 對應 UI 設計指引.md §2 螢幕地圖「啟動畫面」。

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_enter_menu()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_enter_menu()


func _enter_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
