class_name TutorialRetry
extends RefCounted

## 教學重來機制。對應 程式規格書.md §3.13 + 遊戲核心系統機制.md §17。
## 僅序章前半第一連戰啟用。失敗 → 卡組+狀態回滾 → 重來。

## 對話衰減分支判定。
static func get_dialogue_tier(retry_count: int) -> String:
	if retry_count <= 1:
		return "encouraging"  ## 鼓勵性 + 弱點對應提示
	elif retry_count <= 3:
		return "neutral"      ## 中性「再試一次」
	else:
		return "sarcastic"    ## 略諷刺,「兔子也算對手」


## 取得對話衰減提示文字(供 UI 顯示)。
static func get_dialogue_text(retry_count: int) -> String:
	match get_dialogue_tier(retry_count):
		"encouraging":
			return "父親:「兔子怕穿刺,記住這點。我們回去整理一下,再試一次。」"
		"neutral":
			return "父親:「再試一次。」"
		"sarcastic":
			return "父親嘆了口氣:「兔子也算對手?算了,還是試一次。」"
	return "再試一次。"
