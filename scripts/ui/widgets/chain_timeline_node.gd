class_name ChainTimelineNode
extends Control

## 連戰時間軸的單一節點(ADR-0008)。
##
## 4 種狀態(由 data["state"] 決定):
##   sealed_defeated  → 實心綠
##   sealed_escaped   → 實心紅
##   current          → 實心高亮 + pulse(常駐)
##   pending          → 空心細邊
##   pending_elite    → 空心紅邊 + ⚡ 角標
##
## 動畫(由外部 ChainTimeline 觸發,本 widget 提供 play_* API):
##   play_color_lerp     — current → sealed 時用,顏色 + icon 漸變
##   play_scale_in       — 新誕生 chip(精英化 append / clone insert)
##   play_pulse          — pending elite 初次出現,N 個 cycle 後自停

signal clicked(node)

const NODE_HEIGHT := 36
const LABEL_GAP := 2
const ELITE_BADGE_OFFSET := Vector2(8, -8)  ## ⚡ 相對節點中心

var data: Dictionary = {}                   ## 由 ChainTimeline.apply() 設定
var _pulse_tween: Tween = null
var _label: Label
var _is_hovered := false


func _init() -> void:
	custom_minimum_size = Vector2(36, NODE_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", ChainTimeline.LABEL_FONT_SIZE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = -14
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func apply(d: Dictionary) -> void:
	data = d
	if _label != null:
		_label.text = str(d.get("label", ""))
		_label.add_theme_color_override("font_color", _label_color())
	tooltip_text = str(d.get("tooltip", ""))
	if str(d.get("state", "")) == "current":
		_start_current_pulse()
	else:
		_stop_pulse()
	queue_redraw()


func get_node_radius() -> int:
	match str(data.get("state", "")):
		"sealed_defeated", "sealed_escaped":
			return ChainTimeline.SEALED_RADIUS
		"current":
			return ChainTimeline.CURRENT_RADIUS
		_:
			return ChainTimeline.PENDING_RADIUS


func _label_color() -> Color:
	var state: String = str(data.get("state", ""))
	if state.begins_with("sealed_"):
		return UiPalette.TEXT_MAIN
	if state == "current":
		return UiPalette.ACCENT
	return UiPalette.TEXT_DIM


# ============ 繪製 ============

func _draw() -> void:
	var state: String = str(data.get("state", ""))
	var radius: int = get_node_radius()
	var center := Vector2(size.x / 2.0, ChainTimeline.CURRENT_RADIUS)  ## 對齊主軸 y
	var fill: Color
	var border: Color
	var filled := true
	var border_width := 1.0

	match state:
		"sealed_defeated":
			fill = UiPalette.OK_COLOR
			border = UiPalette.OK_COLOR.lightened(0.2)
			border_width = 2.0
		"sealed_escaped":
			fill = UiPalette.FAIL_COLOR
			border = UiPalette.FAIL_COLOR.lightened(0.2)
			border_width = 2.0
		"current":
			fill = UiPalette.ACCENT.darkened(0.2)
			border = UiPalette.ACCENT
			border_width = 2.5
		"pending":
			fill = Color(0, 0, 0, 0)
			border = UiPalette.TEXT_DIM
			border_width = 1.0
			filled = false
		"pending_elite":
			fill = Color(0, 0, 0, 0)
			border = UiPalette.FAIL_COLOR
			border_width = 1.5
			filled = false

	## 主體圓
	if filled:
		draw_circle(center, radius, fill)
	draw_arc(center, radius, 0, TAU, 32, border, border_width, true)

	## sealed 內部 icon
	match state:
		"sealed_defeated":
			_draw_check(center, radius)
		"sealed_escaped":
			_draw_cross(center, radius)
		"current":
			_draw_triangle(center, radius)

	## elite ⚡ 角標
	if state == "pending_elite":
		var badge_pos := center + ELITE_BADGE_OFFSET
		draw_circle(badge_pos, 4, UiPalette.FAIL_COLOR)
		var icon_lbl := "⚡"
		var font := get_theme_default_font()
		draw_string(font, badge_pos + Vector2(-3, 3), icon_lbl,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color.WHITE)

	## hover 外環
	if _is_hovered:
		draw_arc(center, radius + 3, 0, TAU, 32, UiPalette.ACCENT.lightened(0.3), 1.0, true)


func _draw_check(c: Vector2, r: int) -> void:
	var s := r * 0.45
	var pts := PackedVector2Array([
		c + Vector2(-s, 0),
		c + Vector2(-s * 0.3, s * 0.6),
		c + Vector2(s, -s * 0.6),
	])
	draw_polyline(pts, Color.WHITE, 2.0, true)


func _draw_cross(c: Vector2, r: int) -> void:
	var s := r * 0.5
	draw_line(c + Vector2(-s, -s), c + Vector2(s, s), Color.WHITE, 2.0, true)
	draw_line(c + Vector2(-s, s), c + Vector2(s, -s), Color.WHITE, 2.0, true)


func _draw_triangle(c: Vector2, r: int) -> void:
	var s := r * 0.5
	var pts := PackedVector2Array([
		c + Vector2(-s * 0.6, -s),
		c + Vector2(-s * 0.6, s),
		c + Vector2(s, 0),
	])
	draw_colored_polygon(pts, Color.WHITE)


# ============ Input ============

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var state: String = str(data.get("state", ""))
			if state.begins_with("sealed_") or state == "pending_elite":
				clicked.emit(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_is_hovered = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_is_hovered = false
		queue_redraw()


# ============ 動畫 ============

func play_color_lerp(duration: float) -> void:
	## 純 redraw,沒有 property 可 tween;改用 modulate 短暫高亮
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.4, 1.4, 1.4, 1), duration * 0.5)
	tween.tween_property(self, "modulate", Color.WHITE, duration * 0.5)


func play_scale_in(duration: float) -> void:
	pivot_offset = size / 2.0
	scale = Vector2(0.1, 0.1)
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, duration)


func play_pulse(cycles: int, cycle_duration: float) -> void:
	_stop_pulse()
	pivot_offset = size / 2.0
	_pulse_tween = create_tween().set_loops(cycles)
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2(1.15, 1.15), cycle_duration / 2.0)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, cycle_duration / 2.0)


func _start_current_pulse() -> void:
	## current 節點常駐淡淡呼吸(scale 1.0 ↔ 1.05)
	_stop_pulse()
	pivot_offset = size / 2.0
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2(1.06, 1.06), 0.8)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.8)


func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	scale = Vector2.ONE
