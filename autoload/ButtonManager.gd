extends Node


@export var buttons: Array[ButtonData] = [
	preload("res://data/buttons/vending_machine_button.tres"),
	preload("res://data/buttons/trashbin_button.tres"),
	preload("res://data/buttons/vending_machine_soldier_button.tres")
]
var _unlock_states: Dictionary = {}


signal button_purchased(button_data: ButtonData)
signal button_unlock_changed(button_data: ButtonData)
signal button_state_changed(button_data: ButtonData)


func _ready() -> void:
	EconomyManager.money_changed.connect(_on_money_changed)
	_apply_purchased_effects()
	update_button_states()


func _on_money_changed(_new_money: float) -> void:
	update_button_states()


# ============================================================
# BUTTON SEARCH
# ============================================================

func get_button(button_id: String) -> ButtonData:

	for button_data in buttons:

		if button_data == null:
			continue

		if button_data.id == button_id:
			return button_data

	return null


# ============================================================
# UNLOCK
# ============================================================

func is_unlocked(button_data: ButtonData) -> bool:

	if button_data == null:
		return false


	# 조건이 없다면 항상 해금
	if button_data.unlock_condition == null:
		return true


	var condition := button_data.unlock_condition


	match condition.type:

		UnlockCondition.Type.MONEY:
			return EconomyManager.money >= condition.amount


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

		push_warning(
			"ButtonManager: Required button not found: "
			+ condition.value
		)

		return false

	return required_button.bought

# ============================================================
# PURCHASE
# ============================================================

func can_purchase(
	button_data: ButtonData
) -> bool:

	if button_data == null:
		return false


	# 이미 구매함
	if button_data.bought:
		return false


	# 아직 해금되지 않음
	if not is_unlocked(button_data):
		return false


	# 돈 부족
	if not EconomyManager.can_afford(button_data.price):
		return false


	return true


func purchase(
	button_data: ButtonData
) -> bool:

	if not can_purchase(button_data):
		return false


	# 돈 지불
	if button_data.price < 0.0:
		return false
	if button_data.price > 0.0 and not EconomyManager.spend_money(button_data.price):
		return false


	# 구매 처리
	button_data.bought = true
	_apply_effect(button_data)


	# 구매 이벤트
	button_purchased.emit(button_data)


	# 다른 버튼의 해금 상태 확인
	update_button_states()


	return true


func _apply_effect(button_data: ButtonData) -> void:
	if not is_finite(button_data.effect_value) or button_data.effect_value <= 0.0:
		push_warning("ButtonManager: Effect value must be finite and positive: " + button_data.id)
		return
	match button_data.effect_type:
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
			push_warning("ButtonManager: Unsupported effect type on button: " + button_data.id)


func reset_for_prestige() -> void:
	for button_data in buttons:
		if button_data == null:
			continue
		button_data.bought = button_data.permanent_bought
	EconomyManager.set_global_time_multiplier(1.0)
	IncomeManager.reset_runtime_state()
	_apply_purchased_effects()
	update_button_states()


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

		push_warning(
			"ButtonManager: Button not found: "
			+ button_id
		)

		return false


	return purchase(button_data)


# ============================================================
# UPDATE BUTTON STATES
# ============================================================

func update_button_states() -> void:
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
		if unlocked != previously_unlocked:
			button_state_changed.emit(button_data)
			
