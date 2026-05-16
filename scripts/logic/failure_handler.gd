class_name FailureHandler
extends RefCounted

## 失敗代價處理。對應 程式規格書.md §3.4 + 遊戲核心系統機制.md §5。
## 序章前半失敗類型摘要(2026-05-16 起):
##   - 灰兔 default (gray_rabbit + on_fail/spawn_clone): default 逃走 + clone 插入緊接後位置
##                                                        (chain_1 用此取代教學重來)
##   - 灰兔 clone (gray_rabbit + 空 special_effect): 單獨逃走,連戰繼續(走 FOX_FLEE outcome)
##   - 兔子 (rabbit): 連鎖逃跑(現役連戰已不再使用;若 tutorial_retry 開啟則改為觸發重來)
##   - 狐狸 (fox): 單獨逃跑 → 僅該狐狸移出,連戰繼續
##   - 狼型 (wolf): 菁英化 → 排到連戰末段(包含異變的巨狼)
##   - 精英狀態失敗: GAME OVER
##   - 豹型 / 熊型: GAME OVER(序章前半不會出現)

## 結果類型:
enum FailureOutcome {
	TUTORIAL_RETRY,             ## 教學重來:回滾並重新開始連戰(舊機制,2026-05-16 後 chain_1 已停用;TODO 灰兔機制跑順後評估清除)
	RABBIT_CHAIN_FLEE,          ## 兔子連鎖逃跑:所有兔子移出連戰,非兔子敵人留下,連戰繼續
	FOX_FLEE,                   ## 狐狸 / clone 等單獨逃跑:僅該敵人移出,連戰繼續
	WOLF_ELITE_PROMOTION,       ## 狼/巨狼菁英化:排到連戰末段
	GRAY_RABBIT_CLONE_SPAWN,    ## 灰兔失敗 default:default 逃走 + clone 插入緊接後位置(2026-05-16)
	GAME_OVER,                  ## 戰役失敗
}


## 判定失敗處理方式。
## 回傳:{ "outcome": FailureOutcome, "narrative": String, ... }
static func resolve_failure(
	enemy_template: EnemyTemplate,
	enemy_instance: EnemyInstance,
	is_elite_already: bool,
	tutorial_retry_enabled: bool,
) -> Dictionary:
	## 精英狀態 → GAME OVER
	if is_elite_already:
		return {
			"outcome": FailureOutcome.GAME_OVER,
			"narrative": "%s 菁英狀態下失敗 — 戰役結束。" % enemy_instance.display_name,
		}
	## 依敵人類別處理
	match enemy_template.enemy_class:
		"rabbit":
			if enemy_template.id == "fox":
				## 狐狸:單獨逃跑,無連鎖
				return {
					"outcome": FailureOutcome.FOX_FLEE,
					"narrative": "狐狸消失於草叢深處。連戰繼續。",
				}
			## 真正的兔子:連鎖逃跑(只影響兔子,非兔子敵人留下)
			if tutorial_retry_enabled:
				return {
					"outcome": FailureOutcome.TUTORIAL_RETRY,
					"narrative": "兔子驚惶逃竄,其他兔子也跟著跑了。父親:「回去歇口氣再來。」",
				}
			return {
				"outcome": FailureOutcome.RABBIT_CHAIN_FLEE,
				"narrative": "兔子驚惶逃竄,連戰中其他兔子也跟著跑了。",
			}
		"gray_rabbit":
			## 灰兔:讀 instance.special_effect 決定處置(2026-05-16,ADR 未獨立記)
			var fail_spec: Dictionary = enemy_instance.special_effect.get("on_fail", {})
			if fail_spec.get("action", "") == "spawn_clone":
				## default 灰兔:default 逃走 + clone 插入緊接後
				return {
					"outcome": FailureOutcome.GRAY_RABBIT_CLONE_SPAWN,
					"narrative": "灰兔甩開射程跳開 — 但留下一個跟著它跑的身影,下一步就到你眼前。",
					"clone_instance_id": fail_spec.get("clone_instance_id", ""),
				}
			## 無 spawn_clone 特性(例:clone 本身)→ 單獨逃走,連戰繼續
			return {
				"outcome": FailureOutcome.FOX_FLEE,
				"narrative": "灰兔複製體沒了氣力,消失於草叢深處。",
			}
		"wolf":
			return {
				"outcome": FailureOutcome.WOLF_ELITE_PROMOTION,
				"narrative": "%s 受傷退入暗處,等著回來找你。" % enemy_instance.display_name,
			}
		"leopard", "bear":
			return {
				"outcome": FailureOutcome.GAME_OVER,
				"narrative": "%s 是不可失敗的對手 — 戰役結束。" % enemy_instance.display_name,
			}
	return {
		"outcome": FailureOutcome.GAME_OVER,
		"narrative": "未定義的失敗代價 — 戰役結束。",
	}
