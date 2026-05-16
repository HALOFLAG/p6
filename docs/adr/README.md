# Architecture Decision Records (ADR)

這個資料夾記錄 P6 的架構決策。

## 何時寫 ADR

當下列情況發生 → 寫一份 ADR:
- 跨多個模組的選型決策(例:選某 Godot autoload 模式 / 選某資料存檔格式)
- 故意拒絕某個常見方案,且未來人可能會反問「為何不 X」
- 推翻先前的設計方向(連同舊 ADR 標 `Superseded by ADR-NNNN`)

不需要 ADR:
- 純設計討論 → 寫到 `docs/` 對應主題文件
- 單一檔案內的實作選擇 → 寫在 code comment 或 commit message
- 暫時 workaround → 不寫,改完即丟

## 命名與格式

`NNNN-kebab-case-title.md`,從 `0001` 開始遞增。

每份 ADR 結構:

````markdown
# ADR-NNNN: 標題

- Status: Proposed / Accepted / Superseded by ADR-NNNN
- Date: YYYY-MM-DD
- Deciders: haloflag01

## Context
[為什麼要做這個決策]

## Decision
[實際決定了什麼]

## Consequences
[正面 / 負面後果]

## Alternatives considered
[考慮過哪些方案,為何不選]
````

## 與 docs/ 的關係

- `docs/` = **設計文件**(主線、規範、規格)
- `docs/adr/` = **決策紀錄**(為什麼選 A 不選 B)

兩者互補:`docs/卡牌設計原則.md` 寫「卡有 lock_class 三分類」(現況);若 ADR 存在則是「為何採三分類而非四分類」(歷史決策)。

目前 P6 還沒有 ADR;有需要時再從 `0001` 開始建。
