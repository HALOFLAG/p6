class_name EnemyTemplate
extends Resource

## P6 敵人模板靜態定義。對應 敵人設計原則.md §2。

@export var id: String = ""
@export var template_name: String = ""
@export var enemy_class: String = "rabbit"  ## rabbit / wolf / leopard / bear
@export var weakness_range: Array[String] = []  ## ["pierce"] 或 ["impact","pierce"]
@export var combat_state_distribution: Dictionary = { "standard": 1.0 }
@export var design_contract: Dictionary = {}  ## { "teaches": "...", "veteran": "...", "novice": "..." }
@export var traits: Array = []  ## 後續期數預留(主動行為);第一期空陣列
