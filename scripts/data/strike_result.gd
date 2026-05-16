class_name StrikeResult
extends Resource

## 一次本擊結算的 typed 結果。對應 Resolution.resolve() 回傳 + BattleRecord.result 持久化。
## 對應 ADR-0003 + 遊戲核心系統機制.md §2 類型計數結算模型。
##
## 設計合約:
## - 純結算 output。揭露機制(revealed_info)不在此 — 屬 BattleEngine 狀態,留在 BattleRecord 本層
## - 本擊輸入(strike_cards)也不在此 — 屬本擊內容,留在 BattleRecord 本層
## - KISS:6 個 @export 欄位 + serialize 而已,helper method 待第二個 caller 出現再 promote

@export var ohk: bool = false
@export var passing_paths: Array[String] = []        ## 達標的路徑(例:["pierce", "mixed"])
@export var contributions: Dictionary = {}           ## { type_key: count }
@export var mixed_count: int = 0
@export var requirements: Dictionary = {}            ## 該敵人需求 snapshot
@export var shortfalls: Dictionary = {}              ## { type_key: actual - required }(負值 = 差幾)


func to_dict() -> Dictionary:
	return {
		"ohk": ohk,
		"passing_paths": passing_paths,
		"contributions": contributions,
		"mixed_count": mixed_count,
		"requirements": requirements,
		"shortfalls": shortfalls,
	}


static func from_dict(d: Dictionary) -> StrikeResult:
	var r := StrikeResult.new()
	r.ohk = bool(d.get("ohk", false))
	## 從 untyped Array 灌進 typed Array[String] 需要 assign,直接 = 會 lose type
	var pp: Array = d.get("passing_paths", [])
	r.passing_paths.assign(pp)
	r.contributions = d.get("contributions", {})
	r.mixed_count = int(d.get("mixed_count", 0))
	r.requirements = d.get("requirements", {})
	r.shortfalls = d.get("shortfalls", {})
	return r
