# Issue tracker: 本地 markdown(P6)

P6 的 issue / PRD / 工作項目都以 markdown 檔形式寫在 `.scratch/` 下,**不**外推到 GitHub Issues、Linear、Jira 等遠端系統。
這個選擇符合 CLAUDE.md「不可在沒要求的情況下進行上傳」的原則。

## 慣例

- 一個功能一個資料夾:`.scratch/<feature-slug>/`(例:`.scratch/m5-s3-keepsakes/`)
- PRD:`.scratch/<feature-slug>/PRD.md`
- 實作 issue:`.scratch/<feature-slug>/issues/<NN>-<slug>.md`,從 `01` 開始編號
- Triage 狀態用檔案頂部的 `Status:` 行記錄(對應字串見 `triage-labels.md`)
- 留言 / 對話歷史 append 到檔案底部 `## Comments` 區塊

## 當 skill 說「publish 到 issue tracker」

在 `.scratch/<feature-slug>/` 下建新檔(資料夾不存在則建)。

## 當 skill 說「fetch 對應的 ticket」

讀指定路徑的檔案。一般情況下我(使用者)會直接給路徑或 issue 編號。

## 與 docs/ 的分工

- `docs/` = **長期設計文件**(主線設計 / 機制 / 規格);設計穩定後才寫進來
- `.scratch/` = **單一功能的短期工作記錄**(PRD / 子 issue / 進度追蹤);功能做完就可歸檔或刪掉

新增大型設計討論時優先進 `docs/`,而非 `.scratch/`。
