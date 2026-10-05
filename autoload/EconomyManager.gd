extends Node


signal money_changed(new_money: float)
signal multiplier_changed()
signal global_time_multiplier_changed(previous_value: float, new_value: float)


var money: float = 0.0

# 모든 Income Source에 적용
# 각 Income Source 별 multiplier는 따로 관리
var global_multiplier: float = 1.0
var global_time_multiplier: float = 1.0


func reset_money() -> void:
	money = 0.0
	money_changed.emit(money)


func add_money(amount: float) -> void:
	if amount <= 0.0 or not is_finite(amount):
		return

	var rounded_amount := roundf(amount)
	if rounded_amount <= 0.0:
		return
	money += rounded_amount
	money_changed.emit(money)


func can_afford(amount: float) -> bool:
	return amount >= 0.0 and money >= roundf(amount)


func spend_money(amount: float) -> bool:
	if amount <= 0.0 or not is_finite(amount):
		return false

	var rounded_amount := roundf(amount)
	if rounded_amount <= 0.0 or money < rounded_amount:
		return false

	money -= rounded_amount
	money_changed.emit(money)

	return true


func get_global_multiplier() -> float:
	return global_multiplier


func multiply_global_multiplier(value: float) -> void:
	if value <= 0.0 or not is_finite(value):
		return
	global_multiplier *= value
	multiplier_changed.emit()


func set_global_multiplier(value: float) -> void:
	global_multiplier = value if is_finite(value) else 0.0
	global_multiplier = maxf(global_multiplier, 0.0)
	multiplier_changed.emit()


func get_global_time_multiplier() -> float:
	return global_time_multiplier


func multiply_global_time_multiplier(value: float) -> void:
	if value <= 0.0 or not is_finite(value):
		return
	set_global_time_multiplier(global_time_multiplier * value)


func set_global_time_multiplier(value: float) -> void:
	if value <= 0.0 or not is_finite(value):
		return
	var previous_value := global_time_multiplier
	if is_equal_approx(previous_value, value):
		return
	global_time_multiplier = value
	global_time_multiplier_changed.emit(previous_value, global_time_multiplier)
	
