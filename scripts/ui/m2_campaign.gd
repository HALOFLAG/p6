extends Control

## M2 戰役場景。整合連戰結構 + 整備補給 + 失敗代價 + 教學重來 + 自動存檔。
## 對應 開發里程碑.md M2。
##
## 階段四:Phase 驅動的常駐三區塊 —— 全程同一個框架,沒有全螢幕模式跳變。
##   上層 StageZone:場景 + 敘事文字區 + 雙頭像 + 連戰進度(敵人立繪只在戰鬥時出現)
##   中層 StrikeZone:BattleContent(戰鬥)/ PhaseContent(敘事按鈕、整備介面)隨 phase 切換
##   下層 InventoryZone:卡組牌堆 + 選項,永遠在
## 整備為「固定補給」—— 中層 PhaseContent 只做呈現,玩家動作 = 確認收下。
## 戰役 / 連戰邏輯(Phase 狀態機、失敗代價、整備、存檔)維持不變。

enum Phase {
	INTRO,        ## 戰役開場敘事
	PRE_CHAIN,    ## 連戰前敘事(narrative_pre)
	IN_BATTLE,    ## 戰鬥中
	POST_CHAIN,   ## 連戰後敘事(narrative_post)
	SUPPLY,       ## 整備補給套用
	ENDING,       ## 戰役末尾
	GAME_OVER,    ## 戰役失敗
}

const CAMPAIGN_ID := "prologue_first_half"
const HUB_SCENE := "res://scenes/hub.tscn"
const PROLOGUE_SOUVENIR := "mutant_wolf_arm"

## 連戰預覽:點連戰序列 → 立繪左移、剩餘敵人殘影排在其右後方
const ENEMY_FIGURE_NORMAL := Vector2(1040, 92)
const ENEMY_FIGURE_PREVIEW := Vector2(600, 92)
const AFTERIMAGE_SIZE := Vector2(140, 130)
const AFTERIMAGE_START_X := 700.0
const AFTERIMAGE_STEP_X := 160.0  ## 殘影間距(>140 寬度 → 完全不重疊,方便辨識)
const AFTERIMAGE_Y := 92.0

# ============ 戰役狀態 ============
var campaign_def: CampaignDefinition
var chains: Array = []  ## Array[ChainDefinition]
var deck: Array[DeckEntry] = []
var phase: int = Phase.INTRO
var chain_index: int = 0
var enemy_queue: Array = []  ## Array of Dict: { instance_id, enemy_instance, enemy_template, is_elite, label }
var chain_defeated_count: int = 0  ## 此次連戰已擊敗的敵人數(右側連戰序列用)
var engine: BattleEngine = null
var retry_count: int = 0
var deck_snapshot_for_retry: Dictionary = {}
var supply_applied_history: Array = []
var last_calibration_text: String = ""

## 冒險手記紀錄計數(對應 戰鬥紀錄系統設計.md §6.1)
var chain_attempt_for_journal: int = 0  ## 此連戰的嘗試次數(0=首次,失敗重挑或教學重來+1)
var battle_in_chain_counter: int = 0    ## 此嘗試中已記錄的戰鬥數(每次 _record_battle 後 +1)

# ============ Node refs ============
@onready var stage_zone: Control = $StageZone
@onready var portrait_slot: Control = $StageZone/PortraitSlot
@onready var progress_slot: Control = $StageZone/ProgressSlot
@onready var enemy_figure: ColorRect = $StageZone/EnemyFigure
@onready var enemy_figure_label: Label = $StageZone/EnemyFigure/EnemyFigureLabel
@onready var enemy_info_slot: Control = $StageZone/EnemyInfoSlot
@onready var battle_content: Control = $StrikeZone/BattleContent
@onready var phase_content: Control = $StrikeZone/PhaseContent
@onready var strike_slot: HBoxContainer = $StrikeZone/BattleContent/StrikeSlot
@onready var status_content: VBoxContainer = $StrikeZone/BattleContent/StatusPanel/StatusContent
@onready var end_strike_button: Button = $StrikeZone/BattleContent/EndStrikeButton
@onready var advance_button: Button = $StrikeZone/BattleContent/AdvanceButton
@onready var strike_info_label: Label = $StrikeZone/BattleContent/StrikeInfoLabel
@onready var inv_title: Label = $InventoryZone/InvTitle
@onready var pile_slot: HBoxContainer = $InventoryZone/PileSlot
@onready var record_button: Button = $InventoryZone/MenuRow/RecordButton

const ADVENTURE_JOURNAL_SCENE := preload("res://scenes/adventure_journal.tscn")

# ============ 常駐 widget ============
var portrait_pair: PortraitPair
var progress_indicator: ProgressIndicator
var enemy_widget: EnemyWidget
var dialogue_bubble: DialogueBubble
var card_piles: Dictionary = {}  ## { card_id: CardPile }

var _preview_mode: bool = false
var _preview_afterimages: Array[ColorRect] = []


func _ready() -> void:
	_load_resources()
	_build_overlays()
	_build_card_piles()
	end_strike_button.pressed.connect(_on_end_strike_pressed)
	advance_button.pressed.connect(_on_advance_pressed)
	record_button.pressed.connect(_on_record_button_pressed)
	enemy_figure.mouse_filter = Control.MOUSE_FILTER_STOP
	enemy_figure.gui_input.connect(_on_enemy_figure_input)
	progress_slot.mouse_filter = Control.MOUSE_FILTER_STOP
	progress_slot.gui_input.connect(_on_progress_slot_input)
	_enter_phase(Phase.INTRO)


## 開冒險手記 overlay(m2 內任何 phase 都可開;色塊 pass 不限制 PLACE/Lock)
func _on_record_button_pressed() -> void:
	var journal := ADVENTURE_JOURNAL_SCENE.instantiate()
	add_child(journal)


# ============================
#  載入資源
# ============================

func _load_resources() -> void:
	campaign_def = ResourceLibrary.campaign(CAMPAIGN_ID)
	if campaign_def == null:
		return
	for cid in campaign_def.chain_ids:
		var c := ResourceLibrary.chain(cid)
		if c != null:
			chains.append(c)


# ============================
#  常駐 widget 建立
# ============================

func _build_overlays() -> void:
	portrait_pair = PortraitPair.new()
	portrait_slot.add_child(portrait_pair)
	portrait_pair.set_anchors_preset(Control.PRESET_FULL_RECT)

	progress_indicator = ProgressIndicator.new()
	progress_slot.add_child(progress_indicator)
	progress_indicator.set_anchors_preset(Control.PRESET_TOP_WIDE)

	## 對話泡 = overlay,放在 StageZone 內
	dialogue_bubble = DialogueBubble.new()
	stage_zone.add_child(dialogue_bubble)
	dialogue_bubble.position = Vector2(110, 8)


## 庫存區牌堆塊(卡型靜態,建立一次,數量於 _refresh 更新)。
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


# ============================
#  Phase 切換
# ============================

func _enter_phase(new_phase: int) -> void:
	phase = new_phase
	match phase:
		Phase.INTRO:
			_show_narrative(
				"[b]%s[/b]\n\n%s" % [campaign_def.campaign_name, campaign_def.prologue_narrative],
				[{ "label": "開始戰役", "action": "_start_campaign" }]
			)
		Phase.PRE_CHAIN:
			var chain: ChainDefinition = chains[chain_index]
			_show_narrative(
				"[b]%s[/b]\n\n%s" % [chain.display_label, chain.narrative_pre],
				[{ "label": "進入戰鬥", "action": "_begin_chain" }]
			)
		Phase.IN_BATTLE:
			_show_battle()
			_start_next_enemy()
		Phase.POST_CHAIN:
			var chain: ChainDefinition = chains[chain_index]
			_show_narrative(
				"[b]%s 完成[/b]\n\n%s" % [chain.display_label, chain.narrative_post],
				[{ "label": "整備", "action": "_enter_supply" }]
			)
		Phase.SUPPLY:
			_apply_supply()
		Phase.ENDING:
			## 戰役完成 → 標記完成 + 解鎖紀念品,返回 Hub
			GameState.mark_campaign_complete(campaign_def.id)
			GameState.unlock_souvenir(PROLOGUE_SOUVENIR)
			SaveSystem.clear_save()
			_show_narrative(
				"[b]序章前半 完成[/b]\n\n%s\n\n[color=#888](已記錄戰役完成 + 紀念品)[/color]" % campaign_def.ending_narrative,
				[{ "label": "回到 Hub", "action": "_return_to_hub" }]
			)
		Phase.GAME_OVER:
			pass  ## GAME_OVER 入口由 _trigger_game_over 呼叫,自帶 narrative
	_refresh_header()


# ============================
#  戰役流程(邏輯維持不變)
# ============================

func _start_campaign() -> void:
	chain_index = 0
	chain_attempt_for_journal = 0
	deck = DeckManager.build_starting_deck(campaign_def.starting_deck)
	supply_applied_history.clear()
	_enter_phase(Phase.PRE_CHAIN)


func _return_to_hub() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)


func _begin_chain() -> void:
	var chain: ChainDefinition = chains[chain_index]
	## 教學重來:開始連戰前快照卡組
	if chain.tutorial_retry:
		deck_snapshot_for_retry = DeckManager.snapshot(deck)
		retry_count = 0
	## 建立 enemy_queue
	enemy_queue.clear()
	chain_defeated_count = 0
	battle_in_chain_counter = 0
	for inst_id in chain.enemies:
		enemy_queue.append(_build_enemy_entry(inst_id, false))
	_enter_phase(Phase.IN_BATTLE)


func _build_enemy_entry(instance_id: String, is_elite: bool) -> Dictionary:
	var inst: EnemyInstance = ResourceLibrary.enemy_instance(instance_id)
	if inst == null:
		return {}
	var tmpl: EnemyTemplate = ResourceLibrary.enemy_template(inst.template_id)
	var label: String = inst.display_name
	if is_elite:
		label = "[菁英化 ⚠] " + label
	return {
		"instance_id": instance_id,
		"enemy_instance": inst,
		"enemy_template": tmpl,
		"is_elite": is_elite,
		"label": label,
	}


func _start_next_enemy() -> void:
	if enemy_queue.is_empty():
		_complete_chain()
		return
	var entry: Dictionary = enemy_queue[0]
	engine = BattleEngine.new(entry["enemy_instance"], entry["enemy_template"], deck, ResourceLibrary.cards())
	_setup_enemy_visuals(entry)
	_refresh_chain_sequence()
	_refresh_battle_ui()


## 為當前敵人建立 / 更新立繪與情報欄,重置預覽 / 情報展開 / 對話泡。
func _setup_enemy_visuals(entry: Dictionary) -> void:
	var tmpl: EnemyTemplate = entry["enemy_template"]
	var inst: EnemyInstance = entry["enemy_instance"]
	enemy_figure.color = UiPalette.enemy_class_color(tmpl.enemy_class)
	enemy_figure_label.text = "%s\n(點擊查看情報)" % str(entry.get("label", inst.display_name))

	for child in enemy_info_slot.get_children():
		child.queue_free()
	enemy_widget = EnemyWidget.new()
	enemy_info_slot.add_child(enemy_widget)
	enemy_widget.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_widget.setup(tmpl, inst, entry.get("is_elite", false), str(entry.get("label", "")))
	enemy_widget.set_remaining(enemy_queue.size())

	_set_preview_mode(false)
	_apply_enemy_info_state(false)
	portrait_pair.set_speaking("none")
	dialogue_bubble.hide_bubble()


func _on_resolution(result: Dictionary) -> void:
	if engine == null:
		return
	var entry: Dictionary = enemy_queue[0]
	var is_ohk: bool = result.get("ohk", false)
	## 戰後校準分類(6 種對話狀態)
	var weakness_range: Array = entry["enemy_template"].weakness_range
	var total_committed: int = engine.strike.size()
	var cal_state := CalibrationClassifier.classify(result, weakness_range, total_committed)
	last_calibration_text = _build_calibration_text(cal_state)
	if is_ohk:
		## 先寫手記紀錄(read 當前 enemy_queue[0] / engine 狀態),再做隊伍變動
		_record_battle(entry, result, cal_state, -1)
		enemy_queue.pop_front()
		chain_defeated_count += 1
		_after_battle_result(true, entry, "")
	else:
		var outcome := FailureHandler.resolve_failure(
			entry["enemy_template"],
			entry["enemy_instance"],
			entry.get("is_elite", false),
			_current_chain().tutorial_retry,
		)
		_record_battle(entry, result, cal_state, int(outcome.get("outcome", -1)))
		_handle_failure(outcome, entry)


func _build_calibration_text(cal_state: int) -> String:
	## 純文字(對話泡用 Label,不吃 BBCode)。
	var key := CalibrationClassifier.state_key(cal_state)
	var display := CalibrationClassifier.state_display(cal_state)
	var line_data: Dictionary = {}
	var cl: CalibrationLines = ResourceLibrary.calibration_lines()
	if cl != null:
		line_data = cl.get_line(key)
	var player_line: String = str(line_data.get("player", "(佔位:玩家)"))
	var npc_line: String = str(line_data.get("npc", "(佔位:父親)"))
	return "[%s] %s\n（玩家)%s" % [display, npc_line, player_line]


func _handle_failure(outcome: Dictionary, entry: Dictionary) -> void:
	var narrative: String = outcome.get("narrative", "")
	match outcome.get("outcome", -1):
		FailureHandler.FailureOutcome.TUTORIAL_RETRY:
			_trigger_tutorial_retry(narrative)
		FailureHandler.FailureOutcome.RABBIT_CHAIN_FLEE:
			## 兔子失敗 → 連戰中所有兔子(含當前這隻)逃走移出;非兔子敵人留下,連戰繼續
			var fled := 0
			var remaining: Array = []
			for e in enemy_queue:
				if e["enemy_template"].id == "rabbit":
					fled += 1
				else:
					remaining.append(e)
			enemy_queue = remaining
			_after_battle_result(false, entry, "%s(共 %d 隻兔子逃走)。連戰繼續。" % [narrative, fled])
		FailureHandler.FailureOutcome.FOX_FLEE:
			enemy_queue.pop_front()
			_after_battle_result(false, entry, narrative)
		FailureHandler.FailureOutcome.WOLF_ELITE_PROMOTION:
			## 把當前敵人標記菁英並排到 queue 末尾
			enemy_queue.pop_front()
			var elite_entry := _build_enemy_entry(entry["instance_id"], true)
			enemy_queue.append(elite_entry)
			_after_battle_result(false, entry, narrative)
		FailureHandler.FailureOutcome.GAME_OVER:
			_trigger_game_over(narrative)


func _trigger_tutorial_retry(narrative: String) -> void:
	retry_count += 1
	DeckManager.restore(deck, deck_snapshot_for_retry)
	var chain: ChainDefinition = _current_chain()
	enemy_queue.clear()
	chain_defeated_count = 0
	battle_in_chain_counter = 0
	chain_attempt_for_journal += 1  ## 教學重來也算一次嘗試
	for inst_id in chain.enemies:
		enemy_queue.append(_build_enemy_entry(inst_id, false))
	EventBus.emit_signal("tutorial_retry_triggered", retry_count)
	## 切到敘事顯示重來提示,點繼續再進戰鬥
	var dialogue := TutorialRetry.get_dialogue_text(retry_count)
	_show_narrative(
		"[b]教學重來(第 %d 次)[/b]\n\n%s\n\n[color=#888]%s[/color]" % [retry_count, narrative, dialogue],
		[{ "label": "再試一次", "action": "_resume_retry" }]
	)


func _resume_retry() -> void:
	_enter_phase(Phase.IN_BATTLE)


func _complete_chain() -> void:
	_enter_phase(Phase.POST_CHAIN)


func _enter_supply() -> void:
	_enter_phase(Phase.SUPPLY)


func _apply_supply() -> void:
	var chain: ChainDefinition = _current_chain()
	var supply_id: String = chain.post_chain_supply
	if supply_id == "":
		## 無補給(最後一連戰)→ 直接進 ENDING
		_advance_to_next_chain_or_ending()
		return
	var sp: SupplyPhase = ResourceLibrary.supply(supply_id)
	if sp == null:
		_advance_to_next_chain_or_ending()
		return
	var pool_before := _deck_to_dict()
	var summary := SupplyHandler.apply(sp, deck, campaign_def.starting_deck)
	var pool_after := _deck_to_dict()
	supply_applied_history.append(supply_id)
	_save_at_prep_node()
	_record_prep_node(sp, summary, pool_before, pool_after)
	_show_supply(sp, summary)


func _advance_to_next_chain_or_ending() -> void:
	chain_index += 1
	chain_attempt_for_journal = 0  ## 進新連戰 → 重置嘗試計數
	if chain_index >= chains.size():
		_enter_phase(Phase.ENDING)
	else:
		_enter_phase(Phase.PRE_CHAIN)


func _save_at_prep_node() -> void:
	var deck_state: Dictionary = {}
	for entry in deck:
		deck_state[entry.card_id] = entry.snapshot()
	SaveSystem.save_at_prep_node({
		"campaign_id": campaign_def.id,
		"chain_index_completed": chain_index,
		"deck": deck_state,
		"supply_applied_history": supply_applied_history,
	})


# ============================
#  GAME OVER
# ============================

func _trigger_game_over(narrative: String) -> void:
	phase = Phase.GAME_OVER
	_show_narrative(
		"[b][color=#ff7f7f]GAME OVER[/color][/b]\n\n%s" % narrative,
		[
			{ "label": "重新挑戰這場連戰(卡組保留消耗)", "action": "_retry_from_failed_chain" },
			{ "label": "接受戰役失敗", "action": "_accept_campaign_failure" },
		],
		true
	)
	_refresh_header()


func _retry_from_failed_chain() -> void:
	## 重新挑戰失敗的連戰。對應 遊戲核心系統機制.md §7「資源持續縮減模型」。
	## - 卡組:保持失敗時的消耗狀態(不還原、不讀檔)→ 多次重挑卡組持續縮減
	## - 連戰內狀態:重置(enemy_queue 由 _begin_chain 重建,菁英化清除)
	## - 整備補給:不再次觸發
	chain_attempt_for_journal += 1  ## 計入手記:這是第幾次嘗試
	_enter_phase(Phase.PRE_CHAIN)


func _accept_campaign_failure() -> void:
	## 接受戰役失敗 → 回 Hub。卡組於下次進入戰役時完全重置(_start_campaign)。
	SaveSystem.clear_save()
	_return_to_hub()


func _current_chain() -> ChainDefinition:
	if chain_index < 0 or chain_index >= chains.size():
		return null
	return chains[chain_index]


# ============================
#  中層內容切換:戰鬥 / 敘事 / 整備
# ============================

## 切到「非戰鬥」視圖:隱藏 BattleContent、顯示 PhaseContent + 敘事文字區,收掉敵人立繪。
func _enter_nonbattle_view() -> void:
	battle_content.visible = false
	phase_content.visible = true
	enemy_figure.visible = false
	enemy_info_slot.visible = false
	progress_slot.visible = false  ## 連戰序列只在戰鬥中出現
	_set_preview_mode(false)
	dialogue_bubble.hide_bubble()
	portrait_pair.set_speaking("none")


## 純劇情段落:中層 = 文字冒險式對話框(敘述文字 + 推進按鈕)。
## is_warning → 對話框警示色邊框(GAME OVER)。上層維持演出(立繪 + 角色對話泡)。
func _show_narrative(text: String, buttons: Array, is_warning: bool = false) -> void:
	_enter_nonbattle_view()
	var box := _build_narrative_box(text, is_warning)
	for btn_data in buttons:
		var btn := box.add_button(btn_data["label"])
		btn.pressed.connect(Callable(self, btn_data["action"]))


## 整備:中層 = 對話框(整備敘事 + 補給卡塊塞進內容槽 + 收下按鈕)。固定補給,純呈現。
func _show_supply(sp: SupplyPhase, summary: Dictionary) -> void:
	_enter_nonbattle_view()
	var box := _build_narrative_box(
		"[b]整備:%s[/b]\n\n%s\n\n[color=#888]已存檔[/color]" % [sp.id, sp.narrative], false)
	box.set_title("整備補給")

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 12)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	box.content_slot().add_child(chips)
	var changes: Dictionary = summary.get("changes", {})
	if changes.is_empty():
		var none := Label.new()
		none.text = "(卡組恢復至戰前狀態)" if sp.supply_type == "full_restore" else "(無變化)"
		none.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		chips.add_child(none)
	else:
		for cid in changes:
			chips.add_child(_make_supply_chip(cid, changes[cid]))

	var btn := box.add_button("收下補給 / 繼續")
	btn.pressed.connect(_advance_to_next_chain_or_ending)


## 單一補給卡塊:卡名 + ±N(類型色邊框)。
func _make_supply_chip(card_id: String, delta: int) -> PanelContainer:
	var card: CardDefinition = ResourceLibrary.card(card_id)
	var cn := str(card_id)
	var primary := "none"
	if card != null:
		cn = card.card_name
		primary = UiPalette.card_primary_type(card)
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(120, 64)
	chip.add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG_LIGHT, UiPalette.type_color(primary), 2))
	var vb := VBoxContainer.new()
	chip.add_child(vb)
	var name_lbl := Label.new()
	name_lbl.text = cn
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	vb.add_child(name_lbl)
	var delta_lbl := Label.new()
	delta_lbl.text = "%s%d" % ["+" if delta >= 0 else "", delta]
	delta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	delta_lbl.add_theme_font_size_override("font_size", 18)
	delta_lbl.add_theme_color_override("font_color", UiPalette.OK_COLOR if delta >= 0 else UiPalette.FAIL_COLOR)
	vb.add_child(delta_lbl)
	return chip


## 在 PhaseContent 建一個敘事對話框(略內縮),回傳給呼叫端塞按鈕 / 內容。
func _build_narrative_box(text: String, is_warning: bool) -> NarrativeBox:
	for child in phase_content.get_children():
		child.queue_free()
	var box := NarrativeBox.new()
	phase_content.add_child(box)
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 16.0
	box.offset_top = 8.0
	box.offset_right = -16.0
	box.offset_bottom = -8.0
	box.setup(text, is_warning)
	return box


## 切到戰鬥視圖:顯示 BattleContent、隱藏 PhaseContent + 敘事文字區,亮出敵人立繪。
func _show_battle() -> void:
	battle_content.visible = true
	phase_content.visible = false
	enemy_figure.visible = true
	progress_slot.visible = true  ## 連戰序列:新連戰開始時出現
	advance_button.disabled = true
	advance_button.text = "繼續"
	dialogue_bubble.hide_bubble()


# ============================
#  戰鬥輸入
# ============================

func _on_pile_clicked(card_id: String) -> void:
	if engine == null or engine.phase != BattleEngine.Phase.PLACE:
		return
	if not engine.place_card(card_id):
		return
	_refresh_battle_ui()


func _on_unplace_button_pressed(index: int) -> void:
	if engine == null:
		return
	if engine.unplace_card_at(index):
		_refresh_battle_ui()


func _on_lock_button_pressed(index: int) -> void:
	if engine == null:
		return
	if engine.lock_card_at(index):
		_refresh_battle_ui()


func _on_end_strike_pressed() -> void:
	if engine == null or not engine.can_commit():
		return
	_set_preview_mode(false)  ## 結算前收掉連戰預覽,避免殘影殘留到結算 / 對話狀態
	var result := engine.commit_strike()
	_refresh_battle_ui()
	_on_resolution(result)


func _on_advance_pressed() -> void:
	if engine == null or engine.phase != BattleEngine.Phase.RESOLVED:
		return
	if enemy_queue.is_empty():
		_complete_chain()
		return
	_start_next_enemy()


## 點敵人立繪 → 切換敵人情報欄展開 / 收合。
func _on_enemy_figure_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_apply_enemy_info_state(not enemy_info_slot.visible)


## 敵人情報收合 / 展開:立繪固定不動,情報欄在立繪左側出現。與連戰預覽互斥。
func _apply_enemy_info_state(expanded: bool) -> void:
	if expanded and _preview_mode:
		_set_preview_mode(false)
	enemy_info_slot.visible = expanded


## 點連戰序列 → 切換連戰預覽(再次點擊回歸原樣)。
## 只在 PLACE 階段可開:此時 enemy_queue[0] 必為當前敵人,殘影計數(size-1)才準確。
func _on_progress_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if phase != Phase.IN_BATTLE or engine == null or engine.phase != BattleEngine.Phase.PLACE:
			return
		_set_preview_mode(not _preview_mode)


## 連戰預覽開 / 關:開 → 立繪左移、生成剩餘敵人殘影排在其右後方;關 → 歸位、清除。
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


## 生成連戰預覽殘影:enemy_queue 中「當前敵人之後」的每隻 → 一個半透明色塊(各用其類別色)。
func _spawn_preview_afterimages() -> void:
	var upcoming := enemy_queue.size() - 1
	if upcoming <= 0:
		return
	var stage := enemy_figure.get_parent()
	var figure_index := enemy_figure.get_index()
	for i in upcoming:
		var entry: Dictionary = enemy_queue[i + 1]
		var class_color := UiPalette.enemy_class_color(entry["enemy_template"].enemy_class)
		var ghost := ColorRect.new()
		ghost.color = Color(class_color.r, class_color.g, class_color.b, maxf(0.5 - i * 0.08, 0.15))
		ghost.position = Vector2(AFTERIMAGE_START_X + i * AFTERIMAGE_STEP_X, AFTERIMAGE_Y)
		ghost.size = AFTERIMAGE_SIZE
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(ghost)
		stage.move_child(ghost, figure_index)  ## 移到立繪之前 → 畫在立繪後方
		_preview_afterimages.append(ghost)


# ============================
#  戰鬥 UI 更新(狀態驅動)
# ============================

func _refresh_battle_ui() -> void:
	if engine == null:
		return
	if enemy_widget != null:
		enemy_widget.set_revealed(engine.revealed_info)
	_refresh_piles()
	_refresh_strike()
	_refresh_status()
	_refresh_buttons()


func _refresh_piles() -> void:
	var is_place := engine != null and engine.phase == BattleEngine.Phase.PLACE
	for card_id in card_piles:
		var pile: CardPile = card_piles[card_id]
		var entry := DeckManager.find_entry(deck, card_id)
		var remaining: int = entry.count_remaining if entry != null else 0
		## in_strike 只在 PLACE 階段扣:結算後 commit_strike 已把 locked 卡從卡組消耗。
		var in_strike := _count_in_strike(card_id) if is_place else 0
		var available := remaining - in_strike
		pile.set_count(available)
		pile.set_enabled(is_place and available > 0)


## 本擊區時間線:Lock 卡在左、Place 卡在右,同一條 HBox。
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


## 右側面板:PLACE 階段顯示本擊狀態加總;RESOLVED 由 _after_battle_result 接管。
func _refresh_status() -> void:
	if engine.phase != BattleEngine.Phase.PLACE:
		return
	for child in status_content.get_children():
		child.queue_free()
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


## 結算後:狀態面板顯示判定 + 需求 bar(+ 失敗敘述);對話泡浮出戰後校準。
func _after_battle_result(is_ohk: bool, entry: Dictionary, failure_narrative: String) -> void:
	for child in status_content.get_children():
		child.queue_free()
	var verdict := Label.new()
	if is_ohk:
		verdict.text = "✓ 擊敗 %s" % str(entry.get("label", ""))
		verdict.add_theme_color_override("font_color", UiPalette.OK_COLOR)
	else:
		verdict.text = "✗ 對 %s 失敗" % str(entry.get("label", ""))
		verdict.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
	status_content.add_child(verdict)
	status_content.add_child(RequirementBar.build_group(engine.result))
	if failure_narrative != "":
		var fn := Label.new()
		fn.text = failure_narrative
		fn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fn.add_theme_font_size_override("font_size", 11)
		fn.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		status_content.add_child(fn)

	## 對話泡:戰後校準(NPC 頭像亮起)
	portrait_pair.set_speaking("npc")
	dialogue_bubble.show_line("父親 — 戰後校準", last_calibration_text)

	## advance 按鈕啟用
	end_strike_button.disabled = true
	advance_button.disabled = false
	advance_button.text = "繼續" if not enemy_queue.is_empty() else "結束連戰"

	## 連戰序列:擊敗 / 逃跑後即時更新(剛擊敗的敵人劃掉)
	_refresh_chain_sequence()


func _refresh_buttons() -> void:
	if engine == null:
		return
	end_strike_button.disabled = not engine.can_commit()
	## advance 按鈕:結算前禁用;結算後由 _after_battle_result 啟用。
	if engine.phase != BattleEngine.Phase.RESOLVED:
		advance_button.disabled = true


func _refresh_header() -> void:
	if inv_title != null:
		inv_title.text = "庫存區(點牌堆 Place 一張) — 卡組共 %d 張" % DeckManager.total_count(deck)


## 右側連戰序列:顯示「此次連戰」的敵人 —— 已擊敗劃掉(✓)、當前(▶)、後續(○)。
## 數量 = 已擊敗數 + enemy_queue 剩餘數;連戰結束 / 非戰鬥時由 _enter_nonbattle_view 收掉。
func _refresh_chain_sequence() -> void:
	if progress_indicator == null:
		return
	var total := chain_defeated_count + enemy_queue.size()
	progress_indicator.setup(total, chain_defeated_count)


# ============================
#  輔助
# ============================

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


func _count_in_strike(card_id: String) -> int:
	if engine == null:
		return 0
	var n := 0
	for c in engine.strike.placed_cards:
		if c.id == card_id:
			n += 1
	for c in engine.strike.locked_cards:
		if c.id == card_id:
			n += 1
	return n


# ============================
#  冒險手記紀錄(M5-S1)
# ============================

## 將本擊已 locked 的卡組成 { card_id: count }(供 BattleRecord 用)。
func _count_strike_cards() -> Dictionary:
	var counts: Dictionary = {}
	if engine == null:
		return counts
	for c in engine.strike.locked_cards:
		counts[c.id] = int(counts.get(c.id, 0)) + 1
	return counts


## 卡組快照 { card_id: count_remaining }。
func _deck_to_dict() -> Dictionary:
	var d: Dictionary = {}
	for entry in deck:
		d[entry.card_id] = entry.count_remaining
	return d


## 寫一筆戰鬥紀錄到冒險手記。entry = enemy_queue[0],呼叫前 queue 未變動。
## failure_outcome = -1 為 OHK;否則為 FailureHandler.FailureOutcome 值。
func _record_battle(entry: Dictionary, result: Dictionary, cal_state: int, failure_outcome: int) -> void:
	var rec := BattleRecord.new()
	var now := int(Time.get_unix_time_from_system())
	rec.battle_id = "%s_c%d_p%d_a%d_%d" % [
		campaign_def.id, chain_index, battle_in_chain_counter, chain_attempt_for_journal, now]
	rec.campaign_id = campaign_def.id
	rec.chain_index = chain_index
	rec.position_in_chain = battle_in_chain_counter
	rec.retry_count = chain_attempt_for_journal
	rec.enemy_template_id = entry["enemy_template"].id
	rec.enemy_instance_id = entry["enemy_instance"].instance_id
	rec.combat_state = entry["enemy_instance"].combat_state
	rec.is_elite = bool(entry.get("is_elite", false))
	## 序章前半:所有 elite 都是失敗造成的;之後若有原生 elite chain 再分流
	rec.is_elite_from_failure = rec.is_elite
	rec.revealed_info = (engine.revealed_info as Dictionary).duplicate(true)
	rec.strike_cards = _count_strike_cards()
	rec.contributions = (result.get("contributions", {}) as Dictionary).duplicate()
	rec.mixed_count = int(result.get("mixed_count", 0))
	rec.ohk = bool(result.get("ohk", false))
	rec.passing_paths = (result.get("passing_paths", []) as Array).duplicate()
	rec.requirements = (result.get("requirements", {}) as Dictionary).duplicate()
	rec.shortfalls = (result.get("shortfalls", {}) as Dictionary).duplicate()
	rec.calibration_state = cal_state
	rec.failure_outcome = failure_outcome
	rec.timestamp = now
	AdventureRecord.save_battle(rec)
	battle_in_chain_counter += 1


## 寫一筆整備節點紀錄。在 SupplyHandler.apply 之後呼叫。
func _record_prep_node(sp: SupplyPhase, summary: Dictionary, before: Dictionary, after: Dictionary) -> void:
	var rec := PrepNodeRecord.new()
	var now := int(Time.get_unix_time_from_system())
	rec.node_id = "%s_supply_%s_%d" % [campaign_def.id, sp.id, now]
	rec.campaign_id = campaign_def.id
	rec.chain_index_completed = chain_index
	rec.supply_id = sp.id
	rec.card_pool_before = before
	rec.card_pool_after = after
	rec.changes = (summary.get("changes", {}) as Dictionary).duplicate()
	rec.timestamp = now
	AdventureRecord.save_prep_node(rec)
