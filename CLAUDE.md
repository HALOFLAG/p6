每當被要求上傳進度時，排除敏感內容，將進度上傳至https://github.com/HALOFLAG/p6.git
git config --local user.email "haloflag01@gmail.com"
git config --local user.name "haloflag01"
不可在我沒要求的情況下進行上傳。
不可上傳 ./old_game_plan 中的檔案，裡面是舊遊戲資料。
如果有資訊不足的地方，需要我說明的，或是更好的方法，請先詢問我。

需要查找文件內容時，優先從 ./docs/文件目錄.md 開始找起。
- [Godot CLI 路徑](reference_godot_cli.md) — F:\CCTEST\TOOL 下的 Godot 4.6.2 mono;headless 自檢指令

## Agent skills

### Issue tracker

本地 markdown:issue / PRD 寫成 `.scratch/<feature>/` 下的 md 檔,不外推 GitHub Issues。詳見 `docs/agents/issue-tracker.md`。

### Triage labels

5 個中文狀態:待評估 / 待補資訊 / agent-可接 / 人類做 / 不做。詳見 `docs/agents/triage-labels.md`。

### Domain docs

Single-context:領域語言在根目錄 `CONTEXT.md`,設計細節在 `docs/`(以 `docs/文件目錄.md` 為入口),架構決策在 `docs/adr/`。詳見 `docs/agents/domain.md`。