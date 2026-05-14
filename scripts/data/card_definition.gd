class_name CardDefinition
extends Resource

## P6 卡牌靜態定義。對應 卡牌設計原則.md §7。
## 2026-05-14 改版:移除 use_limit / pool_size,改用卡組 count_remaining 表達。

@export var id: String = ""
@export var card_name: String = ""
@export var resource_class: String = "tool"  ## tool / burst / character
@export var function_class: String = "combat"  ## combat / intel / compound
@export var card_form: String = "pool"  ## pool / individual
@export var weakness_type: String = "none"  ## impact / pierce / burn / generic / none
@export var contribution: Dictionary = {}  ## { "pierce": 1 } 或 { "flexible": 2 } 或 {}
@export var strength_level: int = 1  ## 1 / 2 / 3 對應 ★ ★★ ★★★
@export var lock_class: String = "none"  ## none / optional / required
@export var special_effect: Dictionary = {}  ## optional 雙模式 / required 單模式;見 §8 action 列表
@export var description: String = ""
