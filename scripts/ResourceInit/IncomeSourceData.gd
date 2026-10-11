class_name IncomeSourceData
extends Resource

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")

@export var id: String = ""
@export var source_name: String = ""

@export_category("Display")
@export var display_texture: Texture2D
@export var display_position: Vector2 = Vector2.ZERO
@export var display_scale: Vector2 = Vector2.ONE
# Tooltip template placeholders: {source_name}, {payout}, {time} (with unit), {income_per_second}.
@export_multiline var tooltip_text: String = "{payout}원/{time}\n초당 {income_per_second}원"
@export var timer_offset: Vector2 = Vector2(0.0, -110.0)

# 생산량: 기본 수입에 레벨별 증가율을 누적한 뒤 수입 배율을 적용한다.
@export_category("Income")
@export var base_income: float = 0.0
@export var multiplier: float = 1.0
@export var upgrade_base_cost: float = 10.0
## 가격 = 초기 가격 * (1 + linear_growth * 업그레이드 횟수) * 2^(업그레이드 횟수 / doubling_levels).
@export var upgrade_cost_linear_growth: float = 0.8
@export var upgrade_cost_doubling_levels: float = 4.0

@export_category("Upgrade Income")
## 첫 업그레이드의 수입 증가율. 0.3이면 기본 회당 수입의 +30%, 1.0이면 +100%.
@export var upgrade_first_income_ratio: float = 0.3
## 현재 수입 대비 증가율 = first_income_ratio / (1 + decay * (현재 레벨 - 1)).
## 값이 클수록 다음 레벨부터 증가율이 빠르게 낮아진다. 0이면 매번 같은 증가율.
@export var upgrade_income_decay: float = 4.0

# 생산 시간 (time초당 ~원, income source마다 달라짐)
@export_category("Time")
@export var base_time: float = 1.0
@export var time_multiplier: float = 1.0


func get_tooltip_text(template_override: String = "") -> String:
	var template := tooltip_text if template_override.is_empty() else template_override
	if not template.contains("{income_per_second}"):
		if not template.is_empty():
			template += "\n"
		template += "초당 {income_per_second}원"
	var production_time := NUMBER_FORMATTER.format_time(IncomeManager.get_source_production_time(id))
	return template \
		.replace("{source_name}", source_name) \
		.replace("{payout}", NUMBER_FORMATTER.format_number(IncomeManager.get_source_cycle_payout(id))) \
		.replace("{time}s", production_time) \
		.replace("{time}초", production_time) \
		.replace("{time}", production_time) \
		.replace("{income_per_second}", NUMBER_FORMATTER.format_income_per_second(IncomeManager.get_source_income_unrounded(id)))
