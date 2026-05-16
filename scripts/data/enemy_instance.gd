class_name EnemyInstance
extends Resource

## P6 敵人 instance(模板的具體變體)。對應 敵人設計原則.md §2。
## mixed 需求 = max(其他類型) × 1.5 四捨五入(2026-05-14 取整規則統一)。
## strike_limit 依敵人強度決定(普通×2 / 精英×2.5 / BOSS×3+5)。

@export var instance_id: String = ""
@export var template_id: String = ""
@export var requirements: Dictionary = {}  ## { "impact": 3, "pierce": 1, "mixed": 5 }
@export var strike_limit: int = 2
@export var combat_state: String = "standard"  ## standard / proactive / ambush(M1 全為 standard)
@export var visual_cues: Dictionary = {}  ## 對應視覺線索詞彙表
@export var display_name: String = ""  ## 顯示名稱(若空字串則由 template 提供)

## 失敗/揭露/etc 的被動觸發效果(2026-05-16 新增,for 灰兔 spawn_clone 機制)。
## 結構慣例(對齊 CardDefinition.special_effect):
##   { "on_fail": { "action": "spawn_clone", "clone_instance_id": "..." } }
## 目前 FailureHandler 認得的 on_fail action:
##   - "spawn_clone" → 配套 GRAY_RABBIT_CLONE_SPAWN outcome
## 預留 trigger key: on_reveal / on_chain_start 等(待後續期數)
@export var special_effect: Dictionary = {}


func get_min_requirement() -> int:
	var lowest := INF
	for k in requirements:
		if k == "mixed":
			continue
		var v: int = requirements[k]
		if v < lowest:
			lowest = v
	return int(lowest) if lowest != INF else 0


func get_max_requirement() -> int:
	var highest := 0
	for k in requirements:
		if k == "mixed":
			continue
		var v: int = requirements[k]
		if v > highest:
			highest = v
	return highest
