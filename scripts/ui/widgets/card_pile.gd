class_name CardPile
extends PanelContainer

## 牌堆塊(風格無關佔位版)。
## 對應 第一期 UI 線框圖.md §4.6 庫存區 ╔══╗。
##
## 序章前半每種卡內部完全相同(射箭×10 / 投石×8 / 偵查×2),
## 故一種卡 = 一個牌堆塊,顯示卡面 + 剩餘張數;點擊 = Place 一張。
## 待後續期數卡種變多,再引入「手牌扇形」展開池內變化。

signal pile_clicked

const PILE_MIN_SIZE := Vector2(132, 116)

var card: CardDefinition
var _enabled: bool = true

var _type_band: Panel
var _name_label: Label
var _contrib_label: Label
var _count_label: Label
var _hint_label: Label


func _init() -> void:
	custom_minimum_size = PILE_MIN_SIZE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_type_band = Panel.new()
	_type_band.custom_minimum_size = Vector2(0, 8)
	_type_band.add_theme_stylebox_override("panel", UiPalette.make_block(UiPalette.type_color("none")))
	vbox.add_child(_type_band)

	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	vbox.add_child(_name_label)

	_contrib_label = Label.new()
	_contrib_label.add_theme_font_size_override("font_size", 11)
	_contrib_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	vbox.add_child(_contrib_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 18)
	_count_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	vbox.add_child(_count_label)

	_hint_label = Label.new()
	_hint_label.text = "點擊 Place 一張"
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	vbox.add_child(_hint_label)

	_apply_style()


# ============ 對外 API ============

func setup(card_def: CardDefinition) -> void:
	card = card_def
	if card == null:
		return
	var primary := UiPalette.card_primary_type(card)
	_type_band.add_theme_stylebox_override("panel", UiPalette.make_block(UiPalette.type_color(primary)))
	_name_label.text = card.card_name
	_contrib_label.text = UiPalette.contribution_text(card.contribution)


func set_count(n: int) -> void:
	_count_label.text = "× %d" % n


## 不可用時(非 Place 階段 / 數量耗盡)變灰且不可點。
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_apply_style()


# ============ 內部 ============

func _apply_style() -> void:
	var border := UiPalette.PANEL_BORDER
	if _enabled:
		modulate = Color.WHITE
		add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG_LIGHT, border, 2))
	else:
		modulate = Color(1, 1, 1, 0.4)
		add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG, border, 1))
	_hint_label.visible = _enabled


func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pile_clicked.emit()
