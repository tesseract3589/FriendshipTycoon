extends Node


signal prestige_changed()


const JAM_MULTIPLIER_PER_POINT: float = 0.01
const MAX_JJAM: int = 9223372036854775807

@export var money_per_jjam: float = 1000000.0

var total_jjam: int = 0
var current_jjam: int = 0


func get_prestige_multiplier() -> float:
	return 1.0 + float(get_total_jjam()) * JAM_MULTIPLIER_PER_POINT


func get_total_jjam() -> int:
	if total_jjam < 0:
		ErrorManager.report_error("INVALID_JJAM", "누적 짬이 음수입니다.", "PrestigeManager.total_jjam")
		return 0
	return total_jjam


func get_current_jjam() -> int:
	if not ErrorManager.validate_number(money_per_jjam, "PrestigeManager.money_per_jjam", false):
		return 0
	if not ErrorManager.validate_number(EconomyManager.money, "EconomyManager.money"):
		return 0
	var earned := sqrt(EconomyManager.money / money_per_jjam)
	if not is_finite(earned) or earned >= ErrorManager.INT64_LIMIT:
		ErrorManager.report_error("JJAM_OVERFLOW", "환생 보상이 정수 범위를 넘었습니다. 자금과 구매 상태를 유지합니다.", "PrestigeManager.get_current_jjam")
		return 0
	return floori(earned)


func prestige() -> bool:
	if total_jjam < 0:
		get_total_jjam()
		return false
	current_jjam = get_current_jjam()
	if current_jjam <= 0:
		return false
	if total_jjam > MAX_JJAM - current_jjam:
		ErrorManager.report_error("JJAM_OVERFLOW", "누적 짬이 정수 범위를 넘습니다. 환생을 중단하고 현재 상태를 유지합니다.", "PrestigeManager.total_jjam")
		current_jjam = 0
		return false
	total_jjam += current_jjam
	current_jjam = 0
	EconomyManager.reset_money()
	EconomyManager.set_global_multiplier(get_prestige_multiplier())
	ButtonManager.reset_for_prestige()
	prestige_changed.emit()
	return true
