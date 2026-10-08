class_name ButtonData
extends Resource

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")

enum Type {
	INCOME_SOURCE,
	STRUCTURE,
	EFFECT_OBJECT
}

enum EffectType {
	ACTIVATE_SOURCE,
	SOURCE_MULTIPLIER,
	GLOBAL_MULTIPLIER,
	SOURCE_SPEED_MULTIPLIER,
	GLOBAL_TIME_MULTIPLIER,
	NONE
}

enum WorldVisualLayer {
	BACKGROUND = -1,
	OBJECT = 0,
	FRONT_OBJECT = 5,
	STRUCTURE = 10
}

@export var id: String = ""
@export var button_name: String = ""
@export var description: String = ""
@export var price: float = 0.0

@export_category("type")
@export var type: Type = Type.EFFECT_OBJECT

@export_category("Purchased")
@export var bought: bool = false
@export var permanent_bought: bool = false
@export_multiline var tooltip_text: String = ""

@export_category("Unlock")
@export var unlock_condition: UnlockCondition

@export_category("World Display")
@export var show_world_purchase_button: bool = false
@export var world_purchase_button_offset: Vector2 = Vector2(0.0, -100.0)
@export var world_purchase_info_offset: Vector2 = Vector2(-90.0, -190.0)
@export var world_purchase_button_scale: Vector2 = Vector2(0.13, 0.13)
@export var world_visual_layer: WorldVisualLayer = WorldVisualLayer.OBJECT
@export var show_purchased_tooltip: bool = true
@export var click_dialogues: PackedStringArray = PackedStringArray()

# 버튼 구매시 효과
@export_category("Effect")
@export var effect_type: EffectType = EffectType.GLOBAL_MULTIPLIER
@export var effect_target: String = ""
@export var effect_value: float = 1.0


func get_effect_description() -> String:
	if effect_type == EffectType.NONE:
		return description

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
			return "전체 속도 x %s" % value_text
		EffectType.GLOBAL_MULTIPLIER:
			return "전체 수입 x %s" % value_text
		EffectType.ACTIVATE_SOURCE:
			return "수입원"
	return description


func get_purchase_description() -> String:
	if not description.is_empty():
		return description
	return get_effect_description()


func get_purchased_tooltip_text() -> String:
	if not tooltip_text.is_empty():
		return tooltip_text
	if effect_type == EffectType.NONE:
		return ""
	return get_effect_description()
