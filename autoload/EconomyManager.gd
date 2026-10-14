extends Node
const BIG = preload("res://scripts/BigNumber.gd")


signal money_changed(new_money: Variant)
signal multiplier_changed()
signal global_time_multiplier_changed(previous_value: float, new_value: float)


var money: Variant = 0.0:
	set(value):
		money = value
		# Direct replacement represents a new balance, not the old residual wallet.
		money_correction = 0.0
# Signed low part retained across payouts, spending, frames, sources and saves.
var money_correction: Variant = 0.0

# 모든 Income Source에 적용
# 각 Income Source 별 multiplier는 따로 관리
var global_multiplier: Variant = 1.0
var global_time_multiplier: float = 1.0
# Developer overrides stay separate from purchases and prestige bonuses.
var developer_income_multiplier: Variant = 1.0
var developer_time_multiplier: float = 1.0


func reset_money() -> void:
	money = 0.0
	money_correction = 0.0
	money_changed.emit(money)


func add_money(amount: Variant, correction: Variant = 0.0) -> bool:
	if not ErrorManager.validate_number(amount, "EconomyManager.add_money") or BIG.compare(amount, 0.0) == 0:
		return false
	if not BIG.valid_signed(correction) or BIG.compare(BIG.add(amount, correction), 0.0) < 0:
		return false

	var rounded_amount: Variant = BIG.rounded(amount)
	if BIG.compare(rounded_amount, 0.0) <= 0:
		ErrorManager.report_error("INVALID_AMOUNT", "원 단위로 반올림한 금액이 0입니다.", "EconomyManager.add_money")
		return false
	return _apply_money_delta(rounded_amount, correction)


func can_afford(amount: Variant) -> bool:
	if not ErrorManager.validate_number(amount, "EconomyManager.price") or not ErrorManager.validate_number(money, "EconomyManager.money"):
		return false
	return BIG.compare(BIG.add(BIG.subtract(money, BIG.rounded(amount)), money_correction), 0.0) >= 0


func spend_money(amount: Variant) -> bool:
	if not ErrorManager.validate_number(amount, "EconomyManager.spend_money", false):
		return false

	var rounded_amount: Variant = BIG.rounded(amount)
	if BIG.compare(rounded_amount, 0.0) <= 0 or not can_afford(rounded_amount):
		return false

	return _apply_money_delta(BIG.subtract(0.0, rounded_amount))


func _apply_money_delta(delta: Variant, extra_correction: Variant = 0.0) -> bool:
	var addition := BIG.add_with_residual(money, delta)
	var correction: Variant = BIG.add(money_correction, addition[1])
	correction = BIG.add(correction, extra_correction)
	var folded := BIG.add_with_residual(addition[0], correction)
	if not ErrorManager.validate_number(folded[0], "EconomyManager.money") or not BIG.valid_signed(folded[1]):
		return false
	# Commit both parts before synchronous money_changed callbacks can spend/reset.
	money = folded[0]
	money_correction = folded[1]
	money_changed.emit(money)
	return true


func get_global_multiplier() -> Variant:
	return BIG.multiply(global_multiplier, developer_income_multiplier)


func multiply_global_multiplier(value: Variant) -> void:
	if not ErrorManager.validate_number(value, "EconomyManager.multiplier_factor", false):
		return
	set_global_multiplier(BIG.multiply(global_multiplier, value))


func set_global_multiplier(value: Variant) -> void:
	if not ErrorManager.validate_number(value, "EconomyManager.global_multiplier"):
		return
	if not ErrorManager.validate_number(BIG.multiply(value, developer_income_multiplier), "EconomyManager.effective_income_multiplier"):
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


func get_developer_income_multiplier() -> Variant:
	return developer_income_multiplier


func get_developer_time_multiplier() -> float:
	return developer_time_multiplier


func set_developer_multipliers(time_value: float, income_value: Variant) -> bool:
	if not ErrorManager.validate_number(time_value, "EconomyManager.developer_time_multiplier", false):
		return false
	if not ErrorManager.validate_number(income_value, "EconomyManager.developer_income_multiplier"):
		return false
	var effective_time := global_time_multiplier * time_value
	if not ErrorManager.validate_number(effective_time, "EconomyManager.effective_time_multiplier", false):
		return false
	if not ErrorManager.validate_number(BIG.multiply(global_multiplier, income_value), "EconomyManager.effective_income_multiplier"):
		return false
	var previous_time := get_global_time_multiplier()
	var income_multiplier_changed: bool = BIG.compare(developer_income_multiplier, income_value) != 0
	# Commit both factors before notifying production timers and income displays.
	developer_time_multiplier = time_value
	developer_income_multiplier = income_value
	if previous_time != effective_time:
		global_time_multiplier_changed.emit(previous_time, effective_time)
	if income_multiplier_changed:
		multiplier_changed.emit()
	return true
