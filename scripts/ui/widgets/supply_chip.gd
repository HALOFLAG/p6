class_name SupplyChip
extends PanelContainer

## 整備補給卡塊(風格無關佔位版)。
## 顯示「卡名 + ±N(類型色邊框)」,用於:
##   - m2_campaign SUPPLY phase 的當下補給呈現
##   - adventure_journal PrepNode 頁面的歷史補給呈現
## 對應 程式規格書.md §3.14 整備補給 + 戰鬥紀錄系統設計.md §4。

const CHIP_MIN_SIZE := Vector2(120, 64)

var _name_label: Label
var _delta_label: Label


func _init() -> void:
	custom_minimum_size = CHIP_MIN_SIZE
	var vb := VBoxContainer.new()
	add_child(vb)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	vb.add_child(_name_label)
	_delta_label = Label.new()
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_delta_label.add_theme_font_size_override("font_size", 18)
	vb.add_child(_delta_label)


## 以 card_id + delta 填入卡名與正負值。
## card_id 在 ResourceLibrary 找不到時,卡名 fallback 為 id 字串、邊框用 "none" 類型色。
func setup(card_id: String, delta: int) -> void:
	var card: CardDefinition = ResourceLibrary.card(card_id)
	var cn := str(card_id)
	var primary := "none"
	if card != null:
		cn = card.card_name
		primary = UiPalette.card_primary_type(card)
	add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG_LIGHT, UiPalette.type_color(primary), 2))
	_name_label.text = cn
	_delta_label.text = "%s%d" % ["+" if delta >= 0 else "", delta]
	_delta_label.add_theme_color_override("font_color", UiPalette.OK_COLOR if delta >= 0 else UiPalette.FAIL_COLOR)
