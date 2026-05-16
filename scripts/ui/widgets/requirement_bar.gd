class_name RequirementBar
extends HBoxContainer

## 單一類型的需求 bar(風格無關佔位版)。
## 對應 UI 設計指引.md §3.6;結算演出時成組使用。
## 顯示「玩家本擊貢獻 vs 敵人需求」,達標時整條轉綠。

var _chip: PanelContainer
var _chip_label: Label
var _bar: ProgressBar
var _count_label: Label
var _status_label: Label


func _init() -> void:
	add_theme_constant_override("separation", 8)

	_chip = PanelContainer.new()
	_chip.custom_minimum_size = Vector2(56, 0)
	add_child(_chip)
	_chip_label = Label.new()
	_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chip_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	_chip.add_child(_chip_label)

	_bar = ProgressBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.custom_minimum_size = Vector2(0, 20)
	_bar.show_percentage = false
	add_child(_bar)

	_count_label = Label.new()
	_count_label.custom_minimum_size = Vector2(60, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	add_child(_count_label)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(20, 0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)


## actual = 玩家本擊在該類型的貢獻;required = 敵人需求。
func setup(type_key: String, actual: int, required: int) -> void:
	var hit := actual >= required
	var type_col := UiPalette.type_color(type_key)

	_chip.add_theme_stylebox_override("panel", UiPalette.make_panel(type_col.darkened(0.1), Color(0, 0, 0, 0), 0, 3))
	_chip_label.text = UiPalette.type_label(type_key)

	_bar.max_value = max(required, 1)
	_bar.value = clampi(actual, 0, int(_bar.max_value))
	var fill_col := UiPalette.OK_COLOR if hit else type_col
	_bar.add_theme_stylebox_override("background", UiPalette.make_block(UiPalette.PANEL_BG_DARK, 3))
	_bar.add_theme_stylebox_override("fill", UiPalette.make_block(fill_col, 3))

	_count_label.text = "%d / %d" % [actual, required]
	_status_label.text = "✓" if hit else "✗"
	_status_label.add_theme_color_override("font_color", UiPalette.OK_COLOR if hit else UiPalette.FAIL_COLOR)


## 由結算結果(Resolution.resolve 的回傳)建一組 bar,塞進一個 VBoxContainer 回傳。
static func build_group(result: Dictionary) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 4)
	var requirements: Dictionary = result.get("requirements", {})
	var contributions: Dictionary = result.get("contributions", {})
	var mixed_count: int = result.get("mixed_count", 0)
	for type_key in requirements:
		var required: int = requirements[type_key]
		var actual: int = mixed_count if type_key == "mixed" else contributions.get(type_key, 0)
		var bar := RequirementBar.new()
		group.add_child(bar)
		bar.setup(type_key, actual, required)
	return group
