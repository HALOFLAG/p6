class_name Resolution
extends RefCounted

## 結算邏輯 — 比對本擊 vs 敵人需求表,任一條件達標即 OHK。
## 對應 遊戲核心系統機制.md §2 類型計數結算模型。
## 回傳 typed StrikeResult(ADR-0003);揭露機制 snapshot 不在此(屬 BattleEngine 狀態)。

static func resolve(strike: Strike, enemy_instance: EnemyInstance) -> StrikeResult:
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

	var r := StrikeResult.new()
	r.ohk = passing_paths.size() > 0
	r.passing_paths = passing_paths
	r.contributions = contributions
	r.mixed_count = mixed_count
	r.requirements = requirements.duplicate()
	r.shortfalls = shortfalls
	return r
