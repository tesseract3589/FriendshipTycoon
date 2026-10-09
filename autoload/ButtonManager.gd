extends Node


@export var buttons: Array[ButtonData] = [
	preload("res://data/buttons/vending_machine/vending_machine_button.tres"),
	preload("res://data/buttons/vending_machine/trashbin_button.tres"),
	preload("res://data/buttons/vending_machine/vending_machine_soldier_button.tres"),
	preload("res://data/buttons/vending_machine/promo_sign_button.tres"),
	preload("res://data/buttons/vending_machine/bike_delivery_button.tres"),
	preload("res://data/buttons/vending_machine/wireless_antenna_button.tres"),
	preload("res://data/buttons/restaurant/hall_foundation_button.tres"),
	preload("res://data/buttons/restaurant/first_floor_wall_button.tres"),
	preload("res://data/buttons/restaurant/restaurant_button.tres"),
	preload("res://data/buttons/restaurant/cook_soldier_button.tres"),
	preload("res://data/buttons/restaurant/serving_desk_button.tres"),
	preload("res://data/buttons/restaurant/dining_seats_button.tres"),
	preload("res://data/buttons/restaurant/wide_windows_button.tres"),
	preload("res://data/buttons/restaurant/first_floor_ceiling_button.tres"),
	preload("res://data/buttons/restaurant/front_door_button.tres")
]
var _unlock_states: Dictionary = {}
var _purchases_in_progress: Dictionary = {}
var _invalid_world_buttons: Dictionary = {}


signal button_purchased(button_data: ButtonData)
signal button_unlock_changed(button_data: ButtonData)
signal button_state_changed(button_data: ButtonData)


func _ready() -> void:
	EconomyManager.money_changed.connect(_on_money_changed)
	PrestigeManager.prestige_changed.connect(update_button_states)
	ErrorManager.validate_buttons(buttons, IncomeManager.sources)
	_apply_purchased_effects()
	update_button_states()


func _on_money_changed(_new_money: float) -> void:
	update_button_states()


# ============================================================
# BUTTON SEARCH
# ============================================================

func get_button(button_id: String) -> ButtonData:
	return ErrorManager.find_resource(buttons, button_id, "ButtonData") as ButtonData


# ============================================================
# UNLOCK
# ============================================================

func is_unlocked(button_data: ButtonData) -> bool:

	if button_data == null:
		ErrorManager.report_error("INVALID_RESOURCE", "해금할 버튼 리소스가 비어 있습니다.", "ButtonManager.is_unlocked")
		return false
	if get_button(button_data.id) != button_data or not ErrorManager.validate_button_dependency(button_data, buttons):
		return false


	# 조건이 없다면 항상 해금
	if button_data.unlock_condition == null:
		return true


	var condition := button_data.unlock_condition


	match condition.type:

		UnlockCondition.Type.MONEY:
			return EconomyManager.money >= condition.amount
		UnlockCondition.Type.TOTAL_JJAM:
			if PrestigeManager.total_jjam < 0:
				PrestigeManager.get_total_jjam()
				return false
			return PrestigeManager.get_total_jjam() >= int(condition.amount)


		UnlockCondition.Type.BUTTON:
			return _check_button_condition(condition)


	return false


# ============================================================
# BUTTON CONDITION
# ============================================================

func _check_button_condition(
	condition: UnlockCondition
) -> bool:

	var required_button := get_button(condition.value)

	if required_button == null:
		return false

	return required_button.bought

# ============================================================
# PURCHASE
# ============================================================

func can_purchase(
	button_data: ButtonData
) -> bool:

	if not ErrorManager.validate_button(button_data, buttons, IncomeManager.sources):
		return false


	# 이미 구매함
	if button_data.bought:
		return false
	if _invalid_world_buttons.has(button_data.id):
		return false
	if _purchases_in_progress.has(button_data.get_instance_id()) or not _is_effect_valid(button_data):
		return false


	# 아직 해금되지 않음
	if not is_unlocked(button_data):
		return false


	# 돈 부족
	if not EconomyManager.can_afford(button_data.price):
		return false


	return true


func set_world_invalid_buttons(ids: Array[String]) -> void:
	_invalid_world_buttons.clear()
	for id in ids:
		_invalid_world_buttons[id] = true
	update_button_states(true)


func purchase(
	button_data: ButtonData
) -> bool:

	if not can_purchase(button_data):
		return false


	# Spending emits money_changed synchronously, so guard against reentrant purchases.
	_purchases_in_progress[button_data.get_instance_id()] = true
	if button_data.price > 0.0 and not EconomyManager.spend_money(button_data.price):
		_purchases_in_progress.erase(button_data.get_instance_id())
		return false


	# 구매 처리
	button_data.bought = true
	_apply_effect(button_data)
	_purchases_in_progress.erase(button_data.get_instance_id())


	# 구매 이벤트
	button_purchased.emit(button_data)


	# 다른 버튼의 해금 상태 확인
	update_button_states()


	return true


func _is_effect_valid(button_data: ButtonData) -> bool:
	if button_data.effect_type == ButtonData.EffectType.NONE:
		return true
	if not is_finite(button_data.effect_value) or button_data.effect_value <= 0.0:
		ErrorManager.validate_number(button_data.effect_value, "ButtonData:" + button_data.id + ".effect_value", false)
		return false
	var context := "ButtonData:" + button_data.id + ".effect_result"
	match button_data.effect_type:
		ButtonData.EffectType.ACTIVATE_SOURCE:
			if not IncomeManager.source_active.has(button_data.effect_target):
				ErrorManager.report_error("MISSING_SOURCE_STATE", "수입원 실행 상태를 찾을 수 없습니다.", context)
				return false
			return true
		ButtonData.EffectType.SOURCE_MULTIPLIER:
			return IncomeManager.source_multipliers.has(button_data.effect_target) and _is_valid_multiplier_product(
				IncomeManager.get_source_multiplier(button_data.effect_target), button_data.effect_value, context
			)
		ButtonData.EffectType.SOURCE_SPEED_MULTIPLIER:
			return IncomeManager.source_speed_multipliers.has(button_data.effect_target) and _is_valid_multiplier_product(
				IncomeManager.source_speed_multipliers.get(button_data.effect_target, 1.0), button_data.effect_value, context
			) and ErrorManager.validate_number(IncomeManager.get_source_production_time(button_data.effect_target) / button_data.effect_value, context + ".production_time", false)
		ButtonData.EffectType.GLOBAL_MULTIPLIER:
			return _is_valid_multiplier_product(EconomyManager.get_global_multiplier(), button_data.effect_value, context)
		ButtonData.EffectType.GLOBAL_TIME_MULTIPLIER:
			if not _is_valid_multiplier_product(EconomyManager.get_global_time_multiplier(), button_data.effect_value, context):
				return false
			for source in IncomeManager.sources:
				if source != null and not ErrorManager.validate_number(IncomeManager.get_source_production_time(source.id) / button_data.effect_value, context + ":" + source.id, false):
					return false
			return true
	ErrorManager.report_error("INVALID_EFFECT_TYPE", "지원하지 않는 구매 효과입니다.", "ButtonData:" + button_data.id)
	return false


func _is_valid_multiplier_product(current_value: float, factor: float, context: String) -> bool:
	var updated_value := current_value * factor
	return ErrorManager.validate_number(updated_value, context, false)


func _apply_effect(button_data: ButtonData) -> void:
	if not _is_effect_valid(button_data):
		return
	match button_data.effect_type:
		ButtonData.EffectType.NONE:
			return
		ButtonData.EffectType.ACTIVATE_SOURCE:
			IncomeManager.activate_source(button_data.effect_target)
		ButtonData.EffectType.SOURCE_MULTIPLIER:
			IncomeManager.multiply_source_multiplier(button_data.effect_target, button_data.effect_value)
		ButtonData.EffectType.GLOBAL_MULTIPLIER:
			EconomyManager.multiply_global_multiplier(button_data.effect_value)
		ButtonData.EffectType.SOURCE_SPEED_MULTIPLIER:
			IncomeManager.multiply_source_speed_multiplier(button_data.effect_target, button_data.effect_value)
		ButtonData.EffectType.GLOBAL_TIME_MULTIPLIER:
			EconomyManager.multiply_global_time_multiplier(button_data.effect_value)
		_:
			ErrorManager.report_error("INVALID_EFFECT_TYPE", "지원하지 않는 구매 효과입니다.", "ButtonData:" + button_data.id)


func reset_for_prestige() -> void:
	ErrorManager.validate_buttons(buttons, IncomeManager.sources)
	for button_data in buttons:
		if button_data == null:
			continue
		button_data.bought = button_data.permanent_bought
	EconomyManager.set_global_time_multiplier(1.0)
	IncomeManager.reset_runtime_state()
	_apply_purchased_effects()
	# Bought -> locked also changes visuals, even when the unlock flag stays false.
	update_button_states(true)


func _apply_purchased_effects() -> void:
	for button_data in buttons:
		if button_data != null and button_data.bought:
			_apply_effect(button_data)


# ============================================================
# PURCHASE BY ID
# ============================================================

func purchase_by_id(
	button_id: String
) -> bool:

	var button_data := get_button(button_id)

	if button_data == null:
		return false


	return purchase(button_data)


# ============================================================
# UPDATE BUTTON STATES
# ============================================================

func update_button_states(force_notify: bool = false) -> void:
	for button_data in buttons:
		if button_data == null:
			continue
		var unlocked := not button_data.bought and is_unlocked(button_data)
		var previously_unlocked: bool = _unlock_states.get(button_data.id, false)
		_unlock_states[button_data.id] = unlocked
		if unlocked and not previously_unlocked:
			button_unlock_changed.emit(
				button_data
			)
		if force_notify or unlocked != previously_unlocked:
			button_state_changed.emit(button_data)
			
