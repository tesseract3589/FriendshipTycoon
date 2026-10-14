class_name UnlockCondition
extends Resource

enum Type {
	MONEY = 0,
	TOTAL_JJAM = 1,
	BUTTON = 2
}

@export var type: Type
@export var value: String = ""
# MONEY: required money. TOTAL_JJAM: required lifetime jjam (whole points).
@export var amount: float = 0.0
## Optional MONEY threshold beyond float range, e.g. "1e500".
@export var large_amount: String = ""

func get_amount() -> Variant:
	return amount if large_amount.strip_edges().is_empty() else preload("res://scripts/BigNumber.gd").parse(large_amount)
