class_name Resolution
extends RefCounted

## 結算邏輯 — 比對本擊 vs 敵人需求表,任一條件達標即 OHK。
## 對應 遊戲核心系統機制.md §2 類型計數結算模型。


## 結算結果格式:
## {
##   "ohk": bool,
##   "passing_paths": Array[String],  ## 達標的路徑(例:["pierce", "mixed"])
##   "contributions": Dictionary,     ## { "pierce": 1, ... }
##   "mixed_count": int,
##   "requirements": Dictionary,      ## 敵人需求表 snapshot
##   "shortfalls": Dictionary,        ## { "pierce": 0, "impact": -2, "mixed": -4 }(負值表示差幾)
## }
static func resolve(strike: Strike, enemy_instance: EnemyInstance) -> Dictionary:
	var contributions := strike.get_type_counts()
	var mixed_count := strike.get_mixed_count()
	var requirements := enemy_instance.requirements

	var passing_paths: Array[String] = []
	var shortfalls: Dictionary = {}

	for type_key in requirements:
		var required: int = requirements[type_key]
		var actual: int
		if type_key == "mixed":
			actual = mixed_count
		else:
			actual = contributions.get(type_key, 0)
		shortfalls[type_key] = actual - required
		if actual >= required:
			passing_paths.append(type_key)

	return {
		"ohk": passing_paths.size() > 0,
		"passing_paths": passing_paths,
		"contributions": contributions,
		"mixed_count": mixed_count,
		"requirements": requirements.duplicate(),
		"shortfalls": shortfalls,
	}
