class_name ChainDefinition
extends Resource

## 單一連戰的定義。對應 程式規格書.md §3.5。

@export var id: String = ""  ## "chain_1"
@export var display_label: String = ""  ## "連戰 1:獵兔教學"
@export var enemies: Array[String] = []  ## 敵人 instance_id 序列
@export var tutorial_retry: bool = false  ## 是否啟用教學重來(僅序章前半連戰 1 = true)
@export var post_chain_supply: String = ""  ## 對應的 SupplyPhase id(連戰結束後觸發)
@export var narrative_pre: String = ""  ## 連戰前敘事
@export var narrative_post: String = ""  ## 連戰後敘事
