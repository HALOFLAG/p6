class_name CardWidget
extends PanelContainer

## 卡牌色塊 widget(風格無關佔位版)。
## 對應 UI 設計指引.md §3.1 / §3.2。
## 顯示用 + 可掛動作按鈕;互動模型由父場景(庫存區 / 本擊區)決定。
## 美術風格定案後(M6)替換視覺,結構與 API 不變。

signal clicked

enum State {
	NORMAL,       ## 庫存中,可用
	IN_PLACE,     ## 已 Place 到本擊區
	LOCKED,       ## 已 Lock,定格
	DIMMED,       ## 教學期灰階(不建議當前嘗試)
	HIGHLIGHTED,  ## 教學期高亮(建議優先嘗試)
}

const CARD_MIN_SIZE := Vector2(152, 132)

var card: CardDefinition
var _state: int = State.NORMAL

var _type_band: Panel
var _name_label: Label
var _star_label: Label
var _class_label: Label
var _contrib_label: Label
var _lock_label: Label
var _subtitle_label: Label
var _action_row: HBoxContainer


func _init() -> void:
	custom_minimum_size = CARD_MIN_SIZE
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

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	header.add_child(_name_label)
	_star_label = Label.new()
	_star_label.add_theme_color_override("font_color", UiPalette.ACCENT)
	header.add_child(_star_label)

	_class_label = Label.new()
	_class_label.add_theme_font_size_override("font_size", 11)
	_class_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	vbox.add_child(_class_label)

	_contrib_label = Label.new()
	_contrib_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	vbox.add_child(_contrib_label)

	_lock_label = Label.new()
	_lock_label.add_theme_font_size_override("font_size", 11)
	_lock_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	vbox.add_child(_lock_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	_subtitle_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	vbox.add_child(_subtitle_label)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 4)
	vbox.add_child(_action_row)

	_apply_state()


# ============ 對外 API ============

## 以卡牌定義填入靜態資訊。
func setup(card_def: CardDefinition) -> void:
	card = card_def
	if card == null:
		return
	var primary := UiPalette.card_primary_type(card)
	_type_band.add_theme_stylebox_override("panel", UiPalette.make_block(UiPalette.type_color(primary)))
	_name_label.text = card.card_name
	_star_label.text = UiPalette.strength_stars(card.strength_level)
	_class_label.text = "%s・%s" % [
		UiPalette.resource_class_label(card.resource_class),
		UiPalette.function_class_label(card.function_class),
	]
	_contrib_label.text = UiPalette.contribution_text(card.contribution)
	var lock_text := UiPalette.lock_class_label(card.lock_class)
	_lock_label.text = lock_text
	_lock_label.visible = lock_text != ""


## 底部副標(卡組張數 / 本擊狀態 / [Locked] 等),由父場景決定內容。
func set_subtitle(text: String) -> void:
	_subtitle_label.text = text
	_subtitle_label.visible = text != ""


func set_state(new_state: int) -> void:
	_state = new_state
	_apply_state()


## 在卡片底部掛一顆動作按鈕,回傳給父場景連 signal。
func add_action_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	_action_row.add_child(btn)
	return btn


func clear_action_buttons() -> void:
	for child in _action_row.get_children():
		child.queue_free()


# ============ 內部 ============

func _apply_state() -> void:
	var border := UiPalette.PANEL_BORDER
	var border_w := 1
	var bg := UiPalette.PANEL_BG
	modulate = Color.WHITE
	match _state:
		State.NORMAL:
			pass
		State.IN_PLACE:
			border = UiPalette.type_color(UiPalette.card_primary_type(card)) if card != null else UiPalette.ACCENT
			border_w = 2
			bg = UiPalette.PANEL_BG_LIGHT
		State.LOCKED:
			border_w = 2
			bg = UiPalette.PANEL_BG_DARK
			modulate = Color(0.82, 0.82, 0.82)
		State.DIMMED:
			modulate = Color(1, 1, 1, 0.4)
		State.HIGHLIGHTED:
			border = UiPalette.ACCENT
			border_w = 2
	add_theme_stylebox_override("panel", UiPalette.make_panel(bg, border, border_w))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
