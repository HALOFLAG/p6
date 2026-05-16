class_name DialogueBubble
extends PanelContainer

## 對話泡(風格無關佔位版)。
## 對應 第一期 UI 線框圖.md §4.1 變體 C + UI 設計指引.md §3.8。
##
## 用法:作為「overlay 圖層」放在牌桌之上,show_line / hide_bubble 只切 visible 與內容,
## 不影響任何固定區塊的佈局(牌桌不變)。

var _speaker_label: Label
var _text_label: Label


func _init() -> void:
	add_theme_stylebox_override("panel", UiPalette.make_panel(UiPalette.PANEL_BG_LIGHT, UiPalette.ACCENT, 1, 8))
	visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 12)
	_speaker_label.add_theme_color_override("font_color", UiPalette.ACCENT)
	vbox.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(360, 0)
	_text_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	vbox.add_child(_text_label)


## speaker = 顯示用說話者名(空字串則隱藏說話者列)。
func show_line(speaker: String, text: String) -> void:
	_speaker_label.text = speaker
	_speaker_label.visible = speaker != ""
	_text_label.text = text
	visible = true


func hide_bubble() -> void:
	visible = false
