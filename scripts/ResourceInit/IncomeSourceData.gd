class_name IncomeSourceData
extends Resource


@export var id: String = ""
@export var source_name: String = ""

@export_category("Display")
@export var display_texture: Texture2D
@export var display_position: Vector2 = Vector2.ZERO
@export var display_scale: Vector2 = Vector2.ONE
# Tooltip template placeholders: {source_name}, {payout}, and {time}.
@export_multiline var tooltip_text: String = "{payout}원/{time}s"
@export var timer_offset: Vector2 = Vector2(0.0, -110.0)
@export var purchase_info_offset: Vector2 = Vector2(-60.0, 80.0)
@export var purchase_button_offset: Vector2 = Vector2(-60.0, 110.0)
@export var purchase_button_size: Vector2 = Vector2(120.0, 78.0)

# 생산량 (생산량 = base_income * multiplier)
@export_category("Income")
@export var base_income: float = 0.0
@export var multiplier: float = 1.0

# 생산 시간 (time초당 ~원, income source마다 달라짐)
@export_category("Time")
@export var base_time: float = 1.0
@export var time_multiplier: float = 1.0
