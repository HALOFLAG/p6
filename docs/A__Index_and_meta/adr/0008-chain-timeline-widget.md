# ADR-0008:連戰時間軸 widget(BattleView 內常駐 + 點擊跳轉 + 廢除 RecordButton badge)

- 狀態:Accepted
- 日期:2026-05-17
- 決策者:haloflag01
- Supersedes(部分):[ADR-0005 §RecordButton 精英入口 badge](0005-souvenir-conditions-derive-and-evaluator.md)

## 背景

M5 實機驗證(2026-05-17)後,user 觀察:

> 「冒險手記(地圖)應該要實時紀錄玩家的戰鬥?我現在遇到菁英化後的狼,但目前只顯示在第一次戰鬥失敗的位置?」

確認此為設計合理現象:MapView 嚴格遵守「主軸 = 玩家最終 sealed 的歷史」(ADR-0007),不顯示未來節點。但**戰鬥畫面內** UX 缺口存在 —— 玩家在精英狼戰前無法看到「狼精英化後重排到隊尾」這個事件的視覺反饋,只有對話文字告知。

既有的 `ProgressIndicator`(垂直右側 chip 列)顯示 4 種狀態(defeated/escaped/current/pending)但:
1. 沒區分敵人類型(全部 ○ 圖示),玩家無法辨識「哪個 pending chip 是精英狼」
2. 精英化新加入的 chip 跟其他 pending 一樣是 ○,沒突顯
3. 不能點擊跳轉到該戰鬥的 BattleRecord PageView

跑 `/grill-with-docs` 走完 9 個決定(領域語言 / 資料源定位 / 視覺風格 / pending 區隔 / 點擊跳轉 / 動畫 / 敵人 icon / layout / outcome 範圍)。

## 決定

### 1. 領域術語:**連戰時間軸**(Chain Timeline)

CONTEXT.md §連戰新增此術語(與「冒險手記 MapView = 戰役時間軸」同語族但 scope 不同)。

| Widget | Scope | 載體 |
|---|---|---|
| 連戰時間軸 | 當前 attempt × 當前 chain | BattleView 內常駐 |
| MapView | 跨 chain × 跨 attempt(經 chip switcher) | 冒險手記 overlay |

### 2. 資料源:**BattleRecord(過去)+ enemy_queue(未來)**混合模型

- **sealed 節點**:來自 `AdventureRecord.battles`,篩 `campaign_id == X && campaign_attempt == 當前 && chain_id == 當前`
- **current 節點**:`enemy_queue[0]`
- **pending 節點**:`enemy_queue[1..]`

**`chain_progress_states` 的角色被縮減** —— 只用於 chain-level 統計(連戰是否結束、defeated_count 等),不再 drive 時間軸視覺。

**Invariant**:所有 sealed 節點都對應一個 BattleRecord(可點跳 PageView,無例外)。

### 3. 視覺風格:類 MapView 圓形節點 + 連線,縮小 + hierarchy

| 節點類型 | 半徑 | 視覺 | 對比 MapView |
|---|---|---|---|
| MapView inline 戰鬥節點(參考) | 14px | 實心 | (基準) |
| 連戰時間軸 **sealed**(defeated / escaped) | 10px | 實心填色 + 外框 | 比 MapView 小一級 |
| 連戰時間軸 **current** | 12px | 實心 + ACCENT 高亮邊框 + pulse | 比 sealed 大一級 |
| 連戰時間軸 **pending** | 8px | **空心** + 細邊框 1px | 比 sealed 再小 |
| 連戰時間軸 **pending elite** | 8px | 空心 + **紅邊** + ⚡ 角標 | 同 pending 但紅 |

**連線**:
- sealed ↔ sealed / sealed → current:實線 2px
- current → pending / pending ↔ pending:虛線 1px dashed(seg 4 / gap 3,同 MapView old branch 虛線規格)

**節點 icon**:節點本身無 icon(純圓);敵人類型用節點下方中文 label 標示(「兔」「狐」「狼」「異變狼」),完整 instance name 走 tooltip。

### 4. sealed vs pending 視覺對比:實心 / 空心 + 實線 / 虛線

雙重對比,玩家絕對分得出「已發生 vs 未發生」:

```
chain_4 重挑後(精英化排在末段):

●━━●━━●╌╌◐╌╌○╌╌○
 ✓  ✓  ✗  ▶  ○  ⚡
 兔 狐 狼     狼  精狼
sealed       current pending elite-pending
```

虛線語意說明:
- MapView 的虛線 = old retry 分支(從主軸拉到上方,跨「歷史路線」)
- 連戰時間軸的虛線 = 未發生(同主軸上的未來部分)

兩種虛線各自的語境隔離,語意自洽。

### 5. 點擊跳轉 + 廢除 RecordButton badge(Supersedes ADR-0005 §badge)

| 節點類型 | 可點? | 跳轉 |
|---|---|---|
| sealed defeated | ✅ | 該 BattleRecord 的 PageView |
| sealed escaped | ✅ | 該 BattleRecord 的 PageView |
| current | ❌ | 戰鬥未結算,無紀錄 |
| pending(一般) | ❌ | 無紀錄、無 context |
| **pending elite** | ✅ | **`AdventureRecord.get_last_failure(template_id)` 的 PageView**(等同 RecordButton badge 原行為) |

**RecordButton badge 廢除**:
- 移除 [m2_campaign.gd](../../../scripts/ui/m2_campaign.gd) `_setup_record_button_badge` / `_start_record_badge_pulse` / `_stop_record_badge_pulse` / `_refresh_record_badge` / `_record_badge` / `_record_badge_tween` / `_elite_entry_battle_id`
- RecordButton 退回單純「開冒險手記」按鈕(`_on_record_button_pressed` 簡化:直接 `journal.initial_campaign_id = CAMPAIGN_ID; add_child(journal)`)
- ADR-0005 §其他(紀念品 evaluator pattern / `had_game_over_in_campaign` 等核心邏輯)**不動**

**Invariant**:elite context-aware 入口唯一 = 連戰時間軸的 pending elite chip。

### 6. 失敗 / 精英化轉換動畫:最小但有效

| 變化 | 動畫 | 時長 |
|---|---|---|
| current chip 轉 sealed | 顏色 lerp(ACCENT → OK/FAIL)+ icon 切換(▶ → ✓/✗) | 0.25s |
| 末段 append 新 chip(精英化) | Scale 0→1 + alpha 0→1,**從末段位置展開**(不是 slide) | 0.3s |
| 緊接 insert 新 chip(clone) | 同上,從 insert 位置展開 | 0.3s |
| Elite chip 初次出現 pulse | scale + alpha pulse(2 個 cycle 共 1.4s) | 1.4s 後自動停 |

**為何不用 slide**:精英化是「原狼陣亡 + 精英版誕生」(兩個獨立 chip),不是「同一物體移動」;scale-from-position 正確表達「在此位置誕生」。

### 7. Layout 改動

```diff
[m2_campaign.tscn]

+ [新增 node] StageZone/ChainTimelineSlot
+   offset_left=520  offset_top=8  offset_right=1240  offset_bottom=60
+   (寬 720 高 52,stage 右上角;實機微調後的最終位置)

  [改] StageZone/EnemyInfoSlot
-   offset_top = 6
+   offset_top = 44     ## 讓出頂部空間給時間軸保留位移彈性

- [刪除] StageZone/ProgressSlot
```

**位置 history**:草稿原為頂部置中(`y=8-44 x=200-1080`)→ 中下方對齊立繪底部(`y=170-222`)→ 最終定案 stage **右上角**(`y=8-60 x=520-1240`,user 微調寬度)。Stage 中下方視覺壓迫感重 + 跟立繪互相干擾;右上角不擾戰鬥區、跟 enemy figure 同側 + 玩家視線自然從左(玩家)往右(敵人+進度)。

```diff
[m2_campaign.gd]

- @onready var progress_slot: Control = $StageZone/ProgressSlot
+ @onready var chain_timeline_slot: Control = $StageZone/ChainTimelineSlot

  func _ready():
-   progress_indicator = ProgressIndicator.new()
-   progress_slot.add_child(progress_indicator)
+   chain_timeline = ChainTimeline.new()
+   chain_timeline_slot.add_child(chain_timeline)
```

**保留** `scripts/ui/widgets/progress_indicator.gd`(給 m1 dev 場景 [m1_battle.gd](../../../scripts/ui/m1_battle.gd) 用,其 `setup(total, current_index)` 簡單版 API 仍有效)。

### 8. 範圍邊界

時間軸**只**支援以下 5 個 outcome 的視覺呈現:

| Outcome | 時間軸動畫 |
|---|---|
| OHK | current → sealed defeated |
| FOX_FLEE | current → sealed escaped |
| WOLF_ELITE_PROMOTION | current → sealed escaped + 末段展開 pending elite + 1.4s pulse |
| GRAY_RABBIT_CLONE_SPAWN | current → sealed escaped + queue[0] 位置展開新 pending |
| GAME_OVER | 時間軸不動(GAME_OVER 對話框接管畫面) |

**不支援的 outcome**(均為 dead path,序章前半 chain_1~5 全部 `tutorial_retry = false`):
- `TUTORIAL_RETRY`:教學重來機制,已被灰兔機制(GRAY_RABBIT_CLONE_SPAWN)取代
- `RABBIT_CHAIN_FLEE`:集體逃,被灰兔機制取代,現役連戰已不再使用

dead path 的 code 本身保留(若未來啟用 chain.tutorial_retry 仍會走到),但時間軸視覺**不為其設計轉換動畫**。若未來重新啟用,須新 ADR 補設計。

## 後果

### 正面

- **填補 UX 缺口**:玩家在 BattleView 內常駐看到「連戰結構 + 精英化排隊」,不需開冒險手記也能查
- **連戰時間軸 = MapView 語族延伸**:玩家學一次「節點 + 連線」表達法,通用兩個 widget(層級不同 scope)
- **單一 elite context 入口**:廢除 RecordButton badge,避免兩個入口做同件事的認知負擔;連戰時間軸成為唯一 elite 警示 + 跳轉源
- **資料源 invariant 乾淨**:sealed 一定有 BattleRecord(可點),沒「sealed 不可點」的破口
- **動畫最小但完整**:3 種動畫(color lerp / scale / pulse)覆蓋所有 outcome 的視覺反饋,不依賴 emoji / 美術資源
- **未來 cleanup 機會**:dead path(TUTORIAL_RETRY / RABBIT_CHAIN_FLEE)的視覺呈現可在後續 PR 連同 code 清除(不在本 ADR 範圍)

### 負面 / 取捨

- **layout 改動**:`EnemyInfoSlot` 高度縮 38px(228→190);內容自動 reflow(`COLUMN_BUDGET=196` 會多開 1 欄),視覺壓縮但功能不損
- **新 widget 維護成本**:ChainTimeline 是新 class,跟 MapView 兩個渲染器要保持視覺一致(節點 / 線粗 / 虛線規格);後續 visual pass 時兩處要同步
- **RecordButton 簡化**:用戶剛適應 ADR-0005 badge 機制(2026-05-17 凍結),要重新學「精英 context 在時間軸上,不在 RecordButton 上」;但時間軸更顯眼,學習成本應低於 badge
- **資料源混合**:BattleRecord 跟 enemy_queue 兩個源拼接,`_record_battle` + `enemy_queue.pop_front()` 必須緊鄰(目前 [m2_campaign.gd:367-369](../../../scripts/ui/m2_campaign.gd#L367-L369) 已是);未來若拆兩階段,時間軸會閃現不一致狀態,要小心
- **dead path 視覺缺口**:若未來重啟教學重來或集體逃,時間軸**不會有正確動畫**(會直接跳變),要新 ADR 補

## 已考慮的替代方案

### 強化既有 ProgressIndicator(維持垂直右側 chip 方塊)

- 拒絕原因:chip 方塊風格跟 MapView 視覺斷裂;垂直 layout 不表達「前→後」時間順序感;且 chip 方塊難承載「圓節點 + 連線」哲學

### 視覺風格用 emoji(🐇🦊🐺🐻)

- 拒絕原因:Godot 字型 emoji 渲染不穩定(可能 fallback 為 ☐);emoji 風格跟未來美術(森林狩獵)可能衝突;違反「美術後置」原則

### pending 用 alpha 0.5 區隔 sealed(維持實心)

- 拒絕原因:alpha 對比在 8-10px 小節點上不夠強;alpha 0.5 已被 MapView old retry 佔用,語意衝突

### 保留 RecordButton badge(不廢除)

- 拒絕原因:兩個入口做同件事(連戰時間軸 elite chip + badge),認知負擔大;時間軸 context 更豐富(看得到精英狼在隊伍第幾位),badge 只是按鈕邊角紅點

### 精英化用 slide 動畫(chip 從原位移到末段)

- 拒絕原因:概念錯誤 —— 精英化不是「同一隻狼搬位置」是「原狼陣亡 + 精英版誕生」;且 HBox reflow 動畫實作複雜

### 連戰時間軸跨 attempt 顯示歷史

- 拒絕原因:跨 attempt 的歷史查閱已由 MapView chip switcher(ADR-0006)處理,scope 分明;時間軸常駐空間有限,塞跨 attempt 會擁擠 + 跟 MapView 角色重複

### 把連戰時間軸放在 InventoryZone 頂部(避開 EnemyInfoSlot)

- 拒絕原因:違反「連戰時間軸 = 戰鬥 context」直覺;玩家視線在 StageZone,InventoryZone 是手牌區,放錯位置

## 相關

- [ADR-0004:冒險手記 MapView 嚴格走過版 + NarrativePage 共用版型](0004-adventure-journal-mapview-narrative-page.md) — 時間軸視覺風格延伸自此 ADR 的「節點+連線」哲學
- [ADR-0005:紀念品條件 derive + evaluator 集中](0005-souvenir-conditions-derive-and-evaluator.md) — §RecordButton 精英入口 badge 被本 ADR 部分取代;§紀念品 evaluator 維持
- [ADR-0006:冒險手記 attempt 結構(schema v3 + chip switcher)](0006-adventure-journal-attempt-structure.md) — 跨 attempt 查閱由此處理,連戰時間軸只看當前 attempt
- [ADR-0007:MapView latest inline 主軸 + old retries 為上方分支](0007-mapview-latest-inline-old-as-branches.md) — 「主軸 = 玩家最終 sealed 的歷史」哲學延伸到時間軸(sealed 實心 / pending 空心)
- [CONTEXT.md §連戰時間軸](../../../CONTEXT.md)
- [m2_campaign.gd](../../../scripts/ui/m2_campaign.gd) `_refresh_chain_sequence` / `_on_record_button_pressed`(待重構)
- [progress_indicator.gd](../../../scripts/ui/widgets/progress_indicator.gd)(保留給 m1 dev 場景)
- [chain_timeline.gd](../../../scripts/ui/widgets/chain_timeline.gd)(待建立)
