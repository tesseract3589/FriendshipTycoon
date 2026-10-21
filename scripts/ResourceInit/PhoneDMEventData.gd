@tool
class_name PhoneDMEventData
extends GameEventData

@export var dialogues: Array[PhoneDMDialogueData] = []
## The first offer snapshots this many seconds of current total income.
@export_range(1.0, 3600.0, 1.0) var initial_offer_income_seconds: float = 60.0
## Allows an unlocked DM to occur immediately after prestige, even at zero income.
@export_range(1.0, 1000000000000.0, 1.0, "or_greater") var minimum_offer_amount: float = 10000.0
@export var breakdown_chances: PackedFloat32Array = PackedFloat32Array([0.1, 0.3, 0.5])
@export var offer_increase_range: Vector2 = Vector2(0.2, 0.5)
@export var final_offer_increase_range: Vector2 = Vector2(0.5, 1.0)
@export_range(0.2, 5.0, 0.05) var message_interval_seconds: float = 0.85
@export_range(1.0, 10.0, 0.1) var result_display_seconds: float = 2.5
