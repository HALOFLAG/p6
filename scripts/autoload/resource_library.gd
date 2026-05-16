extends Node

## 全域資源目錄 — 所有靜態 .tres(卡牌 / 敵人模板 / 敵人 instance /
## 連戰 / 整備 / 戰役 / 校準台詞)的唯一入口。
##
## ── 為什麼存在 ──
## 在 ResourceLibrary 出現以前,m1_battle / m2_campaign / adventure_journal
## 三個場景各自維護 CARD_PATHS / ENEMY_TEMPLATE_PATHS / ENEMY_INSTANCE_PATHS
## 等 dict,並各自跑 _load_resources()。新增一張卡 = 改三處;格式還會漂移
## (m1 用 ENEMIES 陣列,m2 用兩個獨立 dict)。
##
## ── 新增資源的流程(必讀) ──
## 1. 把 .tres 放到 res://resources/<type>/ 對應子目錄
## 2. 在本檔頂部對應的 *_PATHS dict 加一行 id → 路徑
## 3. 不要在其他場景再用 load("res://resources/...") 載入這類資源;
##    一律呼叫 ResourceLibrary.<type>(id)
##
## ── 失敗模式 ──
## 找不到 id → push_error + 回 null。caller 自己負責容錯。
## 與既有 _load_resources 慣例一致(不改成 assert/crash)。
##
## 對應 docs/A__Index_and_meta/adr/0001-resource-library-autoload.md 設計決策。

# ============ 路徑表(新增資源在這裡註冊)============

const CARD_PATHS := {
	"tool_arrow_pierce": "res://resources/cards/tool_arrow_pierce.tres",
	"tool_stone_impact": "res://resources/cards/tool_stone_impact.tres",
	"intel_weakness": "res://resources/cards/intel_weakness.tres",
}

const ENEMY_TEMPLATE_PATHS := {
	"rabbit": "res://resources/enemies/rabbit_template.tres",
	"fox": "res://resources/enemies/fox_template.tres",
	"wolf": "res://resources/enemies/wolf_template.tres",
	"mutant_wolf": "res://resources/enemies/mutant_wolf_template.tres",
	"gray_rabbit": "res://resources/enemies/gray_rabbit_template.tres",
}

const ENEMY_INSTANCE_PATHS := {
	"rabbit_default": "res://resources/enemies/rabbit_default.tres",
	"fox_default": "res://resources/enemies/fox_default.tres",
	"wolf_default": "res://resources/enemies/wolf_default.tres",
	"mutant_wolf_default": "res://resources/enemies/mutant_wolf_default.tres",
	"gray_rabbit_default": "res://resources/enemies/gray_rabbit_default.tres",
	"gray_rabbit_clone": "res://resources/enemies/gray_rabbit_clone.tres",
}

const CHAIN_PATHS := {
	"chain_1": "res://resources/chains/chain_1.tres",
	"chain_2": "res://resources/chains/chain_2.tres",
	"chain_3": "res://resources/chains/chain_3.tres",
	"chain_4": "res://resources/chains/chain_4.tres",
	"chain_5": "res://resources/chains/chain_5.tres",
}

const SUPPLY_PATHS := {
	"rest_1": "res://resources/supply_phases/rest_1.tres",
	"supply_2": "res://resources/supply_phases/supply_2.tres",
	"supply_3": "res://resources/supply_phases/supply_3.tres",
	"supply_4": "res://resources/supply_phases/supply_4.tres",
}

const CAMPAIGN_PATHS := {
	"prologue_first_half": "res://resources/campaigns/prologue_first_half.tres",
}

const CALIBRATION_LINES_PATH := "res://resources/dialogues/calibration_lines.tres"

# ============ 內部快取(_ready 時填滿,之後唯讀)============

var _cards: Dictionary = {}
var _enemy_templates: Dictionary = {}
var _enemy_instances: Dictionary = {}
var _chains: Dictionary = {}
var _supplies: Dictionary = {}
var _campaigns: Dictionary = {}
var _calibration_lines: CalibrationLines = null


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	for id in CARD_PATHS:
		var r := load(CARD_PATHS[id]) as CardDefinition
		if r == null:
			push_error("ResourceLibrary 無法載入卡牌:" + CARD_PATHS[id])
		else:
			_cards[id] = r
	for id in ENEMY_TEMPLATE_PATHS:
		var r := load(ENEMY_TEMPLATE_PATHS[id]) as EnemyTemplate
		if r == null:
			push_error("ResourceLibrary 無法載入敵人模板:" + ENEMY_TEMPLATE_PATHS[id])
		else:
			_enemy_templates[id] = r
	for id in ENEMY_INSTANCE_PATHS:
		var r := load(ENEMY_INSTANCE_PATHS[id]) as EnemyInstance
		if r == null:
			push_error("ResourceLibrary 無法載入敵人 instance:" + ENEMY_INSTANCE_PATHS[id])
		else:
			_enemy_instances[id] = r
	for id in CHAIN_PATHS:
		var r := load(CHAIN_PATHS[id]) as ChainDefinition
		if r == null:
			push_error("ResourceLibrary 無法載入連戰:" + CHAIN_PATHS[id])
		else:
			_chains[id] = r
	for id in SUPPLY_PATHS:
		var r := load(SUPPLY_PATHS[id]) as SupplyPhase
		if r == null:
			push_error("ResourceLibrary 無法載入整備:" + SUPPLY_PATHS[id])
		else:
			_supplies[id] = r
	for id in CAMPAIGN_PATHS:
		var r := load(CAMPAIGN_PATHS[id]) as CampaignDefinition
		if r == null:
			push_error("ResourceLibrary 無法載入戰役:" + CAMPAIGN_PATHS[id])
		else:
			_campaigns[id] = r
	_calibration_lines = load(CALIBRATION_LINES_PATH) as CalibrationLines
	if _calibration_lines == null:
		push_error("ResourceLibrary 無法載入校準台詞:" + CALIBRATION_LINES_PATH)


# ============ 單一查詢介面 ============

func card(id: String) -> CardDefinition:
	var r: CardDefinition = _cards.get(id, null)
	if r == null:
		push_error("ResourceLibrary 找不到卡牌:" + id)
	return r


func enemy_template(id: String) -> EnemyTemplate:
	var r: EnemyTemplate = _enemy_templates.get(id, null)
	if r == null:
		push_error("ResourceLibrary 找不到敵人模板:" + id)
	return r


func enemy_instance(id: String) -> EnemyInstance:
	var r: EnemyInstance = _enemy_instances.get(id, null)
	if r == null:
		push_error("ResourceLibrary 找不到敵人 instance:" + id)
	return r


func chain(id: String) -> ChainDefinition:
	var r: ChainDefinition = _chains.get(id, null)
	if r == null:
		push_error("ResourceLibrary 找不到連戰:" + id)
	return r


func supply(id: String) -> SupplyPhase:
	var r: SupplyPhase = _supplies.get(id, null)
	if r == null:
		push_error("ResourceLibrary 找不到整備:" + id)
	return r


func campaign(id: String) -> CampaignDefinition:
	var r: CampaignDefinition = _campaigns.get(id, null)
	if r == null:
		push_error("ResourceLibrary 找不到戰役:" + id)
	return r


func calibration_lines() -> CalibrationLines:
	return _calibration_lines


# ============ 批量介面(給遍歷用)============

func cards() -> Dictionary:
	return _cards


func enemy_templates() -> Dictionary:
	return _enemy_templates


func enemy_instances() -> Dictionary:
	return _enemy_instances


func chains() -> Dictionary:
	return _chains


func supplies() -> Dictionary:
	return _supplies


func campaigns() -> Dictionary:
	return _campaigns
