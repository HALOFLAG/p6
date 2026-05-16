extends Control

## 冒險手記 UI(M5-S2,色塊 pass)。
## 對應 戰鬥紀錄系統設計.md §2-§5。
##
## Overlay 模式:由 m2 / hub 等場景 instantiate 加為子節點;「× 關閉」queue_free 即可。
## 內含兩個視圖:MapView(地圖,連戰列 + 重挑疊在下方)+ PageView(雙頁書頁,色塊版)。
## 紀錄資料來自 AdventureRecord autoload(S1 已建)。

## 地圖佈局參數
const MAP_START_X := 120.0
const MAP_START_Y := 16.0
const MAP_NODE_W := 80.0
const MAP_NODE_H := 50.0
const MAP_COL_GAP := 12.0
const MAP_ROW_HEIGHT := 62.0
const MAP_CHAIN_GAP := 16.0
const MAP_PREP_GAP := 24.0

@onready var close_button: Button = $HeaderBar/CloseButton
@onready var map_view: Control = $MapView
@onready var map_nodes_layer: Control = $MapView/MapScroll/MapNodesLayer
@onready var map_empty_hint: Label = $MapView/EmptyHint
@onready var page_view: Control = $PageView
@onready var page_index_label: Label = $PageView/PageHeader/IndexLabel
@onready var back_to_map_btn: Button = $PageView/PageHeader/BackButton
@onready var prev_page_btn: Button = $PageView/PageHeader/PrevButton
@onready var next_page_btn: Button = $PageView/PageHeader/NextButton
@onready var left_page: PanelContainer = $PageView/LeftPage
@onready var right_page: PanelContainer = $PageView/RightPage
@onready var bottom_text_strip: PanelContainer = $PageView/BottomTextStrip

## 合併 + 排序的時間軸 —— 每筆 = { "kind": "battle"|"prep", "record": Resource }
var _timeline: Array = []
var _current_index: int = 0


func _ready() -> void:
	_collect_timeline()
	close_button.pressed.connect(_on_close)
	back_to_map_btn.pressed.connect(_show_map_view)
	prev_page_btn.pressed.connect(_on_prev_page)
	next_page_btn.pressed.connect(_on_next_page)
	_show_map_view()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()


func _collect_timeline() -> void:
	_timeline.clear()
	for r in AdventureRecord.battles:
		_timeline.append({"kind": "battle", "record": r})
	for r in AdventureRecord.prep_nodes:
		_timeline.append({"kind": "prep", "record": r})
	_timeline.sort_custom(func(a, b): return int(a["record"].timestamp) < int(b["record"].timestamp))


# ============ 視圖切換 ============

func _on_close() -> void:
	queue_free()


func _show_map_view() -> void:
	map_view.visible = true
	page_view.visible = false
	_build_map()


func _show_page_view(index: int) -> void:
	if _timeline.is_empty():
		return
	_current_index = clampi(index, 0, _timeline.size() - 1)
	map_view.visible = false
	page_view.visible = true
	_render_page()


func _on_prev_page() -> void:
	if _current_index > 0:
		_show_page_view(_current_index - 1)


func _on_next_page() -> void:
	if _current_index < _timeline.size() - 1:
		_show_page_view(_current_index + 1)


# ============ MapView 建構(連戰列 + 重挑疊在下方)============

func _build_map() -> void:
	for child in map_nodes_layer.get_children():
		child.queue_free()
	if _timeline.is_empty():
		map_empty_hint.visible = true
		map_nodes_layer.custom_minimum_size = Vector2(800, 200)
		return
	map_empty_hint.visible = false

	## 分組:battles_by_chain_retry[chain_index][retry_count] = Array[timeline_idx]
	var battles_by_chain_retry: Dictionary = {}
	var preps_by_chain: Dictionary = {}     ## chain_index_completed → Array[timeline_idx]

	for i in _timeline.size():
		var item: Dictionary = _timeline[i]
		if item["kind"] == "battle":
			var br: BattleRecord = item["record"]
			if not battles_by_chain_retry.has(br.chain_index):
				battles_by_chain_retry[br.chain_index] = {}
			var by_retry: Dictionary = battles_by_chain_retry[br.chain_index]
			if not by_retry.has(br.retry_count):
				by_retry[br.retry_count] = []
			(by_retry[br.retry_count] as Array).append(i)
		else:
			var pr: PrepNodeRecord = item["record"]
			if not preps_by_chain.has(pr.chain_index_completed):
				preps_by_chain[pr.chain_index_completed] = []
			(preps_by_chain[pr.chain_index_completed] as Array).append(i)

	var sorted_chains: Array = battles_by_chain_retry.keys().duplicate()
	sorted_chains.sort()

	var current_y := MAP_START_Y
	var max_x := MAP_START_X
	for ci in sorted_chains:
		var by_retry: Dictionary = battles_by_chain_retry[ci]
		var sorted_retries: Array = by_retry.keys().duplicate()
		sorted_retries.sort()

		var chain_right_x := MAP_START_X
		for retry in sorted_retries:
			var indices: Array = by_retry[retry]
			indices.sort_custom(func(a, b):
				return (_timeline[a]["record"] as BattleRecord).position_in_chain < (_timeline[b]["record"] as BattleRecord).position_in_chain)

			## row label
			var label_text := "連戰 %d" % (int(ci) + 1) if int(retry) == 0 else "↳ 重挑 %d" % int(retry)
			var lbl := Label.new()
			lbl.text = label_text
			lbl.position = Vector2(8, current_y + (MAP_NODE_H - 18) * 0.5)
			lbl.size = Vector2(108, 18)
			lbl.add_theme_color_override("font_color", UiPalette.TEXT_DIM if int(retry) > 0 else UiPalette.TEXT_MAIN)
			lbl.add_theme_font_size_override("font_size", 12)
			map_nodes_layer.add_child(lbl)

			## row connection line(細灰線,從第一個節點到最後一個節點)
			if indices.size() > 1:
				var line := ColorRect.new()
				line.color = UiPalette.PANEL_BORDER
				line.position = Vector2(MAP_START_X + MAP_NODE_W * 0.5, current_y + MAP_NODE_H * 0.5)
				line.size = Vector2(float(indices.size() - 1) * (MAP_NODE_W + MAP_COL_GAP), 2.0)
				line.mouse_filter = Control.MOUSE_FILTER_IGNORE
				map_nodes_layer.add_child(line)

			## nodes
			var x := MAP_START_X
			for idx in indices:
				var node := _make_battle_node(_timeline[idx]["record"] as BattleRecord, idx)
				node.position = Vector2(x, current_y)
				node.size = Vector2(MAP_NODE_W, MAP_NODE_H)
				map_nodes_layer.add_child(node)
				x += MAP_NODE_W + MAP_COL_GAP
			chain_right_x = maxf(chain_right_x, x)
			current_y += MAP_ROW_HEIGHT

		## prep node(s) for this chain
		if preps_by_chain.has(ci):
			var prep_indices: Array = preps_by_chain[ci]
			var px := chain_right_x + MAP_PREP_GAP
			var py := current_y - MAP_ROW_HEIGHT  ## 與最後一列同高
			for idx in prep_indices:
				var node := _make_prep_node(_timeline[idx]["record"] as PrepNodeRecord, idx)
				node.position = Vector2(px, py)
				node.size = Vector2(MAP_NODE_W, MAP_NODE_H)
				map_nodes_layer.add_child(node)
				px += MAP_NODE_W + MAP_COL_GAP
			chain_right_x = maxf(chain_right_x, px)

		max_x = maxf(max_x, chain_right_x)
		current_y += MAP_CHAIN_GAP

	## 更新 scroll 內層尺寸
	map_nodes_layer.custom_minimum_size = Vector2(max_x + 40.0, current_y + 24.0)


func _make_battle_node(record: BattleRecord, timeline_idx: int) -> Control:
	var node := ColorRect.new()
	var color: Color = UiPalette.OK_COLOR if record.ohk else UiPalette.FAIL_COLOR
	if record.is_elite:
		color = color.darkened(0.2)
	node.color = color
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(_on_node_clicked.bind(timeline_idx))
	var tmpl: EnemyTemplate = ResourceLibrary.enemy_template(record.enemy_template_id)
	var short_name := tmpl.template_name if tmpl != null else record.enemy_template_id
	var prefix := "⚠" if record.is_elite else ""
	var suffix := "\n✗" if not record.ohk else ""
	var lbl := Label.new()
	lbl.text = "%s%s%s" % [prefix, short_name, suffix]
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	node.add_child(lbl)
	return node


func _make_prep_node(record: PrepNodeRecord, timeline_idx: int) -> Control:
	var node := ColorRect.new()
	node.color = UiPalette.type_color("flexible")  ## 琥珀
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(_on_node_clicked.bind(timeline_idx))
	var lbl := Label.new()
	lbl.text = "📦\n%s" % record.supply_id
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	node.add_child(lbl)
	return node


## bind(timeline_idx) 在 Godot 4 是 append → 函式簽名 (event, timeline_idx)
func _on_node_clicked(event: InputEvent, timeline_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_page_view(timeline_idx)


# ============ PageView 渲染 ============

func _render_page() -> void:
	if _timeline.is_empty():
		return
	var item: Dictionary = _timeline[_current_index]
	page_index_label.text = "%d / %d" % [_current_index + 1, _timeline.size()]
	prev_page_btn.disabled = _current_index <= 0
	next_page_btn.disabled = _current_index >= _timeline.size() - 1
	_clear_children(left_page)
	_clear_children(right_page)
	_clear_children(bottom_text_strip)
	if item["kind"] == "battle":
		_render_battle_page(item["record"] as BattleRecord)
	else:
		_render_prep_page(item["record"] as PrepNodeRecord)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _render_battle_page(record: BattleRecord) -> void:
	## --- LeftPage:使用的卡 ---
	var lmargin := MarginContainer.new()
	lmargin.add_theme_constant_override("margin_left", 16)
	lmargin.add_theme_constant_override("margin_top", 12)
	lmargin.add_theme_constant_override("margin_right", 16)
	lmargin.add_theme_constant_override("margin_bottom", 12)
	left_page.add_child(lmargin)
	var lvbox := VBoxContainer.new()
	lvbox.add_theme_constant_override("separation", 10)
	lmargin.add_child(lvbox)
	var ltitle := Label.new()
	ltitle.text = "使用的卡 (本擊 %d 張)" % _strike_total(record.strike_cards)
	ltitle.add_theme_color_override("font_color", UiPalette.ACCENT)
	lvbox.add_child(ltitle)
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 8)
	lvbox.add_child(card_row)
	for cid in record.strike_cards:
		var count := int(record.strike_cards[cid])
		var card: CardDefinition = ResourceLibrary.card(cid)
		if card == null:
			continue
		var w := CardWidget.new()
		w.setup(card)
		w.set_subtitle("× %d" % count)
		w.set_state(CardWidget.State.LOCKED)
		card_row.add_child(w)

	## --- RightPage:敵人 + 結果 ---
	var rmargin := MarginContainer.new()
	rmargin.add_theme_constant_override("margin_left", 16)
	rmargin.add_theme_constant_override("margin_top", 12)
	rmargin.add_theme_constant_override("margin_right", 16)
	rmargin.add_theme_constant_override("margin_bottom", 12)
	right_page.add_child(rmargin)
	var rvbox := VBoxContainer.new()
	rvbox.add_theme_constant_override("separation", 10)
	rmargin.add_child(rvbox)

	var tmpl: EnemyTemplate = ResourceLibrary.enemy_template(record.enemy_template_id)
	var enemy_name := tmpl.template_name if tmpl != null else record.enemy_template_id
	var ntitle := Label.new()
	ntitle.text = "敵人:%s%s" % [enemy_name, "  ⚠ 菁英化" if record.is_elite else ""]
	ntitle.add_theme_font_size_override("font_size", 16)
	ntitle.add_theme_color_override("font_color", UiPalette.ACCENT)
	rvbox.add_child(ntitle)

	if tmpl != null:
		var info := Label.new()
		info.text = "類別:%s ・ 戰鬥狀態:%s" % [
			UiPalette.enemy_class_label(tmpl.enemy_class),
			UiPalette.combat_state_label(record.combat_state),
		]
		info.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		info.add_theme_font_size_override("font_size", 12)
		rvbox.add_child(info)
		var weakness_locs: Array[String] = []
		for t in tmpl.weakness_range:
			weakness_locs.append(UiPalette.type_label(t))
		var weak := Label.new()
		weak.text = "弱點範圍:%s" % ", ".join(weakness_locs)
		weak.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
		rvbox.add_child(weak)

	## 已揭露(若有)
	if not record.revealed_info.is_empty():
		var parts: Array[String] = []
		if record.revealed_info.has("enemy_weakness_types"):
			var t_locs: Array[String] = []
			for t in record.revealed_info["enemy_weakness_types"]:
				t_locs.append(UiPalette.type_label(t))
			parts.append("★ 已揭露弱點:%s" % ", ".join(t_locs))
		if record.revealed_info.has("full_requirements"):
			parts.append("★ 已揭露需求")
		if record.revealed_info.has("enemy_class"):
			parts.append("★ 已揭露類別")
		if not parts.is_empty():
			var revealed_lbl := Label.new()
			revealed_lbl.text = "\n".join(parts)
			revealed_lbl.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
			revealed_lbl.add_theme_font_size_override("font_size", 12)
			rvbox.add_child(revealed_lbl)

	## 需求 bar 組(用 record 重組成 result-like dict)
	var result_dict := {
		"ohk": record.ohk,
		"passing_paths": record.passing_paths,
		"contributions": record.contributions,
		"mixed_count": record.mixed_count,
		"requirements": record.requirements,
		"shortfalls": record.shortfalls,
	}
	rvbox.add_child(RequirementBar.build_group(result_dict))

	## 結果橫幅
	var verdict := Label.new()
	if record.ohk:
		var path_locs: Array[String] = []
		for p in record.passing_paths:
			path_locs.append(UiPalette.type_label(p))
		verdict.text = "✓ OHK 成立(%s)" % ", ".join(path_locs)
		verdict.add_theme_color_override("font_color", UiPalette.OK_COLOR)
	else:
		verdict.text = "✗ Underkill"
		verdict.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
	rvbox.add_child(verdict)

	## --- BottomTextStrip:校準 + 失敗 + 時間 ---
	var bmargin := MarginContainer.new()
	bmargin.add_theme_constant_override("margin_left", 16)
	bmargin.add_theme_constant_override("margin_top", 8)
	bmargin.add_theme_constant_override("margin_right", 16)
	bmargin.add_theme_constant_override("margin_bottom", 8)
	bottom_text_strip.add_child(bmargin)
	var bvbox := VBoxContainer.new()
	bvbox.add_theme_constant_override("separation", 4)
	bmargin.add_child(bvbox)
	var cal := Label.new()
	cal.text = "戰後校準狀態:%s" % CalibrationClassifier.state_display(record.calibration_state)
	cal.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	bvbox.add_child(cal)
	if record.failure_outcome != -1:
		var fo := Label.new()
		fo.text = "失敗代價:%s" % _failure_outcome_display(record.failure_outcome)
		fo.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
		bvbox.add_child(fo)
	var ts := Label.new()
	ts.text = "時間:%s  ・ 連戰 %d / 第 %d 場 / 嘗試 %d" % [
		Time.get_datetime_string_from_unix_time(record.timestamp),
		record.chain_index + 1,
		record.position_in_chain + 1,
		record.retry_count + 1,
	]
	ts.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	ts.add_theme_font_size_override("font_size", 11)
	bvbox.add_child(ts)


func _render_prep_page(record: PrepNodeRecord) -> void:
	## --- LeftPage:整備敘事 ---
	var lmargin := MarginContainer.new()
	lmargin.add_theme_constant_override("margin_left", 16)
	lmargin.add_theme_constant_override("margin_top", 12)
	lmargin.add_theme_constant_override("margin_right", 16)
	lmargin.add_theme_constant_override("margin_bottom", 12)
	left_page.add_child(lmargin)
	var lvbox := VBoxContainer.new()
	lvbox.add_theme_constant_override("separation", 10)
	lmargin.add_child(lvbox)
	var ltitle := Label.new()
	ltitle.text = "整備:%s" % record.supply_id
	ltitle.add_theme_color_override("font_color", UiPalette.ACCENT)
	lvbox.add_child(ltitle)
	var sp: SupplyPhase = ResourceLibrary.supply(record.supply_id)
	var narr := Label.new()
	narr.text = sp.narrative if sp != null else "(無敘述)"
	narr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narr.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	lvbox.add_child(narr)

	## --- RightPage:卡組變化 + 前後 ---
	var rmargin := MarginContainer.new()
	rmargin.add_theme_constant_override("margin_left", 16)
	rmargin.add_theme_constant_override("margin_top", 12)
	rmargin.add_theme_constant_override("margin_right", 16)
	rmargin.add_theme_constant_override("margin_bottom", 12)
	right_page.add_child(rmargin)
	var rvbox := VBoxContainer.new()
	rvbox.add_theme_constant_override("separation", 12)
	rmargin.add_child(rvbox)
	var rtitle := Label.new()
	rtitle.text = "卡組變化"
	rtitle.add_theme_color_override("font_color", UiPalette.ACCENT)
	rvbox.add_child(rtitle)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 12)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	rvbox.add_child(chips)
	if record.changes.is_empty():
		var none := Label.new()
		var is_full_restore := sp != null and sp.supply_type == "full_restore"
		none.text = "(卡組恢復至戰前狀態)" if is_full_restore else "(無變化)"
		none.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		chips.add_child(none)
	else:
		for cid in record.changes:
			chips.add_child(_make_supply_chip(cid, int(record.changes[cid])))

	rvbox.add_child(HSeparator.new())
	var total_before := _pool_total(record.card_pool_before)
	var total_after := _pool_total(record.card_pool_after)
	var summary := Label.new()
	summary.text = "整備前 %d 張 → 整備後 %d 張" % [total_before, total_after]
	summary.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	rvbox.add_child(summary)

	## --- BottomTextStrip:時間 ---
	var bmargin := MarginContainer.new()
	bmargin.add_theme_constant_override("margin_left", 16)
	bmargin.add_theme_constant_override("margin_top", 8)
	bmargin.add_theme_constant_override("margin_right", 16)
	bmargin.add_theme_constant_override("margin_bottom", 8)
	bottom_text_strip.add_child(bmargin)
	var bvbox := VBoxContainer.new()
	bmargin.add_child(bvbox)
	var ts := Label.new()
	ts.text = "時間:%s  ・ 完成連戰 %d 後的整備" % [
		Time.get_datetime_string_from_unix_time(record.timestamp),
		record.chain_index_completed + 1,
	]
	ts.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	ts.add_theme_font_size_override("font_size", 11)
	bvbox.add_child(ts)


# ============ 工具 ============

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


func _failure_outcome_display(outcome_int: int) -> String:
	match outcome_int:
		FailureHandler.FailureOutcome.TUTORIAL_RETRY: return "教學重來"
		FailureHandler.FailureOutcome.RABBIT_CHAIN_FLEE: return "兔群連鎖逃走"
		FailureHandler.FailureOutcome.FOX_FLEE: return "狐狸獨自逃走"
		FailureHandler.FailureOutcome.WOLF_ELITE_PROMOTION: return "狼菁英化排末"
		FailureHandler.FailureOutcome.GAME_OVER: return "GAME OVER"
		_: return "(未知 %d)" % outcome_int


func _strike_total(strike_cards: Dictionary) -> int:
	var total := 0
	for v in strike_cards.values():
		total += int(v)
	return total


func _pool_total(pool: Dictionary) -> int:
	var total := 0
	for v in pool.values():
		total += int(v)
	return total
