class_name IncomeSourceView
extends Node2D

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")

@export var source_data: IncomeSourceData

@onready var sprite: Sprite2D = $Sprite
@onready var hover_area: Area2D = $HoverArea
@onready var hover_collision: CollisionShape2D = $HoverArea/CollisionShape2D
@onready var timer_label: Label = $TimerLabel

var source_is_active: bool = false
var _is_pointer_over_source: bool = false
var _display_position: Vector2 = Vector2.ZERO
var _display_scale: Vector2 = Vector2.ONE


func setup(data: IncomeSourceData, display_position: Vector2, display_scale: Vector2) -> void:
	source_data = data
	_display_position = display_position
	_display_scale = display_scale


func _ready() -> void:
	if source_data == null:
		return

	sprite.position = _display_position
	sprite.scale = _display_scale
	hover_area.position = _display_position
	hover_area.scale = _display_scale
	hover_area.input_pickable = true
	if source_data.display_texture != null:
		var hover_shape := RectangleShape2D.new()
		hover_shape.size = source_data.display_texture.get_size()
		hover_collision.shape = hover_shape
	timer_label.position = _display_position + source_data.timer_offset
	timer_label.z_as_relative = false
	timer_label.z_index = 40
	_style_text_label(timer_label)
	hover_area.mouse_entered.connect(_on_mouse_entered_source)
	hover_area.mouse_exited.connect(_on_mouse_exited_source)
	IncomeManager.source_activation_changed.connect(_on_source_activation_changed)
	IncomeManager.source_timer_changed.connect(_on_source_timer_changed)
	IncomeManager.source_multiplier_changed.connect(_on_source_multiplier_changed)
	IncomeManager.source_speed_multiplier_changed.connect(_on_source_speed_multiplier_changed)
	EconomyManager.multiplier_changed.connect(_on_multiplier_changed)
	_set_active(IncomeManager.source_active.get(source_data.id, false))
	_update_timer(IncomeManager.get_source_time_remaining(source_data.id))


func _on_source_activation_changed(source_id: String, is_active: bool) -> void:
	if source_data != null and source_id == source_data.id:
		_set_active(is_active)


func _on_source_timer_changed(source_id: String, seconds_remaining: float) -> void:
	if source_data != null and source_id == source_data.id:
		_update_timer(seconds_remaining)


func _set_active(is_active: bool) -> void:
	source_is_active = is_active
	sprite.visible = is_active
	hover_area.visible = is_active and source_data.display_texture != null
	hover_area.input_pickable = is_active
	timer_label.visible = is_active
	if not is_active:
		_is_pointer_over_source = false
		TooltipManager.hide_tooltip(source_data.id)


func _update_timer(seconds_remaining: float) -> void:
	if seconds_remaining <= 0.0:
		timer_label.text = ""
		return
	var production_time := IncomeManager.get_source_production_time(source_data.id)
	if production_time < 0.1:
		timer_label.text = "매 %.2f초" % production_time
	elif seconds_remaining >= 10.0:
		timer_label.text = "%ds" % ceili(seconds_remaining)
	elif seconds_remaining >= 1.0:
		timer_label.text = "%.1fs" % seconds_remaining
	else:
		timer_label.text = "%.2fs" % maxf(seconds_remaining, 0.01)


func _get_source_info() -> String:
	var production_time := IncomeManager.get_source_production_time(source_data.id)
	var payout := IncomeManager.get_source_cycle_payout(source_data.id)
	return source_data.tooltip_text \
		.replace("{source_name}", source_data.source_name) \
		.replace("{payout}", NUMBER_FORMATTER.format_number(payout)) \
		.replace("{time}", NUMBER_FORMATTER.format_number(production_time))


func _style_text_label(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 1.0))
	label.add_theme_constant_override("outline_size", 3)


func _on_mouse_entered_source() -> void:
	_is_pointer_over_source = true
	_refresh_tooltip()


func _on_mouse_exited_source() -> void:
	_is_pointer_over_source = false
	TooltipManager.hide_tooltip(source_data.id)


func _refresh_tooltip() -> void:
	if not source_is_active or not _is_pointer_over_source:
		return
	TooltipManager.show_tooltip(_get_source_info(), source_data.id)


func _on_source_multiplier_changed(changed_source_id: String) -> void:
	if source_data != null and changed_source_id == source_data.id:
		_refresh_tooltip()


func _on_source_speed_multiplier_changed(changed_source_id: String) -> void:
	if source_data != null and changed_source_id == source_data.id:
		_refresh_tooltip()


func _on_multiplier_changed() -> void:
	_refresh_tooltip()
