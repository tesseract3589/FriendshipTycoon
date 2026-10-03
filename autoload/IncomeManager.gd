extends Node

# 실제 플레이 중 income을 관리하는 함수.
# 각 income source별로 multiplier를 불러오고 적용

signal income_changed()
signal source_multiplier_changed(source_id: String)
signal source_activation_changed(source_id: String, is_active: bool)


@export var sources: Array[IncomeSourceData] = [preload("res://data/starter_income.tres")]


# 플레이 중 Source multiplier
var source_multipliers: Dictionary = {}

# 플레이 중 활성화된 Source 저장
var source_active: Dictionary = {}


func _ready() -> void:
	reset_runtime_state()


func reset_runtime_state() -> void:
	source_multipliers.clear()
	source_active.clear()
	for source in sources:
		if source == null or source.id.is_empty():
			continue
		source_multipliers[source.id] = source.multiplier
		source_active[source.id] = false
	income_changed.emit()


# 소스 활성화
func activate_source(source_id: String) -> void:

	if not source_active.has(source_id):
		return

	if source_active[source_id]:
		return
	source_active[source_id] = true

	source_activation_changed.emit(source_id, true)
	income_changed.emit()


# 특정 source의 multiplier를 불러옴
func get_source_multiplier(source_id: String) -> float:

	if not source_multipliers.has(source_id):
		return 1.0

	return source_multipliers[source_id]


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


# income 계산
func get_source_income(source_id: String) -> float:

	if not source_active.get(source_id, false):
		return 0.0

	var source := get_source(source_id)

	if source == null:
		return 0.0

	var production_time := source.base_time * source.time_multiplier
	if production_time <= 0.0 or not is_finite(production_time):
		return 0.0
	return source.base_income / production_time * get_source_multiplier(source_id) * EconomyManager.get_global_multiplier()


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

	var income := get_total_income_per_second()

	if income <= 0:
		return

	EconomyManager.add_money(
		income * delta
	)
