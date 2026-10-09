extends Node

const CYCLE_BOUNDARY_TOLERANCE: float = 1.0e-9

# 실제 플레이 중 income을 관리하는 함수.
# 각 income source별로 multiplier를 불러오고 적용

signal income_changed()
signal source_multiplier_changed(source_id: String)
signal source_speed_multiplier_changed(source_id: String)
signal source_activation_changed(source_id: String, is_active: bool)
signal source_timer_changed(source_id: String, seconds_remaining: float)
signal source_level_changed(source_id: String, level: int)


@export var sources: Array[IncomeSourceData] = [
	preload("res://data/IncomeSources/vending_machine_income.tres"),
	preload("res://data/IncomeSources/restaurant_income.tres")
]

@export_category("Upgrade Balance")
## 전환 가격까지의 배율 적용 전 초당 수입 증가량 = coefficient * (반올림 전 가격 ^ exponent).
@export var upgrade_income_coefficient: float = 0.1
## 1 미만이면 가격이 비싸질수록 추가 수입 대비 투자금 회수 시간이 길어진다.
@export_range(0.01, 0.99, 0.01) var upgrade_income_exponent: float = 0.7
## 이 가격을 넘으면 증가량의 지수를 낮추되 전환 지점의 수입은 연속적으로 유지한다.
@export var upgrade_income_transition_cost: float = 1000.0
@export_range(0.01, 0.99, 0.01) var upgrade_late_income_exponent: float = 0.15


# 플레이 중 Source multiplier
var source_multipliers: Dictionary = {}
var source_speed_multipliers: Dictionary = {}
var source_levels: Dictionary = {}

# 플레이 중 활성화된 Source 저장
var source_active: Dictionary = {}
var source_time_remaining: Dictionary = {}
var source_timer_display_keys: Dictionary = {}
# Completed-cycle payments stay separate from partial production progress.
var source_pending_payouts: Dictionary = {}
# Prefix sums avoid recalculating a nonlinear price curve on every frame.
var source_upgrade_income_cache: Dictionary = {}


func _ready() -> void:
	EconomyManager.global_time_multiplier_changed.connect(_on_global_time_multiplier_changed)
	EconomyManager.multiplier_changed.connect(_on_global_multiplier_changed)
	reset_runtime_state()


func reset_runtime_state() -> void:
	ErrorManager.validate_registry(sources, "IncomeSourceData")
	var reset_ids: Dictionary = {}
	for id in source_active:
		reset_ids[id] = true
	source_multipliers.clear()
	source_speed_multipliers.clear()
	source_levels.clear()
	source_active.clear()
	source_time_remaining.clear()
	source_timer_display_keys.clear()
	source_pending_payouts.clear()
	source_upgrade_income_cache.clear()
	var valid_upgrade_balance := _validate_upgrade_balance()
	for source in sources:
		if not valid_upgrade_balance or source == null or get_source(source.id) != source or not ErrorManager.validate_income_source(source):
			continue
		source_multipliers[source.id] = source.multiplier
		source_speed_multipliers[source.id] = 1.0
		source_levels[source.id] = 1
		source_active[source.id] = false
		source_time_remaining[source.id] = 0.0
		source_timer_display_keys[source.id] = 0
		source_pending_payouts[source.id] = 0.0
		reset_ids[source.id] = true
	# Notify views only after every source has returned to a consistent state.
	for id: String in reset_ids:
		source_activation_changed.emit(id, false)
		source_timer_changed.emit(id, 0.0)
		source_level_changed.emit(id, 1)
	income_changed.emit()


# 소스 활성화
func activate_source(source_id: String) -> void:
	if get_source(source_id) == null:
		return
	if not source_active.has(source_id):
		ErrorManager.report_error("MISSING_SOURCE_STATE", "수입원 실행 상태가 초기화되지 않았습니다.", "IncomeSourceData:" + source_id)
		return

	if source_active[source_id]:
		return
	source_active[source_id] = true
	var source := get_source(source_id)
	if source != null:
		source_time_remaining[source_id] = _get_production_time(source)
		source_timer_display_keys[source_id] = _get_timer_display_key(source_time_remaining[source_id])

	source_activation_changed.emit(source_id, true)
	source_timer_changed.emit(source_id, source_time_remaining.get(source_id, 0.0))
	income_changed.emit()


func get_source_time_remaining(source_id: String) -> float:
	if not _has_source_state(source_id, source_time_remaining, "timer"):
		return 0.0
	return source_time_remaining.get(source_id, 0.0)


func _get_production_time(source: IncomeSourceData) -> float:
	var speed_multiplier: float = source_speed_multipliers.get(source.id, 1.0)
	var production_time := source.base_time * source.time_multiplier / speed_multiplier / EconomyManager.get_global_time_multiplier()
	if not ErrorManager.validate_number(production_time, "IncomeSourceData:" + source.id + ".production_time", false):
		return 0.0
	return production_time


func get_source_production_time(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null:
		return 0.0
	return _get_production_time(source)


func _get_timer_display_key(seconds_remaining: float) -> int:
	if seconds_remaining >= 10.0:
		return ceili(seconds_remaining)
	if seconds_remaining >= 1.0:
		return roundi(seconds_remaining * 10.0)
	if seconds_remaining >= 0.1:
		return roundi(seconds_remaining * 100.0)
	return 0


# 특정 source의 multiplier를 불러옴
func get_source_multiplier(source_id: String) -> float:
	if not _has_source_state(source_id, source_multipliers, "multiplier"):
		return 1.0

	return source_multipliers[source_id]


func get_source_level(source_id: String) -> int:
	if not _has_source_state(source_id, source_levels, "level"):
		return 1
	return source_levels.get(source_id, 1)


func _has_source_state(source_id: String, state: Dictionary, state_name: String) -> bool:
	if get_source(source_id) == null:
		return false
	if not state.has(source_id):
		ErrorManager.report_error("MISSING_SOURCE_STATE", "수입원 실행 상태를 찾을 수 없습니다.", "IncomeSourceData:" + source_id + "." + state_name)
		return false
	return true


func get_upgrade_cost(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null:
		return 0.0
	var level := get_source_level(source_id)
	var cost := roundf(_get_upgrade_cost_at_level(source, level))
	if not ErrorManager.validate_number(cost, "IncomeSourceData:" + source_id + ".upgrade_cost", false):
		return 0.0
	return cost


func _get_upgrade_cost_at_level(source: IncomeSourceData, level: int) -> float:
	var upgrades := float(level - 1)
	return source.upgrade_base_cost * (1.0 + source.upgrade_cost_linear_growth * upgrades) * pow(2.0, upgrades / source.upgrade_cost_doubling_levels)


func get_upgrade_income_per_second_gain(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null or not source_active.get(source_id, false) or not _validate_upgrade_balance():
		return 0.0
	var gain := get_next_upgrade_income_per_second(source_id) - get_source_income(source_id)
	return gain if ErrorManager.validate_number(gain, "IncomeSourceData:" + source_id + ".upgrade_income_gain") else 0.0


func get_next_upgrade_income_per_second(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null or not source_active.get(source_id, false) or not _validate_upgrade_balance():
		return 0.0
	var production_time := _get_production_time(source)
	if production_time <= 0.0:
		return 0.0
	var next_payout := get_next_upgrade_cycle_payout(source_id)
	var next_income := next_payout / production_time
	return roundf(next_income) if ErrorManager.validate_number(next_income, "IncomeSourceData:" + source_id + ".next_upgrade_income") else 0.0


func get_next_upgrade_cycle_payout(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null or not source_active.get(source_id, false) or not _validate_upgrade_balance():
		return 0.0
	var next_base_payout := _get_source_payout(source) + _get_upgrade_cycle_gain_at_level(source, get_source_level(source_id))
	return _get_rounded_cycle_payout(source, next_base_payout)


func get_upgrade_cycle_payout_gain(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null or not source_active.get(source_id, false) or not _validate_upgrade_balance():
		return 0.0
	var gain := get_next_upgrade_cycle_payout(source_id) - get_source_cycle_payout(source_id)
	return gain if ErrorManager.validate_number(gain, "IncomeSourceData:" + source_id + ".upgrade_cycle_payout_gain") else 0.0


func _get_upgrade_cycle_gain_at_level(source: IncomeSourceData, level: int) -> float:
	# Use the original cycle duration so speed bonuses still benefit every upgrade.
	return _get_upgrade_income_gain_at_cost(_get_upgrade_cost_at_level(source, level)) * source.base_time * source.time_multiplier


func _get_upgrade_income_gain_at_cost(cost: float) -> float:
	if cost <= upgrade_income_transition_cost:
		return upgrade_income_coefficient * pow(cost, upgrade_income_exponent)
	var transition_gain := upgrade_income_coefficient * pow(upgrade_income_transition_cost, upgrade_income_exponent)
	return transition_gain * pow(cost / upgrade_income_transition_cost, upgrade_late_income_exponent)


func upgrade_source(source_id: String) -> bool:
	var source := get_source(source_id)
	if source == null or not _validate_upgrade_balance():
		return false
	if not source_active.get(source_id, false):
		return false
	var cost := get_upgrade_cost(source_id)
	if cost <= 0.0:
		return false
	var next_payout := roundf((_get_source_payout(source) + _get_upgrade_cycle_gain_at_level(source, get_source_level(source_id))) * get_source_multiplier(source_id) * EconomyManager.get_global_multiplier())
	var production_time := _get_production_time(source)
	if production_time <= 0.0 or not ErrorManager.validate_number(next_payout / production_time, "IncomeSourceData:" + source_id + ".upgraded_income"):
		return false
	if not EconomyManager.spend_money(cost):
		return false
	source_levels[source_id] = get_source_level(source_id) + 1
	source_level_changed.emit(source_id, source_levels[source_id])
	income_changed.emit()
	return true


# 특정 source의 multiplier를 변경
func multiply_source_multiplier(
	source_id: String,
	value: float
) -> void:

	if not source_multipliers.has(source_id):
		ErrorManager.report_error("MISSING_SOURCE_STATE", "수입원 배율 상태를 찾을 수 없습니다.", "IncomeSourceData:" + source_id)
		return

	if not ErrorManager.validate_number(value, "IncomeSourceData:" + source_id + ".multiplier_factor", false):
		return
	var updated_multiplier: float = source_multipliers[source_id] * value
	if not ErrorManager.validate_number(updated_multiplier, "IncomeSourceData:" + source_id + ".multiplier", false):
		return
	source_multipliers[source_id] = updated_multiplier

	source_multiplier_changed.emit(source_id)
	income_changed.emit()


func multiply_source_speed_multiplier(source_id: String, value: float) -> void:
	if not source_speed_multipliers.has(source_id):
		ErrorManager.report_error("MISSING_SOURCE_STATE", "수입원 속도 상태를 찾을 수 없습니다.", "IncomeSourceData:" + source_id)
		return
	if not ErrorManager.validate_number(value, "IncomeSourceData:" + source_id + ".speed_factor", false):
		return
	var updated_multiplier: float = source_speed_multipliers[source_id] * value
	if not ErrorManager.validate_number(updated_multiplier, "IncomeSourceData:" + source_id + ".speed_multiplier", false):
		return
	var source := get_source(source_id)
	if source == null:
		return
	var previous_production_time := _get_production_time(source)
	var previous_speed: float = source_speed_multipliers[source_id]
	source_speed_multipliers[source_id] = updated_multiplier
	var updated_production_time := _get_production_time(source)
	if updated_production_time <= 0.0:
		source_speed_multipliers[source_id] = previous_speed
		return
	if previous_production_time > 0.0 and updated_production_time > 0.0:
		_refresh_source_after_time_change(source, updated_production_time / previous_production_time)
	income_changed.emit()


func _on_global_multiplier_changed() -> void:
	income_changed.emit()


func _on_global_time_multiplier_changed(previous_value: float, new_value: float) -> void:
	if previous_value <= 0.0 or new_value <= 0.0:
		return
	var production_time_ratio := previous_value / new_value
	for source in sources:
		if source != null:
			_refresh_source_after_time_change(source, production_time_ratio)
	income_changed.emit()


func _refresh_source_after_time_change(source: IncomeSourceData, production_time_ratio: float) -> void:
	if source_active.get(source.id, false) and production_time_ratio > 0.0 and is_finite(production_time_ratio):
		var remaining: float = source_time_remaining.get(source.id, _get_production_time(source))
		remaining *= production_time_ratio
		source_time_remaining[source.id] = remaining
		source_timer_display_keys[source.id] = _get_timer_display_key(remaining)
		source_timer_changed.emit(source.id, remaining)
	source_speed_multiplier_changed.emit(source.id)


# income 계산
func get_source_income(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null:
		return 0.0
	if not source_active.get(source_id, false):
		return 0.0

	var production_time := _get_production_time(source)
	if production_time <= 0.0 or not is_finite(production_time):
		return 0.0
	var income := get_source_cycle_payout(source_id) / production_time
	return roundf(income) if ErrorManager.validate_number(income, "IncomeSourceData:" + source_id + ".income_per_second") else 0.0


func get_source_cycle_payout(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null:
		return 0.0
	return _get_rounded_cycle_payout(source, _get_source_payout(source))


func _get_rounded_cycle_payout(source: IncomeSourceData, base_payout: float) -> float:
	# Round each completed cycle after every income bonus, before batching cycles.
	var payout := roundf(base_payout * get_source_multiplier(source.id) * EconomyManager.get_global_multiplier())
	return payout if ErrorManager.validate_number(payout, "IncomeSourceData:" + source.id + ".payout") else 0.0


func _get_source_payout(source: IncomeSourceData) -> float:
	return _get_source_payout_at_level(source, get_source_level(source.id))


func _get_source_payout_at_level(source: IncomeSourceData, level: int) -> float:
	var upgrades := level - 1
	if upgrades <= 0:
		return source.base_income
	if not _validate_upgrade_balance():
		return 0.0
	var parameters := [upgrade_income_coefficient, upgrade_income_exponent, upgrade_income_transition_cost,
		upgrade_late_income_exponent, source.upgrade_base_cost,
		source.upgrade_cost_linear_growth, source.upgrade_cost_doubling_levels, source.base_time, source.time_multiplier]
	var cache: Dictionary = source_upgrade_income_cache.get(source.id, {})
	if cache.is_empty() or cache.parameters != parameters or level < int(cache.level):
		cache = {"parameters": parameters, "level": 1, "payout": 0.0}
	for upgrade_level in range(int(cache.level), level):
		var gain := _get_upgrade_cycle_gain_at_level(source, upgrade_level)
		var payout: float = cache.payout + gain
		if not is_finite(payout):
			return payout
		cache.payout = payout
		cache.level = upgrade_level + 1
	source_upgrade_income_cache[source.id] = cache
	return source.base_income + float(cache.payout)


func _validate_upgrade_balance() -> bool:
	if not ErrorManager.validate_number(upgrade_income_coefficient, "IncomeManager.upgrade_income_coefficient", false):
		return false
	if not ErrorManager.validate_number(upgrade_income_exponent, "IncomeManager.upgrade_income_exponent", false):
		return false
	if upgrade_income_exponent >= 1.0:
		ErrorManager.report_error("INVALID_UPGRADE_BALANCE", "업그레이드 수입 지수는 0보다 크고 1보다 작아야 합니다.", "IncomeManager.upgrade_income_exponent")
		return false
	if not ErrorManager.validate_number(upgrade_income_transition_cost, "IncomeManager.upgrade_income_transition_cost", false):
		return false
	if not ErrorManager.validate_number(upgrade_late_income_exponent, "IncomeManager.upgrade_late_income_exponent", false):
		return false
	if upgrade_late_income_exponent > upgrade_income_exponent:
		ErrorManager.report_error("INVALID_UPGRADE_BALANCE", "후반 수입 지수는 초기 수입 지수 이하여야 합니다.", "IncomeManager.upgrade_late_income_exponent")
		return false
	return true


func get_source(source_id: String) -> IncomeSourceData:
	return ErrorManager.find_resource(sources, source_id, "IncomeSourceData") as IncomeSourceData

# 전체 income source들의 income 총합을 계산
func get_total_income_per_second() -> float:

	var total := 0.0

	for source in sources:

		if source == null:
			continue

		total += get_source_income(source.id)

	return total if ErrorManager.validate_number(total, "IncomeManager.total_income_per_second") else 0.0


func _process(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	for source in sources:
		if source == null or get_source(source.id) != source or not source_active.get(source.id, false):
			continue

		var production_time := _get_production_time(source)
		if production_time <= 0.0:
			continue

		var remaining: float = source_time_remaining.get(source.id, production_time)
		remaining -= delta
		if remaining <= production_time * CYCLE_BOUNDARY_TOLERANCE:
			# Cycle counts can exceed int64 at very high production speeds.
			var overdue_cycles := -remaining / production_time
			var nearest_boundary := roundf(overdue_cycles)
			var on_boundary := absf(overdue_cycles - nearest_boundary) <= CYCLE_BOUNDARY_TOLERANCE
			if on_boundary:
				overdue_cycles = nearest_boundary
			var completed_cycles := floorf(overdue_cycles) + 1.0
			var pending: float = source_pending_payouts.get(source.id, 0.0)
			pending += get_source_cycle_payout(source.id) * completed_cycles
			if ErrorManager.validate_number(pending, "IncomeSourceData:" + source.id + ".pending_payout"):
				source_pending_payouts[source.id] = pending
			remaining = production_time if on_boundary else production_time - fposmod(-remaining, production_time)

		source_time_remaining[source.id] = remaining
		var display_key := _get_timer_display_key(remaining)
		if display_key != source_timer_display_keys.get(source.id, -1):
			source_timer_display_keys[source.id] = display_key
			source_timer_changed.emit(source.id, remaining)
		# Pay all completed cycles once per source per frame, without a time gate.
		if source_active.get(source.id, false):
			_flush_source_payout(source.id)


func _flush_source_payout(source_id: String) -> void:
	var pending: float = source_pending_payouts.get(source_id, 0.0)
	var amount := floorf(pending)
	if amount <= 0.0:
		return
	# Each completed cycle has already been rounded to whole won before batching.
	# Commit state before money_changed handlers can purchase upgrades or reset it.
	source_pending_payouts[source_id] = pending - amount
	if not EconomyManager.add_money(amount):
		source_pending_payouts[source_id] = pending
