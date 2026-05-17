class_name ChainTimeline
extends Control

## 連戰時間軸 widget(ADR-0008)。BattleView 內常駐;水平節點時間軸。
##
## 資料源混合:
## - sealed 節點:AdventureRecord.battles 篩(campaign_id, campaign_attempt, chain_index, retry_count)
## - current 節點:enemy_queue[0]
## - pending 節點:enemy_queue[1..]
##
## Invariant:所有 sealed 節點都對應一個 BattleRecord(可點跳 PageView)。
##
## 視覺哲學(ADR-0007 延伸):
## - sealed = 實心節點 + 實線連接(已發生)
## - pending = 空心節點 + 虛線連接(未發生)
## - 雙重對比(實心/空心 + 實線/虛線)讓「已發生 vs 未發生」一眼可分
##
## 動畫(ADR-0008 §6,自動 diff 觸發):
## - current → sealed:color lerp 0.25s
## - 末段 / 緊接 append/insert 新 chip:scale-from-position 0.3s
## - pending elite 初次出現:pulse 1.4s 後自動停

signal node_clicked(battle_id: String)              ## sealed 點擊 → 跳 PageView
signal elite_lookup_clicked(template_id: String)    ## pending elite 點擊 → 跳 last_failure PageView

# ============ 視覺常數 ============
const SEALED_RADIUS := 10
const CURRENT_RADIUS := 12
const PENDING_RADIUS := 8
const NODE_GAP := 48                                ## 節點 center-to-center 間距
const LINE_WIDTH_SOLID := 2.0
const LINE_WIDTH_DASHED := 1.0
const DASH_SEG := 4.0
const DASH_GAP := 3.0
const LABEL_OFFSET_Y := 14                          ## label 在節點下方距離
const LABEL_FONT_SIZE := 11

# ============ 動畫常數 ============
const LERP_DURATION := 0.25
const SCALE_IN_DURATION := 0.3
const PULSE_CYCLES := 2
const PULSE_CYCLE_DURATION := 0.7

# ============ 內部狀態 ============
var _nodes: Array[ChainTimelineNode] = []           ## 按 position 排序的節點
var _prev_snapshot: Array = []                      ## 上次 refresh 後的狀態,用於 diff
var _container: HBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(0, 52)
	_container = HBoxContainer.new()
	_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_container.add_theme_constant_override("separation", NODE_GAP - SEALED_RADIUS * 2)
	_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_container)
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)


# ============ 對外 API ============

## 用當前狀態重新 build 時間軸。
##   chain_attempt = chain_attempt_for_journal(同 chain 內第幾次重挑;0=首次)
##   enemy_queue   = 當前 EnemyEncounter Array(queue[0] 是 current,後面是 pending)
##
## 內部會 diff 跟上次 snapshot 比對,自動觸發動畫:
##   - 新 sealed (current→sealed):color lerp
##   - 新增 chip (size 增加):scale-from-position
##   - 新 pending elite:pulse 1.4s
func refresh(
		campaign_id: String,
		campaign_attempt: int,
		chain_index: int,
		chain_attempt: int,
		enemy_queue: Array,
) -> void:
	var sealed_records: Array[BattleRecord] = _collect_sealed_records(
		campaign_id, campaign_attempt, chain_index, chain_attempt
	)
	var new_snapshot: Array = []

	## 構成新節點列表:sealed (來自 BattleRecord) + current/pending (來自 enemy_queue)
	for rec in sealed_records:
		new_snapshot.append({
			"state": "sealed_defeated" if (rec.result != null and rec.result.ohk) else "sealed_escaped",
			"label": _short_label_for_template(rec.enemy_template_id, rec.is_elite),
			"tooltip": _tooltip_for_template(rec.enemy_template_id, rec.is_elite),
			"battle_id": rec.battle_id,
			"template_id": rec.enemy_template_id,
			"is_elite": rec.is_elite,
		})

	if not enemy_queue.is_empty():
		var current_enc = enemy_queue[0]
		new_snapshot.append({
			"state": "current",
			"label": _short_label_for_template(current_enc.template_id(), current_enc.is_elite),
			"tooltip": _tooltip_for_template(current_enc.template_id(), current_enc.is_elite),
			"battle_id": "",
			"template_id": current_enc.template_id(),
			"is_elite": current_enc.is_elite,
		})
		for i in range(1, enemy_queue.size()):
			var enc = enemy_queue[i]
			new_snapshot.append({
				"state": "pending_elite" if enc.is_elite else "pending",
				"label": _short_label_for_template(enc.template_id(), enc.is_elite),
				"tooltip": _tooltip_for_template(enc.template_id(), enc.is_elite),
				"battle_id": "",
				"template_id": enc.template_id(),
				"is_elite": enc.is_elite,
			})

	_apply_snapshot(new_snapshot)
	_prev_snapshot = new_snapshot
	queue_redraw()


## 清空時間軸(連戰結束 / 非戰鬥 phase)。
func clear_timeline() -> void:
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	_prev_snapshot.clear()
	queue_redraw()


# ============ 內部:資料源組裝 ============

func _collect_sealed_records(
		campaign_id: String, campaign_attempt: int, chain_index: int, chain_attempt: int
) -> Array[BattleRecord]:
	var all: Array[BattleRecord] = AdventureRecord.get_battles_by_campaign(campaign_id, campaign_attempt)
	var result: Array[BattleRecord] = []
	for rec in all:
		if rec.chain_index == chain_index and rec.retry_count == chain_attempt:
			result.append(rec)
	## 按 position_in_chain 排序確保時間順序
	result.sort_custom(func(a, b): return a.position_in_chain < b.position_in_chain)
	return result


# ============ 內部:節點建構 + diff 動畫 ============

func _apply_snapshot(new_snapshot: Array) -> void:
	## Diff 策略:
	## - 若某 index 上次 = "current" 且這次 = "sealed_*" → color lerp 該節點
	## - 若 new_snapshot.size() > _prev_snapshot.size() → 新增節點,對新節點 scale-in
	## - 若某 index 上次 != "pending_elite" 且這次 = "pending_elite" → pulse 該節點
	## - 否則純 set state

	## Step 1: 移除尾部多餘節點(理論不發生,但 RABBIT_CHAIN_FLEE/TUTORIAL_RETRY 一旦啟用會用到)
	while _nodes.size() > new_snapshot.size():
		var n = _nodes.pop_back()
		n.queue_free()

	## Step 2: 新增到 new_snapshot.size()
	while _nodes.size() < new_snapshot.size():
		var node := ChainTimelineNode.new()
		node.clicked.connect(_on_node_clicked)
		_container.add_child(node)
		_nodes.append(node)

	## Step 3: 套用每個節點狀態 + 動畫差異
	for i in _nodes.size():
		var data: Dictionary = new_snapshot[i]
		var prev: Dictionary = _prev_snapshot[i] if i < _prev_snapshot.size() else {}
		var was_new := prev.is_empty()
		var was_current := str(prev.get("state", "")) == "current"
		var was_elite_pending := str(prev.get("state", "")) == "pending_elite"

		_nodes[i].apply(data)

		var state: String = str(data.get("state", ""))
		if was_new and i >= _prev_snapshot.size():
			_nodes[i].play_scale_in(SCALE_IN_DURATION)
		elif was_current and state.begins_with("sealed_"):
			_nodes[i].play_color_lerp(LERP_DURATION)

		if state == "pending_elite" and not was_elite_pending:
			_nodes[i].play_pulse(PULSE_CYCLES, PULSE_CYCLE_DURATION)


func _on_node_clicked(node: ChainTimelineNode) -> void:
	var state: String = str(node.data.get("state", ""))
	if state.begins_with("sealed_"):
		var battle_id: String = str(node.data.get("battle_id", ""))
		if battle_id != "":
			node_clicked.emit(battle_id)
	elif state == "pending_elite":
		var template_id: String = str(node.data.get("template_id", ""))
		if template_id != "":
			elite_lookup_clicked.emit(template_id)


# ============ 內部:連線繪製 ============

func _draw() -> void:
	if _nodes.size() < 2:
		return
	## 等 layout 完成後再繪;節點位置由 HBoxContainer 決定
	for i in range(_nodes.size() - 1):
		var from_node = _nodes[i]
		var to_node = _nodes[i + 1]
		if not is_instance_valid(from_node) or not is_instance_valid(to_node):
			continue
		var from_state: String = str(from_node.data.get("state", ""))
		var to_state: String = str(to_node.data.get("state", ""))
		## sealed/current 之間 = 實線;只要碰到 pending 就虛線
		var solid := not (from_state.begins_with("pending") or to_state.begins_with("pending"))
		var from_x = from_node.position.x + from_node.size.x / 2.0 + from_node.get_node_radius()
		var to_x = to_node.position.x + to_node.size.x / 2.0 - to_node.get_node_radius()
		var y = from_node.position.y + CURRENT_RADIUS  ## 主軸 y = 節點中心
		if solid:
			draw_line(Vector2(from_x, y), Vector2(to_x, y), UiPalette.TEXT_DIM, LINE_WIDTH_SOLID)
		else:
			_draw_dashed_h(Vector2(from_x, y), Vector2(to_x, y))


func _draw_dashed_h(from_pt: Vector2, to_pt: Vector2) -> void:
	var x := from_pt.x
	var max_x := to_pt.x
	while x < max_x:
		var seg_end := minf(x + DASH_SEG, max_x)
		draw_line(Vector2(x, from_pt.y), Vector2(seg_end, to_pt.y),
			UiPalette.TEXT_DIM, LINE_WIDTH_DASHED)
		x = seg_end + DASH_GAP


func _process(_delta: float) -> void:
	## HBoxContainer 排版完成後節點 position 才正確,持續 redraw 連線
	queue_redraw()


# ============ 內部:label / tooltip 對映 ============

func _short_label_for_template(template_id: String, is_elite: bool) -> String:
	var base: String = ""
	match template_id:
		"rabbit": base = "兔"
		"gray_rabbit": base = "灰兔"
		"fox": base = "狐"
		"wolf": base = "狼"
		"mutant_wolf": base = "異變狼"
		"leopard": base = "豹"
		"bear": base = "熊"
		_: base = template_id  ## fallback,提示有 template 沒 mapping
	return base


func _tooltip_for_template(template_id: String, is_elite: bool) -> String:
	var base: String = _short_label_for_template(template_id, is_elite)
	if is_elite:
		return "[菁英化 ⚠] " + base
	return base
