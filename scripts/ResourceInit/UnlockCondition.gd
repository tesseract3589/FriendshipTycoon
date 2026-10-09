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
