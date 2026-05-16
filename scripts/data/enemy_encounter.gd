class_name EnemyEncounter
extends RefCounted

## 「敵人在 context 中」的 typed wrapper。Runtime-only(不存檔,不在 Inspector 編輯)。
##
## 用途範圍(Phase A,Candidate B):
##   - m2_campaign 的 enemy_queue 元素
##   - BattleView.set_encounter 的參數型別
##   - m1_battle dev 模式的單體戰 encounter
##
## 不在範圍:
##   - adventure_journal 渲染不走 Encounter(journal 從 BattleRecord 直讀 typed 欄位即可,
##     沒 string-key dict friction;規範化菁英徽章格式會破壞 journal 的視覺差異)
##   - 不曝 display_label() —— m2 / journal 三個 site 的菁英徽章格式各異,
##     刻意不規範化(若未來真的需要,加 method 而非全面改寫)
##
## 4 個原始欄位 + 2 個 id getter(null-safe)是介面總和。

var enemy_instance: EnemyInstance = null
var enemy_template: EnemyTemplate = null
var is_elite: bool = false
var label_override: String = ""  ## 顯示字串(含菁英 prefix 等);由 caller 組,Encounter 不參與


## 從連戰配置建立(m2 _build_enemy_entry / m1 _start_battle 用)。
## 找不到 instance → 回 null(caller 必須檢查)。
static func from_chain(instance_id: String, is_elite_init: bool) -> EnemyEncounter:
	var inst: EnemyInstance = ResourceLibrary.enemy_instance(instance_id)
	if inst == null:
		return null
	var enc := EnemyEncounter.new()
	enc.enemy_instance = inst
	enc.enemy_template = ResourceLibrary.enemy_template(inst.template_id)
	enc.is_elite = is_elite_init
	return enc


## Null-safe id 訪問(供 RABBIT_CHAIN_FLEE 等過濾邏輯用)。
func template_id() -> String:
	return enemy_template.id if enemy_template != null else ""


func instance_id() -> String:
	return enemy_instance.instance_id if enemy_instance != null else ""
