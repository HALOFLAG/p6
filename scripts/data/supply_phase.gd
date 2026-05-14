class_name SupplyPhase
extends Resource

## 整備階段的固定補給規格。對應 程式規格書.md §3.14。
## 序章前半:rest_1 = full_restore;supply_2/3/4 = add_cards。

@export var id: String = ""
@export var supply_type: String = "add_cards"  ## "full_restore" / "add_cards"
@export var cards_to_add: Dictionary = {}  ## { "tool_arrow_pierce": 2, "tool_stone_impact": 2 }
@export var narrative: String = ""  ## 簡短劇情敘述
