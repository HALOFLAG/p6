# ADR-0003:StrikeResult 抽出為 typed Resource,內嵌進 BattleRecord(Route B)

- 狀態:Accepted
- 日期:2026-05-16
- 決策者:haloflag01

## 背景

[Resolution.resolve()](../../../scripts/logic/resolution.gd) 回傳一個 6 key 的 Dictionary(`ohk` / `passing_paths` / `contributions` / `mixed_count` / `requirements` / `shortfalls`),這個 shape 流經:

```
Resolution.resolve()                       →  Dict
  ↓
BattleEngine.commit_strike()               →  engine.result: Dictionary
  ↓
BattleView.strike_committed signal payload →  emit(Dictionary)
  ↓
  ├→ m1 / m2 host handlers (result.get("ohk", false) 等 dict 訪問)
  ├→ CalibrationClassifier.classify(result, ...) (.get 訪問)
  └→ RequirementBar.build_group(result)            (.get 訪問)
```

同時 [BattleRecord](../../../scripts/data/battle_record.gd) 把**同樣 6 個欄位**以 typed `@export` 形式持久化。adventure_journal 為了餵 RequirementBar,還要從 BattleRecord 手動把 6 個欄位重組成 Dict:

```gdscript
var result_dict := {
    "ohk": record.ohk,
    "passing_paths": record.passing_paths,
    "contributions": record.contributions,
    "mixed_count": record.mixed_count,
    "requirements": record.requirements,
    "shortfalls": record.shortfalls,
}
rvbox.add_child(RequirementBar.build_group(result_dict))
```

「**同一份事實,Dict 和 typed Resource 兩種 shape 共存**」是真實 friction。Dict 路徑沒有 IDE autocomplete、沒有編譯期型別檢查、容易 typo(`result.get("ohh")` 安靜回 null)。

順便發現:`BattleEngine.commit_strike` 第 115 行 `result["revealed_info"] = revealed_info.duplicate()` 是 dead code(零 consumer,m2/m1/battle_view 都從 `engine.revealed_info` 直接讀)。

## 決定

把 6 個結算欄位抽出為 typed `StrikeResult` Resource,**內嵌**進 BattleRecord 與 BattleEngine。

### 主決策:Route B(內嵌)而非 Route A(扁平 + converter)

兩條路線:

- **Route A** — BattleRecord 保持扁平 6 欄位 + 加 `to_strike_result()` converter。disk JSON 不變。「runtime form = StrikeResult,persistence form = flat BattleRecord」雙形態共存
- **Route B** — BattleRecord schema 拆,6 個欄位移進內嵌的 `result: StrikeResult`。Runtime 跟 disk 形狀一致。**選 B**

理由:

1. **P6 未上線** — Route B 的存檔不相容只影響 dev 機上的測試紀錄(`user://battle_records.json`),這是可接受成本;未來上線後再做 Route B 才會嚴重
2. **概念收斂優於介面相容** — Route A 留下「為什麼 record 是 flat 但 runtime 是 nested」的長期心智負擔;Route B 一次性對齊
3. **Migration 成本可控** — 加一個 version check + 不符自動清檔(5 行)即可

### 連帶決策

**Disk JSON 布局** — Nested。`record.to_dict()` 寫:

```json
{
  "battle_id": "...",
  "enemy_template_id": "rabbit",
  "strike_cards": { ... },
  "result": {
    "ohk": true,
    "passing_paths": ["pierce"],
    "contributions": { "pierce": 3 },
    "mixed_count": 3,
    "requirements": { ... },
    "shortfalls": { ... }
  },
  "revealed_info": { ... },
  "calibration_state": 1,
  "failure_outcome": -1,
  ...
}
```

而非 flat 鋪在同一層(後者會讓 disk 不反映 runtime 結構)。

**StrikeResult 介面 = KISS** — 只有 6 個 `@export` 欄位,**不加** helper method。理由:`best_margin` / `closest_gap` / `weakness_contribution` 等只有 `CalibrationClassifier` 一個 caller,搬上去等於把 classifier 算法散開卻不產生 leverage。未來出現第 2 個 caller 再 promote。

**Migration 策略** — `AdventureRecord` VERSION 由 `1` 升 `2`;`_load_from_disk` 讀進來先比 version,不符 → 清空 battles + prep_nodes、刪 disk 檔、`push_warning("舊 record schema 不相容,已重置")`。dev 機上這番痕跡檔自動清掉,以後 schema 變動 bump version 即可,不必手動 `rm`。

**revealed_info 留在 BattleRecord 本層** — 不混進 StrikeResult。理由:`revealed_info` 是 BattleEngine 的揭露狀態 snapshot(揭露機制),不是結算結果的一部分。Caller 本來就從 `engine.revealed_info` 直接讀(不從 `engine.result["revealed_info"]` 讀),所以 BattleEngine 那行 dead code 順手刪。

**strike_cards / calibration_state / failure_outcome 也留在 BattleRecord 本層** — `strike_cards` 是本擊**輸入**(玩家鎖了哪些卡),不是結算**輸出**;`calibration_state` 和 `failure_outcome` 是結算之後的**分類**,不是 Resolution 的回傳。三者跟 result 概念分離。

## 後果

正面:

- 跨 9 個檔案的 `.get("ohk", false)` 等 dict 訪問換成 typed `.ohk`,IDE autocomplete + 編譯期型別檢查回來
- adventure_journal 不再手動重組 Dict;直接 `RequirementBar.build_group(record.result)`
- BattleRecord schema 終於反映 runtime 概念(metadata + enemy context + revealed_info + strike input + result + classifications)
- 順手刪 `BattleEngine.commit_strike` 第 115 行 dead code
- 未來新增結算欄位(例:「達標餘裕」、「節省卡數」)只動 StrikeResult 一處,自動跨 view / record / journal
- VERSION check 機制建立後,以後 schema 變動 bump version 即可,不必手動 `rm` disk

負面 / 取捨:

- **存檔不相容** — 舊 `battle_records.json`(version=1, flat)讀不回。已用 version check 自動清檔緩解;對 P6 dev 期可接受,**上線後**再做 schema 變動會嚴重
- **GDScript signal payload 型別不強制** — `strike_committed(result: StrikeResult)` 改完後,handler 漏改成 `func _on_strike_committed(result: Dictionary)` 不會在 connect 期報錯,要 runtime 才爆。Grep 全部 handler 簽名是必要步驟
- **`Object.get(property)` 在 Resource 上仍可呼叫** — 漏改的 `result.get("ohk", false)` 可能 silent 回奇怪值(Resource 沒 default-arg get)。要 grep `\.get\("(ohk|passing_paths|...)"` 全部改 typed
- **Blast radius 大** — 跨 9 個檔案的同步改動,每個 callsite 都要 typed 化;漏改不是 compile-time 錯誤
- **CalibrationClassifier / RequirementBar 簽名變動** — 沒有 callsite 外的 API consumer,但仍是公開類別

## 已考慮的替代方案

### Route A(扁平 + `to_strike_result()` converter)

- 拒絕原因:雙形態共存的心智負擔長期沒消失;P6 未上線,沒有「保持 disk 相容」的硬性需求
- 若 P6 上線後再做類似 schema 變動,Route A 是當時的對答案

### `inst_to_dict` / `dict_to_inst` Godot 魔法

- 拒絕原因:JSON 帶 script path metadata,script 路徑變動會 break;migrate 畫意難;跟 BattleRecord 既有手寫 `to_dict / from_dict` 風格不一致

### StrikeResult 加 helper method(`best_margin` 等)

- 拒絕原因:目前只有 `CalibrationClassifier` 一個 caller;搬上去等於把 classifier 算法散開卻不產生 leverage。第 2 個 caller 出現再 promote

### `revealed_info` 併入 StrikeResult

- 拒絕原因:`revealed_info` 屬 BattleEngine 的揭露機制 snapshot,不是 Resolution 的結算結果;混在一起會讓 StrikeResult 的「Resolution 的純 output」語意鬆掉

### `strike_cards` 併入 StrikeResult

- 拒絕原因:`strike_cards`(本擊鎖了哪些卡)是 Resolution 的**輸入**之一,不是輸出。混進去 StrikeResult 等於把 Strike 跟 Resolution 兩個概念糊在一起

### 不寫 version check,讓 from_dict 容錯讀兩種 shape

- 拒絕原因:多 ~10 行讀取邏輯永久存在,只為了讀 dev 機上不重要的測試紀錄。Trade 不划算;version-bump-清檔簡潔且為未來變動鋪好機制
