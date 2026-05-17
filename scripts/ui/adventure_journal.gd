extends Control

## 冒險手記 UI(M5-S2,色塊 pass)。
## 對應 戰鬥紀錄系統設計.md §2-§5。
##
## Overlay 模式:由 m2 / hub 等場景 instantiate 加為子節點;「× 關閉」queue_free 即可。
## 三個視圖(2026-05-17 加 WorldView):
##   - WorldView(跨戰役入口,從 Hub 進)
##   - MapView(某個戰役的連戰列 + 重挑疊在下方)
##   - PageView(雙頁書頁,色塊版)
## 紀錄資料來自 AdventureRecord autoload(S1 已建)。
##
## 入口差異:
##   - Hub 進來(JournalBook 點擊):initial_campaign_id 留空 → 顯示 WorldView
##   - m2 進來(RecordButton 點擊):caller 設 initial_campaign_id 為當前戰役 id →
##     直接顯示 MapView(該戰役),省一層;BackButton「← 返回世界」仍可進 WorldView 看其他戰役

## 地圖佈局參數
const MAP_START_X := 120.0
const MAP_START_Y := 16.0
const MAP_NODE_W := 80.0
const MAP_NODE_H := 50.0
const MAP_COL_GAP := 12.0
const MAP_ROW_HEIGHT := 62.0
const MAP_CHAIN_GAP := 16.0
const MAP_PREP_GAP := 24.0

## 主軸佈局參數(ADR-0004 Sub-stage 3a)
const MAIN_AXIS_X := 160.0                ## 主軸節點中心 X
const MAIN_AXIS_START_Y := 30.0           ## 第一個主軸節點中心 Y
const MAIN_NODE_RADIUS := 14.0            ## 可點節點半徑(敘事 / 整備)
const MAIN_NODE_RADIUS_CHAIN := 8.0       ## 連戰主節點半徑 — 縮小作為「不可點」affordance(2026-05-17)
const MAIN_NODE_SPACING := 70.0           ## 主軸節點 center-to-center 間距
const MAIN_AXIS_LINE_WIDTH := 2.0
const MAIN_LABEL_X := 12.0                ## 節點 label 左邊起點
const MAIN_LABEL_WIDTH := 132.0           ## 節點 label 寬度(留給 MAIN_AXIS_X 之前的空間)

## 主軸節點色(ADR-0004 §1 各類型)
const MAIN_NODE_COLOR_NARRATIVE := Color("2a2a2e")  ## 戰役開始 / 結局敘事
const MAIN_NODE_COLOR_CHAIN := Color("c8503c")      ## 連戰
const MAIN_NODE_COLOR_PREP := Color("4f8c5e")       ## 整備

## NarrativePage 共用版型(ADR-0004 Sub-stage 3d)
## 場景插圖區色塊(色塊 pass placeholder;美術 pass 換真插圖)
const SCENE_COLOR_INTRO := Color("3a4a6e")        ## 暗藍 — 戰役入口
const SCENE_COLOR_ENDING := Color("4a2a2a")       ## 暗紅 — 結局
const SCENE_COLOR_PREP_FULL := Color("4a6a3a")    ## 草綠 — full_restore(rest 整備)
const SCENE_COLOR_PREP_ADD := Color("6a5a3a")     ## 棕綠 — add_cards 整備
const SCENE_BLOCK_HEIGHT := 180.0                 ## 右上場景區固定高(下方留給獲得區)

## 戰鬥分支佈局(ADR-0004 Sub-stage 3b)
const BRANCH_X_OFFSET := 40.0            ## 主軸 → 第一個分支節點 center 水平距離
const BRANCH_NODE_RADIUS := 10.0         ## 分支戰鬥節點半徑
const BRANCH_NODE_SPACING_X := 32.0      ## 分支節點 center-to-center 水平
const BRANCH_ROW_SPACING_Y := 32.0       ## 重挑列 center-to-center 垂直
const BRANCH_LABEL_GAP := 8.0            ## 列尾 old/new label 跟最後節點水平距
const BRANCH_OLD_ALPHA := 0.5            ## old 列整列透明度
const BRANCH_NEW_ALPHA := 1.0            ## new 列飽和

## WorldView campaign card 尺寸
const WORLD_CARD_SIZE := Vector2(240, 200)

@onready var close_button: Button = $HeaderBar/CloseButton
@onready var world_view: Control = $WorldView
@onready var world_campaigns_layer: HBoxContainer = $WorldView/WorldCampaignsLayer
@onready var map_view: Control = $MapView
@onready var map_campaign_label: Label = $MapView/MapHeader/MapCampaignLabel
@onready var back_to_world_btn: Button = $MapView/MapHeader/BackToWorldButton
@onready var map_nodes_layer: Control = $MapView/MapScroll/MapNodesLayer
@onready var map_empty_hint: Label = $MapView/EmptyHint
@onready var page_view: Control = $PageView
@onready var page_index_label: Label = $PageView/PageHeader/IndexLabel
@onready var back_to_map_btn: Button = $PageView/PageHeader/BackButton
@onready var prev_page_btn: Button = $PageView/PageHeader/PrevButton
@onready var next_page_btn: Button = $PageView/PageHeader/NextButton
@onready var left_page: PanelContainer = $PageView/LeftPage
@onready var right_page: PanelContainer = $PageView/RightPage

## Caller 在 add_child 前 set 此屬性 = 直接進 MapView 該戰役;留空 = 進 WorldView。
var initial_campaign_id: String = ""

## 合併 + 排序的時間軸 —— 每筆 = { "kind": "battle"|"prep", "record": Resource }
## 內容隨 _selected_campaign_id 篩選(WorldView 階段為空,MapView 時為該戰役紀錄)
var _timeline: Array = []
var _current_index: int = 0
var _selected_campaign_id: String = ""  ## 目前 MapView / PageView 顯示的戰役


func _ready() -> void:
	close_button.pressed.connect(_on_close)
	back_to_world_btn.pressed.connect(_show_world_view)
	back_to_map_btn.pressed.connect(_back_to_current_map)
	prev_page_btn.pressed.connect(_on_prev_page)
	next_page_btn.pressed.connect(_on_next_page)
	## 入口差異
	if initial_campaign_id != "":
		_show_map_view(initial_campaign_id)
	else:
		_show_world_view()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()


## 篩選並組 _timeline。campaign_id 空字串 = 全部(WorldView 不該呼叫此函式,但容錯處理)。
func _collect_timeline_for(campaign_id: String) -> void:
	_timeline.clear()
	for r in AdventureRecord.battles:
		if campaign_id == "" or r.campaign_id == campaign_id:
			_timeline.append({"kind": "battle", "record": r})
	for r in AdventureRecord.prep_nodes:
		if campaign_id == "" or r.campaign_id == campaign_id:
			_timeline.append({"kind": "prep", "record": r})
	_timeline.sort_custom(func(a, b): return int(a["record"].timestamp) < int(b["record"].timestamp))


# ============ 視圖切換 ============

func _on_close() -> void:
	queue_free()


func _show_world_view() -> void:
	world_view.visible = true
	map_view.visible = false
	page_view.visible = false
	_build_world()


## 切到指定 campaign 的 MapView。campaign_id 必填。
func _show_map_view(campaign_id: String) -> void:
	_selected_campaign_id = campaign_id
	_collect_timeline_for(campaign_id)
	world_view.visible = false
	map_view.visible = true
	page_view.visible = false
	## MapHeader campaign label
	var camp_def: CampaignDefinition = ResourceLibrary.campaign(campaign_id)
	map_campaign_label.text = camp_def.campaign_name if camp_def != null else campaign_id
	_build_map()


## PageView BackButton callback:回到目前的 MapView(用 _selected_campaign_id)。
func _back_to_current_map() -> void:
	_show_map_view(_selected_campaign_id)


func _show_page_view(index: int) -> void:
	if _timeline.is_empty():
		return
	_current_index = clampi(index, 0, _timeline.size() - 1)
	world_view.visible = false
	map_view.visible = false
	page_view.visible = true
	_render_page()


func _on_prev_page() -> void:
	if _current_index > 0:
		_show_page_view(_current_index - 1)


func _on_next_page() -> void:
	if _current_index < _timeline.size() - 1:
		_show_page_view(_current_index + 1)


# ============ WorldView 建構(跨戰役入口)============

## 列出 ResourceLibrary 已註冊的所有戰役;每個 = 一張可點 card。
## 狀態:已完成(GameState.is_campaign_complete)/ 有紀錄但未完成 / 從未挑戰。
func _build_world() -> void:
	for child in world_campaigns_layer.get_children():
		child.queue_free()
	var campaigns: Dictionary = ResourceLibrary.campaigns()
	if campaigns.is_empty():
		var none := Label.new()
		none.text = "(尚未註冊任何戰役)"
		none.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		world_campaigns_layer.add_child(none)
		return
	for cid in campaigns:
		var camp: CampaignDefinition = campaigns[cid]
		world_campaigns_layer.add_child(_make_world_campaign_card(camp))


func _make_world_campaign_card(camp: CampaignDefinition) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = WORLD_CARD_SIZE
	var is_complete: bool = GameState.is_campaign_complete(camp.id)
	var has_records: bool = not AdventureRecord.get_battles_by_campaign(camp.id).is_empty()
	var border_color: Color = UiPalette.OK_COLOR if is_complete else (UiPalette.ACCENT if has_records else UiPalette.PANEL_BORDER)
	card.add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG_LIGHT, border_color, 2, 4))
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	var name_lbl := Label.new()
	name_lbl.text = camp.campaign_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	name_lbl.add_theme_font_size_override("font_size", 16)
	vb.add_child(name_lbl)

	var status_lbl := Label.new()
	if is_complete:
		status_lbl.text = "✓ 已通過"
		status_lbl.add_theme_color_override("font_color", UiPalette.OK_COLOR)
	elif has_records:
		status_lbl.text = "有紀錄 — 尚未通過"
		status_lbl.add_theme_color_override("font_color", UiPalette.ACCENT)
	else:
		status_lbl.text = "從未挑戰"
		status_lbl.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(status_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	var hint := Label.new()
	hint.text = "(點擊翻看紀錄)" if has_records else "(尚無紀錄)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 11)
	vb.add_child(hint)

	## 整張卡 = 點擊區
	card.gui_input.connect(_on_world_card_clicked.bind(camp.id))
	return card


func _on_world_card_clicked(event: InputEvent, campaign_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_map_view(campaign_id)


# ============ MapView 建構 ============
# ADR-0004 Sub-stage 3a:主軸結構(只畫走過的;連戰主節點不可點;敘事/整備可點)
# Sub-stage 3b 將在主軸連戰節點旁展開戰鬥分支;3c-3e 補視覺/版型/動態尺寸。

func _build_map() -> void:
	for child in map_nodes_layer.get_children():
		child.queue_free()

	var camp_def: CampaignDefinition = ResourceLibrary.campaign(_selected_campaign_id)
	if camp_def == null:
		map_empty_hint.text = "(找不到戰役定義)"
		map_empty_hint.visible = true
		map_nodes_layer.custom_minimum_size = Vector2(800, 200)
		return

	## 推導「走過」狀態(ADR-0004 §1 嚴格走過版)+ 戰鬥分組(3b)
	var walked_chains: Dictionary = {}   ## chain_index → true
	var walked_preps: Dictionary = {}    ## chain_index_completed → timeline_idx
	## 戰鬥分支分組:chain_index → { retry_count → Array[timeline_idx] (按 position_in_chain 排序) }
	var chain_rows: Dictionary = {}
	for i in _timeline.size():
		var item: Dictionary = _timeline[i]
		if item["kind"] == "battle":
			var br: BattleRecord = item["record"]
			walked_chains[br.chain_index] = true
			if not chain_rows.has(br.chain_index):
				chain_rows[br.chain_index] = {}
			var rows_for_chain: Dictionary = chain_rows[br.chain_index]
			if not rows_for_chain.has(br.retry_count):
				rows_for_chain[br.retry_count] = []
			(rows_for_chain[br.retry_count] as Array).append(i)
		else:
			walked_preps[(item["record"] as PrepNodeRecord).chain_index_completed] = i

	## 各列按 position_in_chain 排序
	for ci in chain_rows:
		var rows_dict: Dictionary = chain_rows[ci]
		for retry in rows_dict:
			(rows_dict[retry] as Array).sort_custom(func(a: int, b: int) -> bool:
				return (_timeline[a]["record"] as BattleRecord).position_in_chain < (_timeline[b]["record"] as BattleRecord).position_in_chain)

	## 各 chain 的「new 列」= max retry_count
	var chain_new_retry: Dictionary = {}
	for ci in chain_rows:
		var max_r := 0
		for r in chain_rows[ci]:
			if int(r) > max_r:
				max_r = int(r)
		chain_new_retry[ci] = max_r

	var is_intro_walked: bool = walked_chains.has(0)
	var is_ending_walked: bool = GameState.is_campaign_complete(_selected_campaign_id)

	## 組主軸節點序列(只放走過的)
	var main_nodes: Array = []
	if is_intro_walked:
		main_nodes.append({ "kind": "narrative_intro", "campaign": camp_def })
	for ci in camp_def.chain_ids.size():
		if walked_chains.has(ci):
			var chain: ChainDefinition = ResourceLibrary.chain(camp_def.chain_ids[ci])
			main_nodes.append({ "kind": "chain", "chain_index": ci, "chain": chain })
		if walked_preps.has(ci):
			main_nodes.append({ "kind": "prep", "chain_index_completed": ci, "timeline_idx": int(walked_preps[ci]) })
	if is_ending_walked:
		main_nodes.append({ "kind": "narrative_ending", "campaign": camp_def })

	if main_nodes.is_empty():
		map_empty_hint.text = "(%s — 尚無紀錄,先去打場仗吧)" % camp_def.campaign_name
		map_empty_hint.visible = true
		map_nodes_layer.custom_minimum_size = Vector2(800, 200)
		return
	map_empty_hint.visible = false

	## Layout 主軸節點 + label;連戰節點要連帶展開戰鬥分支(3b)。
	## 各節點以 center_y 對齊主軸;連戰主節點對齊分支第一列(ADR-0004 §8)。
	var center_y := MAIN_AXIS_START_Y + MAIN_NODE_RADIUS  ## 第一個節點 center
	var first_center_y: float = center_y
	var last_center_y: float = center_y
	for i in main_nodes.size():
		var data: Dictionary = main_nodes[i]
		var radius: float = _main_axis_node_radius(data["kind"])
		var node := _make_main_axis_node(data)
		node.position = Vector2(MAIN_AXIS_X - radius, center_y - radius)
		node.size = Vector2(radius * 2, radius * 2)
		map_nodes_layer.add_child(node)
		## label 在節點左邊,對齊節點 center_y
		var lbl := Label.new()
		lbl.text = _main_axis_label_text(data)
		lbl.position = Vector2(MAIN_LABEL_X, center_y - 9)
		lbl.size = Vector2(MAIN_LABEL_WIDTH, 18)
		lbl.add_theme_color_override("font_color", UiPalette.TEXT_MAIN if data["kind"] != "chain" else UiPalette.TEXT_DIM)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_nodes_layer.add_child(lbl)
		if i == 0:
			first_center_y = center_y

		## 連戰節點要展開戰鬥分支 + 調整下一節點 Y 步距
		var next_step_y: float = MAIN_NODE_SPACING
		if data["kind"] == "chain":
			var ci: int = int(data["chain_index"])
			if chain_rows.has(ci):
				var rows_dict: Dictionary = chain_rows[ci]
				var sorted_retries: Array = rows_dict.keys().duplicate()
				sorted_retries.sort()
				var new_retry: int = chain_new_retry[ci]
				for j in sorted_retries.size():
					var retry: int = int(sorted_retries[j])
					var row_y: float = center_y + j * BRANCH_ROW_SPACING_Y
					_build_branch_row(rows_dict[retry], row_y, retry == new_retry)
				## next step 要超過分支區
				if sorted_retries.size() > 1:
					next_step_y = (sorted_retries.size() - 1) * BRANCH_ROW_SPACING_Y + MAIN_NODE_SPACING
		last_center_y = center_y
		center_y += next_step_y

	## 補回原本 y 變數以維持下方 minimum_size 計算邏輯
	var first_node_y: float = first_center_y
	var last_node_y: float = last_center_y
	var y: float = last_center_y + MAIN_NODE_RADIUS

	## 動態 content width(3e):依最長分支列計算 + padding。
	var max_row_len: int = 0
	for ci in chain_rows:
		for retry in chain_rows[ci]:
			var row_size: int = (chain_rows[ci][retry] as Array).size()
			if row_size > max_row_len:
				max_row_len = row_size
	var content_width: float = 800.0  ## 最小寬(沒分支時也至少這個寬)
	if max_row_len > 0:
		var row_extent: float = BRANCH_X_OFFSET + max(0.0, float(max_row_len - 1) * BRANCH_NODE_SPACING_X) + BRANCH_LABEL_GAP + 60.0
		content_width = max(content_width, MAIN_AXIS_X + row_extent)

	## 主軸垂直線(畫在節點之後但要在 z-order 下方 → 用 move_child 移到 index 0)
	if main_nodes.size() >= 2:
		var axis_line := ColorRect.new()
		axis_line.color = UiPalette.PANEL_BORDER
		axis_line.position = Vector2(MAIN_AXIS_X - MAIN_AXIS_LINE_WIDTH * 0.5, first_node_y)
		axis_line.size = Vector2(MAIN_AXIS_LINE_WIDTH, last_node_y - first_node_y)
		axis_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_nodes_layer.add_child(axis_line)
		map_nodes_layer.move_child(axis_line, 0)  ## 移到 z-order 最底層 → 節點在線上方

	## 更新 scroll 內層尺寸(3e 動態化)— 寬依 max_row_len 計算、高依實際排到的 y
	map_nodes_layer.custom_minimum_size = Vector2(content_width, y + 40)


## 建一個主軸節點(色塊矩形;敘事/整備可點,連戰純結構不可點)。
func _make_main_axis_node(data: Dictionary) -> Control:
	var node := ColorRect.new()
	node.color = _main_axis_node_color(data["kind"])
	match data["kind"]:
		"narrative_intro", "narrative_ending":
			node.mouse_filter = Control.MOUSE_FILTER_STOP
			node.gui_input.connect(_on_main_axis_narrative_clicked.bind(data))
		"prep":
			node.mouse_filter = Control.MOUSE_FILTER_STOP
			node.gui_input.connect(_on_main_axis_prep_clicked.bind(int(data["timeline_idx"])))
		"chain":
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE  ## ADR-0004 §2 連戰主節點不可點
	return node


func _main_axis_node_color(kind: String) -> Color:
	match kind:
		"narrative_intro", "narrative_ending":
			return MAIN_NODE_COLOR_NARRATIVE
		"chain":
			return MAIN_NODE_COLOR_CHAIN
		"prep":
			return MAIN_NODE_COLOR_PREP
		_:
			return UiPalette.TEXT_DIM


## 主軸節點半徑 — 連戰主節點縮小作為「不可點」affordance(2026-05-17 加 chain affordance)
func _main_axis_node_radius(kind: String) -> float:
	match kind:
		"chain":
			return MAIN_NODE_RADIUS_CHAIN
		_:
			return MAIN_NODE_RADIUS


## 建一列戰鬥分支(3b)。 indices 已按 position_in_chain 排序;is_new 決定透明度 + 列尾標記。
## 連線:主軸 → 第一個節點(水平實線)+ 各節點之間(水平實線)。
## 3c 會加 X/框/箭頭等視覺增強;3b 純展開結構 + alpha + old/new label。
func _build_branch_row(indices: Array, row_center_y: float, is_new: bool) -> void:
	var alpha: float = BRANCH_NEW_ALPHA if is_new else BRANCH_OLD_ALPHA
	if indices.is_empty():
		return

	## 主軸 → 第一個分支節點 連線(水平實線)
	var first_x: float = MAIN_AXIS_X + BRANCH_X_OFFSET
	var stub := ColorRect.new()
	stub.color = UiPalette.PANEL_BORDER
	stub.position = Vector2(MAIN_AXIS_X, row_center_y - 1)
	stub.size = Vector2(first_x - MAIN_AXIS_X, 2)
	stub.modulate.a = alpha
	stub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_nodes_layer.add_child(stub)

	## 各節點 + 節點間連線
	## 用 node_centers[i] 記下每節點 center,3c 箭頭(SPAWN/PROMOTION)第二趟 loop 用到。
	var node_centers: Array = []
	var last_center_x: float = first_x
	for i in indices.size():
		var idx: int = int(indices[i])
		var node_center_x: float = first_x + i * BRANCH_NODE_SPACING_X
		if i > 0:
			var hconn := ColorRect.new()
			hconn.color = UiPalette.PANEL_BORDER
			hconn.position = Vector2(last_center_x, row_center_y - 1)
			hconn.size = Vector2(BRANCH_NODE_SPACING_X, 2)
			hconn.modulate.a = alpha
			hconn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			map_nodes_layer.add_child(hconn)
		var rec: BattleRecord = _timeline[idx]["record"]
		var node := _make_branch_battle_node(rec, idx)
		node.position = Vector2(node_center_x - BRANCH_NODE_RADIUS, row_center_y - BRANCH_NODE_RADIUS)
		node.size = Vector2(BRANCH_NODE_RADIUS * 2, BRANCH_NODE_RADIUS * 2)
		node.modulate.a = alpha
		map_nodes_layer.add_child(node)
		## SPAWN / PROMOTION:加外框(節點之後加,確保框在節點旁邊但 mouse_filter IGNORE 不擋 click)
		if _node_needs_frame(rec.failure_outcome):
			var frame := _make_node_frame(node_center_x, row_center_y)
			frame.modulate.a = alpha
			map_nodes_layer.add_child(frame)
		node_centers.append(Vector2(node_center_x, row_center_y))
		last_center_x = node_center_x

	## 第二趟:SPAWN / PROMOTION 畫弧形箭頭到目標節點(同列內)
	for i in indices.size():
		var rec: BattleRecord = _timeline[indices[i]]["record"]
		if not _node_needs_frame(rec.failure_outcome):
			continue
		var target_i: int = _find_arrow_target_index(indices, i)
		if target_i < 0:
			continue
		_draw_branch_arrow(node_centers[i], node_centers[target_i], alpha)

	## 列尾 old/new 文字
	var lbl := Label.new()
	lbl.text = "new" if is_new else "old"
	lbl.position = Vector2(last_center_x + BRANCH_LABEL_GAP, row_center_y - 9)
	lbl.size = Vector2(40, 18)
	lbl.add_theme_color_override("font_color", UiPalette.ACCENT if is_new else UiPalette.TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate.a = alpha
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_nodes_layer.add_child(lbl)


## 戰鬥分支節點 — 依 failure_outcome 派遣視覺(ADR-0004 §4 + Sub-stage 3c):
##   OHK         → 綠色 ColorRect
##   GAME_OVER   → 大 X Label(取代 ColorRect)
##   FOX_FLEE / RABBIT_CHAIN_FLEE → 暗灰 ColorRect
##   SPAWN / PROMOTION → 紅 ColorRect(配套 frame + 箭頭由 _build_branch_row 處理)
##   其他 Underkill → 紅 ColorRect
func _make_branch_battle_node(record: BattleRecord, timeline_idx: int) -> Control:
	var rec_ohk: bool = record.result != null and record.result.ohk
	var failure: int = record.failure_outcome
	var tt_text: String = _branch_node_tooltip(record)

	## GAME_OVER → 大 X 標記
	if failure == FailureHandler.FailureOutcome.GAME_OVER:
		var lbl := Label.new()
		lbl.text = "✗"
		lbl.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.gui_input.connect(_on_branch_battle_node_clicked.bind(timeline_idx))
		lbl.tooltip_text = tt_text
		return lbl

	## 其餘 ColorRect,顏色依 outcome
	var node := ColorRect.new()
	var is_flee: bool = failure == FailureHandler.FailureOutcome.FOX_FLEE \
		or failure == FailureHandler.FailureOutcome.RABBIT_CHAIN_FLEE
	if rec_ohk:
		node.color = UiPalette.OK_COLOR
	elif is_flee:
		node.color = UiPalette.TEXT_DIM  ## 暗灰:逃走,沒打死也沒終結
	else:
		node.color = UiPalette.FAIL_COLOR  ## 紅:SPAWN / PROMOTION / 其他 Underkill
	if record.is_elite:
		node.color = node.color.darkened(0.2)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(_on_branch_battle_node_clicked.bind(timeline_idx))
	node.tooltip_text = tt_text
	return node


## Tooltip 文字 — 敵人名 + 結果 + 場序/嘗試。
func _branch_node_tooltip(record: BattleRecord) -> String:
	var tmpl: EnemyTemplate = ResourceLibrary.enemy_template(record.enemy_template_id)
	var ename: String = tmpl.template_name if tmpl != null else record.enemy_template_id
	var prefix: String = "⚠ " if record.is_elite else ""
	var verdict: String
	if record.result != null and record.result.ohk:
		verdict = "OHK 成立"
	else:
		verdict = "Underkill — " + _failure_outcome_display(record.failure_outcome)
	return "%s%s\n%s\n第 %d 場 / 嘗試 %d" % [
		prefix, ename, verdict, record.position_in_chain + 1, record.retry_count + 1
	]


## SPAWN / PROMOTION 需要外框 + 箭頭(ADR-0004 §4)。
func _node_needs_frame(failure: int) -> bool:
	return failure == FailureHandler.FailureOutcome.GRAY_RABBIT_CLONE_SPAWN \
		or failure == FailureHandler.FailureOutcome.WOLF_ELITE_PROMOTION


## 建黑色外框(透明填充 + 黑邊)圍住節點。3c。
func _make_node_frame(center_x: float, center_y: float) -> Panel:
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color.BLACK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	frame.add_theme_stylebox_override("panel", sb)
	var extent: float = BRANCH_NODE_RADIUS + 4.0
	frame.position = Vector2(center_x - extent, center_y - extent)
	frame.size = Vector2(extent * 2, extent * 2)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame


## 畫弧形箭頭 from→to(3 段 Line2D + 三角頭)。在節點上方走 arch_height 高度。3c。
func _draw_branch_arrow(from_center: Vector2, to_center: Vector2, alpha: float) -> void:
	var arch_height: float = 14.0
	var node_top_offset: float = BRANCH_NODE_RADIUS + 5.0  ## 出發/到達在 frame 上方一點點
	var top_y: float = min(from_center.y, to_center.y) - node_top_offset - arch_height
	## Line2D 是 Node2D(非 Control),沒有 mouse_filter — 預設不參與 Control 輸入
	var line := Line2D.new()
	line.default_color = Color.BLACK
	line.width = 1.5
	line.modulate.a = alpha
	line.add_point(Vector2(from_center.x, from_center.y - node_top_offset))
	line.add_point(Vector2(from_center.x, top_y))
	line.add_point(Vector2(to_center.x, top_y))
	line.add_point(Vector2(to_center.x, to_center.y - node_top_offset))
	map_nodes_layer.add_child(line)
	## 箭頭頭 ▼ 放 target 節點上方
	var head := Label.new()
	head.text = "▼"
	head.position = Vector2(to_center.x - 6, to_center.y - node_top_offset - 10)
	head.size = Vector2(12, 12)
	head.add_theme_color_override("font_color", Color.BLACK)
	head.add_theme_font_size_override("font_size", 10)
	head.modulate.a = alpha
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_nodes_layer.add_child(head)


## SPAWN(灰兔 default)目標 = 下一個位置(clone 在 queue[0] 插入後變成下一場)。
## PROMOTION(狼)目標 = 同列稍後的 is_elite=true 同 instance 節點(菁英版排到末尾後再戰)。
## 回傳同列內 target 的 indices array index;找不到回 -1。
func _find_arrow_target_index(indices: Array, source_i: int) -> int:
	var src_rec: BattleRecord = _timeline[indices[source_i]]["record"]
	match src_rec.failure_outcome:
		FailureHandler.FailureOutcome.GRAY_RABBIT_CLONE_SPAWN:
			## 下一個位置
			if source_i + 1 < indices.size():
				return source_i + 1
			return -1
		FailureHandler.FailureOutcome.WOLF_ELITE_PROMOTION:
			## 同列稍後的 is_elite=true 同 instance
			for j in range(source_i + 1, indices.size()):
				var rec: BattleRecord = _timeline[indices[j]]["record"]
				if rec.is_elite and rec.enemy_instance_id == src_rec.enemy_instance_id:
					return j
			return -1
		_:
			return -1


func _on_branch_battle_node_clicked(event: InputEvent, timeline_idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_show_page_view(timeline_idx)


func _main_axis_label_text(data: Dictionary) -> String:
	match data["kind"]:
		"narrative_intro":
			return "戰役開始"
		"narrative_ending":
			return "結局"
		"chain":
			var chain: ChainDefinition = data["chain"]
			return chain.display_label if chain != null else "連戰 %d" % (int(data["chain_index"]) + 1)
		"prep":
			return "整備"
		_:
			return ""


## 敘事節點點擊 — 3d 接 NarrativePage 共用版型(戰役開始 / 結局)。
func _on_main_axis_narrative_clicked(event: InputEvent, data: Dictionary) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var camp: CampaignDefinition = data["campaign"]
	if camp == null:
		return
	var ctx: Dictionary
	if data["kind"] == "narrative_intro":
		ctx = _context_for_campaign_intro(camp)
	else:
		ctx = _context_for_campaign_ending(camp)
	_show_narrative_page(ctx)


## 整備節點點擊 — 開現有 PrepNodeRecord PageView(3d 後會改用 NarrativePage 共用版型)。
func _on_main_axis_prep_clicked(event: InputEvent, timeline_idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
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
	if item["kind"] == "battle":
		_render_battle_page(item["record"] as BattleRecord)
	else:
		## prep 改走 NarrativePage 共用版型(ADR-0004 §5 + Sub-stage 3d)
		_render_narrative_page(_context_for_prep_record(item["record"] as PrepNodeRecord))


## 顯示敘事頁(戰役開始 / 結局)— 不在 _timeline 中,沒 timeline_idx。
## prev/next 暫 disable(3d v1);未來若整合敘事到 timeline navigation,可改成 prev = 第一場戰鬥 等。
func _show_narrative_page(ctx: Dictionary) -> void:
	page_index_label.text = ""
	prev_page_btn.disabled = true
	next_page_btn.disabled = true
	_clear_children(left_page)
	_clear_children(right_page)
	world_view.visible = false
	map_view.visible = false
	page_view.visible = true
	_render_narrative_page(ctx)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


## 戰鬥頁雙欄(2026-05-17 重構,對應戰鬥紀錄系統設計 §4.1 + §7.1 校準對話精確版承載地):
##   左頁 = 玩家視角 — 使用的卡 + 玩家校準台詞 + 時間/座標 metadata
##   右頁 = 敵人 + 結果視角 — 敵人 + 揭露 + RequirementBar + 結果橫幅 + 失敗代價 + 父親校準台詞
func _render_battle_page(record: BattleRecord) -> void:
	var cal_lines: Dictionary = _get_calibration_line_data(record.calibration_state)
	var cal_display: String = CalibrationClassifier.state_display(record.calibration_state)

	## --- LeftPage:玩家視角 ---
	var lvbox := _build_page_vbox(left_page)
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

	lvbox.add_child(HSeparator.new())
	var player_title := Label.new()
	player_title.text = "玩家(%s)" % cal_display
	player_title.add_theme_color_override("font_color", UiPalette.ACCENT)
	player_title.add_theme_font_size_override("font_size", 13)
	lvbox.add_child(player_title)
	var player_line := Label.new()
	player_line.text = str(cal_lines.get("player", ""))
	player_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	player_line.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	lvbox.add_child(player_line)

	## spacer pushes metadata to bottom of left page
	var lspacer := Control.new()
	lspacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lvbox.add_child(lspacer)
	var ts := Label.new()
	ts.text = "時間:%s\n連戰 %d / 第 %d 場 / 嘗試 %d" % [
		Time.get_datetime_string_from_unix_time(record.timestamp),
		record.chain_index + 1,
		record.position_in_chain + 1,
		record.retry_count + 1,
	]
	ts.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	ts.add_theme_font_size_override("font_size", 11)
	lvbox.add_child(ts)

	## --- RightPage:敵人 + 結果 + 父親 ---
	var rvbox := _build_page_vbox(right_page)

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

	## 需求 bar 組(typed StrikeResult,ADR-0003)
	rvbox.add_child(RequirementBar.build_group(record.result))

	## 結果橫幅
	var verdict := Label.new()
	if record.result != null and record.result.ohk:
		var path_locs: Array[String] = []
		for p in record.result.passing_paths:
			path_locs.append(UiPalette.type_label(p))
		verdict.text = "✓ OHK 成立(%s)" % ", ".join(path_locs)
		verdict.add_theme_color_override("font_color", UiPalette.OK_COLOR)
	else:
		verdict.text = "✗ Underkill"
		verdict.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
	rvbox.add_child(verdict)

	if record.failure_outcome != -1:
		var fo := Label.new()
		fo.text = "失敗代價:%s" % _failure_outcome_display(record.failure_outcome)
		fo.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
		fo.add_theme_font_size_override("font_size", 12)
		rvbox.add_child(fo)

	## spacer pushes 父親 dialogue to bottom of right page
	var rspacer := Control.new()
	rspacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rvbox.add_child(rspacer)
	rvbox.add_child(HSeparator.new())
	var father_title := Label.new()
	father_title.text = "父親 — 戰後校準"
	father_title.add_theme_color_override("font_color", UiPalette.ACCENT)
	father_title.add_theme_font_size_override("font_size", 13)
	rvbox.add_child(father_title)
	var father_line := Label.new()
	father_line.text = str(cal_lines.get("npc", ""))
	father_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	father_line.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	rvbox.add_child(father_line)


## NarrativePage 共用版型(ADR-0004 §5 + Sub-stage 3d):
##   左頁 = 敘事/對話文字 + 時間/座標 metadata(若有)
##   右頁 = 上半部 場景插圖區 + 下半部 獲得/變化區
## 整備頁 / 戰役開始敘事頁 / 結局敘事頁 共用此 render。
## ctx 欄位:title / narrative_text / scene_label / scene_color / right_bottom_widgets / time_metadata
func _render_narrative_page(ctx: Dictionary) -> void:
	## --- LeftPage:敘事文字 + 底部 metadata ---
	var lvbox := _build_page_vbox(left_page)
	var ltitle := Label.new()
	ltitle.text = str(ctx.get("title", ""))
	ltitle.add_theme_color_override("font_color", UiPalette.ACCENT)
	ltitle.add_theme_font_size_override("font_size", 16)
	lvbox.add_child(ltitle)
	var narr := Label.new()
	narr.text = str(ctx.get("narrative_text", ""))
	narr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narr.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	lvbox.add_child(narr)

	var lspacer := Control.new()
	lspacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lvbox.add_child(lspacer)
	var time_meta: String = str(ctx.get("time_metadata", ""))
	if time_meta != "":
		var ts := Label.new()
		ts.text = time_meta
		ts.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		ts.add_theme_font_size_override("font_size", 11)
		lvbox.add_child(ts)

	## --- RightPage:上半場景 + 下半獲得區 ---
	var rvbox := _build_page_vbox(right_page)
	## 右上:場景插圖區(色塊 pass placeholder)
	var scene_block := PanelContainer.new()
	scene_block.custom_minimum_size = Vector2(0, SCENE_BLOCK_HEIGHT)
	var scene_color: Color = ctx.get("scene_color", UiPalette.PANEL_BG_DARK)
	scene_block.add_theme_stylebox_override("panel", UiPalette.make_panel(scene_color, Color(0, 0, 0, 0), 0, 4))
	var scene_label := Label.new()
	scene_label.text = str(ctx.get("scene_label", ""))
	scene_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scene_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scene_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	scene_label.add_theme_font_size_override("font_size", 16)
	scene_block.add_child(scene_label)
	rvbox.add_child(scene_block)

	rvbox.add_child(HSeparator.new())

	## 右下:獲得/變化區 widgets(caller 各自決定)
	var widgets: Array = ctx.get("right_bottom_widgets", [])
	for w in widgets:
		rvbox.add_child(w)


# ============ NarrativePage context builders ============

## 整備節點:左 = supply.narrative + 時間;右上 = 整備地;右下 = SupplyChip + 前後總數
func _context_for_prep_record(record: PrepNodeRecord) -> Dictionary:
	var sp: SupplyPhase = ResourceLibrary.supply(record.supply_id)
	var scene_color: Color = SCENE_COLOR_PREP_ADD
	if sp != null and sp.supply_type == "full_restore":
		scene_color = SCENE_COLOR_PREP_FULL
	return {
		"title": "整備:%s" % record.supply_id,
		"narrative_text": sp.narrative if sp != null else "(無敘述)",
		"scene_label": "整備地",
		"scene_color": scene_color,
		"right_bottom_widgets": _build_prep_widgets(record, sp),
		"time_metadata": "時間:%s\n完成連戰 %d 後的整備" % [
			Time.get_datetime_string_from_unix_time(record.timestamp),
			record.chain_index_completed + 1,
		],
	}


## 戰役開始敘事:左 = campaign.prologue_narrative;右上 = 森林入口;右下 = 起手卡組
func _context_for_campaign_intro(camp: CampaignDefinition) -> Dictionary:
	return {
		"title": "戰役開始 — %s" % camp.campaign_name,
		"narrative_text": camp.prologue_narrative,
		"scene_label": "森林入口",
		"scene_color": SCENE_COLOR_INTRO,
		"right_bottom_widgets": _build_starting_deck_widgets(camp),
		"time_metadata": "",
	}


## 結局敘事:左 = campaign.ending_narrative;右上 = 結局;右下 = 解鎖紀念品
func _context_for_campaign_ending(camp: CampaignDefinition) -> Dictionary:
	return {
		"title": "結局 — %s" % camp.campaign_name,
		"narrative_text": camp.ending_narrative,
		"scene_label": "森林深處",
		"scene_color": SCENE_COLOR_ENDING,
		"right_bottom_widgets": _build_souvenir_widgets(),
		"time_metadata": "",
	}


# ============ NarrativePage 右下 widget builders ============

func _build_prep_widgets(record: PrepNodeRecord, sp: SupplyPhase) -> Array:
	var widgets: Array = []
	var rtitle := Label.new()
	rtitle.text = "卡組變化"
	rtitle.add_theme_color_override("font_color", UiPalette.ACCENT)
	widgets.append(rtitle)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 12)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	if record.changes.is_empty():
		var none := Label.new()
		var is_full_restore: bool = sp != null and sp.supply_type == "full_restore"
		none.text = "(卡組恢復至戰前狀態)" if is_full_restore else "(無變化)"
		none.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		chips.add_child(none)
	else:
		for cid in record.changes:
			var chip := SupplyChip.new()
			chip.setup(cid, int(record.changes[cid]))
			chips.add_child(chip)
	widgets.append(chips)

	var summary := Label.new()
	summary.text = "整備前 %d 張 → 整備後 %d 張" % [
		_pool_total(record.card_pool_before), _pool_total(record.card_pool_after)
	]
	summary.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	widgets.append(summary)
	return widgets


## 戰役開始 — 起手卡組,用 SupplyChip 顯示(+N 寫法跟整備一致)
func _build_starting_deck_widgets(camp: CampaignDefinition) -> Array:
	var widgets: Array = []
	var rtitle := Label.new()
	rtitle.text = "起手卡組"
	rtitle.add_theme_color_override("font_color", UiPalette.ACCENT)
	widgets.append(rtitle)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 12)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	for cid in camp.starting_deck:
		var chip := SupplyChip.new()
		chip.setup(cid, int(camp.starting_deck[cid]))
		chips.add_child(chip)
	widgets.append(chips)
	return widgets


## 結局 — 解鎖紀念品列表(GameState.unlocked_souvenirs ∩ SouvenirInfo.ALL)
func _build_souvenir_widgets() -> Array:
	var widgets: Array = []
	var rtitle := Label.new()
	rtitle.text = "解鎖紀念品"
	rtitle.add_theme_color_override("font_color", UiPalette.ACCENT)
	widgets.append(rtitle)
	if GameState.unlocked_souvenirs.is_empty():
		var none := Label.new()
		none.text = "(無)"
		none.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		widgets.append(none)
		return widgets
	for sid in GameState.unlocked_souvenirs:
		if not SouvenirInfo.ALL.has(sid):
			continue
		var info: Dictionary = SouvenirInfo.ALL[sid]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG_LIGHT, UiPalette.ACCENT, 1, 4))
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 8)
		card.add_child(margin)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		margin.add_child(vb)
		var name_lbl := Label.new()
		name_lbl.text = str(info.get("name", sid))
		name_lbl.add_theme_color_override("font_color", UiPalette.ACCENT)
		name_lbl.add_theme_font_size_override("font_size", 14)
		vb.add_child(name_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = str(info.get("description", ""))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
		desc_lbl.add_theme_font_size_override("font_size", 12)
		vb.add_child(desc_lbl)
		widgets.append(card)
	return widgets


# ============ 工具 ============

## 一律建一個 16/12 邊距 + 10 separation 的 VBox 進 page panel,回傳 vbox 供 caller 填內容。
func _build_page_vbox(page: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	page.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	return vbox


## 取 ResourceLibrary.calibration_lines 對應 state 的 { player, npc } dict;空保護。
func _get_calibration_line_data(cal_state: int) -> Dictionary:
	var key := CalibrationClassifier.state_key(cal_state)
	var cl: CalibrationLines = ResourceLibrary.calibration_lines()
	if cl == null:
		return { "player": "", "npc": "" }
	return cl.get_line(key)


func _failure_outcome_display(outcome_int: int) -> String:
	match outcome_int:
		FailureHandler.FailureOutcome.TUTORIAL_RETRY: return "教學重來"
		FailureHandler.FailureOutcome.RABBIT_CHAIN_FLEE: return "兔群連鎖逃走"
		FailureHandler.FailureOutcome.FOX_FLEE: return "單獨逃走"
		FailureHandler.FailureOutcome.WOLF_ELITE_PROMOTION: return "狼菁英化排末"
		FailureHandler.FailureOutcome.GRAY_RABBIT_CLONE_SPAWN: return "灰兔 default 逃走,clone 緊接於後"
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
