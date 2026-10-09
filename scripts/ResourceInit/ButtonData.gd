@tool
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

@export var id: String = ""
@export var button_name: String = "":
	set(value):
		button_name = value
		emit_changed()
@export var price: float = 0.0:
	set(value):
		price = value
		emit_changed()

@export_category("Purchase Description")
## 구매 버튼에 표시할 설명. 비워 두면 효과에 따른 설명을 자동으로 표시합니다.
@export_multiline var description: String = "":
	set(value):
		description = value
		emit_changed()

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
@export var show_purchased_tooltip: bool = true
@export var click_dialogues: PackedStringArray = PackedStringArray()

# 버튼 구매시 효과
@export_category("Effect")
@export var effect_type: EffectType = EffectType.GLOBAL_MULTIPLIER:
	set(value):
		effect_type = value
		emit_changed()
@export var effect_target: String = "":
	set(value):
		effect_target = value
		emit_changed()
@export var effect_value: float = 1.0:
	set(value):
		effect_value = value
		emit_changed()


func get_effect_description(source_name_override: String = "") -> String:
	if effect_type == EffectType.NONE:
		return description

	var value_text := NUMBER_FORMATTER.format_number(effect_value)
	match effect_type:
		EffectType.SOURCE_MULTIPLIER:
			var source_name := _get_effect_source_name(source_name_override)
			return "%s 수입 x %s" % [source_name, value_text]
		EffectType.SOURCE_SPEED_MULTIPLIER:
			var speed_source_name := _get_effect_source_name(source_name_override)
			return "%s 속도 x %s" % [speed_source_name, value_text]
		EffectType.GLOBAL_TIME_MULTIPLIER:
			return "전체 속도 x %s" % value_text
		EffectType.GLOBAL_MULTIPLIER:
			return "전체 수입 x %s" % value_text
		EffectType.ACTIVATE_SOURCE:
			return "수입원"
	return description


func _get_effect_source_name(source_name_override: String) -> String:
	if not source_name_override.is_empty():
		return source_name_override
	# Autoload instances do not run inside the scene editor.
	if Engine.is_editor_hint():
		return effect_target
	var source := IncomeManager.get_source(effect_target)
	return source.source_name if source != null else effect_target


func get_purchase_description(source_name_override: String = "") -> String:
	if not description.is_empty():
		return description
	return get_effect_description(source_name_override)


func get_purchase_label_text(source_name_override: String = "") -> String:
	return "%s\n%s\n가격: %s" % [
		button_name,
		get_purchase_description(source_name_override),
		"무료" if is_zero_approx(price) else NUMBER_FORMATTER.format_number(price)
	]


func get_purchased_tooltip_text() -> String:
	if not tooltip_text.is_empty():
		return tooltip_text
	if effect_type == EffectType.NONE:
		return ""
	return get_effect_description()
