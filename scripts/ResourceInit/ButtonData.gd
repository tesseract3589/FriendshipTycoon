class_name ButtonData
extends Resource

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")

enum EffectType {
	ACTIVATE_SOURCE,
	SOURCE_MULTIPLIER,
	GLOBAL_MULTIPLIER,
	SOURCE_SPEED_MULTIPLIER,
	GLOBAL_TIME_MULTIPLIER
}

@export var id: String = ""
@export var button_name: String = ""
@export var description: String = ""
@export var price: float = 0.0

@export_category("Purchased")
@export var bought: bool = false
@export var permanent_bought: bool = false

@export_category("Unlock")
@export var unlock_condition: UnlockCondition

@export_category("World Display")
@export var show_world_purchase_button: bool = false
@export var world_purchase_button_offset: Vector2 = Vector2(0.0, -68.0)
@export var world_purchase_info_offset: Vector2 = Vector2(-90.0, -144.0)
@export var world_purchase_button_scale: Vector2 = Vector2(0.13, 0.13)
@export var click_dialogues: PackedStringArray = PackedStringArray()

# 버튼 구매시 효과
@export_category("Effect")
@export var effect_type: EffectType = EffectType.GLOBAL_MULTIPLIER
@export var effect_target: String = ""
@export var effect_value: float = 1.0


func get_effect_description() -> String:
	var value_text := NUMBER_FORMATTER.format_number(effect_value)
	match effect_type:
		EffectType.SOURCE_MULTIPLIER:
			var source_name := effect_target
			var source_data := IncomeManager.get_source(effect_target)
			if source_data != null:
				source_name = source_data.source_name
			return "%s 수입 x %s" % [source_name, value_text]
		EffectType.SOURCE_SPEED_MULTIPLIER:
			var speed_source_name := effect_target
			var speed_source_data := IncomeManager.get_source(effect_target)
			if speed_source_data != null:
				speed_source_name = speed_source_data.source_name
			return "%s 속도 x %s" % [speed_source_name, value_text]
		EffectType.GLOBAL_TIME_MULTIPLIER:
			return "전체 생산 속도 x %s" % value_text
		EffectType.GLOBAL_MULTIPLIER:
			return "전체 수입 x %s" % value_text
		EffectType.ACTIVATE_SOURCE:
			var source := IncomeManager.get_source(effect_target)
			return "%s 활성화" % (source.source_name if source != null else effect_target)
	return description
