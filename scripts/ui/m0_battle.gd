extends Control

## M0 純文字戰鬥場景。
## 目標:Place 射箭 → End Strike → 顯示「穿刺 1 ≥ 1 → OHK ✓」。

const CARD_PATH := "res://resources/cards/tool_arrow_pierce.tres"
const ENEMY_TEMPLATE_PATH := "res://resources/enemies/rabbit_template.tres"
const ENEMY_INSTANCE_PATH := "res://resources/enemies/rabbit_default.tres"

@onready var enemy_label: RichTextLabel = $VBox/EnemyPanel/EnemyLabel
@onready var hand_label: RichTextLabel = $VBox/HandPanel/HandLabel
@onready var strike_label: RichTextLabel = $VBox/StrikePanel/StrikeLabel
@onready var result_label: RichTextLabel = $VBox/ResultPanel/ResultLabel
@onready var place_button: Button = $VBox/ButtonRow/PlaceButton
@onready var unplace_button: Button = $VBox/ButtonRow/UnplaceButton
@onready var end_strike_button: Button = $VBox/ButtonRow/EndStrikeButton
@onready var reset_button: Button = $VBox/ButtonRow/ResetButton

var card_def: CardDefinition
var enemy_template: EnemyTemplate
var enemy_instance: EnemyInstance
var deck: Array[DeckEntry] = []
var card_library: Dictionary = {}
var engine: BattleEngine


func _ready() -> void:
	_load_resources()
	_initialize_battle()
	_connect_signals()
	_refresh_ui()


func _load_resources() -> void:
	card_def = load(CARD_PATH) as CardDefinition
	enemy_template = load(ENEMY_TEMPLATE_PATH) as EnemyTemplate
	enemy_instance = load(ENEMY_INSTANCE_PATH) as EnemyInstance
	if card_def == null:
		push_error("無法載入卡牌:" + CARD_PATH)
	if enemy_template == null:
		push_error("無法載入敵人模板:" + ENEMY_TEMPLATE_PATH)
	if enemy_instance == null:
		push_error("無法載入敵人 instance:" + ENEMY_INSTANCE_PATH)
	card_library[card_def.id] = card_def


func _initialize_battle() -> void:
	deck.clear()
	## M0:卡組起手 = 3 張射箭(讓玩家有餘裕嘗試)
	var entry := DeckEntry.new()
	entry.card_id = card_def.id
	entry.count_remaining = 3
	entry.count_consumed_total = 0
	deck.append(entry)
	engine = BattleEngine.new(enemy_instance, enemy_template, deck, card_library)


func _connect_signals() -> void:
	place_button.pressed.connect(_on_place_pressed)
	unplace_button.pressed.connect(_on_unplace_pressed)
	end_strike_button.pressed.connect(_on_end_strike_pressed)
	reset_button.pressed.connect(_on_reset_pressed)


func _on_place_pressed() -> void:
	if engine.place_card(card_def.id):
		_refresh_ui()
	else:
		_show_error("無法 Place — 已達本擊上限或卡組不足")


func _on_unplace_pressed() -> void:
	if engine.unplace_card(card_def.id):
		_refresh_ui()


func _on_end_strike_pressed() -> void:
	if engine.phase != BattleEngine.Phase.PLACE:
		return
	engine.commit_strike()
	_refresh_ui()


func _on_reset_pressed() -> void:
	_initialize_battle()
	_refresh_ui()


func _refresh_ui() -> void:
	_refresh_enemy()
	_refresh_hand()
	_refresh_strike()
	_refresh_result()
	_refresh_buttons()


func _refresh_enemy() -> void:
	var name := enemy_template.template_name
	var req: Dictionary = enemy_instance.requirements
	var req_str := ""
	for k in req:
		req_str += "%s %d / " % [_localize_type(k), req[k]]
	req_str = req_str.trim_suffix(" / ")
	enemy_label.text = "[b]目標:[/b]%s\n[color=#888]需求:%s | 本擊上限:%d 張[/color]" % [
		name, req_str, enemy_instance.strike_limit
	]


func _refresh_hand() -> void:
	var lines: Array[String] = []
	lines.append("[b]卡組(剩餘張數):[/b]")
	for entry in deck:
		var card: CardDefinition = card_library.get(entry.card_id, null)
		var display_name: String = entry.card_id
		var contrib_dict: Dictionary = {}
		if card != null:
			display_name = card.card_name
			contrib_dict = card.contribution
		var contrib_str := _format_contribution(contrib_dict)
		lines.append("  %s × %d  [color=#888]%s[/color]" % [display_name, entry.count_remaining, contrib_str])
	hand_label.text = "\n".join(lines)


func _refresh_strike() -> void:
	var placed := engine.strike.placed_cards
	var locked := engine.strike.locked_cards
	var lines: Array[String] = []
	lines.append("[b]本擊區:[/b]")
	if placed.is_empty() and locked.is_empty():
		lines.append("  [color=#888](尚未 Place 任何卡)[/color]")
	for c in placed:
		lines.append("  [Place] %s  [color=#888]%s[/color]" % [c.card_name, _format_contribution(c.contribution)])
	for c in locked:
		lines.append("  [Locked] %s  [color=#888]%s[/color]" % [c.card_name, _format_contribution(c.contribution)])
	lines.append("[color=#888]張數:%d / %d[/color]" % [engine.strike.size(), enemy_instance.strike_limit])
	strike_label.text = "\n".join(lines)


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

	var lines: Array[String] = []
	lines.append("[b]結算:[/b]")
	for type_key in requirements:
		var required: int = requirements[type_key]
		var actual: int
		if type_key == "mixed":
			actual = mixed_count
		else:
			actual = contributions.get(type_key, 0)
		var hit := actual >= required
		var prefix := "  [color=#7fff7f]✓[/color]" if hit else "  [color=#ff7f7f]✗[/color]"
		lines.append("%s %s:%d / %d" % [prefix, _localize_type(type_key), actual, required])

	lines.append("")
	if ohk:
		var localized_paths: Array[String] = []
		for path in passing:
			localized_paths.append(_localize_type(path))
		lines.append("[color=#7fff7f][b]✓ OHK 成立[/b]  達標路徑:%s[/color]" % ", ".join(localized_paths))
	else:
		lines.append("[color=#ff7f7f][b]✗ Underkill[/b]  所有路徑皆未達標[/color]")
	result_label.text = "\n".join(lines)


func _refresh_buttons() -> void:
	var in_place := engine.phase == BattleEngine.Phase.PLACE
	place_button.disabled = not in_place
	unplace_button.disabled = not in_place or engine.strike.placed_cards.is_empty()
	end_strike_button.disabled = not in_place or engine.strike.placed_cards.is_empty()
	reset_button.disabled = false


func _show_error(msg: String) -> void:
	result_label.text = "[color=#ff7f7f]" + msg + "[/color]"


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
