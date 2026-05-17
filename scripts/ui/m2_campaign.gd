extends Control

## M2 戰役場景。整合連戰結構 + 整備補給 + 失敗代價 + 教學重來 + 自動存檔。
## 對應 開發里程碑.md M2。
##
## 階段五:戰鬥-zone UI 抽到 BattleView(對應 ADR-0002)。
##   host 仍主導 Phase 狀態機(INTRO/PRE_CHAIN/IN_BATTLE/POST_CHAIN/SUPPLY/ENDING/GAME_OVER)、
##   enemy_queue / FailureHandler 派遣 / 整備 / 教學重來 / 紀錄 / 存檔,
##   並擁有跨 phase widgets(portrait_pair / chain_timeline / dialogue_bubble / narrative_box)。
##   戰鬥-zone(pile / strike timeline / status panel / enemy figure / 連戰預覽)由 view 處理。

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

# ============ 戰役狀態 ============
var campaign_def: CampaignDefinition
var chains: Array = []  ## Array[ChainDefinition]
var deck: Array[DeckEntry] = []
var phase: int = Phase.INTRO
var chain_index: int = 0
var enemy_queue: Array[EnemyEncounter] = []  ## 連戰當前 + 後續敵人;typed wrapper(Candidate B Phase A)
var chain_defeated_count: int = 0  ## 此次連戰已擊敗的敵人數(右側連戰序列用)
## 連戰進度狀態序列(2026-05-17)。每一筆 = "defeated" / "escaped"。
## 連戰開始 / 教學重來時清空;OHK 後 append "defeated";失敗逃跑類(FOX_FLEE / WOLF_ELITE_PROMOTION /
## GRAY_RABBIT_CLONE_SPAWN / RABBIT_CHAIN_FLEE)append "escaped"。
## ProgressIndicator 視覺 = 此序列 + ["current"](若 queue 非空)+ ["pending" × queue.size - 1]。
var chain_progress_states: Array[String] = []
var engine: BattleEngine = null
var retry_count: int = 0
var deck_snapshot_for_retry: Dictionary = {}
var supply_applied_history: Array = []
var last_calibration_text: String = ""

## 冒險手記紀錄計數(對應 戰鬥紀錄系統設計.md §6.1)
var chain_attempt_for_journal: int = 0  ## 此連戰的嘗試次數(0=首次,失敗重挑或教學重來+1)
var battle_in_chain_counter: int = 0    ## 此嘗試中已記錄的戰鬥數(每次 _record_battle 後 +1)

## 戰役 attempt 號(M5-S4 / ADR-0006)。`_start_campaign` 開頭從 AdventureRecord derive。
## 每場 BattleRecord / PrepNodeRecord 寫入此值;chain retry 不變動此值(同 attempt 內)。
## SaveSystem.save_at_prep_node payload 帶此值預埋,未來 load 流程實作時讀回。
var current_campaign_attempt: int = 1

# ============ Node refs ============
@onready var stage_zone: Control = $StageZone
@onready var portrait_slot: Control = $StageZone/PortraitSlot
@onready var chain_timeline_slot: Control = $StageZone/ChainTimelineSlot
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

# ============ host 持有的跨 phase widgets ============
var portrait_pair: PortraitPair
var chain_timeline: ChainTimeline
var dialogue_bubble: DialogueBubble

# ============ BattleView(戰鬥-zone UI 控制器)============
var view: BattleView


func _ready() -> void:
	_load_resources()
	_build_overlays()
	_build_view()
	record_button.pressed.connect(_on_record_button_pressed)
	_enter_phase(Phase.INTRO)


## 開冒險手記 overlay(m2 內任何 phase 都可開;色塊 pass 不限制 PLACE/Lock)。
## ADR-0008:elite context-aware 入口已搬到連戰時間軸 elite chip;
## RecordButton 退回單純「開冒險手記主入口」按鈕,進該戰役 MapView。
func _on_record_button_pressed() -> void:
	var journal := ADVENTURE_JOURNAL_SCENE.instantiate()
	journal.initial_campaign_id = CAMPAIGN_ID
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
#  host overlays + BattleView 建立
# ============================

func _build_overlays() -> void:
	portrait_pair = PortraitPair.new()
	portrait_slot.add_child(portrait_pair)
	portrait_pair.set_anchors_preset(Control.PRESET_FULL_RECT)

	chain_timeline = ChainTimeline.new()
	chain_timeline_slot.add_child(chain_timeline)
	chain_timeline.set_anchors_preset(Control.PRESET_FULL_RECT)
	chain_timeline.node_clicked.connect(_on_timeline_node_clicked)
	chain_timeline.elite_lookup_clicked.connect(_on_timeline_elite_lookup)

	## 對話泡 = overlay,放在 StageZone 內
	dialogue_bubble = DialogueBubble.new()
	stage_zone.add_child(dialogue_bubble)
	dialogue_bubble.position = Vector2(110, 8)


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
		"advance_button": advance_button,
		"strike_info_label": strike_info_label,
	})
	## 連戰預覽 — Callable 註冊一次,view 在玩家開啟預覽時 pull;
	## enemy_queue 的多個變動點不必再記得 refresh preview(ADR-0002 §連帶決策)。
	view.set_preview_source(_compute_upcoming_preview)
	view.strike_committed.connect(_on_strike_committed)
	view.advance_pressed.connect(_on_advance_pressed)


## 預覽 source — 回傳「當前敵人之後」每隻敵人的類別色。
func _compute_upcoming_preview() -> Array[Color]:
	var out: Array[Color] = []
	for i in range(1, enemy_queue.size()):
		var enc: EnemyEncounter = enemy_queue[i]
		if enc.enemy_template != null:
			out.append(UiPalette.enemy_class_color(enc.enemy_template.enemy_class))
	return out


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
			## 戰役完成 → 標記完成 + 集中 evaluator 解鎖紀念品(ADR-0005),返回 Hub
			GameState.mark_campaign_complete(campaign_def.id)
			for sid in SouvenirConditions.evaluate_on_campaign_complete(campaign_def.id):
				GameState.unlock_souvenir(sid)
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
	## ADR-0006:從 records derive 新 attempt 號,寫進所有後續 records 與 save payload。
	current_campaign_attempt = AdventureRecord.next_attempt_index_for(campaign_def.id)
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
	## 建立 enemy_queue(typed EnemyEncounter)
	enemy_queue.clear()
	chain_defeated_count = 0
	chain_progress_states.clear()
	battle_in_chain_counter = 0
	for inst_id in chain.enemies:
		var enc := _build_enemy_entry(inst_id, false)
		if enc != null:
			enemy_queue.append(enc)
	_enter_phase(Phase.IN_BATTLE)


## 建一個 EnemyEncounter,組顯示用 label(含菁英 prefix)存進 label_override。
## 找不到 instance → 回 null;caller 必須檢查。
func _build_enemy_entry(instance_id: String, is_elite: bool) -> EnemyEncounter:
	var enc := EnemyEncounter.from_chain(instance_id, is_elite)
	if enc == null:
		return null
	var base_name: String = enc.enemy_instance.display_name
	enc.label_override = ("[菁英化 ⚠] " if is_elite else "") + base_name
	return enc


func _start_next_enemy() -> void:
	if enemy_queue.is_empty():
		_complete_chain()
		return
	## 無卡可出 → GAME OVER 無重挑(2026-05-17)。重挑也會立刻撞同一面牆,所以不給選項。
	if DeckManager.total_count(deck) == 0:
		_trigger_game_over(
			"你的箭袋空了,投石袋也空了 — 沒有資源面對下一個對手。父親在你身邊一言不發。",
			false,
		)
		return
	var enc: EnemyEncounter = enemy_queue[0]
	engine = BattleEngine.new(enc.enemy_instance, enc.enemy_template, deck, ResourceLibrary.cards())
	view.set_engine(engine)
	view.set_encounter(enc, enemy_queue.size())
	portrait_pair.set_speaking("none")
	dialogue_bubble.hide_bubble()
	_refresh_chain_sequence()


## view 結束本擊後:戰後校準分類 → 紀錄 → 派遣失敗 / OHK 後續。
func _on_strike_committed(result: StrikeResult) -> void:
	if engine == null or result == null:
		return
	var enc: EnemyEncounter = enemy_queue[0]
	var is_ohk: bool = result.ohk
	## 戰後校準分類(6 種對話狀態)
	var weakness_range: Array = enc.enemy_template.weakness_range
	var total_committed: int = engine.strike.size()
	var cal_state := CalibrationClassifier.classify(result, weakness_range, total_committed)
	last_calibration_text = _build_calibration_text(cal_state)
	if is_ohk:
		## 先寫手記紀錄(read 當前 enemy_queue[0] / engine 狀態),再做隊伍變動
		_record_battle(enc, result, cal_state, -1)
		enemy_queue.pop_front()
		chain_defeated_count += 1
		chain_progress_states.append("defeated")
		_after_battle_result(true, enc, "")
	else:
		var outcome := FailureHandler.resolve_failure(
			enc.enemy_template,
			enc.enemy_instance,
			enc.is_elite,
			_current_chain().tutorial_retry,
		)
		_record_battle(enc, result, cal_state, int(outcome.get("outcome", -1)))
		_handle_failure(outcome, enc)


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


func _handle_failure(outcome: Dictionary, enc: EnemyEncounter) -> void:
	var narrative: String = outcome.get("narrative", "")
	match outcome.get("outcome", -1):
		FailureHandler.FailureOutcome.TUTORIAL_RETRY:
			_trigger_tutorial_retry(narrative)
		FailureHandler.FailureOutcome.RABBIT_CHAIN_FLEE:
			## 兔子失敗 → 連戰中所有兔子(含當前這隻)逃走移出;非兔子敵人留下,連戰繼續
			var fled := 0
			var remaining: Array[EnemyEncounter] = []
			for e in enemy_queue:
				if e.template_id() == "rabbit":
					fled += 1
				else:
					remaining.append(e)
			enemy_queue = remaining
			for i in fled:  ## 每隻逃走的都算「未成功擊敗」(順序近似,RABBIT_CHAIN_FLEE 目前未啟用)
				chain_progress_states.append("escaped")
			_after_battle_result(false, enc, "%s(共 %d 隻兔子逃走)。連戰繼續。" % [narrative, fled])
		FailureHandler.FailureOutcome.FOX_FLEE:
			enemy_queue.pop_front()
			chain_progress_states.append("escaped")
			_after_battle_result(false, enc, narrative)
		FailureHandler.FailureOutcome.WOLF_ELITE_PROMOTION:
			## 把當前敵人標記菁英並排到 queue 末尾(原狼算「未成功擊敗」,菁英版是新 chip 進 queue)
			enemy_queue.pop_front()
			chain_progress_states.append("escaped")
			var elite_enc := _build_enemy_entry(enc.instance_id(), true)
			if elite_enc != null:
				enemy_queue.append(elite_enc)
			_after_battle_result(false, enc, narrative)
		FailureHandler.FailureOutcome.GRAY_RABBIT_CLONE_SPAWN:
			## 灰兔 default 逃走 + clone 插入 queue[0](當前緊接後位置)
			enemy_queue.pop_front()
			chain_progress_states.append("escaped")
			var clone_id: String = str(outcome.get("clone_instance_id", ""))
			var clone_enc := _build_enemy_entry(clone_id, false)
			if clone_enc != null:
				enemy_queue.insert(0, clone_enc)
			_after_battle_result(false, enc, narrative)
		FailureHandler.FailureOutcome.GAME_OVER:
			_trigger_game_over(narrative)


func _trigger_tutorial_retry(narrative: String) -> void:
	retry_count += 1
	DeckManager.restore(deck, deck_snapshot_for_retry)
	var chain: ChainDefinition = _current_chain()
	enemy_queue.clear()
	chain_defeated_count = 0
	chain_progress_states.clear()
	battle_in_chain_counter = 0
	chain_attempt_for_journal += 1  ## 教學重來也算一次嘗試
	for inst_id in chain.enemies:
		var enc := _build_enemy_entry(inst_id, false)
		if enc != null:
			enemy_queue.append(enc)
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
	## ADR-0006 預埋契約:campaign_attempt 寫進 payload,等未來 load 流程實作讀回(避免 load 被誤判為新 attempt)
	SaveSystem.save_at_prep_node({
		"campaign_id": campaign_def.id,
		"campaign_attempt": current_campaign_attempt,
		"chain_index_completed": chain_index,
		"deck": deck_state,
		"supply_applied_history": supply_applied_history,
	})


# ============================
#  GAME OVER
# ============================

## allow_retry = false 用於「無卡 GAME_OVER」直接呼叫(2026-05-17)— 重挑也會立刻撞同一面牆。
## Safety:就算 caller 傳 true,只要 deck 已空就強制覆寫成 false —— 不然重挑會在 _start_next_enemy
## 立刻觸發無卡 GAME_OVER,連續兩個對話框,UX 很差。
func _trigger_game_over(narrative: String, allow_retry: bool = true) -> void:
	phase = Phase.GAME_OVER
	var can_retry := allow_retry and DeckManager.total_count(deck) > 0
	var buttons: Array = []
	if can_retry:
		buttons.append({ "label": "重新挑戰這場連戰(卡組保留消耗)", "action": "_retry_from_failed_chain" })
	buttons.append({ "label": "接受戰役失敗", "action": "_accept_campaign_failure" })
	_show_narrative(
		"[b][color=#ff7f7f]GAME OVER[/color][/b]\n\n%s" % narrative,
		buttons,
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
	chain_timeline_slot.visible = false  ## 連戰時間軸只在戰鬥中出現
	chain_timeline.clear_timeline()
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
			var chip := SupplyChip.new()
			chip.setup(cid, changes[cid])
			chips.add_child(chip)

	var btn := box.add_button("收下補給 / 繼續")
	btn.pressed.connect(_advance_to_next_chain_or_ending)


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
	chain_timeline_slot.visible = true  ## 連戰時間軸:新連戰開始時出現
	advance_button.disabled = true
	advance_button.text = "繼續"
	dialogue_bubble.hide_bubble()


# ============================
#  Advance(view 通知 host)
# ============================

func _on_advance_pressed() -> void:
	if engine == null or engine.phase != BattleEngine.Phase.RESOLVED:
		return
	if enemy_queue.is_empty():
		_complete_chain()
		return
	_start_next_enemy()


# ============================
#  結算後:host 自訂 status 渲染(取代 view 的通用顯示)
# ============================

## 結算後:狀態面板顯示判定 + 需求 bar(+ 失敗敘述);對話泡浮出戰後校準。
## 此呼叫在 view._refresh_all() 之後(view 已先寫了通用 RESOLVED 顯示),host 覆寫之。
func _after_battle_result(is_ohk: bool, enc: EnemyEncounter, failure_narrative: String) -> void:
	for child in status_content.get_children():
		child.queue_free()
	var verdict := Label.new()
	if is_ohk:
		verdict.text = "✓ 擊敗 %s" % enc.label_override
		verdict.add_theme_color_override("font_color", UiPalette.OK_COLOR)
	else:
		verdict.text = "✗ 對 %s 失敗" % enc.label_override
		verdict.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
	status_content.add_child(verdict)
	status_content.add_child(RequirementBar.build_group(engine.result as StrikeResult))
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

	## advance 按鈕啟用(view 在 RESOLVED 時不主動 enable,host 決定何時啟用 + 文字)
	advance_button.disabled = false
	view.set_advance_label("繼續" if not enemy_queue.is_empty() else "結束連戰")

	## 連戰序列:擊敗 / 逃跑後即時更新(剛擊敗的敵人劃掉)
	_refresh_chain_sequence()


func _refresh_header() -> void:
	if inv_title != null:
		inv_title.text = "庫存區(點牌堆 Place 一張) — 卡組共 %d 張" % DeckManager.total_count(deck)


## 連戰時間軸:顯示「此次連戰」每隻敵人的狀態(ADR-0008)。
## sealed_defeated / sealed_escaped / current / pending / pending_elite 五態,
## 資料源 = 過去 BattleRecord + 未來 enemy_queue 混合。
## 連戰結束 / 非戰鬥時由 _enter_nonbattle_view 清空。
func _refresh_chain_sequence() -> void:
	if chain_timeline == null:
		return
	chain_timeline.refresh(
		CAMPAIGN_ID,
		current_campaign_attempt,
		chain_index,
		chain_attempt_for_journal,
		enemy_queue,
	)


## 連戰時間軸 sealed chip 點擊:跳該 BattleRecord 的 PageView。
func _on_timeline_node_clicked(battle_id: String) -> void:
	var journal := ADVENTURE_JOURNAL_SCENE.instantiate()
	journal.initial_battle_id = battle_id
	add_child(journal)


## 連戰時間軸 pending elite chip 點擊:跳該敵人上次失敗 PageView
## (取代 ADR-0005 RecordButton badge 行為)。
func _on_timeline_elite_lookup(template_id: String) -> void:
	var last_fail: BattleRecord = AdventureRecord.get_last_failure(template_id)
	if last_fail == null:
		return
	var journal := ADVENTURE_JOURNAL_SCENE.instantiate()
	journal.initial_battle_id = last_fail.battle_id
	add_child(journal)


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


## 寫一筆戰鬥紀錄到冒險手記。enc = enemy_queue[0],呼叫前 queue 未變動。
## failure_outcome = -1 為 OHK;否則為 FailureHandler.FailureOutcome 值。
func _record_battle(enc: EnemyEncounter, result: StrikeResult, cal_state: int, failure_outcome: int) -> void:
	var rec := BattleRecord.new()
	var now := int(Time.get_unix_time_from_system())
	rec.battle_id = "%s_att%d_c%d_p%d_a%d_%d" % [
		campaign_def.id, current_campaign_attempt, chain_index, battle_in_chain_counter, chain_attempt_for_journal, now]
	rec.campaign_id = campaign_def.id
	rec.campaign_attempt = current_campaign_attempt
	rec.chain_index = chain_index
	rec.position_in_chain = battle_in_chain_counter
	rec.retry_count = chain_attempt_for_journal
	rec.enemy_template_id = enc.template_id()
	rec.enemy_instance_id = enc.instance_id()
	rec.combat_state = enc.enemy_instance.combat_state
	rec.is_elite = enc.is_elite
	## 序章前半:所有 elite 都是失敗造成的;之後若有原生 elite chain 再分流
	rec.is_elite_from_failure = rec.is_elite
	rec.revealed_info = (engine.revealed_info as Dictionary).duplicate(true)
	rec.strike_cards = _count_strike_cards()
	rec.result = result  ## typed StrikeResult,ADR-0003
	rec.calibration_state = cal_state
	rec.failure_outcome = failure_outcome
	rec.timestamp = now
	AdventureRecord.save_battle(rec)
	battle_in_chain_counter += 1


## 寫一筆整備節點紀錄。在 SupplyHandler.apply 之後呼叫。
func _record_prep_node(sp: SupplyPhase, summary: Dictionary, before: Dictionary, after: Dictionary) -> void:
	var rec := PrepNodeRecord.new()
	var now := int(Time.get_unix_time_from_system())
	rec.node_id = "%s_att%d_supply_%s_%d" % [campaign_def.id, current_campaign_attempt, sp.id, now]
	rec.campaign_id = campaign_def.id
	rec.campaign_attempt = current_campaign_attempt
	rec.chain_index_completed = chain_index
	rec.supply_id = sp.id
	rec.card_pool_before = before
	rec.card_pool_after = after
	rec.changes = (summary.get("changes", {}) as Dictionary).duplicate()
	rec.timestamp = now
	AdventureRecord.save_prep_node(rec)
