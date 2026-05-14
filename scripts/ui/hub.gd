extends Control

## Hub 中樞場景。對應 程式規格書.md §3 + 遊戲核心系統機制.md §7。
## M3 雛形:戰役選擇 + 父親 NPC 對話(佔位)+ 紀念品展示位(完成後才顯示)。

const CAMPAIGN_SCENE := "res://scenes/m2_campaign.tscn"
const PROLOGUE_ID := "prologue_first_half"
const PROLOGUE_SOUVENIR := "mutant_wolf_arm"

@onready var npc_label: RichTextLabel = $VBox/NpcPanel/NpcLabel
@onready var campaign_button: Button = $VBox/CampaignPanel/CampaignVBox/CampaignButton
@onready var campaign_status_label: Label = $VBox/CampaignPanel/CampaignVBox/CampaignStatusLabel
@onready var souvenir_panel: PanelContainer = $VBox/SouvenirPanel
@onready var souvenir_label: RichTextLabel = $VBox/SouvenirPanel/SouvenirLabel
@onready var reset_button: Button = $VBox/DevRow/ResetProgressButton


func _ready() -> void:
	campaign_button.pressed.connect(_on_campaign_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	_refresh()


func _refresh() -> void:
	var done := GameState.is_campaign_complete(PROLOGUE_ID)
	## 父親 NPC 對話(佔位,依完成狀態變化)
	if done:
		npc_label.text = "[b]父親[/b]\n(佔位)「你做得不錯。但森林深處的事,我還是得自己去看看。」"
		campaign_status_label.text = "狀態:已完成 ✓(可重新挑戰)"
	else:
		npc_label.text = "[b]父親[/b]\n(佔位)「準備好了嗎?今天換你決定每一箭。」"
		campaign_status_label.text = "狀態:尚未完成"
	## 紀念品展示位 —— 只在完成後出現,不顯示未解鎖位
	if GameState.unlocked_souvenirs.has(PROLOGUE_SOUVENIR):
		souvenir_panel.visible = true
		souvenir_label.text = "[b]紀念品[/b]\n(佔位)異變的巨狼斷臂 —— 左臂呈現極深的黑色。"
	else:
		souvenir_panel.visible = false


func _on_campaign_pressed() -> void:
	get_tree().change_scene_to_file(CAMPAIGN_SCENE)


func _on_reset_pressed() -> void:
	GameState.reset_progress()
	SaveSystem.clear_save()
	_refresh()
