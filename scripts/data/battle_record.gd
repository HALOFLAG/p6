class_name BattleRecord
extends Resource

## 單一場戰鬥的紀錄。對應 戰鬥紀錄系統設計.md §6.1。
##
## 設計合約:
## - 失敗紀錄永久保留,即使重新挑戰成功也不抹除(保留疤痕)→ append-only
## - 每場戰鬥(含 OHK 與各種失敗)都產生一筆;重挑會生新紀錄(retry_count + 1)
## - 跟 SaveSystem 獨立(存檔回滾不影響紀錄)
##
## 2026-05-16 schema v2(ADR-0003):
## - 6 個結算欄位(ohk / passing_paths / contributions / mixed_count / requirements / shortfalls)
##   收進 typed `result: StrikeResult`
## - revealed_info / strike_cards / calibration_state / failure_outcome 留本層(不屬結算 output)
## - AdventureRecord VERSION 同步升 2;舊 v1 records 不相容,讀進來會被清掉

@export var battle_id: String = ""               ## 唯一識別,通常為 campaign_chain_pos_attempt_timestamp
@export var campaign_id: String = ""
@export var chain_index: int = -1                 ## 第幾個連戰(0-based)
@export var position_in_chain: int = -1           ## 此次嘗試中,本場是該連戰的第幾場(0-based)
@export var retry_count: int = 0                  ## 該連戰的嘗試次數(0 = 第一次)

## 敵人
@export var enemy_template_id: String = ""
@export var enemy_instance_id: String = ""
@export var combat_state: String = ""             ## standard / proactive / ambush
@export var is_elite: bool = false
@export var is_elite_from_failure: bool = false   ## 是否為失敗造成的精英化

## 該場戰鬥中玩家已揭露的資訊(snapshot;BattleEngine 揭露機制狀態)
@export var revealed_info: Dictionary = {}

## 本擊輸入:玩家鎖了哪些卡(結算的輸入,不在 StrikeResult 中)
@export var strike_cards: Dictionary = {}         ## { card_id: count }

## 結算結果(typed,ADR-0003)
@export var result: StrikeResult = null

## 結算後分類
@export var calibration_state: int = -1           ## CalibrationClassifier 6 狀態之一
@export var failure_outcome: int = -1             ## FailureHandler.FailureOutcome(OHK 時 = -1)

@export var timestamp: int = 0                    ## Unix 時間戳(秒)


func to_dict() -> Dictionary:
	return {
		"battle_id": battle_id,
		"campaign_id": campaign_id,
		"chain_index": chain_index,
		"position_in_chain": position_in_chain,
		"retry_count": retry_count,
		"enemy_template_id": enemy_template_id,
		"enemy_instance_id": enemy_instance_id,
		"combat_state": combat_state,
		"is_elite": is_elite,
		"is_elite_from_failure": is_elite_from_failure,
		"revealed_info": revealed_info,
		"strike_cards": strike_cards,
		"result": result.to_dict() if result != null else {},
		"calibration_state": calibration_state,
		"failure_outcome": failure_outcome,
		"timestamp": timestamp,
	}


static func from_dict(d: Dictionary) -> BattleRecord:
	var r := BattleRecord.new()
	r.battle_id = str(d.get("battle_id", ""))
	r.campaign_id = str(d.get("campaign_id", ""))
	r.chain_index = int(d.get("chain_index", -1))
	r.position_in_chain = int(d.get("position_in_chain", -1))
	r.retry_count = int(d.get("retry_count", 0))
	r.enemy_template_id = str(d.get("enemy_template_id", ""))
	r.enemy_instance_id = str(d.get("enemy_instance_id", ""))
	r.combat_state = str(d.get("combat_state", ""))
	r.is_elite = bool(d.get("is_elite", false))
	r.is_elite_from_failure = bool(d.get("is_elite_from_failure", false))
	r.revealed_info = d.get("revealed_info", {})
	r.strike_cards = d.get("strike_cards", {})
	r.result = StrikeResult.from_dict(d.get("result", {}))
	r.calibration_state = int(d.get("calibration_state", -1))
	r.failure_outcome = int(d.get("failure_outcome", -1))
	r.timestamp = int(d.get("timestamp", 0))
	return r
