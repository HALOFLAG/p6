# Domain Docs(P6)

mattpocock 工程 skill(`improve-codebase-architecture` / `diagnose` / `tdd` 等)讀 P6 設計文件的規則。

## 探索前要讀

- **根目錄 `CONTEXT.md`** — P6 的領域語言摘要(術語表 + 核心概念地圖)
- **`docs/文件目錄.md`** — 完整設計文件索引,按「實作必看度」分五層
- **`docs/adr/`** — 架構決策紀錄(本專案剛起步,可能為空;有相關主題再讀)

P6 是**單一 context** 專案(單一 Godot 遊戲 codebase,非 monorepo),不會有 `CONTEXT-MAP.md` 或 `src/<context>/docs/adr/`。

## 找具體設計時

`CONTEXT.md` 只給術語 + 概念地圖,**機制細節**請從 `docs/文件目錄.md` 的對照表進入:

| 你要動什麼 | 從哪份文件查 |
| --- | --- |
| 戰鬥流程 / 結算 | `docs/遊戲核心系統機制.md` |
| 卡牌 | `docs/卡牌設計原則.md` + `docs/卡牌資料庫.md` |
| 敵人 | `docs/敵人設計原則.md` + `docs/敵人資料庫.md` |
| 程式架構 / 模組 | `docs/程式規格書.md` |
| UI 介面 | `docs/UI 設計指引.md` + `docs/第一期 UI 線框圖.md` |
| 戰鬥紀錄 / 冒險手記 | `docs/戰鬥紀錄系統設計.md` |
| 開發里程碑 / scope | `docs/開發里程碑.md` + `docs/第一期開發Scope.md` |

不確定哪份適用 → 先讀 `docs/文件目錄.md`。

## 用 glossary 的詞彙

`CONTEXT.md` 列出的術語(本擊 / OHK / Place / Lock / 類型計數 / lock_class / flexible / 整備期 / 戰後校準 / 教學重來 等)在 issue 標題、重構提案、假設、測試名稱中使用時,**請沿用原詞**,不要漂移到同義詞。

不在 glossary 的概念 = 訊號:要嘛你發明了專案沒在用的語言(重新考慮),要嘛是真的缺口(留給 `/grill-with-docs` 處理)。

## ADR 衝突要標出

P6 的 ADR 制度剛起步,目前 `docs/adr/` 可能為空。但若未來有 ADR,且你的產出與 ADR 衝突,**明確標出**而不要默默覆蓋:

> *與 ADR-0007(類型計數模型)衝突 —— 但值得重啟討論,因為 ⋯*

## 與 docs/old_docs/ 的關係

`docs/old_docs/` 是 2026-05-12 重構前的舊文件,內容已被整合進主線文件。
**不要引用 old_docs/ 作為設計依據** —— 主線(`docs/` 下根層)是唯一活躍版本。
