extends Node
const BIG = preload("res://scripts/BigNumber.gd")

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
	preload("res://data/IncomeSources/restaurant_income.tres"),
	preload("res://data/IncomeSources/spa_income.tres")
]

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
var source_pending_corrections: Dictionary = {}
var _runtime_generation: int = 0
# Cache cumulative income so only newly reached levels need to be calculated.
var source_upgrade_income_cache: Dictionary = {}


func _ready() -> void:
	EconomyManager.global_time_multiplier_changed.connect(_on_global_time_multiplier_changed)
	EconomyManager.multiplier_changed.connect(_on_global_multiplier_changed)
	reset_runtime_state()


func reset_runtime_state() -> void:
	_runtime_generation += 1
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
	source_pending_corrections.clear()
	source_upgrade_income_cache.clear()
	for source in sources:
		if source == null or get_source(source.id) != source or not ErrorManager.validate_income_source(source):
			continue
		source_multipliers[source.id] = source.multiplier
		source_speed_multipliers[source.id] = 1.0
		source_levels[source.id] = 1
		source_active[source.id] = false
		source_time_remaining[source.id] = 0.0
		source_timer_display_keys[source.id] = 0
		source_pending_payouts[source.id] = 0.0
		source_pending_corrections[source.id] = 0.0
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
func get_source_multiplier(source_id: String) -> Variant:
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


func get_upgrade_cost(source_id: String) -> Variant:
	var source := get_source(source_id)
	if source == null:
		return 0.0
	var level := get_source_level(source_id)
	var cost: Variant = BIG.rounded(_get_upgrade_cost_at_level(source, level))
	if not ErrorManager.validate_number(cost, "IncomeSourceData:" + source_id + ".upgrade_cost", false):
		return 0.0
	return cost


func _get_upgrade_cost_at_level(source: IncomeSourceData, level: int) -> Variant:
	var upgrades := float(level - 1)
	# Preserve native rounding for existing gameplay, extend only when pow overflows.
	var native_growth := pow(2.0, upgrades / source.upgrade_cost_doubling_levels)
	var native_cost := source.upgrade_base_cost * (1.0 + source.upgrade_cost_linear_growth * upgrades) * native_growth
	if is_finite(native_cost):
		return native_cost
	var growth: Variant = native_growth if is_finite(native_growth) else BIG.power_of_ten(upgrades / source.upgrade_cost_doubling_levels * log(2.0) / log(10.0))
	return BIG.multiply(BIG.multiply(source.upgrade_base_cost, 1.0 + source.upgrade_cost_linear_growth * upgrades), growth)


func get_upgrade_income_per_second_gain(source_id: String) -> Variant:
	var source := get_source(source_id)
	if source == null or not source_active.get(source_id, false) or not _validate_upgrade_balance(source):
		return 0.0
	var gain: Variant = BIG.subtract(get_next_upgrade_income_per_second(source_id), get_source_income(source_id))
	return gain if ErrorManager.validate_number(gain, "IncomeSourceData:" + source_id + ".upgrade_income_gain") else 0.0


func get_next_upgrade_income_per_second(source_id: String) -> Variant:
	var source := get_source(source_id)
	if source == null or not source_active.get(source_id, false) or not _validate_upgrade_balance(source):
		return 0.0
	var production_time := _get_production_time(source)
	if production_time <= 0.0:
		return 0.0
	var next_payout: Variant = get_next_upgrade_cycle_payout(source_id)
	var next_income: Variant = BIG.divide(next_payout, production_time)
	return BIG.rounded(next_income) if ErrorManager.validate_number(next_income, "IncomeSourceData:" + source_id + ".next_upgrade_income") else 0.0


func get_next_upgrade_cycle_payout(source_id: String) -> Variant:
	var source := get_source(source_id)
	if source == null or not source_active.get(source_id, false) or not _validate_upgrade_balance(source):
		return 0.0
	var next_base_payout: Variant = BIG.add(_get_source_payout(source), _get_upgrade_cycle_gain_at_level(source, get_source_level(source_id)))
	return _get_rounded_cycle_payout(source, next_base_payout)


func get_upgrade_cycle_payout_gain(source_id: String) -> Variant:
	var source := get_source(source_id)
	if source == null or not source_active.get(source_id, false) or not _validate_upgrade_balance(source):
		return 0.0
	var gain: Variant = BIG.subtract(get_next_upgrade_cycle_payout(source_id), get_source_cycle_payout(source_id))
	return gain if ErrorManager.validate_number(gain, "IncomeSourceData:" + source_id + ".upgrade_cycle_payout_gain") else 0.0


func _get_upgrade_cycle_gain_at_level(source: IncomeSourceData, level: int) -> Variant:
	var income_ratio := source.upgrade_first_income_ratio / (1.0 + source.upgrade_income_decay * float(level - 1))
	return BIG.multiply(_get_source_payout_at_level(source, level), income_ratio)


func upgrade_source(source_id: String) -> bool:
	var source := get_source(source_id)
	if source == null or not _validate_upgrade_balance(source):
		return false
	if not source_active.get(source_id, false):
		return false
	var cost: Variant = get_upgrade_cost(source_id)
	if BIG.compare(cost, 0.0) <= 0:
		return false
	var next_payout: Variant = get_next_upgrade_cycle_payout(source_id)
	var production_time := _get_production_time(source)
	if production_time <= 0.0 or not ErrorManager.validate_number(BIG.divide(next_payout, production_time), "IncomeSourceData:" + source_id + ".upgraded_income"):
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
	var updated_multiplier: Variant = BIG.multiply(source_multipliers[source_id], value)
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
func get_source_income(source_id: String) -> Variant:
	return BIG.rounded(get_source_income_unrounded(source_id))


func get_source_income_unrounded(source_id: String) -> Variant:
	var source := get_source(source_id)
	if source == null:
		return 0.0
	if not source_active.get(source_id, false):
		return 0.0

	var production_time := _get_production_time(source)
	if production_time <= 0.0 or not is_finite(production_time):
		return 0.0
	var income: Variant = BIG.divide(get_source_cycle_payout(source_id), production_time)
	return income if ErrorManager.validate_number(income, "IncomeSourceData:" + source_id + ".income_per_second") else 0.0


func get_source_cycle_payout(source_id: String) -> Variant:
	var source := get_source(source_id)
	if source == null:
		return 0.0
	return _get_rounded_cycle_payout(source, _get_source_payout(source))


func _get_rounded_cycle_payout(source: IncomeSourceData, base_payout: Variant) -> Variant:
	# Round each completed cycle after every income bonus, before batching cycles.
	var raw_payout: Variant = BIG.multiply(BIG.multiply(base_payout, get_source_multiplier(source.id)), EconomyManager.get_global_multiplier())
	var payout: Variant = BIG.rounded(raw_payout)
	# Positive sub-won cycles must accumulate, even when individually rounded to zero.
	if BIG.compare(payout, 0.0) == 0 and BIG.valid(raw_payout, false):
		payout = raw_payout
	return payout if ErrorManager.validate_number(payout, "IncomeSourceData:" + source.id + ".payout") else 0.0


func _get_source_payout(source: IncomeSourceData) -> Variant:
	return _get_source_payout_at_level(source, get_source_level(source.id))


func _get_source_payout_at_level(source: IncomeSourceData, level: int) -> Variant:
	var upgrades := level - 1
	if upgrades <= 0:
		return source.base_income
	if not _validate_upgrade_balance(source):
		return 0.0
	var parameters := [source.base_income, source.upgrade_first_income_ratio, source.upgrade_income_decay]
	var cache: Dictionary = source_upgrade_income_cache.get(source.id, {})
	if cache.is_empty() or cache.parameters != parameters or level < int(cache.level):
		cache = {"parameters": parameters, "level": 1, "payout": source.base_income}
	var exact_end := mini(level, int(cache.level) + 2048)
	for upgrade_level in range(int(cache.level), exact_end):
		var income_ratio := source.upgrade_first_income_ratio / (1.0 + source.upgrade_income_decay * float(upgrade_level - 1))
		var gain: Variant = BIG.multiply(cache.payout, income_ratio)
		var payout: Variant = BIG.add(cache.payout, gain)
		if not BIG.valid(payout):
			return payout
		cache.payout = payout
		cache.level = upgrade_level + 1
	if exact_end < level:
		# Approximate only the distant tail; work stays bounded for huge saved levels.
		var first := float(exact_end - 1)
		var last := float(level - 1)
		var ratio := source.upgrade_first_income_ratio
		var decay := source.upgrade_income_decay
		var logarithmic_growth: float
		if decay == 0.0:
			logarithmic_growth = (last - first) * log(1.0 + ratio)
		else:
			var start_y := 1.0 + decay * first
			var end_y := 1.0 + decay * last
			var start_integral := start_y * log(1.0 + ratio / start_y) + ratio * log(start_y + ratio)
			var end_integral := end_y * log(1.0 + ratio / end_y) + ratio * log(end_y + ratio)
			logarithmic_growth = (end_integral - start_integral) / decay
			logarithmic_growth += (log(1.0 + ratio / start_y) - log(1.0 + ratio / end_y)) * 0.5
			var start_derivative := -decay * (ratio / start_y) / (start_y + ratio)
			var end_derivative := -decay * (ratio / end_y) / (end_y + ratio)
			logarithmic_growth += (end_derivative - start_derivative) / 12.0
		cache.payout = BIG.multiply(cache.payout, BIG.power_of_ten(logarithmic_growth / log(10.0)))
		cache.level = level
	source_upgrade_income_cache[source.id] = cache
	return cache.payout


func _validate_upgrade_balance(source: IncomeSourceData) -> bool:
	var context := "IncomeSourceData:" + source.id
	return ErrorManager.validate_number(source.upgrade_first_income_ratio, context + ".upgrade_first_income_ratio", false) \
		and ErrorManager.validate_number(source.upgrade_income_decay, context + ".upgrade_income_decay")


func get_source(source_id: String) -> IncomeSourceData:
	return ErrorManager.find_resource(sources, source_id, "IncomeSourceData") as IncomeSourceData

# 전체 income source들의 income 총합을 계산
func get_total_income_per_second() -> Variant:

	var total: Variant = 0.0

	for source in sources:

		if source == null:
			continue

		total = BIG.add(total, get_source_income_unrounded(source.id))

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
			var on_boundary := false
			var completed_cycles: Variant
			if is_finite(overdue_cycles):
				var nearest_boundary := roundf(overdue_cycles)
				on_boundary = absf(overdue_cycles - nearest_boundary) <= CYCLE_BOUNDARY_TOLERANCE
				if on_boundary:
					overdue_cycles = nearest_boundary
				completed_cycles = floorf(overdue_cycles) + 1.0
			else:
				completed_cycles = BIG.add(BIG.floored(BIG.divide(-remaining, production_time)), 1.0)
			var pending: Variant = source_pending_payouts.get(source.id, 0.0)
			var accumulated := BIG.add_with_residual(pending, BIG.multiply(get_source_cycle_payout(source.id), completed_cycles))
			var correction: Variant = BIG.add(source_pending_corrections.get(source.id, 0.0), accumulated[1])
			if ErrorManager.validate_number(accumulated[0], "IncomeSourceData:" + source.id + ".pending_payout") and BIG.valid_signed(correction):
				source_pending_payouts[source.id] = accumulated[0]
				source_pending_corrections[source.id] = correction
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
	var pending: Variant = source_pending_payouts.get(source_id, 0.0)
	var pending_correction: Variant = source_pending_corrections.get(source_id, 0.0)
	var folded := BIG.add_with_residual(pending, pending_correction)
	var amount: Variant = BIG.floored(folded[0])
	var correction: Variant = BIG.truncated(folded[1])
	var remainder: Variant = BIG.subtract(folded[0], amount)
	var remainder_correction: Variant = BIG.subtract(folded[1], correction)
	# Borrow one won if a negative low part puts the true amount below the floor.
	if BIG.compare(BIG.add(remainder, remainder_correction), 0.0) < 0:
		var reduced: Variant = BIG.subtract(amount, 1.0)
		if BIG.compare(reduced, amount) == 0:
			correction = BIG.subtract(correction, 1.0)
		else:
			amount = reduced
		remainder = BIG.add(remainder, 1.0)
	if BIG.compare(BIG.add(amount, correction), 0.0) <= 0:
		return
	var generation := _runtime_generation
	# Transfer the integer low part to the wallet; keep fractional won at the source.
	# Commit before callbacks; a prestige/reset must not resurrect pending earnings.
	source_pending_payouts[source_id] = remainder
	source_pending_corrections[source_id] = remainder_correction
	if not EconomyManager.add_money(amount, correction) and generation == _runtime_generation:
		source_pending_payouts[source_id] = pending
		source_pending_corrections[source_id] = pending_correction
