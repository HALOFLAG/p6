# Triage Labels

5 個 mattpocock skill 規範的 triage 角色,對應到 P6 本地 markdown 模式使用的中文字串。
在 issue 檔案頂部以 `Status: <字串>` 形式記錄,或寫成檔名前綴。

| Label in mattpocock/skills | P6 對應字串 | 意思 |
| --- | --- | --- |
| `needs-triage` | `待評估` | 使用者需要先評估這個 issue 要不要做 / 怎麼做 |
| `needs-info` | `待補資訊` | 等使用者補充細節才能繼續 |
| `ready-for-agent` | `agent-可接` | 規格完整,Claude 可直接 AFK 接手實作 |
| `ready-for-human` | `人類做` | 需要使用者親自實作(美術 / 主觀決策 / 外部工具) |
| `wontfix` | `不做` | 決定不做這個項目 |

當 skill 提及某角色(例:"apply the AFK-ready triage label"),套用右欄字串。
