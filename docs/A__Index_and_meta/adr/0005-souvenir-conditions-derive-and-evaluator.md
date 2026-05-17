# ADR-0005:紀念品條件採事件 derive + 集中 evaluator

- 狀態:Accepted
- 日期:2026-05-17
- 決策者:haloflag01

## 背景

M5-S3 紀念品系統化加入第二個紀念品 `broken_bow`(折斷的弓)時,出現「**該紀念品的觸發條件中間狀態存哪**」這個結構性決定。

`broken_bow` 觸發條件:**戰役過程中曾發生 GAME_OVER 至少一次,玩家重啟後最終完成戰役**。對應 [failure_handler.gd](../../../scripts/logic/failure_handler.gd) 序章前半唯一 GAME_OVER 路徑 = 狼/異變巨狼精英化二戰失敗。

此條件需要「跨戰役多場戰鬥的歷史」這個跨時點資訊。三方案候選:

| 方案 | 做法 |
|---|---|
| **A. GameState 加 boolean 欄位** | `had_game_over_in_campaign: Dictionary<campaign_id, bool>` + 各失敗點 setter + persist |
| **B. 純 derive from BattleRecord** | 完成戰役時掃 `AdventureRecord.battles_for_campaign(cid)`,檢查 `failure_outcome == GAME_OVER` |
| **C. AdventureRecord campaign-level metadata** | `AdventureRecord` 升 VERSION,加 campaign meta block |

延伸問題:**未來若條件多元化**(假設 5-20 個紀念品 + 各種行動條件如「某敵人一次成功擊敗」「完美通關」「揭露某隱藏資訊」),三方案的軌跡如何?

## 決定

**採 B。所有紀念品解鎖條件集中在 `scripts/data/souvenir_conditions.gd`,從事件 record(BattleRecord / PrepNodeRecord / 未來的 DialogueChoiceRecord)derive。GameState 維持只存「結果」(`unlocked_souvenirs`),不存「條件中間態」。**

### 集中 evaluator pattern

```gdscript
# scripts/data/souvenir_conditions.gd
class_name SouvenirConditions
extends RefCounted

## 戰役完成時呼叫,回傳該戰役應解鎖的所有 souvenir_id。
static func evaluate_on_campaign_complete(campaign_id: String) -> Array:
    var unlocked: Array = []
    if campaign_id == "prologue_half_1":
        unlocked.append("mutant_wolf_arm")  ## 基本紀念品 — 無條件
        if AdventureRecord.had_game_over_in_campaign(campaign_id):
            unlocked.append("broken_bow")
    return unlocked
```

呼叫端([m2_campaign.gd:189-190](../../../scripts/ui/m2_campaign.gd#L189-L190)):

```gdscript
GameState.mark_campaign_complete(campaign_def.id)
for sid in SouvenirConditions.evaluate_on_campaign_complete(campaign_def.id):
    GameState.unlock_souvenir(sid)
```

**新增紀念品的全部變動:**
1. `souvenir_info.gd` 加 entry(視覺資料)
2. `souvenir_conditions.gd` 加 1 個 if + 必要時加 1 個 `AdventureRecord` derive helper
3. **零 schema 變動**(不動 GameState 欄位、不動 AdventureRecord VERSION)

### 例外:彩蛋式即時行為(escape hatch)

若未來真出現「按 ESC 5 次」「Hub 待 10 分鐘」這類**非事件式即時行為**條件(設計上很 cheesy 不在 P6 主軸內),**個別**加 GameState 欄位即可,不破壞主體 pattern。判斷標準:**該條件能否從 record 推導 → 能 → 用 B;不能 → 評估加新 record 類型(事件擴張)優於加 GameState boolean**。

## 後果

### 正面

- **資料只存一次**:`failure_outcome` 已寫進 BattleRecord schema v2([ADR-0003](0003-strike-result-embedded-in-battle-record.md)),事實已記錄,不重複
- **避免雙寫 bug**:單一 source of truth,GameState boolean / BattleRecord 不可能不一致
- **schema 永不擴張**:新紀念品不動 GameState 欄位、不動 AdventureRecord VERSION(不需 migration)
- **集中可讀**:所有條件邏輯在 `souvenir_conditions.gd` 一個檔,新增 / 修改 / debug 不必跨檔找 setter
- **跟 ADR-0003 一致**:事件式典範延伸 — record 寫一次,後續邏輯都 derive
- **未來新增紀念品邊際成本低**:加 1 個 if + (按需) 1 個 helper

### 負面 / 取捨

- **每次戰役完成多掃一遍 records**(本期序章 records ≤ 30,無感;未來戰役大規模時若效能成題,可在 AdventureRecord 內加 cache)
- **「條件中間態」隱性化**:GameState 直接 dump 看不出「我為何拿到這個紀念品」,需透過 evaluator + record 推。是否解鎖某紀念品的 debug 路徑變成「跑 evaluator」,不是「讀 boolean」
- **要求新增紀念品的人遵守 pattern**:若有人在某觸發點直接 `GameState.unlock_souvenir(...)` 跳過 evaluator,會破壞集中性。**緩解**:`souvenir_conditions.gd` 檔頭明寫此 pattern + ADR 引用

## 已考慮的替代方案

### A. GameState 加 boolean 欄位

- 拒絕原因:**1 個紀念品時看似簡單,5-20 個時 setter 散布災難**。每個紀念品條件要在對應觸發點(failure_handler / m2_campaign / 各 phase / 對話流程)加 set 邏輯,「修改某紀念品條件」變成跨檔搜尋
- 額外 con:GameState schema 每加一個 boolean 都要 persist + load + reset,持續擴張

### C. AdventureRecord campaign-level metadata

- 拒絕原因:升 AdventureRecord VERSION 要走 ADR-0003 migration 機制(舊 disk JSON 自動清檔 + push_warning),代價遠超回報。為「紀念品條件」這種 derive 可解決的問題付 schema migration 成本,投資錯位

### B' GameState 加 boolean 但用集中 evaluator 一次性 set

- 例如:戰役完成時 evaluator 推出 boolean → set 進 GameState → 解鎖
- 拒絕原因:**boolean 多餘**,evaluator 推完就能直接決定解鎖什麼,中間多一個 state 等於多一個出 bug 的可能性。GameState 應只存「最終結果」(`unlocked_souvenirs`),不存「推導過程中的中間值」

### 在各觸發點直接 `GameState.unlock_souvenir(...)`

- 例如:GAME_OVER handler 直接 set `had_game_over = true` 後續戰役完成檢查時 unlock
- 拒絕原因:**觸發點變成決定點**,違反「事件記錄事實 / 解鎖邏輯集中」分層。同時 GAME_OVER handler 不該知道任何紀念品 ID(關注點混淆)

## 相關

- [ADR-0003:StrikeResult 內嵌進 BattleRecord](0003-strike-result-embedded-in-battle-record.md) — 事件式典範來源
- [戰鬥紀錄系統設計.md §7.4 紀念品](../../C__Implementation_benchmarks/戰鬥紀錄系統設計.md) — 紀念品設計
- [souvenir_info.gd](../../../scripts/data/souvenir_info.gd) — 紀念品視覺資料(跟條件資料分離)
- [CONTEXT.md](../../../CONTEXT.md) — 「紀念品」術語條目
