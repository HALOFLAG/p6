class_name NarrativeBox
extends PanelContainer

## 文字冒險式對話框 —— 敘事 / 整備 phase 的中層主閱讀區。
## 對應 階段四討論:中層替換為「更大的對話框」,上層維持演出(立繪 + 角色對話泡)。
##
## 結構:標題(可選)+ 捲動敘述文字 + 內容槽(可塞補給卡塊等)+ 置中按鈕列。
## 風格無關佔位版;美術風格定案後(M6)替換視覺。

var _title_label: Label
var _text_label: RichTextLabel
var _content_slot: VBoxContainer
var _buttons_row: HBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG, UiPalette.PANEL_BORDER))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_color_override("font_color", UiPalette.ACCENT)
	_title_label.visible = false
	vbox.add_child(_title_label)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = true
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_color_override("default_color", UiPalette.TEXT_MAIN)
	vbox.add_child(_text_label)

	_content_slot = VBoxContainer.new()
	_content_slot.add_theme_constant_override("separation", 8)
	vbox.add_child(_content_slot)

	_buttons_row = HBoxContainer.new()
	_buttons_row.add_theme_constant_override("separation", 16)
	_buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_buttons_row)


# ============ 對外 API ============

## 設定敘述文字。is_warning → 邊框轉警示色(GAME OVER)。每次 setup 清空標題 / 內容槽 / 按鈕。
func setup(text: String, is_warning: bool = false) -> void:
	var border := UiPalette.FAIL_COLOR if is_warning else UiPalette.PANEL_BORDER
	add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG, border))
	_text_label.text = text
	_title_label.text = ""
	_title_label.visible = false
	for child in _content_slot.get_children():
		child.queue_free()
	for child in _buttons_row.get_children():
		child.queue_free()


## 可選:標題 / 說話者列。
func set_title(title: String) -> void:
	_title_label.text = title
	_title_label.visible = title != ""


## 加一顆推進 / 選項按鈕,回傳給呼叫端連 signal。
func add_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 44)
	_buttons_row.add_child(btn)
	return btn


## 內容槽:呼叫端可往裡面塞額外內容(整備卡塊等)。
func content_slot() -> VBoxContainer:
	return _content_slot
