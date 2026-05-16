class_name PortraitPair
extends VBoxContainer

## 雙頭像(玩家 + NPC,風格無關佔位版)。
## 對應 第一期 UI 線框圖.md §4.1。
## 發言者亮起、沉默者暗淡 —— 對應雙聲道對話的「誰在說話」。
## 立繪用色塊佔位;美術風格定案後(M6)替換為頭像。

const BOX_SIZE := Vector2(80, 42)
const PLAYER_COLOR := Color("4a78a8")
const NPC_COLOR := Color("a8794a")

var _player_box: PanelContainer
var _npc_box: PanelContainer


func _init() -> void:
	add_theme_constant_override("separation", 4)
	_player_box = _make_box("玩家", PLAYER_COLOR)
	_npc_box = _make_box("父親", NPC_COLOR)
	## 父親在上、玩家在下(對應截圖版型)
	add_child(_npc_box)
	add_child(_player_box)
	set_speaking("none")


func _make_box(text: String, color: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = BOX_SIZE
	box.add_theme_stylebox_override("panel", UiPalette.make_panel(color.darkened(0.15), UiPalette.PANEL_BORDER, 1, 3))
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	box.add_child(label)
	return box


## who = "player" / "npc" / "none" —— 發言者全亮,其餘暗淡。
func set_speaking(who: String) -> void:
	_player_box.modulate = Color.WHITE if who == "player" else Color(1, 1, 1, 0.45)
	_npc_box.modulate = Color.WHITE if who == "npc" else Color(1, 1, 1, 0.45)
	if who == "none":
		_player_box.modulate = Color(1, 1, 1, 0.7)
		_npc_box.modulate = Color(1, 1, 1, 0.7)
