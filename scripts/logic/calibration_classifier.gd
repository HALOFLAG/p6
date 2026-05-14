class_name CalibrationClassifier
extends RefCounted

## 戰後校準分類器。對應 遊戲核心系統機制.md §10。
## 把一次本擊的結算結果分類為 6 種對話狀態。
## M3:閾值為初版,屬平衡議題,後續可調。

enum State {
	BIG_OVERKILL,    ## 大幅 Overkill — 用太多了
	PRECISE,         ## 精準擊殺 — 判斷準確
	BARELY_PASSED,   ## 勉強過 — 剛好夠,很險
	WRONG_TYPE,      ## 差一步(類型錯)— 完全沒打弱點
	INSUFFICIENT,    ## 差一步(量不足)— 方向對但不夠
	BIG_SHORTFALL,   ## 大幅不足 — 方向根本錯了
}


## 分類。
## result: Resolution.resolve() 的回傳;weakness_range: 該敵人弱點類型陣列;
## total_committed: 本擊總張數。
static func classify(result: Dictionary, weakness_range: Array, total_committed: int) -> int:
	var ohk: bool = result.get("ohk", false)
	var shortfalls: Dictionary = result.get("shortfalls", {})
	var contributions: Dictionary = result.get("contributions", {})
	var requirements: Dictionary = result.get("requirements", {})
	var passing_paths: Array = result.get("passing_paths", [])

	if ohk:
		## 玩家通過的最佳路徑餘裕(actual - required)
		var best_margin := -9999
		for p in passing_paths:
			var m: int = shortfalls.get(p, 0)
			if m > best_margin:
				best_margin = m
		## 最便宜路徑(最低需求)
		var min_req := 9999
		for t in requirements:
			var rv: int = requirements[t]
			if rv < min_req:
				min_req = rv
		if best_margin <= 0:
			return State.BARELY_PASSED
		elif min_req > 0 and total_committed >= min_req * 2:
			return State.BIG_OVERKILL
		else:
			return State.PRECISE
	else:
		## 失敗:找最接近達標的路徑(shortfall 最大 = 最不負)
		var closest_gap := -9999
		for t in shortfalls:
			var g: int = shortfalls[t]
			if g > closest_gap:
				closest_gap = g
		## 是否完全沒投資弱點類型
		var weakness_contribution := 0
		for t in weakness_range:
			weakness_contribution += contributions.get(t, 0)
		var total_contribution := 0
		for t in contributions:
			total_contribution += contributions[t]
		if total_contribution > 0 and weakness_contribution == 0:
			return State.WRONG_TYPE
		elif closest_gap >= -2:
			return State.INSUFFICIENT
		else:
			return State.BIG_SHORTFALL


static func state_key(state: int) -> String:
	match state:
		State.BIG_OVERKILL: return "big_overkill"
		State.PRECISE: return "precise"
		State.BARELY_PASSED: return "barely_passed"
		State.WRONG_TYPE: return "wrong_type"
		State.INSUFFICIENT: return "insufficient"
		State.BIG_SHORTFALL: return "big_shortfall"
	return "unknown"


static func state_display(state: int) -> String:
	match state:
		State.BIG_OVERKILL: return "大幅 Overkill"
		State.PRECISE: return "精準擊殺"
		State.BARELY_PASSED: return "勉強過"
		State.WRONG_TYPE: return "差一步(類型錯)"
		State.INSUFFICIENT: return "差一步(量不足)"
		State.BIG_SHORTFALL: return "大幅不足"
	return "?"
