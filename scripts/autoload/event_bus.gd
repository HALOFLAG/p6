extends Node

signal card_placed(card_id: String)
signal card_unplaced(card_id: String)
signal strike_committed
signal resolution_complete(result: Dictionary)
signal tutorial_retry_triggered(retry_count: int)
signal supply_applied(phase_id: String)


func emit_card_placed(card_id: String) -> void:
	call_deferred("emit_signal", "card_placed", card_id)


func emit_strike_committed() -> void:
	call_deferred("emit_signal", "strike_committed")


func emit_resolution_complete(result: Dictionary) -> void:
	call_deferred("emit_signal", "resolution_complete", result)
