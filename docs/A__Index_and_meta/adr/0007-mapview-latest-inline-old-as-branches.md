# ADR-0007:MapView latest retry inline 主軸 + old retries 為上方分支

- 狀態:Accepted
- 日期:2026-05-17
- 決策者:haloflag01
- Supersedes(部分):[ADR-0004 §3 戰鬥分支 old/new 視覺](0004-adventure-journal-mapview-narrative-page.md)

## 背景

M5-S4 完成 attempt 結構後實機觀察,user 反饋:

> 「重新挑戰時會直接拉出分支,我想調整成舊的路線(包含戰鬥節點)被拉出,而新的(多一戰鬥節點)會維持在主軸上,這樣就會有我們看到的主軸是主要發生過的事的感覺。」

ADR-0004 §3 原決定:該 chain 的**所有 retry 列**(含 latest)都從連戰主節點橫向分支出去,只用整列透明度(new=1.0 / old=0.5)+ 列尾 "new"/"old" 文字標記區分。

問題:這樣 latest retry 跟 old retry 在 layout 上等價(都是分支),失去「**主軸 = 玩家最終 sealed 的歷史**」的視覺哲學。連戰主節點縮成 8px 小 dot 也讓主軸視覺弱化。

跑 `/grill-with-docs` 走完 6 個決定(整體 layout / 虛線接點 / 節點尺寸 / old row 順序 / 主軸間距規則)。

## 決定

### 1. Latest retry 戰鬥節點 inline 主軸右側

該連戰最大 `retry_count` 的列**直接接在連戰主節點右側水平展開**,不再走分支 row。

```
主軸(垂直)
│
●(narrative)
│
●━━ ■ ━ ■ ━ ■                ← 連戰主節點 + latest 戰鬥節點 inline 主軸
│
●(prep)
│         ╭━ □ ━ □ ━ □ ✗ old  ← old retry 拉到上方,虛線連接
│        ╱
●━━ ■ ━ ■ ━ ■                ← 連戰主軸 inline = latest
│
```

### 2. Old retries 拉到該連戰主節點**上方**,獨立分支 row,虛線連接

- 虛線從**主軸線該 row Y 位置**水平拉到該 row 第一個 old 節點(grilling Q1)
- Old 節點縮小 + 整列 alpha 0.5(維持 ADR-0004 §3 的透明度設計)
- 列尾仍標 "old" 文字;**取消 "new" 文字**(latest 已是主軸 inline,不需標籤)

### 3. 多 old retry 時,舊在最上

```
old retry 0 (最早)  ─────────  ← 最上方
old retry 1        ─────────
old retry 2 (近)   ─────────  ← 緊鄰主軸
●━━ ■ ━ ■ ━ ■ (latest inline)
```

**為什麼舊在最上**:自然時間順序,從上往下讀 = 從舊到新到最終 sealed,符合冒險手記翻頁敘事感。

### 4. 節點尺寸對比

| 節點類型 | 半徑 | 角色 |
|---|---|---|
| 連戰主節點(chain main) | 12px(舊 8px) | 主軸 anchor,放大 |
| narrative / prep 主軸節點 | 14px(不變) | 主軸節點 |
| **inline 戰鬥節點(latest)** | **14px**(舊在分支 10px) | 主視覺主角 |
| **old 分支戰鬥節點** | **7px**(舊 10px) | 副視覺,縮小 |
| 主軸線粗 | 2px | 主軸 |
| Old 分支連線(節點間) | 1px | 細 |
| Old 虛線(主軸→首節點) | 1px dashed(seg 4 / gap 3) | 細 + 斷續 |

**對比強度**:
- 節點半徑比 14:7 = 2:1
- 連線粗細 2px:1px
- Old alpha 0.5 + dashed 連接

三重對比讓主軸視覺壓倒分支。

### 5. 主軸節點固定間距,有 old retries 時上方額外騰出空間

- 預設主軸節點 center-to-center = `MAIN_NODE_SPACING = 70px`(不變)
- 戰鬥節點水平佔用空間**不影響**下一個主軸節點垂直位置(grilling Q3)
- Chain 有 N_old > 0 時,該 chain 主節點 Y 額外 += `N_old × BRANCH_ROW_SPACING_Y`,給上方 old rows 騰出空間

### 6. SPAWN / PROMOTION frame + arrow 兩種半徑都支援

`_make_node_frame(center_x, center_y, radius)` / `_draw_branch_arrow(..., radius)` 加 radius 參數,inline (14px) 跟 old (7px) 兩種尺寸都正確繪。

## 後果

### 正面

- **「主軸 = 玩家最終 sealed 的歷史」哲學落實**:玩家一眼看到主軸 = 真實走過 + 完成版的時間線
- **三重視覺對比**(大小 / 線粗 / 透明)讓主軸 / 分支層級清晰
- **冒險手記敘事感**:翻頁式時間軸,old retry 視覺上「翻過的紙頁」感(上方拉出)
- **連戰主節點放大**:不再是縮成 8px 的小 dot,跟其他主軸節點同層級
- **CONTEXT.md / ADR-0006 攝影學一致**:同 attempt 內的 chain retry vs attempt 跨界(chip)兩個層級分明

### 負面 / 取捨

- **MapView layout 邏輯複雜化**:從「所有 retry 統一走分支」變成「latest 走 inline / old 走分支」,renderer 路徑分支增加
- **連戰戰鬥節點橫向擴展時 scroll 量加**:inline 節點較大(14px)+ 較寬間距(38px),5 個節點 ≈ 240px;6 連戰若全部寬會超出 1280px(scroll 即可,MapScroll horizontal_scroll_mode=1 已 enable)
- **垂直空間動態擴充**:chain 有 N_old > 0 時上方額外加 N_old × 32px,Map 整體高度隨重挑次數而擴張(可接受,通常 N_old ≤ 2-3)
- **ADR-0004 §3 部分被取代**:該條保留作為「歷史設計」參考,實作以本 ADR 為準

## 已考慮的替代方案

### 連戰主節點移除,直接讓第一個 inline 戰鬥節點接到主軸線

- 拒絕原因:連戰主節點作為「這個 chain 的起點 anchor」+ 對齊 prep / narrative 主軸節點層級重要;移除會讓主軸節點層級不一致

### Old retries 拉到下方而非上方

- 拒絕原因:「下方」會跟下一個主軸節點(整備 / 下一連戰)垂直碰撞,需要更多空間管理。「上方」貼著該連戰主節點頂部,自然不擾下文

### 多 old retry 時新在最上(時間反序)

- 拒絕原因:違反「冒險手記翻頁=順序」直覺;新疊在最上等於每次重挑都「推開」歷史,反不自然

### Inline 節點跟 old 節點同尺寸

- 拒絕原因:失去 user 明確要求的「主軸節點放大強化對比」效果。對比是視覺哲學落實的關鍵

### 主軸垂直間距完全固定,old retries 跟主軸節點重疊或裁切

- 拒絕原因:重疊不可讀;裁切等於丟失資料。動態擴充垂直空間是唯一無損方案

## 相關

- [ADR-0004:冒險手記 MapView 嚴格走過版 + NarrativePage 共用版型](0004-adventure-journal-mapview-narrative-page.md) — §3 戰鬥分支 old/new 視覺被本 ADR 部分取代;其他章節維持
- [ADR-0006:冒險手記 attempt 結構(schema v3 + chip switcher)](0006-adventure-journal-attempt-structure.md) — 跨 attempt 結構(chip)/ 本 ADR 處理同 attempt 內 chain retry 結構,兩者正交
- [戰鬥紀錄系統設計.md](../../C__Implementation_benchmarks/戰鬥紀錄系統設計.md) §一「行動造圖」哲學
- [adventure_journal.gd](../../../scripts/ui/adventure_journal.gd) `_build_inline_battles` / `_build_old_branch_row` / `_draw_dashed_horizontal`
