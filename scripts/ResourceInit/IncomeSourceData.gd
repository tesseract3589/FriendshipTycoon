class_name IncomeSourceData
extends Resource


@export var id: String = ""
@export var source_name: String = ""

# 생산량 (생산량 = base_income * multiplier)
@export_category("Income")
@export var base_income: float = 0.0
@export var multiplier: float = 1.0

# 생산 시간 (time초당 ~원, income source마다 달라짐)
@export_category("Time")
@export var base_time: float = 1.0
@export var time_multiplier: float = 1.0
