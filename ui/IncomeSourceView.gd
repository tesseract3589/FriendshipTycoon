class_name IncomeSourceView
extends Node2D

@export var source_data: IncomeSourceData

@onready var sprite: Sprite2D = $Sprite
@onready var timer_label: Label = $TimerLabel


func _ready() -> void:
	if source_data == null:
		return

	sprite.texture = source_data.display_texture
	sprite.position = source_data.display_position
	sprite.scale = source_data.display_scale
	timer_label.position = source_data.display_position + source_data.timer_offset
	IncomeManager.source_activation_changed.connect(_on_source_activation_changed)
	IncomeManager.source_timer_changed.connect(_on_source_timer_changed)
	_set_active(IncomeManager.source_active.get(source_data.id, false))
	_update_timer(IncomeManager.get_source_time_remaining(source_data.id))


func _on_source_activation_changed(source_id: String, is_active: bool) -> void:
	if source_data != null and source_id == source_data.id:
		_set_active(is_active)


func _on_source_timer_changed(source_id: String, seconds_remaining: float) -> void:
	if source_data != null and source_id == source_data.id:
		_update_timer(seconds_remaining)


func _set_active(is_active: bool) -> void:
	sprite.visible = is_active
	timer_label.visible = is_active


func _update_timer(seconds_remaining: float) -> void:
	if seconds_remaining <= 0.0:
		timer_label.text = ""
		return
	timer_label.text = "%d초" % ceili(seconds_remaining)
