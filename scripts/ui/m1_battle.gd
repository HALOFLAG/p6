extends Control

## M1 戰鬥場景(色塊版 — 固定區塊空間佈局)。
## 對應 第一期 UI 線框圖.md §3 變體 A/B/C:一套場景,狀態驅動,牌桌不變。
## 區塊:TopBar / MiddleStage / StrikeZone / InventoryZone / EnemyInfoSlot —— 各自固定,
## 變化的只有「桌上物件」(本擊區的卡、敵人情報的揭露、對話泡、頭像發言狀態)。

## m1 dev 戰鬥的敵人選單(序章前半 4 種)。
## 慣例:enemy_template id = key;enemy_instance id = key + "_default"。
const ENEMY_KEYS := ["rabbit", "fox", "wolf", "mutant_wolf"]

## 序章前半起手卡組規格(對應 卡牌資料庫.md §4.1)
const STARTING_DECK := {
	"tool_arrow_pierce": 10,
	"tool_stone_impact": 8,
	"intel_weakness": 2,
}

## 連戰預覽:點連戰序列 → 立繪左移、剩餘敵人殘影排在其右後方
const ENEMY_FIGURE_NORMAL := Vector2(1040, 92)
const ENEMY_FIGURE_PREVIEW := Vector2(600, 92)
const PREVIEW_REMAINING := 3  ## m1 佔位數;m2 由連戰資料提供實際剩餘敵人數
const AFTERIMAGE_SIZE := Vector2(140, 130)
const AFTERIMAGE_START_X := 700.0
const AFTERIMAGE_STEP_X := 160.0  ## 殘影間距(>140 寬度 → 完全不重疊,方便辨識)
const AFTERIMAGE_Y := 92.0

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

var portrait_pair: PortraitPair
var progress_indicator: ProgressIndicator
var enemy_widget: EnemyWidget
var dialogue_bubble: DialogueBubble
var card_piles: Dictionary = {}  ## { card_id: CardPile }

var _preview_mode: bool = false
var _preview_afterimages: Array[ColorRect] = []


func _ready() -> void:
	_build_overlays()
	_build_dev_enemy_buttons()
	_build_card_piles()
	end_strike_button.pressed.connect(_on_end_strike_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	## 點敵人立繪 → 切換敵人情報欄展開(對應線框圖「點擊展開」)
	enemy_figure.mouse_filter = Control.MOUSE_FILTER_STOP
	enemy_figure.gui_input.connect(_on_enemy_figure_input)
	## 點連戰序列(進度指示器)→ 切換連戰預覽
	progress_slot.mouse_filter = Control.MOUSE_FILTER_STOP
	progress_slot.gui_input.connect(_on_progress_slot_input)
	_start_battle(ENEMY_KEYS[0])


## 建立固定區塊內的常駐 widget:雙頭像、連戰進度、對話泡(overlay)。
func _build_overlays() -> void:
	portrait_pair = PortraitPair.new()
	portrait_slot.add_child(portrait_pair)
	portrait_pair.set_anchors_preset(Control.PRESET_FULL_RECT)

	progress_indicator = ProgressIndicator.new()
	progress_slot.add_child(progress_indicator)
	progress_indicator.set_anchors_preset(Control.PRESET_TOP_WIDE)
	progress_indicator.setup(5, 0)  ## m1 佔位:對應序章前半 5 連戰,第 1 個為當前

	## 對話泡 = overlay 圖層,加在根節點之上,絕對定位,不影響任何固定區塊
	dialogue_bubble = DialogueBubble.new()
	add_child(dialogue_bubble)
	dialogue_bubble.position = Vector2(110, 8)


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


## 庫存區 3 個牌堆塊(卡型靜態,建立一次,數量於 _refresh 更新)。
func _build_card_piles() -> void:
	for child in pile_slot.get_children():
		child.queue_free()
	card_piles.clear()
	for card_id in ResourceLibrary.cards():
		var card: CardDefinition = ResourceLibrary.card(card_id)
		if card == null:
			continue
		var pile := CardPile.new()
		pile_slot.add_child(pile)
		pile.setup(card)
		pile.pile_clicked.connect(_on_pile_clicked.bind(card_id))
		card_piles[card_id] = pile


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
	var template: EnemyTemplate = ResourceLibrary.enemy_template(enemy_key)
	var instance: EnemyInstance = ResourceLibrary.enemy_instance(enemy_key + "_default")
	if template == null or instance == null:
		return
	engine = BattleEngine.new(instance, template, deck, ResourceLibrary.cards())

	## 敵人立繪色塊 = 類別色
	enemy_figure.color = UiPalette.enemy_class_color(template.enemy_class)
	enemy_figure_label.text = "%s\n(點擊查看情報)" % (instance.display_name if instance.display_name != "" else template.template_name)

	## 敵人情報欄(重建,填入 StageZone 內的 EnemyInfoSlot;預設收合,點敵人才展開)
	for child in enemy_info_slot.get_children():
		child.queue_free()
	enemy_widget = EnemyWidget.new()
	enemy_info_slot.add_child(enemy_widget)
	enemy_widget.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_widget.setup(template, instance)
	_set_preview_mode(false)
	_apply_enemy_info_state(false)

	portrait_pair.set_speaking("none")
	dialogue_bubble.hide_bubble()
	_refresh_ui()


## 點敵人立繪 → 切換敵人情報欄展開 / 收合。
func _on_enemy_figure_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_apply_enemy_info_state(not enemy_info_slot.visible)


## 敵人情報收合 / 展開:立繪固定不動,情報欄在立繪左側出現 / 隱藏。
## 與連戰預覽互斥:展開情報時關掉預覽。
func _apply_enemy_info_state(expanded: bool) -> void:
	if expanded and _preview_mode:
		_set_preview_mode(false)
	enemy_info_slot.visible = expanded


## 點連戰序列 → 切換連戰預覽(再次點擊回歸原樣)。
func _on_progress_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_preview_mode(not _preview_mode)


## 連戰預覽開 / 關。
## 開:立繪左移,生成「剩餘敵人」半透明殘影色塊,等距排在立繪右後方(可重疊、越後越淡)。
## 關:立繪歸位、殘影清除。與敵人情報欄互斥。
func _set_preview_mode(on: bool) -> void:
	_preview_mode = on
	for ghost in _preview_afterimages:
		ghost.get_parent().remove_child(ghost)
		ghost.queue_free()
	_preview_afterimages.clear()
	if on:
		enemy_info_slot.visible = false
		enemy_figure.position = ENEMY_FIGURE_PREVIEW
		_spawn_preview_afterimages()
	else:
		enemy_figure.position = ENEMY_FIGURE_NORMAL


## 生成連戰預覽殘影:半透明色塊,等距排在立繪右後方,畫在立繪之後(z 序)。
func _spawn_preview_afterimages() -> void:
	if engine == null:
		return
	var stage := enemy_figure.get_parent()
	var figure_index := enemy_figure.get_index()
	var class_color := UiPalette.enemy_class_color(engine.enemy_template.enemy_class)
	for i in PREVIEW_REMAINING:
		var ghost := ColorRect.new()
		ghost.color = Color(class_color.r, class_color.g, class_color.b, maxf(0.5 - i * 0.08, 0.15))
		ghost.position = Vector2(AFTERIMAGE_START_X + i * AFTERIMAGE_STEP_X, AFTERIMAGE_Y)
		ghost.size = AFTERIMAGE_SIZE
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(ghost)
		stage.move_child(ghost, figure_index)  ## 移到立繪之前 → 畫在立繪後方
		_preview_afterimages.append(ghost)


# ====================
#  輸入處理
# ====================

func _on_enemy_button_pressed(enemy_key: String) -> void:
	_start_battle(enemy_key)


func _on_pile_clicked(card_id: String) -> void:
	if engine.phase != BattleEngine.Phase.PLACE:
		return
	if not engine.place_card(card_id):
		return
	_refresh_ui()


func _on_unplace_button_pressed(index: int) -> void:
	if not engine.unplace_card_at(index):
		return
	_refresh_ui()


func _on_lock_button_pressed(index: int) -> void:
	if not engine.lock_card_at(index):
		return
	_refresh_ui()


func _on_end_strike_pressed() -> void:
	if not engine.can_commit():
		return
	_set_preview_mode(false)  ## 結算前收掉連戰預覽
	engine.commit_strike()
	_refresh_ui()
	## 結算後:對話泡浮出(m1 佔位台詞),NPC 頭像亮起 —— 牌桌不動,只是桌上物件變化
	var verdict: String = "一擊命中。" if engine.result.get("ohk", false) else "沒打穿 —— 再想想。"
	portrait_pair.set_speaking("npc")
	dialogue_bubble.show_line("父親", verdict + "(戰後校準對話佔位)")


func _on_reset_pressed() -> void:
	_start_battle(current_enemy_key)


# ====================
#  UI 更新(狀態驅動,牌桌不變)
# ====================

func _refresh_ui() -> void:
	enemy_widget.set_revealed(engine.revealed_info)
	_refresh_piles()
	_refresh_strike()
	_refresh_status()
	_refresh_buttons()


func _refresh_piles() -> void:
	var is_place := engine.phase == BattleEngine.Phase.PLACE
	for card_id in card_piles:
		var pile: CardPile = card_piles[card_id]
		var entry := _find_deck_entry(card_id)
		var remaining := entry.count_remaining if entry != null else 0
		## in_strike 只在 PLACE 階段扣:結算後 commit_strike 已把 locked 卡從卡組消耗,
		## count_remaining 已反映,不能再扣一次(否則顯示負數)。
		var in_strike := _count_in_strike_local(card_id) if is_place else 0
		var available := remaining - in_strike
		pile.set_count(available)
		pile.set_enabled(is_place and available > 0)


## 本擊區時間線:Lock 卡在左、Place 卡在右,同一條 HBox(對應線框圖單一時間線)。
func _refresh_strike() -> void:
	for child in strike_slot.get_children():
		child.queue_free()
	var is_place := engine.phase == BattleEngine.Phase.PLACE

	## ---- 已 Lock 的卡(定格)----
	var locked_groups := _group_pool_cards(engine.strike.locked_cards)
	for card_id in locked_groups:
		var info: Dictionary = locked_groups[card_id]
		strike_slot.add_child(_make_card_widget(info["card"], CardWidget.State.LOCKED, "Locked ×%d" % info["count"]))
	for c in engine.strike.locked_cards:
		if c.lock_class == "none":
			continue
		strike_slot.add_child(_make_card_widget(c, CardWidget.State.LOCKED, "Locked"))

	## ---- Place 中的卡(可調整)----
	var placed_groups := _group_pool_cards(engine.strike.placed_cards)
	for card_id in placed_groups:
		var info: Dictionary = placed_groups[card_id]
		var w := _make_card_widget(info["card"], CardWidget.State.IN_PLACE, "Place ×%d" % info["count"])
		if is_place:
			var unplace_btn := w.add_action_button("−1" if info["count"] > 1 else "Unplace")
			unplace_btn.pressed.connect(_on_unplace_button_pressed.bind(info["last_index"]))
		strike_slot.add_child(w)
	for i in engine.strike.placed_cards.size():
		var c: CardDefinition = engine.strike.placed_cards[i]
		if c.lock_class == "none":
			continue
		var w := _make_card_widget(c, CardWidget.State.IN_PLACE, "Place")
		if is_place:
			var unplace_btn := w.add_action_button("Unplace")
			unplace_btn.pressed.connect(_on_unplace_button_pressed.bind(i))
			var hint := " (揭露弱點)" if c.lock_class == "optional" else (" (必須)" if c.lock_class == "required" else "")
			var lock_btn := w.add_action_button("Lock" + hint)
			lock_btn.pressed.connect(_on_lock_button_pressed.bind(i))
		strike_slot.add_child(w)

	if strike_slot.get_child_count() == 0:
		var hint := Label.new()
		hint.text = "(時間線:尚未 Place 任何卡)"
		hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		strike_slot.add_child(hint)

	strike_info_label.text = "本擊張數:%d  (本擊上限暫時停用)" % engine.strike.size()


func _make_card_widget(card: CardDefinition, state: int, subtitle: String) -> CardWidget:
	var w := CardWidget.new()
	w.setup(card)
	w.set_subtitle(subtitle)
	w.set_state(state)
	return w


## 右側面板:Place 階段顯示本擊狀態加總;結算後顯示需求 bar + 判定。
func _refresh_status() -> void:
	for child in status_content.get_children():
		child.queue_free()

	if engine.phase != BattleEngine.Phase.RESOLVED:
		var title := Label.new()
		title.text = "本擊狀態"
		title.add_theme_color_override("font_color", UiPalette.ACCENT)
		status_content.add_child(title)
		var counts := engine.strike.get_type_counts()
		var mixed := engine.strike.get_mixed_count()
		status_content.add_child(_make_status_row("衝擊", counts.get("impact", 0)))
		status_content.add_child(_make_status_row("穿刺", counts.get("pierce", 0)))
		status_content.add_child(_make_status_row("燃燒", counts.get("burn", 0)))
		status_content.add_child(_make_status_row("混合", mixed))
		return

	## 結算:標題帶判定 + 需求 bar
	var r: Dictionary = engine.result
	var title := Label.new()
	if r.get("ohk", false):
		var loc_paths: Array[String] = []
		for p in r.get("passing_paths", []):
			loc_paths.append(UiPalette.type_label(p))
		title.text = "結算 — ✓ OHK(%s)" % ", ".join(loc_paths)
		title.add_theme_color_override("font_color", UiPalette.OK_COLOR)
	else:
		title.text = "結算 — ✗ Underkill"
		title.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
	status_content.add_child(title)
	status_content.add_child(RequirementBar.build_group(r))


func _make_status_row(type_label: String, value: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = type_label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = str(value)
	value_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	row.add_child(value_label)
	return row


func _refresh_buttons() -> void:
	end_strike_button.disabled = not engine.can_commit()


# ====================
#  輔助
# ====================

## 將 lock_class="none" 的卡按 id 分組,記錄該 id 最後出現的索引(供 Unplace 使用)。
func _group_pool_cards(cards: Array[CardDefinition]) -> Dictionary:
	var groups: Dictionary = {}
	for i in cards.size():
		var c: CardDefinition = cards[i]
		if c.lock_class != "none":
			continue
		if not groups.has(c.id):
			groups[c.id] = { "card": c, "count": 0, "last_index": i }
		groups[c.id]["count"] += 1
		groups[c.id]["last_index"] = i
	return groups


func _find_deck_entry(card_id: String) -> DeckEntry:
	for e in deck:
		if e.card_id == card_id:
			return e
	return null


func _count_in_strike_local(card_id: String) -> int:
	var n := 0
	for c in engine.strike.placed_cards:
		if c.id == card_id:
			n += 1
	for c in engine.strike.locked_cards:
		if c.id == card_id:
			n += 1
	return n
