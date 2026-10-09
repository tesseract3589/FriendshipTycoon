class_name WorldUIMinimumScale
extends Node

## Keeps a world Control readable below the reference camera zoom.
@export_range(0.1, 2.5, 0.05) var minimum_zoom: float = 1.0

var _control: Control
var _base_scale: Vector2
var _base_position: Vector2
var _anchor_ratio: Vector2


static func attach(control: Control, anchor_ratio: Vector2) -> WorldUIMinimumScale:
	var limiter := WorldUIMinimumScale.new()
	limiter._control = control
	limiter._base_scale = control.scale
	limiter._base_position = control.position
	limiter._anchor_ratio = anchor_ratio
	control.add_child(limiter)
	limiter._update_scale()
	return limiter


func set_base_position(value: Vector2) -> void:
	_base_position = value
	_update_scale()


func _process(_delta: float) -> void:
	_update_scale()


func _update_scale() -> void:
	if not is_instance_valid(_control):
		return
	var canvas := _control.get_canvas_transform()
	var zoom := Vector2(canvas.x.length(), canvas.y.length())
	var compensation := Vector2(
		maxf(1.0, minimum_zoom / maxf(zoom.x, 0.001)),
		maxf(1.0, minimum_zoom / maxf(zoom.y, 0.001))
	)
	_control.scale = _base_scale * compensation
	# Scale around the chosen point without changing the Control's layout size.
	var anchor := _control.size * _anchor_ratio
	_control.position = _base_position + (_base_scale * anchor * (Vector2.ONE - compensation)).rotated(_control.rotation)
