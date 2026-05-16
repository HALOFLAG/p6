extends Control

## M1 戰鬥場景(dev 用)。
##
## 用途(2026-05-16 起):
##   1. **戰鬥階段機制驗證** — BattleView / BattleEngine 動過後跑這裡確認最簡 host 還能運作。
##      m2 的 phase 狀態機 / FailureHandler / 教學重來等不在範圍內,純看戰鬥-zone 是否健康
##   2. **新卡片驗證** — 加入新 CardDefinition 後,在這裡跟既有敵人對打,看 contribution / lock_class /
##      special_effect 行為是否如設計
##   3. **新敵人驗證** — 加入新 EnemyTemplate / EnemyInstance 後,加進 ENEMY_KEYS 即可在 DevPanel 直接挑
##
## 範圍:host 邏輯 = 選敵人 + 起手卡組 + 觸發戰鬥;戰鬥-zone UI 全交給 BattleView(ADR-0002)。
## host 仍擁有跨 phase widgets(portrait_pair / progress_indicator / dialogue_bubble)+ dev 工具
## (DevPanel 敵人選單 + Reset 按鈕)。**不註冊** 連戰預覽 source(單體戰沒有連戰概念)。
##
## 不在範圍:連戰 / 整備 / 失敗代價分支 / 教學重來 / 戰役流程 / 紀錄寫入。要驗這些去 m2_campaign。

## m1 dev 戰鬥的敵人選單。加新敵人時直接 append id,DevPanel 會自動生按鈕。
## 慣例:enemy_template id = key;enemy_instance id = key + "_default"。
const ENEMY_KEYS := ["rabbit", "fox", "wolf", "mutant_wolf"]

## 序章前半起手卡組規格(對應 卡牌資料庫.md §4.1)
const STARTING_DECK := {
	"tool_arrow_pierce": 10,
	"tool_stone_impact": 8,
	"intel_weakness": 2,
}

@onready var portrait_slot: Control = $StageZone/PortraitSlot
@onready var progress_slot: Control = $StageZone/ProgressSlot
@onready var enemy_figure: ColorRect = $StageZone/EnemyFigure
@onready var enemy_figure_label: Label = $StageZone/EnemyFigure/EnemyFigureLabel
@onready var strike_slot: HBoxContainer = $StrikeZone/StrikeSlot
@onready var status_content: VBoxContainer = $StrikeZone/StatusPanel/StatusContent
@onready var end_strike_button: Button = $StrikeZone/EndStrikeButton
@onready var strike_info_label: Label = $StrikeZone/StrikeInfoLabel
@onready var pile_slot: HBoxContainer = $InventoryZone/PileSlot
@onready var enemy_info_slot: Control = $StageZone/EnemyInfoSlot
@onready var dev_enemy_buttons: HBoxContainer = $InventoryZone/DevPanel/DevContent/EnemyButtons
@onready var reset_button: Button = $InventoryZone/DevPanel/DevContent/ResetButton

var current_enemy_key: String = ""
var deck: Array[DeckEntry] = []
var engine: BattleEngine
var view: BattleView

var portrait_pair: PortraitPair
var progress_indicator: ProgressIndicator
var dialogue_bubble: DialogueBubble


func _ready() -> void:
	_build_overlays()
	_build_view()
	_build_dev_enemy_buttons()
	reset_button.pressed.connect(_on_reset_pressed)
	_start_battle(ENEMY_KEYS[0])


## host overlays:雙頭像、連戰進度、對話泡(跨 phase 使用,不歸 BattleView)。
func _build_overlays() -> void:
	portrait_pair = PortraitPair.new()
	portrait_slot.add_child(portrait_pair)
	portrait_pair.set_anchors_preset(Control.PRESET_FULL_RECT)

	progress_indicator = ProgressIndicator.new()
	progress_slot.add_child(progress_indicator)
	progress_indicator.set_anchors_preset(Control.PRESET_TOP_WIDE)
	progress_indicator.setup(5, 0)  ## m1 佔位:對應序章前半 5 連戰,第 1 個為當前

	## 對話泡 = overlay,加在根節點之上,絕對定位
	dialogue_bubble = DialogueBubble.new()
	add_child(dialogue_bubble)
	dialogue_bubble.position = Vector2(110, 8)


## m1 dev 模式:不註冊 preview_source(單體戰沒有連戰概念);progress_slot 不傳入 attach,
## view 不在其上 wire 任何 input → 點 progress_indicator 是真正的 no-op(無誤導 affordance)。
func _build_view() -> void:
	view = BattleView.new()
	view.attach({
		"pile_slot": pile_slot,
		"strike_slot": strike_slot,
		"status_content": status_content,
		"enemy_figure": enemy_figure,
		"enemy_figure_label": enemy_figure_label,
		"enemy_info_slot": enemy_info_slot,
		"end_strike_button": end_strike_button,
		"strike_info_label": strike_info_label,
	})
	view.strike_committed.connect(_on_strike_committed)


func _build_dev_enemy_buttons() -> void:
	for child in dev_enemy_buttons.get_children():
		child.queue_free()
	for key in ENEMY_KEYS:
		var tmpl: EnemyTemplate = ResourceLibrary.enemy_template(key)
		if tmpl == null:
			continue
		var btn := Button.new()
		btn.text = tmpl.template_name
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_enemy_button_pressed.bind(key))
		dev_enemy_buttons.add_child(btn)


func _initialize_deck() -> void:
	deck.clear()
	for card_id in STARTING_DECK:
		var entry := DeckEntry.new()
		entry.card_id = card_id
		entry.count_remaining = STARTING_DECK[card_id]
		entry.count_consumed_total = 0
		deck.append(entry)


func _start_battle(enemy_key: String) -> void:
	current_enemy_key = enemy_key
	_initialize_deck()
	## m1 dev:單體戰一隻 encounter,is_elite=false;view.set_encounter(enc, -1) 表不顯示連戰剩餘
	var enc := EnemyEncounter.from_chain(enemy_key + "_default", false)
	if enc == null:
		return
	engine = BattleEngine.new(enc.enemy_instance, enc.enemy_template, deck, ResourceLibrary.cards())
	view.set_engine(engine)
	view.set_encounter(enc, -1)
	portrait_pair.set_speaking("none")
	dialogue_bubble.hide_bubble()


# ====================
#  輸入處理
# ====================

func _on_enemy_button_pressed(enemy_key: String) -> void:
	_start_battle(enemy_key)


func _on_reset_pressed() -> void:
	_start_battle(current_enemy_key)


## view 結束本擊後通知;m1 dev 模式僅顯示佔位 NPC 台詞。
func _on_strike_committed(result: StrikeResult) -> void:
	var verdict: String = "一擊命中。" if result != null and result.ohk else "沒打穿 —— 再想想。"
	portrait_pair.set_speaking("npc")
	dialogue_bubble.show_line("父親", verdict + "(戰後校準對話佔位)")
