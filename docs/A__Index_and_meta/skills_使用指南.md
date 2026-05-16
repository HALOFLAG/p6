# Mattpocock Skills 使用指南

> **狀態**:已安裝 6 個 skill(2026-05-16)
>
> 來源:[mattpocock/skills](https://github.com/mattpocock/skills) ── Matt Pocock 為 Claude Code 開發者寫的工程工作流 skill 包
> 安裝位置:`~/.claude/skills/`(global,綁定 Claude Code agent)
> 影響範圍:**所有 Claude Code session**,不限於 P6 專案

---
接下來照這 4 步走
重啟 Claude Code session —— 這個對話看不到新 skill,新對話才會
/setup-matt-pocock-skills —— issue tracker 選「本地檔案」、docs 位置選 docs/
/improve-codebase-architecture —— 給它掃 P6 現況,看建議跟我先前猜的差不差(預期會點到 CARD_PATHS 三重複、_make_supply_chip 重複、m2_campaign 過肥等)
/write-a-skill + 餵指南裡的 /p6-docs-first 草稿 —— 落地第一個 P6 專屬 skill

---
## Mattpocock Skills 指令一覽

| Skill | 觸發 | 一句話功能 | 何時用 |
|---|---|---|---|
| **setup-matt-pocock-skills** | `/setup-matt-pocock-skills` | 一次性配置:設定 issue tracker / triage 標籤 / docs 位置;產出 `docs/A__Index_and_meta/agents/*` 三份規範 | 裝完 skills 第一件事(P6 已跑過 2026-05-16) |
| **caveman** | `/caveman` 或關鍵字(`caveman mode` / `less tokens` / `be brief`) | Token 壓縮模式:砍冠詞贅字、用 `->`、縮寫、技術詞照舊。**持續整個 session 直到 `stop caveman`** | 長段討論完、進機械式實作階段 |
| **handoff** | `/handoff` 或「準備交接」 | 生 markdown 摘要(目前狀態 + 引用既有產物 + 建議下次 skill);路徑 `%TEMP%\handoff-XXXXXX.md` | 暫停實作前 / 跨 session 接手 |
| **write-a-skill** | `/write-a-skill` | Meta tool:草擬 SKILL.md(<100 行)+ 可選 REFERENCE.md / EXAMPLES.md / scripts/。重點是 `description` 須含「Use when [明確觸發]」 | 想把踩過的坑寫成強制流程 |
| **improve-codebase-architecture** | `/improve-codebase-architecture` | 掃 codebase 找架構改善機會:重複 code、職責不清、單檔過肥、抽象缺失。用深淺模組 / seam / leverage / locality 詞彙 | 階段交界、新功能前、感覺「越來越難改」時 |
| **grill-with-docs** | `/grill-with-docs` 或「先對齊一下文件」 | 用既有 `docs/` 拷問計畫:跟 domain model 對不對、有無違反既定設計、漏讀哪份相關文件、要不要先更新文件再動工 | 任何新階段 / 新功能規劃前 |

> 每個 skill 的完整使用方式 + P6 對應痛點見 §二「各 skill 使用方式」。
> P6 本 session 已實際用過:`/setup-matt-pocock-skills`、`/improve-codebase-architecture`、`/grill-with-docs`。

---

## 一、為什麼裝這 6 個

對應你個人開發 + AI 協助 + 重度文件驅動的 P6 工作流的具體痛點:

| 痛點 | 對應 skill |
|---|---|
| 動工漏讀對應設計文件 | grill-with-docs |
| 對話跨 session 重新講進度浪費 | handoff |
| 對話太長 token 預算吃緊 | caveman |
| 把每次踩過的坑變強制流程 | write-a-skill(寫 P6 專屬) |
| 不確定哪裡該重構、害怕腐化 | improve-codebase-architecture |
| 設定 / 配置 | setup-matt-pocock-skills(必跑一次) |

---

## 二、各 skill 使用方式

### 🔧 setup-matt-pocock-skills

**用一次就好**,初次設定其他 skill 用到的偏好。

- **觸發**:`/setup-matt-pocock-skills`
- **會問**:issue tracker(GitHub / Linear / 本地檔案)、triage 標籤、文件儲存位置
- **P6 建議答**:
  - issue tracker → **本地檔案**(P6 沒接 GitHub Issues / Linear)
  - 文件位置 → `docs/`
- **何時跑**:**裝完第一件事**

---

### 🦴 caveman ── token 壓縮模式

**觸發**:你說 `caveman mode` / `talk like caveman` / `use caveman` / `less tokens` / `be brief` / `/caveman`

**啟動後** ── 持續整個 session,不會自己漂回正常,只有你說 `stop caveman` / `normal mode` 才關。

**壓縮規則**:砍冠詞、贅字、客套、含糊;允許句子片段;短同義詞;縮寫(DB/auth/config);因果用 `->`;**技術詞 / code block / 錯誤訊息原樣保留**

**例外**(自動恢復正常):危險操作警告、不可逆動作確認、多步驟順序、你說「再說一次」 ── 解釋完恢復 caveman。

**對比**:
- 正常:「Sure! I'd be happy to help. The issue is likely caused by...」
- caveman:「Bug in auth middleware. Token check use `<` not `<=`. Fix:」

**何時開**:長段討論完、進入機械式實作階段時開最划算(實作的指令不需要客套)。

---

### 📋 handoff ── 跨 session 交接

**觸發**:`/handoff` 或你說「準備交接」「下個 session 接著」之類

**會做**:
1. `mktemp -t handoff-XXXXXX.md` 生成臨時檔
2. 寫入摘要:目前狀態、引用既有產物(計畫 / commit / diff)用**路徑或 URL** 不複製內容、建議下次該用哪些 skill
3. 若你給 `/handoff 下次要做 S3` 之類,會聚焦在那個目標

**P6 使用情境**:
- 暫停實作前(像今天的 M5-S2 收尾)
- 下次 session 開頭把交接檔餵給新對話,新 Claude 就能直接接

**輸出位置**:Windows 上 `mktemp` 通常落在 `%TEMP%\` 或類似。生成後路徑會印出來,記得存到 P6 專案某處或記憶。

---

### 🪛 write-a-skill ── 寫自己的 skill

**觸發**:`/write-a-skill`

**流程**:
1. **問你需求**:這 skill 做什麼?用在什麼情境?需要可執行腳本還是純指令?
2. **草擬** SKILL.md(< 100 行)+ 可選 REFERENCE.md / EXAMPLES.md / scripts/
3. **跟你 review**:涵蓋完整嗎?

**skill 檔案結構**:
```
~/.claude/skills/skill-name/
├── SKILL.md           # 主指令(必有,< 100 行)
├── REFERENCE.md       # 細節(可選)
├── EXAMPLES.md        # 範例(可選)
└── scripts/           # 工具腳本(可選)
```

**SKILL.md 模板**:
```markdown
---
name: skill-name
description: 一句話說功能。Use when [明確觸發條件].
---

# Skill Name

## Quick start
[最小可動例子]

## Workflows
[步驟 / checklist]

## Advanced features
[連到 REFERENCE.md]
```

**最關鍵的事**:`description` 是 Claude 用來判斷「該不該載這 skill」的依據。
- ≤ 1024 字元
- 第三人稱
- **第二句必為「Use when [明確觸發]」**(關鍵字 / 檔名模式 / 情境)
- 模糊描述如「Helps with documents」會讓 Claude 不知何時用,等於沒裝

**P6 用法**:寫專屬 skill 把每次踩到的坑變強制流程(見第四節)。

---

### 🏗️ improve-codebase-architecture ── 架構審查

**觸發**:`/improve-codebase-architecture`

**會做**:掃 codebase 找架構改善機會 ── 重複 code、職責不清、單檔過肥、抽象缺失之類。

**P6 預期會點到的東西**:
- `CARD_PATHS` / `ENEMY_TEMPLATE_PATHS` / `ENEMY_INSTANCE_PATHS` 在 m1 / m2 / journal 重複 3 次 → 建議抽 `ResourceLibrary` autoload
- `_make_supply_chip` 在 m2_campaign 跟 adventure_journal 各一份 → 抽 widget 或 UiPalette 靜態
- `m2_campaign.gd` ~700 行接近 god file → 抽 `battle_view.gd`
- `_group_pool_cards` / `_count_in_strike` 等小 helper 散落多處
- 沒自動測試(battle_engine / resolution 等純邏輯易測)

**何時跑**:
- 階段交界(剛做完 M5-S2 是好時機)
- 新功能前(防止再蓋一層腐化)
- 感覺「越來越難改」時

---

### 📚 grill-with-docs ── 動工前對齊面談

**觸發**:`/grill-with-docs` 或你說「先對齊一下文件再做」「先 grill 這個計畫」

**會做**:用既有 `docs/` 拷問你(我)的計畫 ── 跟 domain model 對不對、有沒有違反既定設計、漏掉哪份相關文件、要不要先更新文件再動工。

**P6 對應痛點**:我這幾次漏讀 `第一期 UI 線框圖.md`、`戰鬥紀錄系統設計.md`、`整備補給「固定 vs 玩家選擇」設計` 都是同類問題 ── 動工前讓 grill 拷問一遍能少踩坑。

**何時跑**:任何新階段 / 新功能規劃前。S3 開工前可以先跑一次。

---

## 三、接下來要做的動作(按順序)

### 1. 重啟 Claude Code(必做)

**這個對話 session 看不到新 skill** ── skill 是啟動時掃描的。**關掉重開 Claude Code**(或開新對話)才會看到 6 個新的 `/<name>` 指令。

### 2. `/setup-matt-pocock-skills`(裝完第一件)

問你 issue tracker / 文件位置等偏好。P6 建議:
- issue tracker:**本地檔案**
- 文件位置:`docs/`

### 3. `/improve-codebase-architecture`(順手測試 + 看建議)

把工具跟現況碰一下,看它對 P6 的審查跟我先前猜的差多少:

> 我猜會被點到:`CARD_PATHS` 三重複、`_make_supply_chip` 重複、m2_campaign 過肥、無自動測試。

看建議合理 → 動小重構;不合 → 知道工具不適合這類專案。

### 4. `/write-a-skill` 寫第一個 P6 專屬 skill

最高槓桿。建議從 **`/p6-docs-first`** 開始 ── 強制動 m2 / journal / hub / battle 邏輯前讀對應 doc。草稿(可以直接餵給 write-a-skill 用):

```markdown
---
name: p6-docs-first
description: Forces reading the relevant P6 design doc before modifying core game
  files in the Godot project. Use when user asks to modify scripts/ui/m2_campaign.gd,
  scripts/ui/adventure_journal.gd, scripts/ui/hub.gd, scripts/logic/* battle files,
  or when starting any new P6 feature. Also use when the user mentions "P6 動工" or
  references docs/.
---

# P6 動工前讀文件

對應檔案 → 必讀的設計文件:

| 要動的檔 / 範疇 | 動工前讀 |
|---|---|
| m2_campaign.gd / 戰鬥流邏輯 | docs/C__Implementation_benchmarks/遊戲核心系統機制.md, docs/C__Implementation_benchmarks/開發里程碑.md M2 |
| adventure_journal | docs/C__Implementation_benchmarks/戰鬥紀錄系統設計.md |
| hub | docs/B__Design_specifications/UI 設計指引.md §3.11, §3.12 |
| 整備節點 / supply | docs/C__Implementation_benchmarks/程式規格書.md §3.14 |
| 卡牌 | docs/B__Design_specifications/卡牌設計原則.md |
| 敵人 | docs/B__Design_specifications/敵人設計原則.md |
| 戰鬥介面版型 | docs/C__Implementation_benchmarks/第一期 UI 線框圖.md |

不確定哪份適用 → 先讀 docs/A__Index_and_meta/文件目錄.md。

完成代碼變更後,headless 自檢:
F:\CCTEST\TOOL\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64_console.exe --headless --quit-after 5 "scenes/X.tscn"
若有新增 class_name,先 --headless --import 重建類別快取。
```

### 5. (選)再寫一個 `/p6-godot-verify`

把「headless 自檢 + --import 時機」這條 SOP 變強制流程,避免我下次又忘。

### 6. 回到 P6 開發

- F6 實跑驗證 M5-S2(暫停前未做)
- 或接 M5-S3 紀念品系統化
- 或先動 improve-codebase-architecture 建議的重構

---

## 四、推薦寫的 P6 專屬 skill(優先序)

| skill 名 | 解決的痛點 | 優先 |
|---|---|---|
| `/p6-docs-first` | 我漏讀對應 doc 就動工 | 🔴 高 |
| `/p6-godot-verify` | 我忘 headless 自檢、或新 class_name 沒 --import | 🔴 高 |
| `/p6-colorblock-pass` | 提到色塊 pass 自動套用三區塊 / UiPalette / widget 複用慣例 | 🟡 中 |
| `/p6-resource-library` | 想加新卡 / 新敵人時,自動知道要在 ResourceLibrary 註冊 | 🟢 低(S3 完才需要) |
| `/p6-docs-index-sync` | 新增 / 修改 docs 後自動更新 文件目錄.md | 🟢 低 |

---

## 五、工具管理(npm CLI)

```bash
# 列出已裝
npx skills@latest list -g

# 加新的(從同一個 repo 加更多)
npx skills@latest add mattpocock/skills -g -a claude-code -s <skill1> <skill2> -y

# 加別人的 skill 包
npx skills@latest add <owner>/<repo> -g -a claude-code --skill <skill> -y

# 移除
npx skills@latest remove -g -a claude-code -s <skill1> <skill2> -y

# 更新
npx skills@latest update -g -y
```

---

## 六、注意事項

1. **skill 是 session-load**:裝完 / 改完一定要**重開 Claude Code session** 才生效
2. **`description` 是觸發的關鍵**:寫專屬 skill 時 description 要明確、含具體觸發詞,模糊描述等於沒裝
3. **安全評估**(裝時 socket.dev 給的):
   - caveman / grill-with-docs / improve-codebase-architecture / write-a-skill = Low Risk
   - setup-matt-pocock-skills = Med Risk(改設定)
   - handoff = High Risk(因為 file system 存取 + mktemp);**內容掃過是 Safe**,只是能力風險評估較高
4. **skill 是社群擴充**,Anthropic 沒背書;Matt 可能會迭代 API
5. **裝了不滿意可以 remove**,風險低
