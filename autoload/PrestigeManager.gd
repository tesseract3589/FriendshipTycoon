extends Node


signal prestige_changed()


const JAM_MULTIPLIER_PER_POINT: float = 0.01

@export var money_per_jjam: float = 1000000.0

var total_jjam: int = 0
var current_jjam: int = 0


func get_prestige_multiplier() -> float:
	return 1.0 + float(total_jjam) * JAM_MULTIPLIER_PER_POINT


func get_current_jjam() -> int:
	if money_per_jjam <= 0.0 or not is_finite(money_per_jjam):
		return 0
	return maxi(floori(sqrt(maxf(EconomyManager.money / money_per_jjam, 0.0))), 0)


func prestige() -> bool:
	current_jjam = get_current_jjam()
	if current_jjam <= 0:
		return false
	total_jjam += current_jjam
	current_jjam = 0
	EconomyManager.reset_money()
	EconomyManager.set_global_multiplier(get_prestige_multiplier())
	ButtonManager.reset_for_prestige()
	prestige_changed.emit()
	return true
