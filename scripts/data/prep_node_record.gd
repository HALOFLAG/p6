class_name PrepNodeRecord
extends Resource

## 單一整備節點的紀錄。對應 戰鬥紀錄系統設計.md §6.2。
## 每完成一場連戰、整備補給套用後產生一筆。
##
## 2026-05-17 schema v3(ADR-0006):加 `campaign_attempt: int` 同 BattleRecord。

@export var node_id: String = ""                  ## 唯一識別:campaign_supply_timestamp
@export var campaign_id: String = ""
@export var campaign_attempt: int = 1             ## 第幾次嘗試(M5-S4 / ADR-0006)
@export var chain_index_completed: int = -1       ## 剛完成的連戰索引(整備是在這連戰之後)
@export var supply_id: String = ""

## 整備前後的卡組狀態(各 card_id → 張數)
@export var card_pool_before: Dictionary = {}
@export var card_pool_after: Dictionary = {}
@export var changes: Dictionary = {}              ## 來自 SupplyHandler.apply 的 summary

@export var timestamp: int = 0


func to_dict() -> Dictionary:
	return {
		"node_id": node_id,
		"campaign_id": campaign_id,
		"campaign_attempt": campaign_attempt,
		"chain_index_completed": chain_index_completed,
		"supply_id": supply_id,
		"card_pool_before": card_pool_before,
		"card_pool_after": card_pool_after,
		"changes": changes,
		"timestamp": timestamp,
	}


static func from_dict(d: Dictionary) -> PrepNodeRecord:
	var r := PrepNodeRecord.new()
	r.node_id = str(d.get("node_id", ""))
	r.campaign_id = str(d.get("campaign_id", ""))
	r.campaign_attempt = int(d.get("campaign_attempt", 1))
	r.chain_index_completed = int(d.get("chain_index_completed", -1))
	r.supply_id = str(d.get("supply_id", ""))
	r.card_pool_before = d.get("card_pool_before", {})
	r.card_pool_after = d.get("card_pool_after", {})
	r.changes = d.get("changes", {})
	r.timestamp = int(d.get("timestamp", 0))
	return r
