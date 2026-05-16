# ADR-0001: ResourceLibrary 採 Godot autoload(單例)而非 DI

- Status: Accepted
- Date: 2026-05-16
- Deciders: haloflag01

## Context

P6 重構前,m1_battle / m2_campaign / adventure_journal 三個場景各自硬編相同的 `CARD_PATHS` / `ENEMY_TEMPLATE_PATHS` / `ENEMY_INSTANCE_PATHS` dict + 自己跑 `_load_resources()`。新增一張卡 = 改三處;m1 跟 m2 對「敵人資源」格式還不一致(m1 用 `ENEMIES` 陣列,m2 用兩個獨立 dict)。

決定建一個唯一入口集中所有靜態 .tres(卡牌 / 敵人模板 / 敵人 instance / 連戰 / 整備 / 戰役 / 校準台詞)。

實作模式有兩條路:

1. **Godot autoload(單例)** — 全域可呼叫 `ResourceLibrary.card("id")`,所有 caller 透過同一個 singleton 取資源
2. **Dependency injection** — `ResourceLibrary` 是普通 class,每個 scene 在建構時注入一份;測試時可注入 fake

DI 在「BattleEngine 等純邏輯模組要 unit test」時較友善 — 測試可直接餵 fake library;autoload 則需要在測試場景 override autoload。

## Decision

**選 autoload 單例**,理由如下:

1. **P6 規模小**,所有遊戲執行階段都需要相同的資源目錄,沒有「正常 vs 測試」兩種模式同時存在的情境;DI plumbing 的成本不划算
2. **遊戲全程資源目錄相同** — 不像 web app 有 multi-tenant、不同 user 看到不同資源這種需求;static catalog 用 singleton 是最直覺的模型
3. **caller 介面最簡潔** — `ResourceLibrary.card("tool_arrow_pierce")` vs 每個 scene 要在 `_ready` 接住注入的 ResourceLibrary 並存到 member var,後者只是把全域變成了「每場景一個 reference 到同一個東西」,沒有實質好處
4. **要單元測試 BattleEngine 等模組時**,寫個 `tests/fixtures/test_resource_library.gd`(滿足相同 method 介面),在測試場景 override autoload 即可。Godot 支援這個模式

## Consequences

正面:
- 三個 UI 檔不再重複路徑 dict + `_load_resources()`(刪除約 90 行 dead code)
- 新增卡牌 / 敵人 / 整備 / 連戰 / 戰役只需在 `scripts/autoload/resource_library.gd` 註冊一行
- m1 跟 m2 的敵人資源格式分歧(`ENEMIES` 陣列 vs 兩 dict)被消除
- BattleEngine 接受的 `card_library: Dictionary` 參數可由 `ResourceLibrary.cards()` 統一提供
- `CampaignDefinition` 順便簡化 — `chain_paths: Array[String]` 改為 `chain_ids: Array[String]`;`supply_paths` 整個欄位移除(supply 用 id 透過 ResourceLibrary 查)

負面 / 取捨:
- BattleEngine / Resolution 等純邏輯模組想單元測試時,需要寫 fixture autoload + 測試場景設定。不像純 DI 那麼開箱即用
- ResourceLibrary 啟動時 eager load 所有 .tres(P6 規模約 20+ 個檔,實測啟動成本可忽略;遊戲規模成長到數百資源時要考慮 lazy load)

## Alternatives considered

### Dependency Injection(每場景注入)

- 拒絕原因:見 Decision §1, 2
- 若未來 P6 規模長到「需要在 runtime 切換完全不同的資源目錄」(例:DLC / mod 系統 / 多語言版本),再回頭重新評估

### 自動掃描 res://resources/<type>/*.tres

- 完全免註冊,丟 .tres 即上架
- 拒絕原因:Godot export 後 res:// 在某些平台需要額外 PCK manifest 才能掃目錄;為了避免「dev 環境正常、export 後資源消失」這種難 debug 的 bug,選手動註冊
- 若之後驗證過 Windows export 沒問題,可重新考慮

### Dictionary 屬性公開(`ResourceLibrary.cards["xxx"]`)

- 介面更少 method,但 caller 必須知道 dict key、不能誤 path、典型錯字只能 runtime 才知道
- 選 typed methods(`card(id) -> CardDefinition`)以獲得 IDE autocomplete + 型別提示
