class_name ButtonData
extends Resource

enum EffectType {
	ACTIVATE_SOURCE,
	SOURCE_MULTIPLIER,
	GLOBAL_MULTIPLIER
}

@export var id: String = ""
@export var button_name: String = ""
@export var price: float = 0.0

@export_category("Purchased")
@export var bought: bool = false
@export var permanent_bought: bool = false

@export_category("Unlock")
@export var unlock_condition: UnlockCondition

# 버튼 구매시 효과
@export_category("Effect")
@export var effect_type: EffectType = EffectType.GLOBAL_MULTIPLIER
@export var effect_target: String = ""
@export var effect_value: float = 1.0
