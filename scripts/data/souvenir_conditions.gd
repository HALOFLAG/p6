class_name SouvenirConditions
extends RefCounted

## 紀念品解鎖條件集中 evaluator(對應 ADR-0005)。
##
## 設計原則:
## - 條件從事件 record(BattleRecord / PrepNodeRecord)derive,不在 GameState 加 boolean
## - 所有紀念品條件邏輯集中在本檔,新增紀念品 = 加 if 分支 + (按需) AdventureRecord helper
## - GameState 只存「結果」(unlocked_souvenirs),不存「條件中間態」
##
## 新增紀念品 checklist:
##   1. souvenir_info.gd 加 entry(視覺資料)
##   2. 本檔 evaluate_on_campaign_complete(或對應 evaluator)加 if 分支
##   3. 若條件需新查詢,加 AdventureRecord helper(如 had_game_over_in_campaign)
##   4. 零 schema 變動(不動 GameState 欄位、不動 AdventureRecord VERSION)
##
## 例外:彩蛋式即時行為(如「按 ESC 5 次」)若出現,個別加 GameState 欄位,
## 不破壞主體 pattern。判斷標準:該條件能否從 record 推導 → 能 → 用本 evaluator。


## 戰役完成時呼叫,回傳該戰役應解鎖的所有 souvenir_id。
## 呼叫端:m2_campaign.gd Phase.ENDING 進入時。
static func evaluate_on_campaign_complete(campaign_id: String) -> Array[String]:
	var unlocked: Array[String] = []
	if campaign_id == "prologue_first_half":
		## 基本紀念品 — 完成序章無條件
		unlocked.append("mutant_wolf_arm")
		## 失敗疤痕紀念品 — 戰役過程中曾觸發 GAME_OVER 至少一次
		## 序章前半唯一 GAME_OVER 路徑:狼/異變巨狼精英化二戰失敗
		if AdventureRecord.had_game_over_in_campaign(campaign_id):
			unlocked.append("broken_bow")
	return unlocked
