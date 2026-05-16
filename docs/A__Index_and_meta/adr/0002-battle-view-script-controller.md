# ADR-0002:BattleView 採純 script 控制器(host 提供 node 參照)而非自含 scene

- 狀態:Accepted
- 日期:2026-05-16
- 決策者:haloflag01

## 背景

[m1_battle.gd](../../../scripts/ui/m1_battle.gd) 與 [m2_campaign.gd](../../../scripts/ui/m2_campaign.gd) 各自渲染相同的「戰鬥-zone UI」:卡牌牌堆(pile_slot)、本擊時間線(strike_slot)、狀態面板(status_content)、敵人立繪(enemy_figure)、敵人情報欄(enemy_info_slot)、連戰預覽殘影(afterimages)。

重複範圍約 250 行,函式對應:

| 函式 | m1_battle | m2_campaign |
|---|---|---|
| `_build_card_piles` | L102-114 | L138-150 |
| `_refresh_piles` | L266-277 | L676-686 |
| `_refresh_strike` | L281-324 | L690-733 |
| `_make_card_widget` | L327-332 | L736-741 |
| `_make_status_row` | L369-380 | L762-773 |
| `_group_pool_cards` | L392-402 | L838-848 |
| `_count_in_strike(_local)` | L412-420 | L851-861 |
| `_set_preview_mode` / `_spawn_preview_afterimages` | L178-207 | L627-658 |
| `_on_enemy_figure_input` / `_apply_enemy_info_state` | L156-166 | L605-614 |
| `ENEMY_FIGURE_*`、`AFTERIMAGE_*` 常數 | L20-26 | L28-33 |

m2 的修正會 silent rot m1。未來新增 replay / tutorial mode 等場景時會再複製一次。

決定抽出 `BattleView` 作為唯一的戰鬥-zone seam。實作模式有兩條路:

1. **自含 widget(`battle_view.tscn` + 內含節點)** — view 自帶 scene tree,host 場景 instantiate 後 add_child
2. **純 script 控制器(`battle_view.gd`,host 透過 attach 傳入 node 參照)** — view 不擁有任何節點,只持有 references 操作 host 提供的 widget

## 決定

**選純 script 控制器**,並一併決定以下連帶設計。

### 主決策:接合方式

`BattleView extends RefCounted`(或 Node),無 `.tscn`。host 場景維持其現有 `.tscn` 不動;host 在 `_ready` 中呼叫:

```gdscript
view = BattleView.new()
view.attach({
    "pile_slot": pile_slot,
    "strike_slot": strike_slot,
    "status_content": status_content,
    "enemy_figure": enemy_figure,
    "enemy_info_slot": enemy_info_slot,
    "end_strike_button": end_strike_button,
    "advance_button": advance_button,
    "progress_slot": progress_slot,
})
```

view 將 callback 接到 host 提供的 button / gui_input,以 host 提供的 container 為渲染目標。

理由:

1. **host 場景以 hand-laid 絕對位置匹配第一期 UI 線框圖** — `EnemyFigure` offset_left=1040、`PileSlot` 在 `InventoryZone`、`StatusPanel` 在 `StrikeZone` 右側,各自有精確 anchors_preset + offset。改成自含 widget 要 gut 兩個 `.tscn` 並重排,風險高且失去 host 對佈局微調的能力
2. **m1 與 m2 場景佈局相同** — 重複的是 script 邏輯,不是 scene tree;不需要為「scene 共用」付自含模式的代價
3. **未來 replay 場景加入時** — 新場景照樣 hand-lay 戰鬥 widgets(維持線框圖一致),呼叫 attach 即可,不必繼承一個 fixed scene

### 連帶決策

**範圍** — BattleView 只擁有戰鬥-zone widgets(上表所列)。`dialogue_bubble` / `portrait_pair` / `progress_indicator` / `narrative_box` 留在 host —— 它們跨 phase 使用(m2 在 PRE_CHAIN / POST_CHAIN / INTRO 都用 dialogue + portraits;`progress_indicator` 語意上屬於連戰而非單一戰鬥)。

**Engine 生命週期** — host 建立 `BattleEngine`,每場戰鬥呼叫一次 `view.set_engine(new_engine)`,view 內部重新渲染。host 才掌握 `enemy_instance` / `enemy_template` / `deck` / `card_library` 的來源(campaign / chain / queue 邏輯);讓 view 自建 engine 等於把 campaign 細節推給 view。

**連戰預覽資料源** — Callable 模式。host 在 `_ready` 註冊一次 `view.set_preview_source(Callable)`,view 在玩家開啟預覽時 pull。理由:m2 的 `enemy_queue` 有四個變動點(OHK `pop_front` / `FOX_FLEE` 移除 / `RABBIT_CHAIN_FLEE` 整批移除 / `WOLF_ELITE_PROMOTION` 末尾追加);push 模式(`set_upcoming_preview(list)`)要求每個變動點都呼叫 refresh,drift 風險高。m1 dev 模式不註冊 source → 預覽 affordance 自動 suppress(單敵人 dev 模式本就沒有連戰概念)。

**對外 signal 契約** — 僅兩個 signal:
- `strike_committed(result: Dictionary)` — view 內部呼叫 `engine.commit_strike()` 後 emit;host 接手戰後校準分類 / FailureHandler / record_battle
- `advance_pressed()` — host 決定 advance 在當前 phase 的意義(下一隻敵人 / 連戰結束 / Ending)

view 完全吞掉 place / unplace / lock / 敵人情報切換 / 預覽切換等純渲染互動。

### 連帶實作:Candidate 2 `BattleEngine.available_count`

抽出 BattleView 時順帶把「remaining − in_strike(僅 PLACE 階段)」規則收回 engine:

```gdscript
# BattleEngine
func available_count(card_id: String) -> int:
    var entry := _find_entry(card_id)
    if entry == null:
        return 0
    if phase == Phase.PLACE:
        return entry.count_remaining - _count_in_strike(card_id)
    return entry.count_remaining
```

理由:「commit_strike 後 locked 卡已從卡組消耗,RESOLVED 階段不再 subtract in_strike」這條規則是 engine 內部知識;今天 m1/m2 的 `_refresh_piles` 都得知道這條規則。promote 後 view 只需 `engine.available_count(id)` + 自己判斷 `enabled = (engine.phase == PLACE and count > 0)`(view 本來就要看 phase 做其他渲染)。

## 後果

正面:

- 250+ 行戰鬥-zone UI 重複碼消除;m1 / m2 變成薄 host(主要持有各自的 phase 邏輯 / 教學重來 / 補給 / 紀錄)
- 未來 replay / tutorial / 練習模式新場景 = 寫 host script + 用既有 `.tscn` 樣式擺好 widgets + `attach` + 兩個 signal handler
- `available_count` 把「PLACE vs RESOLVED 雙減 bug」風險集中到一處
- BattleView 的 signal 契約顯式 — host 只需關心 strike_committed + advance_pressed,不再 reach into `engine.strike.placed_cards`
- 連戰預覽資料源 Callable 化 → m2 不再需要在四個 enemy_queue 變動點記得 refresh preview

負面 / 取捨:

- caller 必須記得傳入正確的 node 參照;弄錯名稱 → runtime 才報錯(自含 widget 在 editor 即可發現)
- 比自含 widget 難在 isolation 中單元測試 —— 測試要 mock 多個 Control node
- BattleView 持有 host 節點的 reference,host 場景 free 時要確保 view 已釋放(RefCounted + 在 host `_exit_tree` 中清空 reference 即可)
- attach() 介面欄位多(~8 個),簽名不漂亮;用單一 Dictionary 參數讓呼叫方好讀

## 已考慮的替代方案

### 自含 `battle_view.tscn`

- 拒絕原因:見決定主決策。host 場景的絕對位置佈局與線框圖直接對應,gut + 重排成本高、容易出錯;且 m1 / m2 共用的是 script 邏輯,不是 scene 佈局
- 若未來「需要在多個極不同的佈局中插入戰鬥 UI」(極不可能 — 線框圖是固定設計),再回頭考慮

### Engine 由 view 自建(`view.start_battle(instance, template, deck, library)`)

- 拒絕原因:host 才知道 enemy_instance / template / deck / library 的來源(campaign / chain / queue 邏輯);讓 view 自建等於把 campaign 細節(以及未來 replay 從紀錄重建 engine 的細節)推給 view。view 只該關心「渲染當前這個 engine」

### 預覽用 push 模式(`view.set_upcoming_preview(list)`)

- 拒絕原因:m2 的 enemy_queue 有 4 個變動點(`_on_resolution` OHK pop / `_handle_failure` 三個分支);push 模式每個變動點都要呼叫 refresh,容易漏寫(drift 風險)。Callable 模式 host 註冊一次,view 開啟預覽時 always pull fresh,單一真實來源

### Bundled `pile_state(id) -> { count, enabled }` 取代 `available_count`

- 拒絕原因:pile 渲染未來可能想要更多欄位(highlight / glow / 動畫狀態);engine 回傳型別不應隨 view 渲染需求成長。view 自己 compose `count` + `phase` → enabled 即可

### 透過 autoload(`CurrentBattle`)共享 engine 給 view

- 拒絕原因:增加全域動態狀態,測試與替換變難;違反 ADR-0001 的「動態狀態顯式傳遞」精神(ADR-0001 把 ResourceLibrary 限定為 static catalog)

### 把 EventBus 的 card_placed / card_locked 訊號接進來

- 不在本 ADR 範圍 — Candidate 3(EventBus 是 dead seam,要麼正式接起來、要麼刪除)是獨立決定。本 ADR 的 signal 契約刻意 minimal,future-proof 留到 Candidate 3 處理時再加
- **2026-05-16 後記**:Candidate 3 已處理 — EventBus autoload 全刪(5 emit 點 vs 0 listener,zero adapter)。BattleView 的 explicit signal 契約成為 P6 跨模組信號的預設模式。詳見 `程式規格書.md` §2 autoload 不採用 EventBus 註記
