class_name CampaignDefinition
extends Resource

## 整個戰役的配置。對應 程式規格書.md §3.5。
## 序章前半 = 5 連戰 + 4 整備補給。

@export var id: String = ""  ## "prologue_first_half"
@export var campaign_name: String = ""
@export var is_prologue: bool = true
@export var starting_deck: Dictionary = {}  ## { card_id: count }
@export var chain_ids: Array[String] = []  ## 連戰 id 序列(透過 ResourceLibrary.chain(id) 取得)
@export var prologue_narrative: String = ""  ## 戰役開場
@export var ending_narrative: String = ""  ## 戰役末尾
