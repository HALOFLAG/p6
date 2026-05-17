# ADR-0006:冒險手記 attempt 結構(schema v3 + chip switcher)

- 狀態:Accepted
- 日期:2026-05-17
- 決策者:haloflag01

## 背景

M5-S3 完成後實機觀察冒險手記,發現一個結構性問題:

> 玩家「接受戰役失敗」回 Hub → 再進序章 → **新一輪戰鬥的 `retry_count` 從 0 開始,跟先前 attempt 的 retry_count=0 撞在同一條 timeline**

現況 `BattleRecord` 只有 `chain_index` + `retry_count`(連戰內重挑次數),沒有「attempt」概念。MapView 按 `chain_index` × `retry_count` 分組,跨 attempt 的紀錄會 mix 進同一條時間線,失去「玩家經歷了 N 次獨立冒險」的敘事重量。

同時 ADR-0004 §3 決定的「new 列 = 該 chain 最大 retry_count」視覺,在跨 attempt 情境下也會錯亂(來自兩個 attempt 的 retry_count=0 被歸成同一 row)。

設計分支多,跑 `/grill-with-docs` 走完 7 個關鍵決定。

## 決定

### 1. attempt 邊界 = `_start_campaign()` 觸發時刻

**每次玩家從 Hub 進序章(觸發 `_start_campaign`)= 新 attempt**。

| Scenario | attempt 計數 |
|---|---|
| 全新玩家進序章 → 通關 | 1 attempt |
| 進序章 → GAME_OVER → 接受失敗 → 回 Hub → 再進 → 通關 | **2 attempts** |
| 進序章 → GAME_OVER → 「重新挑戰這場連戰」→ 通關 | 1 attempt(retry 屬同 attempt 內事件) |
| 通關 → 回 Hub → 再進序章 replay | **2 attempts** |
| [DEV] 重置進度 | AdventureRecord.clear_all(),不適用 |

**為什麼選 `_start_campaign` 觸發**:「卡組從頭重置」就是「新 timeline 開始」的物理事實。不需要追狀態(「上次是怎麼結束的」)就能判定。對應現有 single entry point,觸發邊界乾淨。

**S4 預埋契約**(未來 load_save 實作時):SaveSystem `save_at_prep_node` payload 加 `campaign_attempt` 欄位寫進磁碟;load 流程實作時要讀回此欄位繼續同 attempt,**不可呼叫 `_start_campaign`**(會產生新 attempt 號)。

### 2. attempt_id 形態 = int counter per campaign

`BattleRecord` / `PrepNodeRecord` 加 `campaign_attempt: int = 1` 欄位。

- **形態**:int 計數,從 1 開始,per campaign
- **顯示**:「第 N 次嘗試」(符合冒險手記語感,玩家不需追現實日期)
- **拒絕 timestamp**:玩家無需追日期,且 system clock backwards 可能造成 sort 錯亂
- **拒絕 UUID**:overkill,不能直顯

### 3. counter 來源 = Derive from records

新增 `AdventureRecord.next_attempt_index_for(campaign_id)`:

```gdscript
func next_attempt_index_for(campaign_id: String) -> int:
    var max_idx: int = 0
    for r in get_battles_by_campaign(campaign_id):
        if r.campaign_attempt > max_idx:
            max_idx = r.campaign_attempt
    return max_idx + 1
```

**為什麼 derive 不 store**:跟 ADR-0005「derive over store」原則一致。GameState 不加 `campaign_attempts_counter` 欄位,從現有 records 推導。第一次進序章(無 records)→ 回 1;第二次(有 attempt=1 records)→ 回 2。

### 4. broken_bow 條件不改 — 維持 ADR-0005 的「Permanent + Any-attempt」

`AdventureRecord.had_game_over_in_campaign(cid)` **不加 attempt 篩選**,仍掃所有 attempt 的 records。紀念品邏輯維持 ADR-0005 現況。

**為什麼 attempt 引入後紀念品邏輯不改**:
- attempt 概念用於 MapView 視覺分組,跟紀念品條件解耦
- 「Permanent + Any-attempt」實質上跟「Permanent + Latest-attempt」差異極小(只差一條「A1 接受失敗 → A2 乾淨完成」的邊緣情境)
- 「Refresh per attempt」會 unset 玩家先前獲得的收藏品,違反「紀念品=帶回家的真實物件」隱喻
- 接受 ADR-0005 的權衡:「乾淨 replay 仍掛 broken_bow」這個邊緣情境用「紀念品=過去歷史的證物」哲學接受

### 5. MapView 跨 attempt 視覺 = 頂部 chip selector(一頁一組主軸)

**MapHeader 加 chip row**,每個 chip 對應一個 attempt:

```
MapHeader: [序章前半: 森林獵人父子]  [第 1 次] [第 2 次 ●當前]
─────────────────────────────────────────────────
●━━━●━━━●━━━●━━━●━━━●  ← 當前選的 attempt 主軸(整個 MapView 只顯示這一組)
```

- **一頁只顯示一組主軸**(該 attempt 的所有節點)
- chip 點擊 → 切換 `_selected_attempt` → 重 build MapView
- chip 多時橫向 scroll

**為什麼選 chip 不選 vertical stacking / WorldView attempt selector**:
- Vertical stacking 一眼看到所有 attempt 但畫面變很長(3 attempts ≈ 2300px scroll)
- WorldView attempt selector 多一層 navigation,玩家動線變繁
- chip 是「切換地圖」感最直接的實現,符合 user 直覺「一頁就一組主軸」
- chip 在 MapHeader 不影響主視圖寬度

### 6. 預設顯示 = Latest attempt(不論狀態)

進入 MapView 預設 `_selected_attempt = max(existing attempts)`。

| 情境 | 預設顯示 |
|---|---|
| attempt 1 進行中(首次冒險) | attempt 1 |
| attempt 1 已完成、attempt 2 進行中 | **attempt 2**(玩家當前進度) |
| attempt 1 接受失敗、attempt 2 進行中 | **attempt 2** |

**為什麼 latest 不論狀態**:玩家進手記預設看「我目前/最近的冒險」最直覺;若選「latest completed」會讓玩家進來看不到當前進度,反直覺。

**精英入口 jump 流程整合**(M5-S3 既有的 `initial_battle_id`):取 `BattleRecord.campaign_attempt` 設 `_selected_attempt`,確保跳到正確 attempt 的 PageView。

### 7. chip status = Minimal(只標識,不顯示完成/放棄)

```
[第 1 次] [第 2 次 ●當前]    ← 不加 ✓完成 / ✗放棄 等狀態 icon
```

attempt 的結果**從 map 本身視覺 derive**:
- 完成 = map 末段是結局敘事節點
- 放棄 = map 末段是大 X(GAME_OVER 節點)
- 進行中 = latest 且未到結束

**為什麼 Minimal**:
- 跟 ADR-0005「derive over store」一致 — 不額外追蹤 attempt outcome 欄位
- 避免邊界 case derive 邏輯(GAME_OVER + 放棄、最後一連戰失敗、卡組耗盡 GAME_OVER...)
- chip 簡潔,attempt 多時不爆視覺
- 「冒險手記」哲學:手記是供翻閱的,點 chip 翻頁看結果是自然動作

## 後果

### 正面

- **「兩條獨立路線」字面實現**:玩家每次重開冒險都是視覺上獨立的時間線
- **MapView 視覺淨化**:單一 chip 內只有該 attempt 的紀錄,old/new 列邏輯(ADR-0004 §3)局限在同 attempt 內,不會跨 attempt 錯亂
- **「主軸 = 玩家最終 sealed 的歷史」哲學落實**:每個 attempt 自己的主軸,不被其他 attempt 干擾
- **schema 升級乾淨**:int 欄位 + ADR-0003 既有 migration 機制,代價低
- **「derive over store」一致性延續**:next_attempt_index_for + chip outcome derive 都從 records 推
- **紀念品邏輯零變動**:ADR-0005 + souvenir_conditions.gd 不改

### 負面 / 取捨

- **schema 升 v3 → 玩家現有進度(disk JSON v2)會被清掉**:跟 ADR-0003 v1→v2 同機制(push_warning + 清檔)。可接受因為實機資料少
- **MapView 重 build 邏輯複雜化**:加 `_selected_attempt` state + chip switch handler + collect_timeline 加 attempt 篩選
- **chip status Minimal → 玩家要切到該 attempt 才知結果**:接受 — 一致性與 derive 原則優先
- **未來 attempt 多時 chip row 橫向 scroll**:序章預期 ≤ 3 不痛;未來戰役多時可加摺疊機制
- **「乾淨 replay 仍掛 broken_bow」邊緣情境延續**:ADR-0005 已接受此權衡,不重複處理

## 已考慮的替代方案

### attempt 邊界 = 「接受失敗後再進」或「ENDING 後再進」

- 拒絕原因:這兩個都需要追「上次結束狀態」(persistent state),違反 derive over store。`_start_campaign` 觸發是現有 single entry point,「卡組從頭重置」物理事實直接判定

### attempt_id = Unix timestamp

- 拒絕原因:玩家不需追現實日期(冒險手記用「第 N 次」更符合語感);system clock backwards 可能造成 sort 錯亂

### attempt_id = UUID-like string

- 拒絕原因:overkill,顯示醜,schema 重(string 比 int 大);全域唯一在 single-player local 環境無價值

### MapView 跨 attempt = Vertical stacking(垂直堆疊獨立子 MapView)

- 拒絕原因:多 attempt scroll 量大(3 attempts ≈ 2300px);user 明確表達「想要切換式、一頁一組主軸」

### MapView 跨 attempt = WorldView 加 AttemptListView 中間層

- 拒絕原因:多一層 navigation 動線繁;跨 attempt 切換頻率不該超過進入戰役頻率,加層不划算

### chip status = 顯示「完成 / 放棄 / 進行中」

- 拒絕原因:需要 store(GameState 加 dictionary)或複雜 derive(處理「最後一連戰失敗」「卡組耗盡 GAME_OVER」等邊界);違反 ADR-0005「derive over store」
- 此外 attempt outcome 在 map 自身視覺已表達(末段節點型態),chip 重複表達是冗餘

### broken_bow 條件改為 Latest-attempt + Permanent

- 拒絕原因:跟 Permanent + Any-attempt 實質差異極小(只差「A1 接受失敗 → A2 乾淨完成」邊緣情境);引入額外條件 logic 不划算

### broken_bow 條件改為 Refresh per attempt completion

- 拒絕原因:「收藏品消失」嚴重反直覺;違反「紀念品=帶回家的真實物件」隱喻;違反 BattleRecord「失敗的疤痕永久保留」設計合約延伸的紀念品語意

## 相關

- [ADR-0003:StrikeResult 內嵌進 BattleRecord](0003-strike-result-embedded-in-battle-record.md) — schema 升級 / migration 機制來源
- [ADR-0004:冒險手記 MapView 嚴格走過版 + NarrativePage 共用版型](0004-adventure-journal-mapview-narrative-page.md) — MapView old/new 列邏輯;本 ADR 將該邏輯局限在 single attempt 內
- [ADR-0005:紀念品條件採事件 derive + 集中 evaluator](0005-souvenir-conditions-derive-and-evaluator.md) — derive over store 原則延續;紀念品邏輯不改
- [戰鬥紀錄系統設計.md](../../C__Implementation_benchmarks/戰鬥紀錄系統設計.md) — schema v3 + attempt 概念
- [CONTEXT.md](../../../CONTEXT.md) — 「attempt」術語條目
