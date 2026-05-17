extends Control

## Hub 中樞 —— point-and-click 場景。
## 對應 UI 設計指引.md §2 螢幕地圖 + §3.11(NPC 對話)+ §3.12(紀念品)。
##
## 結構:
##   - 主場景(HubScene):背景 + 父親立繪 + 書架 + 紀念品擺設物件
##     - 點父親 → 對話泡顯示父親的話(依進度)
##     - 點書架 → 切到戰役選擇子畫面
##     - 點紀念品物件 → 對話泡顯示描述(只放已解鎖的物件)
##   - 戰役選擇子畫面(CampaignScreen):戰役卡片 + 返回鈕
##   - 角落 DevPanel:重置進度 / 回主選單
## 嚴格遵守:紀念品「不顯示未解鎖位、不顯示解鎖條件」(§3.12)。

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const CAMPAIGN_SCENE := "res://scenes/m2_campaign.tscn"
const PROLOGUE_ID := "prologue_first_half"
const ADVENTURE_JOURNAL_SCENE := preload("res://scenes/adventure_journal.tscn")

## 紀念品定義 — 2026-05-17 抽出到 SouvenirInfo class(跨場景共用)。
## 留 alias 維持向下相容,實際資料來自 SouvenirInfo.ALL。
const SOUVENIR_INFO := SouvenirInfo.ALL

@onready var hub_scene: Control = $HubScene
@onready var father_figure: ColorRect = $HubScene/FatherFigure
@onready var father_label: Label = $HubScene/FatherFigure/FatherLabel
@onready var book_shelf: ColorRect = $HubScene/BookShelf
@onready var book_shelf_label: Label = $HubScene/BookShelf/BookShelfLabel
@onready var journal_book: ColorRect = $HubScene/JournalBook
@onready var journal_book_label: Label = $HubScene/JournalBook/JournalBookLabel
@onready var souvenir_layer: Control = $HubScene/SouvenirLayer
@onready var campaign_screen: Control = $CampaignScreen
@onready var campaign_status_label: Label = $CampaignScreen/CenterStack/Card/CardMargin/CardVBox/StatusLabel
@onready var campaign_enter_btn: Button = $CampaignScreen/CenterStack/Card/CardMargin/CardVBox/EnterButton
@onready var campaign_back_btn: Button = $CampaignScreen/BackButton
@onready var reset_btn: Button = $DevPanel/DevContent/ResetButton
@onready var return_menu_btn: Button = $DevPanel/DevContent/ReturnMenuButton

var dialogue_bubble: DialogueBubble


func _ready() -> void:
	father_figure.mouse_filter = Control.MOUSE_FILTER_STOP
	father_figure.gui_input.connect(_on_father_input)
	book_shelf.mouse_filter = Control.MOUSE_FILTER_STOP
	book_shelf.gui_input.connect(_on_bookshelf_input)
	journal_book.mouse_filter = Control.MOUSE_FILTER_STOP
	journal_book.gui_input.connect(_on_journal_input)
	campaign_enter_btn.pressed.connect(_on_campaign_enter)
	campaign_back_btn.pressed.connect(_on_campaign_back)
	reset_btn.pressed.connect(_on_reset)
	return_menu_btn.pressed.connect(_on_return_menu)

	## 對話泡 = overlay,加在最上層
	dialogue_bubble = DialogueBubble.new()
	add_child(dialogue_bubble)
	dialogue_bubble.position = Vector2(360, 30)

	## 場景物件的多行標籤(.tscn 不放多行字串)
	book_shelf_label.text = "書架\n(戰役選擇)"
	journal_book_label.text = "日誌本\n(冒險手記)"

	_rebuild_souvenirs()
	_show_main_scene()
	_refresh_state()


# ============ 狀態 / 紀念品重建 ============

func _refresh_state() -> void:
	var done := GameState.is_campaign_complete(PROLOGUE_ID)
	father_label.text = "父親\n(點擊對話)"
	if done:
		campaign_status_label.text = "狀態:✓ 已完成(可重新挑戰)"
		campaign_status_label.add_theme_color_override("font_color", UiPalette.OK_COLOR)
	else:
		campaign_status_label.text = "狀態:尚未完成"
		campaign_status_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)


## 依 GameState.unlocked_souvenirs 動態生成場景中的紀念品物件。
## 嚴格遵守:沒有「???」未解鎖位、不顯示解鎖條件 —— 沒解鎖就根本不存在。
func _rebuild_souvenirs() -> void:
	for child in souvenir_layer.get_children():
		child.queue_free()
	for sid in GameState.unlocked_souvenirs:
		if not SOUVENIR_INFO.has(sid):
			continue
		var info: Dictionary = SOUVENIR_INFO[sid]
		var obj := ColorRect.new()
		obj.color = info.get("color", Color(0.4, 0.4, 0.4, 1))
		obj.position = info["pos"]
		obj.size = info["size"]
		obj.mouse_filter = Control.MOUSE_FILTER_STOP
		obj.gui_input.connect(_on_souvenir_input.bind(sid))
		souvenir_layer.add_child(obj)
		var lbl := Label.new()
		lbl.text = "%s\n(點擊查看)" % info["name"]
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
		obj.add_child(lbl)


# ============ 點擊處理 ============

func _on_father_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var done := GameState.is_campaign_complete(PROLOGUE_ID)
	var line: String
	if done:
		line = "你做得不錯。但森林深處的事,我還是得自己去看看。"
	else:
		line = "準備好了嗎?今天換你決定每一箭。"
	dialogue_bubble.show_line("父親", line + "  (佔位)")


func _on_bookshelf_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_campaign_screen()


## 點日誌本 → 開冒險手記 overlay
func _on_journal_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var journal := ADVENTURE_JOURNAL_SCENE.instantiate()
		add_child(journal)


## gui_input.connect(...).bind(sid) → Godot 4 bind 把 sid 附加在 event 之後
func _on_souvenir_input(event: InputEvent, sid: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var info: Dictionary = SOUVENIR_INFO.get(sid, {})
	var sname: String = str(info.get("name", sid))
	var desc: String = str(info.get("description", ""))
	dialogue_bubble.show_line(sname, desc)


func _on_campaign_enter() -> void:
	get_tree().change_scene_to_file(CAMPAIGN_SCENE)


func _on_campaign_back() -> void:
	_show_main_scene()


func _on_reset() -> void:
	GameState.reset_progress()
	SaveSystem.clear_save()
	AdventureRecord.clear_all()  ## [DEV] 重置同步清掉冒險手記紀錄(平時遊戲流程不會呼叫)
	_rebuild_souvenirs()
	_show_main_scene()
	_refresh_state()


func _on_return_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# ============ 畫面切換 ============

func _show_main_scene() -> void:
	hub_scene.visible = true
	campaign_screen.visible = false
	if dialogue_bubble != null:
		dialogue_bubble.hide_bubble()


func _show_campaign_screen() -> void:
	_refresh_state()
	hub_scene.visible = false
	campaign_screen.visible = true
	if dialogue_bubble != null:
		dialogue_bubble.hide_bubble()
