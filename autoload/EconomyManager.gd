extends Node


signal money_changed(new_money: float)
signal multiplier_changed()
signal global_time_multiplier_changed(previous_value: float, new_value: float)


var money: float = 0.0

# 모든 Income Source에 적용
# 각 Income Source 별 multiplier는 따로 관리
var global_multiplier: float = 1.0
var global_time_multiplier: float = 1.0
# Developer overrides stay separate from purchases and prestige bonuses.
var developer_income_multiplier: float = 1.0
var developer_time_multiplier: float = 1.0


func reset_money() -> void:
	money = 0.0
	money_changed.emit(money)


func add_money(amount: float) -> bool:
	if not ErrorManager.validate_number(amount, "EconomyManager.add_money") or amount == 0.0:
		return false

	var rounded_amount := roundf(amount)
	if rounded_amount <= 0.0:
		ErrorManager.report_error("INVALID_AMOUNT", "원 단위로 반올림한 금액이 0입니다.", "EconomyManager.add_money")
		return false
	var updated_money := money + rounded_amount
	if not ErrorManager.validate_number(updated_money, "EconomyManager.money"):
		return false
	if updated_money == money:
		ErrorManager.report_error("PRECISION_LOSS", "자금이 너무 커서 수입을 정확히 더할 수 없습니다.", "EconomyManager.add_money")
		return false
	money = updated_money
	money_changed.emit(money)
	return true


func can_afford(amount: float) -> bool:
	return ErrorManager.validate_number(amount, "EconomyManager.price") and ErrorManager.validate_number(money, "EconomyManager.money") and money >= roundf(amount)


func spend_money(amount: float) -> bool:
	if not ErrorManager.validate_number(amount, "EconomyManager.spend_money", false):
		return false

	var rounded_amount := roundf(amount)
	if rounded_amount <= 0.0 or money < rounded_amount:
		return false

	var updated_money := money - rounded_amount
	if not ErrorManager.validate_number(updated_money, "EconomyManager.money"):
		return false
	if updated_money == money:
		ErrorManager.report_error("PRECISION_LOSS", "자금이 너무 커서 구매 금액을 정확히 차감할 수 없습니다. 결제를 중단합니다.", "EconomyManager.spend_money")
		return false
	money = updated_money
	money_changed.emit(money)

	return true


func get_global_multiplier() -> float:
	return global_multiplier * developer_income_multiplier


func multiply_global_multiplier(value: float) -> void:
	if not ErrorManager.validate_number(value, "EconomyManager.multiplier_factor", false):
		return
	set_global_multiplier(global_multiplier * value)


func set_global_multiplier(value: float) -> void:
	if not ErrorManager.validate_number(value, "EconomyManager.global_multiplier"):
		return
	if not ErrorManager.validate_number(value * developer_income_multiplier, "EconomyManager.effective_income_multiplier"):
		return
	global_multiplier = value
	multiplier_changed.emit()


func get_global_time_multiplier() -> float:
	return global_time_multiplier * developer_time_multiplier


func multiply_global_time_multiplier(value: float) -> void:
	if not ErrorManager.validate_number(value, "EconomyManager.time_multiplier_factor", false):
		return
	set_global_time_multiplier(global_time_multiplier * value)


func set_global_time_multiplier(value: float) -> void:
	if not ErrorManager.validate_number(value, "EconomyManager.global_time_multiplier", false):
		return
	var effective_value := value * developer_time_multiplier
	if not ErrorManager.validate_number(effective_value, "EconomyManager.effective_time_multiplier", false):
		return
	if global_time_multiplier == value:
		return
	var previous_value := get_global_time_multiplier()
	global_time_multiplier = value
	global_time_multiplier_changed.emit(previous_value, effective_value)


func get_developer_income_multiplier() -> float:
	return developer_income_multiplier


func get_developer_time_multiplier() -> float:
	return developer_time_multiplier


func set_developer_multipliers(time_value: float, income_value: float) -> bool:
	if not ErrorManager.validate_number(time_value, "EconomyManager.developer_time_multiplier", false):
		return false
	if not ErrorManager.validate_number(income_value, "EconomyManager.developer_income_multiplier"):
		return false
	var effective_time := global_time_multiplier * time_value
	if not ErrorManager.validate_number(effective_time, "EconomyManager.effective_time_multiplier", false):
		return false
	if not ErrorManager.validate_number(global_multiplier * income_value, "EconomyManager.effective_income_multiplier"):
		return false
	var previous_time := get_global_time_multiplier()
	var income_multiplier_changed := developer_income_multiplier != income_value
	# Commit both factors before notifying production timers and income displays.
	developer_time_multiplier = time_value
	developer_income_multiplier = income_value
	if previous_time != effective_time:
		global_time_multiplier_changed.emit(previous_time, effective_time)
	if income_multiplier_changed:
		multiplier_changed.emit()
	return true
