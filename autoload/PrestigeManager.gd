extends Node
const BIG = preload("res://scripts/BigNumber.gd")


signal prestige_changed()


const JAM_MULTIPLIER_PER_POINT: float = 0.01
const MAX_JJAM: int = 9223372036854775807

@export var money_per_jjam: float = 1000000.0

var total_jjam: Variant = 0
var current_jjam: Variant = 0


func get_prestige_multiplier() -> Variant:
	return BIG.add(1.0, BIG.multiply(get_total_jjam(), JAM_MULTIPLIER_PER_POINT))


func get_total_jjam() -> Variant:
	if not BIG.valid(total_jjam):
		ErrorManager.report_error("INVALID_JJAM", "누적 짬이 음수입니다.", "PrestigeManager.total_jjam")
		return 0
	return total_jjam


func get_current_jjam() -> Variant:
	if not ErrorManager.validate_number(money_per_jjam, "PrestigeManager.money_per_jjam", false):
		return 0
	if not ErrorManager.validate_number(EconomyManager.money, "EconomyManager.money"):
		return 0
	var earned: Variant = BIG.square_root(BIG.divide(EconomyManager.money, money_per_jjam))
	if not ErrorManager.validate_number(earned, "PrestigeManager.current_jjam"):
		return 0
	return BIG.whole_count(earned)


func prestige() -> bool:
	if not BIG.valid(total_jjam):
		get_total_jjam()
		return false
	current_jjam = get_current_jjam()
	if BIG.compare(current_jjam, 0) <= 0:
		return false
	if total_jjam is int and current_jjam is int and total_jjam <= MAX_JJAM - current_jjam:
		total_jjam += current_jjam
	else:
		var accumulated: Variant = BIG.add(total_jjam, current_jjam)
		if not ErrorManager.validate_number(accumulated, "PrestigeManager.total_jjam"):
			return false
		total_jjam = BIG.whole_count(accumulated)
	current_jjam = 0
	EconomyManager.reset_money()
	EconomyManager.set_global_multiplier(get_prestige_multiplier())
	ButtonManager.reset_for_prestige()
	prestige_changed.emit()
	return true
