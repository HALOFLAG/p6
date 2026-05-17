class_name SouvenirInfo
extends RefCounted

## 紀念品定義表 — 跨場景共用(hub 視覺擺設 + adventure_journal 結局頁解鎖列表)。
## 2026-05-17 抽出(原本 hardcoded 在 hub.gd)。
## 對應 ADR-0004:結局敘事頁右下「獲得區」資料來源。
##
## 未來紀念品多時可改 .tres 化(每個紀念品一個 SouvenirDefinition.tres),
## 由 ResourceLibrary 統一管理;目前數量太少,const dict 即可。
##
## 欄位用途:
##   name        — 顯示名(hub + journal 共用)
##   description — 詳細描述(hub 點擊對話泡 + journal 結局頁清單)
##   pos / size  — hub 場景擺設位置(hub 專用,journal 不讀)
##   color       — hub 場景色塊色(hub 專用,journal 不讀)
const ALL := {
	"mutant_wolf_arm": {
		"name": "異變的巨狼斷臂",
		"description": "左臂呈現極深的黑色。森林深處的異變,終究跟著你回家了。",
		"pos": Vector2(980, 180),
		"size": Vector2(120, 100),
		"color": Color(0.30, 0.18, 0.18, 1),
	},
}
