class_name UnlockCondition
extends Resource

enum Type {
	MONEY,
	UPGRADE,
	BUTTON
}

@export var type: Type
@export var value: String = ""
@export var amount: float = 0.0
