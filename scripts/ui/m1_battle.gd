extends Control

## M1 戰鬥場景。
## 目標:4 種敵人 × 3 種卡型,Place + Lock 完整流程,結算與揭露。

const CARD_PATHS := {
	"tool_arrow_pierce": "res://resources/cards/tool_arrow_pierce.tres",
	"tool_stone_impact": "res://resources/cards/tool_stone_impact.tres",
	"intel_weakness": "res://resources/cards/intel_weakness.tres",
}

## 序章前半 4 種敵人:每組 = [模板路徑, instance 路徑]
const ENEMIES := [
	{
		"key": "rabbit",
		"template": "res://resources/enemies/rabbit_template.tres",
		"instance": "res://resources/enemies/rabbit_default.tres",
	},
	{
		"key": "fox",
		"template": "res://resources/enemies/fox_template.tres",
		"instance": "res://resources/enemies/fox_default.tres",
	},
	{
		"key": "wolf",
		"template": "res://resources/enemies/wolf_template.tres",
		"instance": "res://resources/enemies/wolf_default.tres",
	},
	{
		"key": "mutant_wolf",
		"template": "res://resources/enemies/mutant_wolf_template.tres",
		"instance": "res://resources/enemies/mutant_wolf_default.tres",
	},
]

## 序章前半起手卡組規格(對應 卡牌資料庫.md §4.1)
const STARTING_DECK := {
	"tool_arrow_pierce": 10,
	"tool_stone_impact": 8,
	"intel_weakness": 2,
}

@onready var enemy_buttons_row: HBoxContainer = $VBox/EnemySelector/EnemyButtons
@onready var enemy_label: RichTextLabel = $VBox/EnemyPanel/EnemyLabel
@onready var revealed_label: RichTextLabel = $VBox/RevealedPanel/RevealedLabel
@onready var hand_buttons_row: HBoxContainer = $VBox/HandPanel/HandPanelVBox/HandButtons
@onready var hand_label: RichTextLabel = $VBox/HandPanel/HandPanelVBox/HandLabel
@onready var strike_container: VBoxContainer = $VBox/StrikePanel/StrikePanelVBox/StrikeScroll/StrikeContainer
@onready var strike_info_label: Label = $VBox/StrikePanel/StrikePanelVBox/StrikeInfoLabel
@onready var end_strike_button: Button = $VBox/ButtonRow/EndStrikeButton
@onready var reset_button: Button = $VBox/ButtonRow/ResetButton
@onready var result_label: RichTextLabel = $VBox/ResultPanel/ResultLabel

var card_library: Dictionary = {}
var enemy_data: Dictionary = {}  ## { key: { template: ..., instance: ... } }
var current_enemy_key: String = ""
var deck: Array[DeckEntry] = []
var engine: BattleEngine


func _ready() -> void:
	_load_resources()
	_build_enemy_buttons()
	_build_hand_buttons()
	end_strike_button.pressed.connect(_on_end_strike_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	_start_battle(ENEMIES[0]["key"])


func _load_resources() -> void:
	for card_id in CARD_PATHS:
		var card := load(CARD_PATHS[card_id]) as CardDefinition
		if card == null:
			push_error("無法載入卡牌:" + CARD_PATHS[card_id])
		else:
			card_library[card_id] = card
	for entry in ENEMIES:
		var key: String = entry["key"]
		var template := load(entry["template"]) as EnemyTemplate
		var instance := load(entry["instance"]) as EnemyInstance
		if template == null or instance == null:
			push_error("無法載入敵人資源:" + key)
			continue
		enemy_data[key] = { "template": template, "instance": instance }


func _build_enemy_buttons() -> void:
	for child in enemy_buttons_row.get_children():
		child.queue_free()
	for entry in ENEMIES:
		var key: String = entry["key"]
		var data: Dictionary = enemy_data.get(key, {})
		if data.is_empty():
			continue
		var btn := Button.new()
		var template: EnemyTemplate = data["template"]
		btn.text = template.template_name
		btn.pressed.connect(_on_enemy_button_pressed.bind(key))
		enemy_buttons_row.add_child(btn)


func _build_hand_buttons() -> void:
	for child in hand_buttons_row.get_children():
		child.queue_free()
	for card_id in CARD_PATHS:
		var card: CardDefinition = card_library.get(card_id, null)
		if card == null:
			continue
		var btn := Button.new()
		btn.text = "Place 「%s」" % card.card_name
		btn.pressed.connect(_on_place_button_pressed.bind(card_id))
		btn.name = "PlaceBtn_" + card_id
		hand_buttons_row.add_child(btn)


func _initialize_deck() -> void:
	deck.clear()
	for card_id in STARTING_DECK:
		var entry := DeckEntry.new()
		entry.card_id = card_id
		entry.count_remaining = STARTING_DECK[card_id]
		entry.count_consumed_total = 0
		deck.append(entry)


func _start_battle(enemy_key: String) -> void:
	current_enemy_key = enemy_key
	_initialize_deck()
	var data: Dictionary = enemy_data[enemy_key]
	engine = BattleEngine.new(data["instance"], data["template"], deck, card_library)
	_refresh_ui()


func _on_enemy_button_pressed(enemy_key: String) -> void:
	_start_battle(enemy_key)


func _on_place_button_pressed(card_id: String) -> void:
	if not engine.place_card(card_id):
		_show_error("無法 Place「%s」— 卡組不足或已達本擊上限" % card_library[card_id].card_name)
		return
	_refresh_ui()


func _on_unplace_button_pressed(index: int) -> void:
	if not engine.unplace_card_at(index):
		return
	_refresh_ui()


func _on_lock_button_pressed(index: int) -> void:
	if not engine.lock_card_at(index):
		return
	_refresh_ui()


func _on_end_strike_pressed() -> void:
	if not engine.can_commit():
		return
	engine.commit_strike()
	_refresh_ui()


func _on_reset_pressed() -> void:
	_start_battle(current_enemy_key)


## ====================
##  UI 更新
## ====================

func _refresh_ui() -> void:
	_refresh_enemy()
	_refresh_revealed()
	_refresh_hand()
	_refresh_strike()
	_refresh_result()
	_refresh_buttons()


func _refresh_enemy() -> void:
	var data: Dictionary = enemy_data[current_enemy_key]
	var template: EnemyTemplate = data["template"]
	var instance: EnemyInstance = data["instance"]
	var weakness_loc: Array[String] = []
	for t in template.weakness_range:
		weakness_loc.append(_localize_type(t))
	var weakness_str := ", ".join(weakness_loc)
	var limit_text := "%d 張" % instance.strike_limit if BattleEngine.STRIKE_LIMIT_ENABLED else "停用(暫時)"
	enemy_label.text = "[b]目標:[/b]%s\n[color=#888]類別:%s | 弱點範圍:%s | 戰鬥狀態:%s | 本擊上限:%s[/color]" % [
		instance.display_name,
		_localize_enemy_class(template.enemy_class),
		weakness_str,
		_localize_combat_state(instance.combat_state),
		limit_text,
	]


func _refresh_revealed() -> void:
	var info := engine.revealed_info
	if info.is_empty():
		revealed_label.text = "[color=#888][b]已揭露:[/b](尚未揭露任何敵人資訊)[/color]"
		return
	var lines: Array[String] = ["[b]已揭露:[/b]"]
	if info.has("enemy_weakness_types"):
		var mode_str := "深度(當前敵人)" if info.get("weakness_reveal_mode", "") == "depth" else "廣度(連戰所有剩餘敵人)"
		var types_array: Array = info["enemy_weakness_types"]
		var types_loc: Array[String] = []
		for t in types_array:
			types_loc.append(_localize_type(t))
		lines.append("  弱點類型(%s):%s" % [mode_str, ", ".join(types_loc)])
	if info.has("full_requirements"):
		lines.append("  完整需求表:%s" % str(info["full_requirements"]))
	if info.has("enemy_class"):
		lines.append("  敵人類別:%s" % _localize_enemy_class(info["enemy_class"]))
	revealed_label.text = "\n".join(lines)


func _refresh_hand() -> void:
	var lines: Array[String] = ["[b]卡組(剩餘張數):[/b]"]
	for entry in deck:
		var card: CardDefinition = card_library.get(entry.card_id, null)
		var display_name: String = entry.card_id
		var contrib_str := "(無貢獻)"
		if card != null:
			display_name = card.card_name
			contrib_str = _format_contribution(card.contribution)
		var in_strike := _count_in_strike_local(entry.card_id)
		var available := entry.count_remaining - in_strike
		lines.append("  %s × %d  (本擊中:%d)  [color=#888]%s[/color]" % [display_name, entry.count_remaining, in_strike, contrib_str])
	hand_label.text = "\n".join(lines)
	## 更新 Place 按鈕 disabled 狀態
	for card_id in CARD_PATHS:
		var btn: Button = hand_buttons_row.get_node_or_null("PlaceBtn_" + card_id)
		if btn == null:
			continue
		var entry := _find_deck_entry(card_id)
		var in_strike := _count_in_strike_local(card_id)
		var available := 0
		if entry != null:
			available = entry.count_remaining - in_strike
		var limit_reached := BattleEngine.STRIKE_LIMIT_ENABLED and engine.strike.size() >= engine.enemy_instance.strike_limit
		btn.disabled = engine.phase != BattleEngine.Phase.PLACE or available <= 0 or limit_reached


func _refresh_strike() -> void:
	for child in strike_container.get_children():
		child.queue_free()
	if engine.strike.placed_cards.is_empty() and engine.strike.locked_cards.is_empty():
		var lbl := Label.new()
		lbl.text = "  (尚未 Place 任何卡)"
		lbl.modulate = Color(0.6, 0.6, 0.6)
		strike_container.add_child(lbl)
	## Locked 區:lock_class=none 的疊放;其他個別顯示
	var locked_pool_groups := _group_pool_cards(engine.strike.locked_cards)
	for card_id in locked_pool_groups:
		var info: Dictionary = locked_pool_groups[card_id]
		strike_container.add_child(_make_stacked_row("[Locked]", info["card"], info["count"], -1, -1))
	for i in engine.strike.locked_cards.size():
		var c: CardDefinition = engine.strike.locked_cards[i]
		if c.lock_class == "none":
			continue
		strike_container.add_child(_make_stacked_row("[Locked]", c, 1, -1, -1))
	## Placed 區:lock_class=none 的疊放(Unplace 移除最後一張);其他個別顯示帶 Lock 按鈕
	var placed_pool_groups := _group_pool_cards(engine.strike.placed_cards)
	for card_id in placed_pool_groups:
		var info: Dictionary = placed_pool_groups[card_id]
		strike_container.add_child(_make_stacked_row("[Place]", info["card"], info["count"], info["last_index"], -1))
	for i in engine.strike.placed_cards.size():
		var c: CardDefinition = engine.strike.placed_cards[i]
		if c.lock_class == "none":
			continue
		var unplace_idx := i
		var lock_idx := i
		strike_container.add_child(_make_stacked_row("[Place]", c, 1, unplace_idx, lock_idx))
	strike_info_label.text = "本擊張數:%d  (本擊上限暫時停用)" % engine.strike.size()


## 將 lock_class="none" 的卡按 id 分組,記錄該 id 在原陣列中最後出現的索引(供 Unplace 使用)。
## 回傳格式:{ card_id: { "card": CardDefinition, "count": int, "last_index": int } }
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


func _make_stacked_row(prefix: String, card: CardDefinition, count: int, unplace_idx: int, lock_idx: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	var count_str := " × %d" % count if count > 1 else ""
	lbl.text = "%s %s%s  (%s)" % [prefix, card.card_name, count_str, _format_contribution(card.contribution)]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	if engine.phase == BattleEngine.Phase.PLACE:
		if unplace_idx >= 0:
			var unplace_btn := Button.new()
			unplace_btn.text = "−1" if count > 1 else "Unplace"
			unplace_btn.pressed.connect(_on_unplace_button_pressed.bind(unplace_idx))
			row.add_child(unplace_btn)
		if lock_idx >= 0:
			var lock_btn := Button.new()
			var hint := ""
			if card.lock_class == "optional":
				hint = " (揭露弱點)"
			elif card.lock_class == "required":
				hint = " (必須)"
			lock_btn.text = "Lock 此卡" + hint
			lock_btn.pressed.connect(_on_lock_button_pressed.bind(lock_idx))
			row.add_child(lock_btn)
	return row


func _refresh_result() -> void:
	if engine.phase != BattleEngine.Phase.RESOLVED:
		result_label.text = "[color=#888]按下「結束本擊」後顯示結算結果。[/color]"
		return
	var r: Dictionary = engine.result
	var contributions: Dictionary = r.get("contributions", {})
	var mixed_count: int = r.get("mixed_count", 0)
	var requirements: Dictionary = r.get("requirements", {})
	var passing: Array = r.get("passing_paths", [])
	var ohk: bool = r.get("ohk", false)

	var lines: Array[String] = ["[b]結算:[/b]"]
	for type_key in requirements:
		var required: int = requirements[type_key]
		var actual: int = mixed_count if type_key == "mixed" else contributions.get(type_key, 0)
		var hit := actual >= required
		var prefix := "  [color=#7fff7f]✓[/color]" if hit else "  [color=#ff7f7f]✗[/color]"
		lines.append("%s %s:%d / %d" % [prefix, _localize_type(type_key), actual, required])
	lines.append("")
	if ohk:
		var loc_paths: Array[String] = []
		for p in passing:
			loc_paths.append(_localize_type(p))
		lines.append("[color=#7fff7f][b]✓ OHK 成立[/b]  達標路徑:%s[/color]" % ", ".join(loc_paths))
	else:
		lines.append("[color=#ff7f7f][b]✗ Underkill[/b]  所有路徑皆未達標[/color]")
	result_label.text = "\n".join(lines)


func _refresh_buttons() -> void:
	end_strike_button.disabled = not engine.can_commit()
	reset_button.disabled = false


func _show_error(msg: String) -> void:
	result_label.text = "[color=#ff7f7f]" + msg + "[/color]"


## ====================
##  輔助
## ====================

func _find_deck_entry(card_id: String) -> DeckEntry:
	for e in deck:
		if e.card_id == card_id:
			return e
	return null


func _count_in_strike_local(card_id: String) -> int:
	var n := 0
	for c in engine.strike.placed_cards:
		if c.id == card_id:
			n += 1
	for c in engine.strike.locked_cards:
		if c.id == card_id:
			n += 1
	return n


func _format_contribution(contrib: Dictionary) -> String:
	if contrib.is_empty():
		return "(無貢獻)"
	var parts: Array[String] = []
	for k in contrib:
		parts.append("+%d %s" % [contrib[k], _localize_type(k)])
	return ", ".join(parts)


func _localize_type(type_key: String) -> String:
	match type_key:
		"impact": return "衝擊"
		"pierce": return "穿刺"
		"burn": return "燃燒"
		"mixed": return "混合"
		"flexible": return "任意"
		"generic": return "通用"
		_: return type_key


func _localize_enemy_class(cls: String) -> String:
	match cls:
		"rabbit": return "兔子型"
		"wolf": return "狼型"
		"leopard": return "豹型"
		"bear": return "熊型"
		_: return cls


func _localize_combat_state(state: String) -> String:
	match state:
		"standard": return "標準"
		"proactive": return "先攻"
		"ambush": return "被襲"
		_: return state


