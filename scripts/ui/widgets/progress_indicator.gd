class_name ProgressIndicator
extends VBoxContainer

## 連戰 / 戰役進度點(風格無關佔位版)。
## 對應 UI 設計指引.md §3.10。
## 4 種狀態:✓ defeated(OHK 成功)/ ✗ escaped(未成功擊敗,2026-05-17 新加)/ ▶ current / ○ pending。
## 垂直堆疊,放在戰鬥畫面最右側。
##
## 兩個 API:
##   setup(total, current_index)  —— 簡單版,m1 dev 用(全部 chips 兩態:已過 = ✓,當前 = ▶,未到 = ○)
##   setup_states(states)         —— 完整版,m2 用,每個 chip 一個 state string

const CHIP_SIZE := Vector2(28, 24)


## 簡單版:total = 總節點數;current_index = 當前所在(0-based)。
## 內部轉成 setup_states([defeated × current_index, current, pending × rest])。
func setup(total: int, current_index: int) -> void:
	var states: Array[String] = []
	for i in total:
		if i < current_index:
			states.append("defeated")
		elif i == current_index:
			states.append("current")
		else:
			states.append("pending")
	setup_states(states)


## 完整版:每個 chip 對應 states[i] 的狀態 string。
## 認得的 state:"defeated" / "escaped" / "current" / "pending"。
func setup_states(states: Array) -> void:
	for child in get_children():
		child.queue_free()
	add_theme_constant_override("separation", 4)
	## 整個指示器對滑鼠透明 —— 點擊事件交給外層容器處理(m1:連戰預覽)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in states:
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
		match state:
			"defeated":
				label.text = "✓"
				bg = UiPalette.OK_COLOR.darkened(0.45)
				fg = UiPalette.OK_COLOR
			"escaped":
				label.text = "✗"
				bg = UiPalette.FAIL_COLOR.darkened(0.45)
				fg = UiPalette.FAIL_COLOR
			"current":
				label.text = "▶"
				bg = UiPalette.ACCENT.darkened(0.5)
				fg = UiPalette.ACCENT
			_:  ## pending or unknown
				label.text = "○"
				bg = UiPalette.PANEL_BG_DARK
				fg = UiPalette.TEXT_DIM
		label.add_theme_color_override("font_color", fg)
		chip.add_theme_stylebox_override("panel", UiPalette.make_panel(bg, UiPalette.PANEL_BORDER, 1, 3))
		add_child(chip)
