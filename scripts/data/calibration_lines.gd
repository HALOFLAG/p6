class_name CalibrationLines
extends Resource

## 戰後校準對話台詞庫。對應 遊戲核心系統機制.md §10 雙聲道架構。
## 結構:lines = { state_key: { "player": String, "npc": String } }
## M3 為佔位文字,後續補完整內容(每模板專屬長對話、核心儀式化短語等)。

@export var lines: Dictionary = {}


func get_line(state_key: String) -> Dictionary:
	return lines.get(state_key, { "player": "(佔位:玩家)", "npc": "(佔位:父親)" })
