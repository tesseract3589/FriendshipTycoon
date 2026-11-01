class_name DepartureLoopSprite
extends Sprite2D

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")

enum Phase { DRIVING, WAITING, FADING }

@export var motion: DepartureMotionData
@export var render_layer: RENDER_ORDER.WorldLayer = RENDER_ORDER.WorldLayer.OBJECT

var _active: bool = false
var _spawn_position: Vector2
var _speed: float = 0.0
var _elapsed: float = 0.0
var _phase: Phase = Phase.FADING
var _hover_areas: Array[Area2D] = []
var _hover_transforms: Array[Transform2D] = []
var _travel_bounds_provider: Callable

signal world_hover_availability_changed()


func _ready() -> void:
	_spawn_position = position
	RENDER_ORDER.apply_world_layer(self, render_layer)
	set_process(false)


func configure_world_hover_areas(areas: Array[Area2D], reference_transform: Transform2D) -> void:
	_hover_areas = areas.duplicate()
	_hover_transforms.clear()
	for area in _hover_areas:
		_hover_transforms.append(reference_transform.affine_inverse() * area.global_transform)


func set_purchase_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	position = _spawn_position
	_speed = 0.0
	_elapsed = 0.0
	_phase = Phase.FADING
	self_modulate.a = 0.0 if active else 1.0
	_sync_hover_areas()
	set_process(active and motion != null)


func is_world_hover_enabled() -> bool:
	return _active and _phase == Phase.DRIVING


func set_travel_bounds_provider(provider: Callable) -> void:
	_travel_bounds_provider = provider


func _process(delta: float) -> void:
	if not _active or motion == null:
		return
	match _phase:
		Phase.FADING:
			_elapsed += delta
			self_modulate.a = minf(_elapsed / motion.fade_duration, 1.0)
			if _elapsed >= motion.fade_duration:
				_phase = Phase.DRIVING
				_elapsed = 0.0
				world_hover_availability_changed.emit()
		Phase.DRIVING:
			var multiplier := _get_drive_speed_multiplier()
			var maximum_speed := motion.maximum_speed * multiplier
			var acceleration := motion.acceleration * multiplier
			# A restored save or reduced bonus must obey the current visual cap immediately.
			_speed = minf(_speed, maximum_speed)
			# Integrate acceleration up to the cap, then cruise for the rest of this frame.
			var accelerating_time := minf(delta, maxf(0.0, (maximum_speed - _speed) / acceleration))
			var distance := _speed * accelerating_time + 0.5 * acceleration * accelerating_time * accelerating_time
			_speed = minf(_speed + acceleration * accelerating_time, maximum_speed)
			distance += _speed * (delta - accelerating_time)
			# Purchase visuals inherit the layout's scale. Drive in world pixels so
			# resizing the artwork does not change its acceleration or cruise speed.
			global_position.x += distance
			if _has_reached_travel_end():
				_phase = Phase.WAITING
				_elapsed = 0.0
				self_modulate.a = 0.0
				world_hover_availability_changed.emit()
		Phase.WAITING:
			_elapsed += delta
			if _elapsed >= motion.respawn_delay:
				position = _spawn_position
				_speed = 0.0
				_elapsed = 0.0
				_phase = Phase.FADING
	_sync_hover_areas()


func _get_drive_speed_multiplier() -> float:
	var source_multiplier := 1.0
	if not motion.speed_source_id.is_empty():
		var source_speed: float = IncomeManager.source_speed_multipliers.get(motion.speed_source_id, 1.0)
		source_multiplier = source_speed / motion.source_speed_baseline
	# Use the same effective global speed as production, including developer/future
	# prestige bonuses. Read live values so save restoration needs no extra signals.
	var global_multiplier := EconomyManager.get_global_time_multiplier() / motion.global_speed_baseline
	return clampf(source_multiplier * global_multiplier, 0.0, motion.maximum_speed_multiplier)


func _has_reached_travel_end() -> bool:
	if position.x <= _spawn_position.x or not _travel_bounds_provider.is_valid():
		return false
	# Use the same outer world edge as the scroll clamp, independently of camera
	# pan/zoom. Keep driving until even the rear has cleared that edge.
	var bounds: Vector2 = _travel_bounds_provider.call()
	var world_rect := global_transform * get_rect()
	return world_rect.position.x > bounds.y + motion.world_exit_margin


func _sync_hover_areas() -> void:
	for index in range(_hover_areas.size()):
		if is_instance_valid(_hover_areas[index]):
			_hover_areas[index].global_transform = global_transform * _hover_transforms[index]
