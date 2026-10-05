extends Node

# 실제 플레이 중 income을 관리하는 함수.
# 각 income source별로 multiplier를 불러오고 적용

signal income_changed()
signal source_multiplier_changed(source_id: String)
signal source_speed_multiplier_changed(source_id: String)
signal source_activation_changed(source_id: String, is_active: bool)
signal source_timer_changed(source_id: String, seconds_remaining: float)
signal source_level_changed(source_id: String, level: int)


@export var sources: Array[IncomeSourceData] = [preload("res://data/IncomeSources/vending_machine_income.tres")]


# 플레이 중 Source multiplier
var source_multipliers: Dictionary = {}
var source_speed_multipliers: Dictionary = {}
var source_levels: Dictionary = {}

# 플레이 중 활성화된 Source 저장
var source_active: Dictionary = {}
var source_time_remaining: Dictionary = {}
var source_timer_display_keys: Dictionary = {}


func _ready() -> void:
	EconomyManager.global_time_multiplier_changed.connect(_on_global_time_multiplier_changed)
	reset_runtime_state()


func reset_runtime_state() -> void:
	source_multipliers.clear()
	source_speed_multipliers.clear()
	source_levels.clear()
	source_active.clear()
	source_time_remaining.clear()
	source_timer_display_keys.clear()
	for source in sources:
		if source == null or source.id.is_empty():
			continue
		source_multipliers[source.id] = source.multiplier
		source_speed_multipliers[source.id] = 1.0
		source_levels[source.id] = 1
		source_active[source.id] = false
		source_time_remaining[source.id] = 0.0
		source_timer_display_keys[source.id] = 0
	income_changed.emit()


# 소스 활성화
func activate_source(source_id: String) -> void:

	if not source_active.has(source_id):
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
	return source_time_remaining.get(source_id, 0.0)


func _get_production_time(source: IncomeSourceData) -> float:
	var speed_multiplier: float = source_speed_multipliers.get(source.id, 1.0)
	var production_time := source.base_time * source.time_multiplier / speed_multiplier / EconomyManager.get_global_time_multiplier()
	if production_time <= 0.0 or not is_finite(production_time):
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

	if not source_multipliers.has(source_id):
		return 1.0

	return source_multipliers[source_id]


func get_source_level(source_id: String) -> int:
	return source_levels.get(source_id, 1)


func get_upgrade_cost(source_id: String) -> float:
	var source := get_source(source_id)
	if source == null:
		return 0.0
	var level := get_source_level(source_id)
	return roundf(source.upgrade_base_cost * pow(source.upgrade_cost_growth, level - 1))


func upgrade_source(source_id: String) -> bool:
	if not source_active.get(source_id, false):
		return false
	var cost := get_upgrade_cost(source_id)
	if cost <= 0.0 or not EconomyManager.spend_money(cost):
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
		return

	if value <= 0.0 or not is_finite(value):
		return
	source_multipliers[source_id] *= value

	source_multiplier_changed.emit(source_id)
	income_changed.emit()


func multiply_source_speed_multiplier(source_id: String, value: float) -> void:
	if not source_speed_multipliers.has(source_id):
		return
	if value <= 0.0 or not is_finite(value):
		return
	var source := get_source(source_id)
	if source == null:
		return
	var previous_production_time := _get_production_time(source)
	source_speed_multipliers[source_id] *= value
	var updated_production_time := _get_production_time(source)
	if previous_production_time > 0.0 and updated_production_time > 0.0:
		_refresh_source_after_time_change(source, updated_production_time / previous_production_time)
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

	if not source_active.get(source_id, false):
		return 0.0

	var source := get_source(source_id)

	if source == null:
		return 0.0

	var production_time := _get_production_time(source)
	if production_time <= 0.0 or not is_finite(production_time):
		return 0.0
	return _get_source_payout(source) / production_time * get_source_multiplier(source_id) * EconomyManager.get_global_multiplier()


func _get_source_payout(source: IncomeSourceData) -> float:
	return source.base_income + source.upgrade_income_per_level * (get_source_level(source.id) - 1)


func get_source(source_id: String) -> IncomeSourceData:

	for source in sources:

		if source == null:
			continue

		if source.id == source_id:
			return source

	return null

# 전체 income source들의 income 총합을 계산
func get_total_income_per_second() -> float:

	var total := 0.0

	for source in sources:

		if source == null:
			continue

		total += get_source_income(source.id)

	return total


func _process(delta: float) -> void:
	for source in sources:
		if source == null or not source_active.get(source.id, false):
			continue

		var production_time := _get_production_time(source)
		if production_time <= 0.0:
			continue

		var remaining: float = source_time_remaining.get(source.id, production_time)
		remaining -= delta
		if remaining <= 0.0:
			var completed_cycles := floori(-remaining / production_time) + 1
			EconomyManager.add_money(
				_get_source_payout(source)
				* get_source_multiplier(source.id)
				* EconomyManager.get_global_multiplier()
				* completed_cycles
			)
			remaining += production_time * completed_cycles

		source_time_remaining[source.id] = remaining
		var display_key := _get_timer_display_key(remaining)
		if display_key != source_timer_display_keys.get(source.id, -1):
			source_timer_display_keys[source.id] = display_key
			source_timer_changed.emit(source.id, remaining)
