class_name EnemyWidget
extends PanelContainer

## 敵人情報欄(風格無關佔位版)。
## 對應 UI 設計指引.md §3.5 + 第一期 UI 線框圖.md §4.3。
##
## 內容用「HBox 容納多個 VBox 欄」手動分欄:每欄累積估計高度到 COLUMN_BUDGET 就
## 往右開新欄 —— 內容垂直可讀、不往下超出 StageZone。
## (改用基本容器,不依賴 VFlowContainer 自動換欄 —— 後者排版不穩定。)
## 立繪不在此 widget —— 立繪是舞台上的獨立色塊。widget 每場戰鬥重建一次。

const COLUMN_BUDGET := 196.0   ## 單欄內容估計高度上限(px);超過往右開新欄
const COL_SEPARATION := 4      ## 欄內列距(與 _add_row 估高一致)
const KEY_LABEL_WIDTH := 88

var _columns_box: HBoxContainer

var _elite_label: Label
var _weakness_label: Label
var _remaining_label: Label
var _req_value_labels: Dictionary = {}  ## { type_key: Label }

# 分欄狀態(setup 期間使用)
var _cur_column: VBoxContainer
var _cur_height: float = 0.0


func _init() -> void:
	add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG, UiPalette.PANEL_BORDER))
	_columns_box = HBoxContainer.new()
	_columns_box.add_theme_constant_override("separation", 16)
	add_child(_columns_box)


# ============ 對外 API ============

## 以模板 + instance 建構內容,手動分欄塞入。widget 每場戰鬥重建一次。
func setup(template: EnemyTemplate, instance: EnemyInstance, is_elite: bool = false, display_name_override: String = "") -> void:
	if template == null or instance == null:
		return
	for child in _columns_box.get_children():
		child.queue_free()
	_req_value_labels.clear()
	_cur_column = null
	_cur_height = 0.0
	_open_column()

	## 標題
	_add_row(_plain_label("敵人情報", UiPalette.ACCENT), 24)
	_add_row(HSeparator.new(), 10)

	## 名稱列(名稱 + 菁英標記)
	var nm := display_name_override
	if nm == "":
		nm = instance.display_name if instance.display_name != "" else template.template_name
	var name_row := HBoxContainer.new()
	var name_label := _plain_label(nm, UiPalette.TEXT_MAIN)
	name_label.add_theme_font_size_override("font_size", 16)
	name_row.add_child(name_label)
	_elite_label = _plain_label("⚠ 菁英化", UiPalette.FAIL_COLOR)
	_elite_label.visible = is_elite
	name_row.add_child(_elite_label)
	_add_row(name_row, 28)

	## 類別 / 戰鬥狀態
	var class_label := _plain_label("類別:%s ・ 狀態:%s" % [
		UiPalette.enemy_class_label(template.enemy_class),
		UiPalette.combat_state_label(instance.combat_state),
	], UiPalette.TEXT_DIM)
	class_label.add_theme_font_size_override("font_size", 12)
	_add_row(class_label, 20)

	## 弱點範圍
	var weakness_locs: Array[String] = []
	for t in template.weakness_range:
		weakness_locs.append(UiPalette.type_label(t))
	_weakness_label = _plain_label("弱點範圍:%s" % ", ".join(weakness_locs), UiPalette.TEXT_MAIN)
	_add_row(_weakness_label, 24)

	## 需求層級
	_add_row(_plain_label("需求層級:%s" % UiPalette.requirement_tier(instance.get_max_requirement()), UiPalette.TEXT_MAIN), 24)

	_add_row(HSeparator.new(), 10)

	## 需求表標題
	var req_title := _plain_label("需求表", UiPalette.TEXT_DIM)
	req_title.add_theme_font_size_override("font_size", 12)
	_add_row(req_title, 20)

	## 需求列(每個需求鍵一列,值先填 ???;set_revealed 原地替換)
	for type_key in instance.requirements:
		var row := HBoxContainer.new()
		var key_label := _plain_label("%s需求" % UiPalette.type_label(type_key), UiPalette.TEXT_MAIN)
		key_label.custom_minimum_size = Vector2(KEY_LABEL_WIDTH, 0)
		row.add_child(key_label)
		var value_label := _plain_label("???", UiPalette.TEXT_DIM)
		row.add_child(value_label)
		_add_row(row, 24)
		_req_value_labels[type_key] = value_label

	## 連戰剩餘敵人(m2 用,預設隱藏)
	_remaining_label = _plain_label("", UiPalette.TEXT_DIM)
	_remaining_label.add_theme_font_size_override("font_size", 12)
	_remaining_label.visible = false
	_add_row(_remaining_label, 0)


## 由 BattleEngine.revealed_info 更新已揭露資訊(原地替換,不改變行數)。
func set_revealed(info: Dictionary) -> void:
	if info.has("full_requirements"):
		for type_key in info["full_requirements"]:
			if _req_value_labels.has(type_key):
				var lbl: Label = _req_value_labels[type_key]
				lbl.text = str(info["full_requirements"][type_key])
				lbl.add_theme_color_override("font_color", UiPalette.ACCENT)
	if info.has("enemy_weakness_types") and _weakness_label != null:
		var mode := "深度" if info.get("weakness_reveal_mode", "") == "depth" else "廣度"
		var types_loc: Array[String] = []
		for t in info["enemy_weakness_types"]:
			types_loc.append(UiPalette.type_label(t))
		_weakness_label.text = "弱點範圍:%s ★已揭露(%s)" % [", ".join(types_loc), mode]
		_weakness_label.add_theme_color_override("font_color", UiPalette.ACCENT)


## 連戰剩餘敵人數(m2 用;m1 單體戰不呼叫)。
func set_remaining(count: int) -> void:
	if _remaining_label == null:
		return
	_remaining_label.text = "連戰剩餘敵人:%d" % count
	_remaining_label.visible = true


# ============ 內部:手動分欄 ============

func _open_column() -> void:
	_cur_column = VBoxContainer.new()
	_cur_column.add_theme_constant_override("separation", COL_SEPARATION)
	_cur_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_cur_column.custom_minimum_size = Vector2(180, 0)
	_columns_box.add_child(_cur_column)
	_cur_height = 0.0


## 把一列加入當前欄;若加入後會超過高度上限就先開新欄(第一列不換)。
func _add_row(node: Control, est_height: float) -> void:
	if _cur_height + est_height > COLUMN_BUDGET and _cur_column.get_child_count() > 0:
		_open_column()
	_cur_column.add_child(node)
	_cur_height += est_height + COL_SEPARATION


func _plain_label(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	return lbl
