class_name ProgressIndicator
extends VBoxContainer

## 連戰 / 戰役進度點(風格無關佔位版)。
## 對應 UI 設計指引.md §3.10。
## 已完成 → ✓、當前 → ▶、未開始 → ○。
## 垂直堆疊,放在戰鬥畫面最右側。

const CHIP_SIZE := Vector2(28, 24)


## total = 總節點數;current_index = 當前所在(0-based)。
func setup(total: int, current_index: int) -> void:
	for child in get_children():
		child.queue_free()
	add_theme_constant_override("separation", 4)
	## 整個指示器對滑鼠透明 —— 點擊事件交給外層容器處理(m1:連戰預覽)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in total:
		var chip := PanelContainer.new()
		chip.custom_minimum_size = CHIP_SIZE
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(label)
		var bg: Color
		var fg: Color
		if i < current_index:
			label.text = "✓"
			bg = UiPalette.OK_COLOR.darkened(0.45)
			fg = UiPalette.OK_COLOR
		elif i == current_index:
			label.text = "▶"
			bg = UiPalette.ACCENT.darkened(0.5)
			fg = UiPalette.ACCENT
		else:
			label.text = "○"
			bg = UiPalette.PANEL_BG_DARK
			fg = UiPalette.TEXT_DIM
		label.add_theme_color_override("font_color", fg)
		chip.add_theme_stylebox_override("panel", UiPalette.make_panel(bg, UiPalette.PANEL_BORDER, 1, 3))
		add_child(chip)
