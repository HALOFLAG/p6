class_name UiPalette
extends RefCounted

## 佔位配色表 + 樣式工廠 + 顯示字串集中地。
## 風格無關階段(M0-M5)用色塊呈現;美術風格定案後(M6)整批替換這支。
## 對應 UI 設計指引.md §9「風格無關 vs 風格相關」。

# ============ 類型色(衝擊/穿刺/燃燒/...) ============
const TYPE_COLORS := {
	"impact": Color("e8943a"),    # 衝擊 — 琥珀橙
	"pierce": Color("3e7cb1"),    # 穿刺 — 鋼藍
	"burn": Color("d2452f"),      # 燃燒 — 緋紅
	"mixed": Color("8e6bb0"),     # 混合 — 紫
	"flexible": Color("c9a23f"),  # 任意 — 金
	"generic": Color("9aa0a6"),   # 通用 — 灰
	"intel": Color("3fa98c"),     # 情報 — 青綠
	"none": Color("6b6e76"),      # 無 — 深灰
}

# ============ 敵人類別色 ============
const ENEMY_CLASS_COLORS := {
	"rabbit": Color("8fae6b"),       # 兔子型 — 草綠
	"gray_rabbit": Color("6e7e8f"),  # 灰兔型 — 偏藍灰(失敗 spawn clone 機制)
	"wolf": Color("a06a4a"),         # 狼型 — 棕
	"leopard": Color("c2913e"),      # 豹型 — 土黃
	"bear": Color("7a4a4a"),         # 熊型 — 暗紅棕
}

# ============ 通用面板色 ============
const PANEL_BG := Color("23252b")
const PANEL_BG_LIGHT := Color("2d2f37")
const PANEL_BG_DARK := Color("1a1b20")
const PANEL_BORDER := Color("3d404a")
const ACCENT := Color("d8c47a")        # 高亮 / 當前焦點
const TEXT_MAIN := Color("e6e7ea")
const TEXT_DIM := Color("8a8d96")
const OK_COLOR := Color("7fcf6b")
const FAIL_COLOR := Color("d2655a")


# ============ 顏色查詢 ============

static func type_color(type_key: String) -> Color:
	return TYPE_COLORS.get(type_key, TYPE_COLORS["none"])


static func enemy_class_color(cls: String) -> Color:
	return ENEMY_CLASS_COLORS.get(cls, Color("808080"))


## 卡牌的主色 —— 優先取 contribution 的第一個類型,情報卡取 intel,否則取弱點類型。
static func card_primary_type(card: CardDefinition) -> String:
	if card != null and not card.contribution.is_empty():
		for k in card.contribution:
			return k
	if card != null and card.function_class == "intel":
		return "intel"
	if card != null and card.weakness_type != "none":
		return card.weakness_type
	return "none"


# ============ 樣式工廠 ============

## 建一個 StyleBoxFlat 面板樣式。border_color 為空時不畫邊框。
static func make_panel(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 1, radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb


## 純色塊樣式(無內距),給 type band / portrait 用。
static func make_block(color: Color, radius: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(0)
	return sb


# ============ 顯示字串 ============

static func type_label(type_key: String) -> String:
	match type_key:
		"impact": return "衝擊"
		"pierce": return "穿刺"
		"burn": return "燃燒"
		"mixed": return "混合"
		"flexible": return "任意"
		"generic": return "通用"
		"intel": return "情報"
		"none": return "無"
		_: return type_key


static func enemy_class_label(cls: String) -> String:
	match cls:
		"rabbit": return "兔子型"
		"gray_rabbit": return "灰兔型"
		"wolf": return "狼型"
		"leopard": return "豹型"
		"bear": return "熊型"
		_: return cls


static func combat_state_label(state: String) -> String:
	match state:
		"standard": return "標準"
		"proactive": return "先攻"
		"ambush": return "被襲"
		_: return state


static func resource_class_label(rc: String) -> String:
	match rc:
		"tool": return "工具"
		"burst": return "爆發"
		"character": return "角色"
		_: return rc


static func function_class_label(fc: String) -> String:
	match fc:
		"combat": return "戰鬥"
		"intel": return "情報"
		"compound": return "複合"
		_: return fc


static func lock_class_label(lc: String) -> String:
	match lc:
		"none": return ""
		"optional": return "◐ 可 Lock 揭露"
		"required": return "🔒 必須 Lock"
		_: return lc


## 把 contribution dict 轉成「+1 穿刺, +2 衝擊」這類字串。
static func contribution_text(contrib: Dictionary) -> String:
	if contrib.is_empty():
		return "(無貢獻)"
	var parts: Array[String] = []
	for k in contrib:
		parts.append("+%d %s" % [contrib[k], type_label(k)])
	return ", ".join(parts)


## 強度等級 → ★ 字串。
static func strength_stars(level: int) -> String:
	return "★".repeat(max(level, 0))


## 由最高需求推估需求層級(佔位規則)。
static func requirement_tier(max_req: int) -> String:
	if max_req <= 3:
		return "低"
	elif max_req <= 7:
		return "中"
	return "高"
