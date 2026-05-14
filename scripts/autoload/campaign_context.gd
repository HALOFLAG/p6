extends Node

var tutorial_retry_enabled: bool = false
var retry_count: int = 0
var deck_snapshot = null
var current_campaign_id: String = ""
var current_chain_id: String = ""


func reset() -> void:
	tutorial_retry_enabled = false
	retry_count = 0
	deck_snapshot = null
	current_campaign_id = ""
	current_chain_id = ""
