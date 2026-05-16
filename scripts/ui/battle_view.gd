class_name BattleView
extends RefCounted

## 戰鬥-zone UI 控制器(純 script,不擁有 scene tree)。
## 對應 ADR-0002:host 場景維持 .tscn 不動,將 widget node refs 透過 attach 傳入;
## view 渲染 + 內部消化 place/unplace/lock/敵人情報切換/連戰預覽切換,對外只 emit 兩個 signal。
##
## 範圍(只擁有「戰鬥-zone widgets」):
##   pile_slot / strike_slot / status_content / enemy_figure / enemy_info_slot
##   end_strike_button / advance_button(可選)/ progress_slot(可選)/ strike_info_label(可選)
##
## 不擁有(host 維持):
##   dialogue_bubble / portrait_pair / progress_indicator / narrative_box
##   —— 它們跨 phase 使用,host 在 INTRO / PRE_CHAIN / POST_CHAIN 也要用。
##
## 對外 API:
##   attach(refs)              —— 一次傳入所有 node refs(可選欄位允許 missing)
##   set_engine(engine)        —— 切換到下一場戰鬥的 BattleEngine,view 重新渲染
##   set_encounter(enc, n)     —— host 傳 EnemyEncounter + 連戰剩餘數(n<0 表 m1 dev 不顯示)
##   set_preview_source(c)     —— Callable -> Array[Color];m1 dev 不註冊 → 預覽 affordance 自動 suppress
##   set_advance_label(text)   —— host 自訂 advance 按鈕顯示文字(「繼續」/「結束連戰」)
##   signal strike_committed(result: Dictionary)
##   signal advance_pressed

signal strike_committed(result: StrikeResult)
signal advance_pressed

## 預覽佈局常數(來自原 m1/m2 既定值)
const ENEMY_FIGURE_NORMAL := Vector2(1040, 92)
const ENEMY_FIGURE_PREVIEW := Vector2(600, 92)
const AFTERIMAGE_SIZE := Vector2(140, 130)
const AFTERIMAGE_START_X := 700.0
const AFTERIMAGE_STEP_X := 160.0
const AFTERIMAGE_Y := 92.0

# ============ Host 提供的 node refs ============
var pile_slot: HBoxContainer
var strike_slot: HBoxContainer
var status_content: VBoxContainer
var enemy_figure: ColorRect
var enemy_figure_label: Label
var enemy_info_slot: Control
var end_strike_button: Button
var advance_button: Button
var progress_slot: Control
var strike_info_label: Label

# ============ 內部狀態 ============
var engine: BattleEngine
var enemy_widget: EnemyWidget
var card_piles: Dictionary = {}  ## { card_id: CardPile }
var _preview_source: Callable
var _preview_mode: bool = false
var _preview_afterimages: Array[ColorRect] = []
var _inputs_wired: bool = false


# ============================
#  對外 API
# ============================

## 一次傳入 host 場景的 widget node refs。可選欄位允許 missing(m1 沒有 advance_button,等)。
## 必選:pile_slot / strike_slot / status_content / enemy_figure / enemy_info_slot / end_strike_button
## 可選:enemy_figure_label / advance_button / progress_slot / strike_info_label
func attach(refs: Dictionary) -> void:
	pile_slot = refs.get("pile_slot")
	strike_slot = refs.get("strike_slot")
	status_content = refs.get("status_content")
	enemy_figure = refs.get("enemy_figure")
	enemy_figure_label = refs.get("enemy_figure_label")
	enemy_info_slot = refs.get("enemy_info_slot")
	end_strike_button = refs.get("end_strike_button")
	advance_button = refs.get("advance_button")
	progress_slot = refs.get("progress_slot")
	strike_info_label = refs.get("strike_info_label")
	_build_card_piles()
	_wire_inputs()


## 切換到新一場戰鬥的 engine。重建 enemy_widget,重置預覽 / 情報展開,重新渲染。
func set_engine(new_engine: BattleEngine) -> void:
	engine = new_engine
	_setup_enemy_visuals_default()
	_set_preview_mode(false)
	_apply_enemy_info_state(false)
	_refresh_all()


## 自訂 enemy 顯示 — host 傳 EnemyEncounter(菁英 / label_override 內嵌)+ 連戰剩餘數。
## remaining_count < 0 表 m1 dev 單體戰:不顯示連戰剩餘 counter。
func set_encounter(enc: EnemyEncounter, remaining_count: int = -1) -> void:
	if enc == null:
		return
	var tmpl := enc.enemy_template
	var inst := enc.enemy_instance
	if enemy_figure_label != null:
		var display: String = enc.label_override if enc.label_override != "" else inst.display_name
		enemy_figure_label.text = "%s\n(點擊查看情報)" % display
	if enemy_widget != null:
		enemy_widget.setup(tmpl, inst, enc.is_elite, enc.label_override)
		if remaining_count >= 0:
			enemy_widget.set_remaining(remaining_count)


## 註冊預覽資料 Callable。Callable 回傳 Array[Color](每隻剩餘敵人的類別色)。
## m1 dev 不呼叫 → 預覽 affordance 點擊時自動 suppress。
func set_preview_source(src: Callable) -> void:
	_preview_source = src


## 自訂 advance 按鈕文字(m2 用,文字隨 enemy_queue 是否空切換)。
func set_advance_label(text: String) -> void:
	if advance_button != null:
		advance_button.text = text


# ============================
#  Setup helpers
# ============================

func _build_card_piles() -> void:
	if pile_slot == null:
		return
	for child in pile_slot.get_children():
		child.queue_free()
	card_piles.clear()
	for card_id in ResourceLibrary.cards():
		var card: CardDefinition = ResourceLibrary.card(card_id)
		if card == null:
			continue
		var pile := CardPile.new()
		pile_slot.add_child(pile)
		pile.setup(card)
		pile.pile_clicked.connect(_on_pile_clicked.bind(card_id))
		card_piles[card_id] = pile


func _wire_inputs() -> void:
	if _inputs_wired:
		return
	if end_strike_button != null:
		end_strike_button.pressed.connect(_on_end_strike_button_pressed)
	if advance_button != null:
		advance_button.pressed.connect(_on_advance_button_pressed)
	if enemy_figure != null:
		enemy_figure.mouse_filter = Control.MOUSE_FILTER_STOP
		enemy_figure.gui_input.connect(_on_enemy_figure_input)
	if progress_slot != null:
		progress_slot.mouse_filter = Control.MOUSE_FILTER_STOP
		progress_slot.gui_input.connect(_on_progress_slot_input)
	_inputs_wired = true


func _setup_enemy_visuals_default() -> void:
	if engine == null:
		return
	var tmpl := engine.enemy_template
	var inst := engine.enemy_instance
	if enemy_figure != null:
		enemy_figure.color = UiPalette.enemy_class_color(tmpl.enemy_class)
	if enemy_figure_label != null:
		var display: String = inst.display_name if inst.display_name != "" else tmpl.template_name
		enemy_figure_label.text = "%s\n(點擊查看情報)" % display
	if enemy_info_slot != null:
		for child in enemy_info_slot.get_children():
			child.queue_free()
		enemy_widget = EnemyWidget.new()
		enemy_info_slot.add_child(enemy_widget)
		enemy_widget.set_anchors_preset(Control.PRESET_FULL_RECT)
		enemy_widget.setup(tmpl, inst)


# ============================
#  輸入處理(全部 view 內部消化)
# ============================

func _on_pile_clicked(card_id: String) -> void:
	if engine == null or engine.phase != BattleEngine.Phase.PLACE:
		return
	if not engine.place_card(card_id):
		return
	_refresh_all()


func _on_unplace_button_pressed(index: int) -> void:
	if engine == null:
		return
	if engine.unplace_card_at(index):
		_refresh_all()


func _on_lock_button_pressed(index: int) -> void:
	if engine == null:
		return
	if engine.lock_card_at(index):
		_refresh_all()


func _on_end_strike_button_pressed() -> void:
	if engine == null or not engine.can_commit():
		return
	_set_preview_mode(false)  ## 結算前收掉連戰預覽,避免殘影殘留到結算狀態
	var result: StrikeResult = engine.commit_strike()
	_refresh_all()
	strike_committed.emit(result)


func _on_advance_button_pressed() -> void:
	if engine == null or engine.phase != BattleEngine.Phase.RESOLVED:
		return
	advance_pressed.emit()


## 點敵人立繪 → 切換敵人情報欄展開 / 收合。
func _on_enemy_figure_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if enemy_info_slot == null:
			return
		_apply_enemy_info_state(not enemy_info_slot.visible)


## 點連戰序列 → 切換連戰預覽(僅 PLACE 階段 + 有註冊預覽 source 才生效)。
func _on_progress_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if engine == null or engine.phase != BattleEngine.Phase.PLACE:
			return
		if not _preview_source.is_valid():
			return  ## m1 dev 模式 / 未註冊預覽 source → affordance 無效
		_set_preview_mode(not _preview_mode)


# ============================
#  敵人情報 / 連戰預覽 overlay
# ============================

## 敵人情報收合 / 展開:立繪固定不動,情報欄在立繪左側出現。與連戰預覽互斥。
func _apply_enemy_info_state(expanded: bool) -> void:
	if enemy_info_slot == null:
		return
	if expanded and _preview_mode:
		_set_preview_mode(false)
	enemy_info_slot.visible = expanded


## 連戰預覽開 / 關:開 → 立繪左移、生成殘影排在其右後方;關 → 立繪歸位、殘影清除。
func _set_preview_mode(on: bool) -> void:
	_preview_mode = on
	for ghost in _preview_afterimages:
		var parent := ghost.get_parent()
		if parent != null:
			parent.remove_child(ghost)
		ghost.queue_free()
	_preview_afterimages.clear()
	if on:
		if enemy_info_slot != null:
			enemy_info_slot.visible = false
		if enemy_figure != null:
			enemy_figure.position = ENEMY_FIGURE_PREVIEW
		_spawn_preview_afterimages()
	else:
		if enemy_figure != null:
			enemy_figure.position = ENEMY_FIGURE_NORMAL


## 從 _preview_source pull 一份 Array[Color];每個 color 生一個半透明殘影,畫在立繪後方。
func _spawn_preview_afterimages() -> void:
	if enemy_figure == null or not _preview_source.is_valid():
		return
	var classes: Array = _preview_source.call()
	if classes.is_empty():
		return
	var stage := enemy_figure.get_parent()
	var figure_index := enemy_figure.get_index()
	for i in classes.size():
		var color: Color = classes[i]
		var ghost := ColorRect.new()
		ghost.color = Color(color.r, color.g, color.b, maxf(0.5 - i * 0.08, 0.15))
		ghost.position = Vector2(AFTERIMAGE_START_X + i * AFTERIMAGE_STEP_X, AFTERIMAGE_Y)
		ghost.size = AFTERIMAGE_SIZE
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(ghost)
		stage.move_child(ghost, figure_index)  ## 移到立繪之前 → 畫在立繪後方
		_preview_afterimages.append(ghost)


# ============================
#  Renderers
# ============================

func _refresh_all() -> void:
	if engine == null:
		return
	if enemy_widget != null:
		enemy_widget.set_revealed(engine.revealed_info)
	_refresh_piles()
	_refresh_strike()
	_refresh_status()
	_refresh_buttons()


func _refresh_piles() -> void:
	if pile_slot == null:
		return
	var is_place := engine.phase == BattleEngine.Phase.PLACE
	for card_id in card_piles:
		var pile: CardPile = card_piles[card_id]
		var n := engine.available_count(card_id)
		pile.set_count(n)
		pile.set_enabled(is_place and n > 0)


## 本擊區時間線:Lock 卡在左、Place 卡在右,同一條 HBox(對應線框圖單一時間線)。
func _refresh_strike() -> void:
	if strike_slot == null:
		return
	for child in strike_slot.get_children():
		child.queue_free()
	var is_place := engine.phase == BattleEngine.Phase.PLACE

	## ---- 已 Lock 的卡(定格)----
	var locked_groups := _group_pool_cards(engine.strike.locked_cards)
	for card_id in locked_groups:
		var info: Dictionary = locked_groups[card_id]
		strike_slot.add_child(_make_card_widget(info["card"], CardWidget.State.LOCKED, "Locked ×%d" % info["count"]))
	for c in engine.strike.locked_cards:
		if c.lock_class == "none":
			continue
		strike_slot.add_child(_make_card_widget(c, CardWidget.State.LOCKED, "Locked"))

	## ---- Place 中的卡(可調整)----
	var placed_groups := _group_pool_cards(engine.strike.placed_cards)
	for card_id in placed_groups:
		var info: Dictionary = placed_groups[card_id]
		var w := _make_card_widget(info["card"], CardWidget.State.IN_PLACE, "Place ×%d" % info["count"])
		if is_place:
			var unplace_btn := w.add_action_button("−1" if info["count"] > 1 else "Unplace")
			unplace_btn.pressed.connect(_on_unplace_button_pressed.bind(info["last_index"]))
		strike_slot.add_child(w)
	for i in engine.strike.placed_cards.size():
		var c: CardDefinition = engine.strike.placed_cards[i]
		if c.lock_class == "none":
			continue
		var w := _make_card_widget(c, CardWidget.State.IN_PLACE, "Place")
		if is_place:
			var unplace_btn := w.add_action_button("Unplace")
			unplace_btn.pressed.connect(_on_unplace_button_pressed.bind(i))
			var hint := " (揭露弱點)" if c.lock_class == "optional" else (" (必須)" if c.lock_class == "required" else "")
			var lock_btn := w.add_action_button("Lock" + hint)
			lock_btn.pressed.connect(_on_lock_button_pressed.bind(i))
		strike_slot.add_child(w)

	if strike_slot.get_child_count() == 0:
		var hint := Label.new()
		hint.text = "(時間線:尚未 Place 任何卡)"
		hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		strike_slot.add_child(hint)

	if strike_info_label != null:
		strike_info_label.text = "本擊張數:%d  (本擊上限暫時停用)" % engine.strike.size()


func _make_card_widget(card: CardDefinition, state: int, subtitle: String) -> CardWidget:
	var w := CardWidget.new()
	w.setup(card)
	w.set_subtitle(subtitle)
	w.set_state(state)
	return w


## 狀態面板:PLACE 階段顯示本擊狀態加總;RESOLVED 顯示判定 + 需求 bar(host 可在 strike_committed
## 後 override status_content 加入更豐富的資訊,如「✓ 擊敗 X」+ 失敗敘述等)。
func _refresh_status() -> void:
	if status_content == null:
		return
	for child in status_content.get_children():
		child.queue_free()

	if engine.phase != BattleEngine.Phase.RESOLVED:
		var title := Label.new()
		title.text = "本擊狀態"
		title.add_theme_color_override("font_color", UiPalette.ACCENT)
		status_content.add_child(title)
		var counts := engine.strike.get_type_counts()
		var mixed := engine.strike.get_mixed_count()
		status_content.add_child(_make_status_row("衝擊", counts.get("impact", 0)))
		status_content.add_child(_make_status_row("穿刺", counts.get("pierce", 0)))
		status_content.add_child(_make_status_row("燃燒", counts.get("burn", 0)))
		status_content.add_child(_make_status_row("混合", mixed))
		return

	## RESOLVED — 通用判定 + 需求 bar(m2 會在 strike_committed handler 中 override)
	var r: StrikeResult = engine.result
	var resolved_title := Label.new()
	if r != null and r.ohk:
		var loc_paths: Array[String] = []
		for p in r.passing_paths:
			loc_paths.append(UiPalette.type_label(p))
		resolved_title.text = "結算 — ✓ OHK(%s)" % ", ".join(loc_paths)
		resolved_title.add_theme_color_override("font_color", UiPalette.OK_COLOR)
	else:
		resolved_title.text = "結算 — ✗ Underkill"
		resolved_title.add_theme_color_override("font_color", UiPalette.FAIL_COLOR)
	status_content.add_child(resolved_title)
	status_content.add_child(RequirementBar.build_group(r))


func _make_status_row(type_label: String, value: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = type_label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = str(value)
	value_label.add_theme_color_override("font_color", UiPalette.TEXT_MAIN)
	row.add_child(value_label)
	return row


## 按鈕啟用狀態:end_strike 跟 engine.can_commit() 走;advance 在非 RESOLVED 時 disable
## (RESOLVED 時 host 自行啟用 + 設置文字)。
func _refresh_buttons() -> void:
	if end_strike_button != null:
		end_strike_button.disabled = not engine.can_commit()
	if advance_button != null and engine.phase != BattleEngine.Phase.RESOLVED:
		advance_button.disabled = true


# ============================
#  輔助
# ============================

## 將 lock_class="none" 的卡按 id 分組,記錄該 id 最後出現的索引(供 Unplace 使用)。
func _group_pool_cards(cards: Array[CardDefinition]) -> Dictionary:
	var groups: Dictionary = {}
	for i in cards.size():
		var c: CardDefinition = cards[i]
		if c.lock_class != "none":
			continue
		if not groups.has(c.id):
			groups[c.id] = { "card": c, "count": 0, "last_index": i }
		groups[c.id]["count"] += 1
		groups[c.id]["last_index"] = i
	return groups
