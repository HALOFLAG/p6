extends Control

## M2 戰役場景。整合連戰結構 + 整備補給 + 失敗代價 + 教學重來 + 自動存檔。
## 對應 開發里程碑.md M2。

enum Phase {
	INTRO,        ## 戰役開場敘事
	PRE_CHAIN,    ## 連戰前敘事(narrative_pre)
	IN_BATTLE,    ## 戰鬥中
	POST_CHAIN,   ## 連戰後敘事(narrative_post)
	SUPPLY,       ## 整備補給套用
	ENDING,       ## 戰役末尾
	GAME_OVER,    ## 戰役失敗
}

const CAMPAIGN_PATH := "res://resources/campaigns/prologue_first_half.tres"
const CALIBRATION_LINES_PATH := "res://resources/dialogues/calibration_lines.tres"
const HUB_SCENE := "res://scenes/hub.tscn"
const PROLOGUE_SOUVENIR := "mutant_wolf_arm"
const CARD_PATHS := {
	"tool_arrow_pierce": "res://resources/cards/tool_arrow_pierce.tres",
	"tool_stone_impact": "res://resources/cards/tool_stone_impact.tres",
	"intel_weakness": "res://resources/cards/intel_weakness.tres",
}
const ENEMY_INSTANCE_PATHS := {
	"rabbit_default": "res://resources/enemies/rabbit_default.tres",
	"fox_default": "res://resources/enemies/fox_default.tres",
	"wolf_default": "res://resources/enemies/wolf_default.tres",
	"mutant_wolf_default": "res://resources/enemies/mutant_wolf_default.tres",
}
const ENEMY_TEMPLATE_PATHS := {
	"rabbit": "res://resources/enemies/rabbit_template.tres",
	"fox": "res://resources/enemies/fox_template.tres",
	"wolf": "res://resources/enemies/wolf_template.tres",
	"mutant_wolf": "res://resources/enemies/mutant_wolf_template.tres",
}

# ============ 戰役狀態 ============
var campaign_def: CampaignDefinition
var chains: Array = []  ## Array[ChainDefinition]
var supplies: Dictionary = {}  ## { supply_id: SupplyPhase }
var card_library: Dictionary = {}  ## { card_id: CardDefinition }
var enemy_templates: Dictionary = {}  ## { template_id: EnemyTemplate }
var enemy_instances: Dictionary = {}  ## { instance_id: EnemyInstance }
var calibration_lines: CalibrationLines = null

var deck: Array[DeckEntry] = []
var phase: int = Phase.INTRO
var chain_index: int = 0
var enemy_queue: Array = []  ## Array of Dict: { instance_id, enemy_instance, enemy_template, is_elite, label }
var engine: BattleEngine = null
var retry_count: int = 0
var deck_snapshot_for_retry: Dictionary = {}
var supply_applied_history: Array = []
var last_calibration_text: String = ""

# ============ Node refs ============
@onready var header_label: RichTextLabel = $VBox/Header/HeaderLabel
@onready var narrative_panel: PanelContainer = $VBox/NarrativePanel
@onready var narrative_label: RichTextLabel = $VBox/NarrativePanel/NarrativeVBox/NarrativeLabel
@onready var narrative_buttons: HBoxContainer = $VBox/NarrativePanel/NarrativeVBox/NarrativeButtons

@onready var battle_panel: PanelContainer = $VBox/BattlePanel
@onready var battle_enemy_label: RichTextLabel = $VBox/BattlePanel/BattleVBox/EnemySubPanel/EnemyLabel
@onready var battle_revealed_label: RichTextLabel = $VBox/BattlePanel/BattleVBox/RevealedSubPanel/RevealedLabel
@onready var battle_hand_label: RichTextLabel = $VBox/BattlePanel/BattleVBox/HandSubPanel/HandVBox/HandLabel
@onready var battle_hand_buttons: HBoxContainer = $VBox/BattlePanel/BattleVBox/HandSubPanel/HandVBox/HandButtons
@onready var battle_strike_container: VBoxContainer = $VBox/BattlePanel/BattleVBox/StrikeSubPanel/StrikeVBox/StrikeScroll/StrikeContainer
@onready var battle_strike_info: Label = $VBox/BattlePanel/BattleVBox/StrikeSubPanel/StrikeVBox/StrikeInfoLabel
@onready var battle_end_strike_btn: Button = $VBox/BattlePanel/BattleVBox/BattleButtons/EndStrikeButton
@onready var battle_result_label: RichTextLabel = $VBox/BattlePanel/BattleVBox/ResultSubPanel/ResultLabel
@onready var battle_advance_btn: Button = $VBox/BattlePanel/BattleVBox/BattleButtons/AdvanceButton


func _ready() -> void:
	_load_resources()
	_build_hand_buttons()
	battle_end_strike_btn.pressed.connect(_on_end_strike_pressed)
	battle_advance_btn.pressed.connect(_on_advance_pressed)
	_enter_phase(Phase.INTRO)


# ============================
#  載入資源
# ============================

func _load_resources() -> void:
	campaign_def = load(CAMPAIGN_PATH) as CampaignDefinition
	if campaign_def == null:
		push_error("無法載入戰役:" + CAMPAIGN_PATH)
		return
	for path in campaign_def.chain_paths:
		var c := load(path) as ChainDefinition
		if c != null:
			chains.append(c)
	for supply_id in campaign_def.supply_paths:
		var sp := load(campaign_def.supply_paths[supply_id]) as SupplyPhase
		if sp != null:
			supplies[supply_id] = sp
	for card_id in CARD_PATHS:
		var card := load(CARD_PATHS[card_id]) as CardDefinition
		if card != null:
			card_library[card_id] = card
	for tmpl_id in ENEMY_TEMPLATE_PATHS:
		var tmpl := load(ENEMY_TEMPLATE_PATHS[tmpl_id]) as EnemyTemplate
		if tmpl != null:
			enemy_templates[tmpl_id] = tmpl
	for inst_id in ENEMY_INSTANCE_PATHS:
		var inst := load(ENEMY_INSTANCE_PATHS[inst_id]) as EnemyInstance
		if inst != null:
			enemy_instances[inst_id] = inst
	calibration_lines = load(CALIBRATION_LINES_PATH) as CalibrationLines
	if calibration_lines == null:
		push_error("無法載入校準台詞:" + CALIBRATION_LINES_PATH)


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
#  戰役流程
# ============================

func _start_campaign() -> void:
	chain_index = 0
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
	for inst_id in chain.enemies:
		enemy_queue.append(_build_enemy_entry(inst_id, false))
	_enter_phase(Phase.IN_BATTLE)


func _build_enemy_entry(instance_id: String, is_elite: bool) -> Dictionary:
	var inst: EnemyInstance = enemy_instances.get(instance_id, null)
	if inst == null:
		push_error("無此 enemy_instance:" + instance_id)
		return {}
	var tmpl: EnemyTemplate = enemy_templates.get(inst.template_id, null)
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
	engine = BattleEngine.new(entry["enemy_instance"], entry["enemy_template"], deck, card_library)
	_refresh_battle_ui()


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
		enemy_queue.pop_front()
		_after_battle_result(true, entry, "")
	else:
		var outcome := FailureHandler.resolve_failure(
			entry["enemy_template"],
			entry["enemy_instance"],
			entry.get("is_elite", false),
			_current_chain().tutorial_retry,
		)
		_handle_failure(outcome, entry)


func _build_calibration_text(cal_state: int) -> String:
	var key := CalibrationClassifier.state_key(cal_state)
	var display := CalibrationClassifier.state_display(cal_state)
	var line_data: Dictionary = {}
	if calibration_lines != null:
		line_data = calibration_lines.get_line(key)
	var player_line: String = str(line_data.get("player", "(佔位:玩家)"))
	var npc_line: String = str(line_data.get("npc", "(佔位:父親)"))
	return "[b]戰後校準[/b] — %s\n  [玩家] %s\n  [父親] %s" % [display, player_line, npc_line]


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


func _after_battle_result(is_ohk: bool, entry: Dictionary, failure_narrative: String) -> void:
	## 顯示:結算明細 + 勝敗 + 戰後校準對話 → 玩家點「下一個敵人 / 完成連戰」
	var parts: Array[String] = []
	parts.append(_build_resolution_breakdown())
	if is_ohk:
		parts.append("[color=#7fff7f][b]✓ 擊敗 %s[/b][/color]" % entry["label"])
	else:
		parts.append("[color=#ff7f7f][b]✗ 對 %s 失敗[/b][/color]\n%s" % [entry["label"], failure_narrative])
	if last_calibration_text != "":
		parts.append(last_calibration_text)
	battle_result_label.text = "\n\n".join(parts)
	battle_end_strike_btn.disabled = true
	battle_advance_btn.disabled = false
	battle_advance_btn.text = "繼續" if not enemy_queue.is_empty() else "結束連戰"


func _on_advance_pressed() -> void:
	if engine == null or engine.phase != BattleEngine.Phase.RESOLVED:
		return
	if enemy_queue.is_empty():
		_complete_chain()
		return
	_start_next_enemy()


func _trigger_tutorial_retry(narrative: String) -> void:
	retry_count += 1
	DeckManager.restore(deck, deck_snapshot_for_retry)
	var chain: ChainDefinition = _current_chain()
	enemy_queue.clear()
	for inst_id in chain.enemies:
		enemy_queue.append(_build_enemy_entry(inst_id, false))
	EventBus.emit_signal("tutorial_retry_triggered", retry_count)
	## 切到敘事面板顯示重來提示,點繼續再進戰鬥
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
	if not supplies.has(supply_id):
		push_warning("找不到 supply:" + supply_id)
		_advance_to_next_chain_or_ending()
		return
	var sp: SupplyPhase = supplies[supply_id]
	var summary := SupplyHandler.apply(sp, deck, campaign_def.starting_deck)
	supply_applied_history.append(supply_id)
	_save_at_prep_node()
	## 顯示補給內容
	var changes_lines: Array[String] = []
	var changes: Dictionary = summary["changes"]
	for cid in changes:
		var delta: int = changes[cid]
		var card: CardDefinition = card_library.get(cid, null)
		var cn: String = str(cid)
		if card != null:
			cn = card.card_name
		var sign: String = "+" if delta >= 0 else ""
		changes_lines.append("  %s %s%d" % [cn, sign, delta])
	var changes_str := "\n".join(changes_lines) if not changes_lines.is_empty() else "  (無變化)"
	_show_narrative(
		"[b]整備:%s[/b]\n\n%s\n\n卡組變化:\n%s\n\n[color=#888]已存檔[/color]" % [sp.id, sp.narrative, changes_str],
		[{ "label": "繼續", "action": "_advance_to_next_chain_or_ending" }]
	)


func _advance_to_next_chain_or_ending() -> void:
	chain_index += 1
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
		]
	)
	_refresh_header()


func _retry_from_failed_chain() -> void:
	## 重新挑戰失敗的連戰。對應 遊戲核心系統機制.md §7「資源持續縮減模型」。
	## - 卡組:保持失敗時的消耗狀態(不還原、不讀檔)→ 多次重挑卡組持續縮減
	## - 連戰內狀態:重置(enemy_queue 由 _begin_chain 重建,菁英化清除)
	## - 整備補給:不再次觸發
	## - chain_index 已停在失敗的連戰,直接重新進入該連戰
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
#  Narrative UI
# ============================

func _show_narrative(text: String, buttons: Array) -> void:
	narrative_panel.visible = true
	battle_panel.visible = false
	narrative_label.text = text
	for child in narrative_buttons.get_children():
		child.queue_free()
	for btn_data in buttons:
		var btn := Button.new()
		btn.text = btn_data["label"]
		var action: String = btn_data["action"]
		btn.pressed.connect(Callable(self, action))
		narrative_buttons.add_child(btn)


# ============================
#  Battle UI
# ============================

func _show_battle() -> void:
	narrative_panel.visible = false
	battle_panel.visible = true
	battle_result_label.text = ""
	battle_advance_btn.disabled = true
	battle_advance_btn.text = "繼續"


func _build_hand_buttons() -> void:
	for child in battle_hand_buttons.get_children():
		child.queue_free()
	for card_id in CARD_PATHS:
		var card: CardDefinition = card_library.get(card_id, null)
		if card == null:
			continue
		var btn := Button.new()
		btn.text = "Place 「%s」" % card.card_name
		btn.name = "PlaceBtn_" + card_id
		btn.pressed.connect(_on_place_button_pressed.bind(card_id))
		battle_hand_buttons.add_child(btn)


func _on_place_button_pressed(card_id: String) -> void:
	if engine == null:
		return
	if not engine.place_card(card_id):
		battle_result_label.text = "[color=#ff7f7f]無法 Place「%s」— 卡組不足[/color]" % card_library[card_id].card_name
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
	var result := engine.commit_strike()
	_refresh_battle_ui()
	_on_resolution(result)


func _refresh_battle_ui() -> void:
	if engine == null:
		return
	_refresh_battle_enemy()
	_refresh_battle_revealed()
	_refresh_battle_hand()
	_refresh_battle_strike()
	_refresh_battle_result_panel()
	_refresh_battle_buttons()


func _refresh_battle_enemy() -> void:
	var inst: EnemyInstance = engine.enemy_instance
	var tmpl: EnemyTemplate = engine.enemy_template
	var label: String = inst.display_name
	if not enemy_queue.is_empty():
		var entry: Dictionary = enemy_queue[0]
		label = str(entry.get("label", inst.display_name))
	var weakness_loc: Array[String] = []
	for t in tmpl.weakness_range:
		weakness_loc.append(_localize_type(t))
	var weakness_str := ", ".join(weakness_loc)
	var remaining := enemy_queue.size()
	battle_enemy_label.text = "[b]當前目標:[/b]%s\n[color=#888]類別:%s | 弱點範圍:%s | 剩餘敵人:%d[/color]" % [
		label,
		_localize_enemy_class(tmpl.enemy_class),
		weakness_str,
		remaining,
	]


func _refresh_battle_revealed() -> void:
	var info := engine.revealed_info
	if info.is_empty():
		battle_revealed_label.text = "[color=#888]已揭露:(尚未)[/color]"
		return
	var lines: Array[String] = ["[b]已揭露:[/b]"]
	if info.has("enemy_weakness_types"):
		var mode := "深度(當前)" if info.get("weakness_reveal_mode", "") == "depth" else "廣度(連戰剩餘)"
		var types_array: Array = info["enemy_weakness_types"]
		var types_loc: Array[String] = []
		for t in types_array:
			types_loc.append(_localize_type(t))
		lines.append("  弱點類型(%s):%s" % [mode, ", ".join(types_loc)])
	if info.has("enemy_class"):
		lines.append("  類別:%s" % _localize_enemy_class(info["enemy_class"]))
	battle_revealed_label.text = "\n".join(lines)


func _refresh_battle_hand() -> void:
	var lines: Array[String] = ["[b]卡組(剩餘張數):[/b]"]
	for entry in deck:
		var card: CardDefinition = card_library.get(entry.card_id, null)
		var dn: String = entry.card_id
		var contrib_str := "(無貢獻)"
		if card != null:
			dn = card.card_name
			contrib_str = _format_contribution(card.contribution)
		var in_strike := _count_in_strike(entry.card_id)
		lines.append("  %s × %d  (本擊中:%d)  [color=#888]%s[/color]" % [dn, entry.count_remaining, in_strike, contrib_str])
	battle_hand_label.text = "\n".join(lines)
	## 更新 Place 按鈕
	for card_id in CARD_PATHS:
		var btn: Button = battle_hand_buttons.get_node_or_null("PlaceBtn_" + card_id)
		if btn == null:
			continue
		var entry := DeckManager.find_entry(deck, card_id)
		var in_strike := _count_in_strike(card_id)
		var available := 0
		if entry != null:
			available = entry.count_remaining - in_strike
		btn.disabled = engine.phase != BattleEngine.Phase.PLACE or available <= 0


func _refresh_battle_strike() -> void:
	for child in battle_strike_container.get_children():
		child.queue_free()
	if engine.strike.placed_cards.is_empty() and engine.strike.locked_cards.is_empty():
		var lbl := Label.new()
		lbl.text = "  (尚未 Place 任何卡)"
		lbl.modulate = Color(0.6, 0.6, 0.6)
		battle_strike_container.add_child(lbl)
	## 疊放 locked none 類
	var locked_groups := _group_pool_cards(engine.strike.locked_cards)
	for cid in locked_groups:
		var info: Dictionary = locked_groups[cid]
		battle_strike_container.add_child(_make_strike_row("[Locked]", info["card"], info["count"], -1, -1))
	for i in engine.strike.locked_cards.size():
		var c: CardDefinition = engine.strike.locked_cards[i]
		if c.lock_class == "none":
			continue
		battle_strike_container.add_child(_make_strike_row("[Locked]", c, 1, -1, -1))
	## 疊放 placed none 類
	var placed_groups := _group_pool_cards(engine.strike.placed_cards)
	for cid in placed_groups:
		var info: Dictionary = placed_groups[cid]
		battle_strike_container.add_child(_make_strike_row("[Place]", info["card"], info["count"], info["last_index"], -1))
	for i in engine.strike.placed_cards.size():
		var c: CardDefinition = engine.strike.placed_cards[i]
		if c.lock_class == "none":
			continue
		battle_strike_container.add_child(_make_strike_row("[Place]", c, 1, i, i))
	battle_strike_info.text = "本擊張數:%d  (本擊上限暫時停用)" % engine.strike.size()


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


func _make_strike_row(prefix: String, card: CardDefinition, count: int, unplace_idx: int, lock_idx: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	var count_str := " × %d" % count if count > 1 else ""
	lbl.text = "%s %s%s  (%s)" % [prefix, card.card_name, count_str, _format_contribution(card.contribution)]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	if engine.phase == BattleEngine.Phase.PLACE:
		if unplace_idx >= 0:
			var unplace_btn := Button.new()
			unplace_btn.text = "−1" if count > 1 else "Unplace"
			unplace_btn.pressed.connect(_on_unplace_button_pressed.bind(unplace_idx))
			row.add_child(unplace_btn)
		if lock_idx >= 0:
			var lock_btn := Button.new()
			var hint := " (揭露弱點)" if card.lock_class == "optional" else " (必須)"
			lock_btn.text = "Lock 此卡" + hint
			lock_btn.pressed.connect(_on_lock_button_pressed.bind(lock_idx))
			row.add_child(lock_btn)
	return row


func _refresh_battle_result_panel() -> void:
	if engine.phase != BattleEngine.Phase.RESOLVED:
		battle_result_label.text = "[color=#888]按下「結束本擊」後顯示結算結果。[/color]"
		return
	## 結算後完整顯示由 _after_battle_result 接管(含校準對話);此處僅在 RESOLVED
	## 但尚未呼叫 _after_battle_result 的瞬間提供基礎明細
	battle_result_label.text = _build_resolution_breakdown()


## 建立結算明細字串(各類型 actual/required + OHK 判定)。
func _build_resolution_breakdown() -> String:
	var r: Dictionary = engine.result
	var contributions: Dictionary = r.get("contributions", {})
	var mixed_count: int = r.get("mixed_count", 0)
	var requirements: Dictionary = r.get("requirements", {})
	var passing: Array = r.get("passing_paths", [])
	var ohk: bool = r.get("ohk", false)
	var lines: Array[String] = ["[b]結算:[/b]"]
	for type_key in requirements:
		var required: int = requirements[type_key]
		var actual: int = mixed_count if type_key == "mixed" else contributions.get(type_key, 0)
		var hit := actual >= required
		var prefix := "  [color=#7fff7f]✓[/color]" if hit else "  [color=#ff7f7f]✗[/color]"
		lines.append("%s %s:%d / %d" % [prefix, _localize_type(type_key), actual, required])
	if ohk:
		var loc_paths: Array[String] = []
		for p in passing:
			loc_paths.append(_localize_type(p))
		lines.append("[color=#7fff7f][b]✓ OHK 成立[/b]  達標路徑:%s[/color]" % ", ".join(loc_paths))
	else:
		lines.append("[color=#ff7f7f][b]✗ Underkill[/b]  所有路徑皆未達標[/color]")
	return "\n".join(lines)


func _refresh_battle_buttons() -> void:
	battle_end_strike_btn.disabled = not engine.can_commit()
	## advance 按鈕在結算後由 _after_battle_result 啟用;結算前禁用
	if engine.phase != BattleEngine.Phase.RESOLVED:
		battle_advance_btn.disabled = true


func _refresh_header() -> void:
	var phase_label := _localize_phase(phase)
	var chain_label := "—"
	if chain_index >= 0 and chain_index < chains.size():
		chain_label = "%d / %d  (%s)" % [chain_index + 1, chains.size(), chains[chain_index].display_label]
	header_label.text = "[b]%s[/b]  |  連戰 %s  |  狀態:%s  |  卡組總張數:%d" % [
		campaign_def.campaign_name,
		chain_label,
		phase_label,
		DeckManager.total_count(deck),
	]


# ============================
#  輔助
# ============================

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


func _format_contribution(contrib: Dictionary) -> String:
	if contrib.is_empty():
		return "(無貢獻)"
	var parts: Array[String] = []
	for k in contrib:
		parts.append("+%d %s" % [contrib[k], _localize_type(k)])
	return ", ".join(parts)


func _localize_type(type_key: String) -> String:
	match type_key:
		"impact": return "衝擊"
		"pierce": return "穿刺"
		"burn": return "燃燒"
		"mixed": return "混合"
		"flexible": return "任意"
		"generic": return "通用"
		_: return type_key


func _localize_enemy_class(cls: String) -> String:
	match cls:
		"rabbit": return "兔子型"
		"wolf": return "狼型"
		"leopard": return "豹型"
		"bear": return "熊型"
		_: return cls


func _localize_phase(p: int) -> String:
	match p:
		Phase.INTRO: return "戰役開場"
		Phase.PRE_CHAIN: return "連戰前"
		Phase.IN_BATTLE: return "戰鬥中"
		Phase.POST_CHAIN: return "連戰結束"
		Phase.SUPPLY: return "整備補給"
		Phase.ENDING: return "戰役完成"
		Phase.GAME_OVER: return "GAME OVER"
		_: return "?"
