class_name CloudLayer
extends Node2D

const CLOUD_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Cloud1.png"),
	preload("res://assets/sprites/Cloud2.png"),
]
const CLOUD_COUNT: int = 20
const REFERENCE_WORLD_WIDTH: float = 4000.0
const MIN_SCALE: float = 0.22
const MAX_SCALE: float = 0.32
const MIN_SPEED: float = 8.0
const MAX_SPEED: float = 18.0
const MIN_HEIGHT: float = -1300.0
const MAX_HEIGHT: float = -300.0
const WORLD_MARGIN: float = 500.0

var _random := RandomNumberGenerator.new()
var _clouds: Array[Sprite2D] = []
var _speeds: Array[float] = []
var _horizontal_bounds := Vector2.ZERO
var _has_bounds: bool = false


func _ready() -> void:
	_random.randomize()
	# Main supplies the full world range after validating the source layout.
	set_process(false)


func configure_world_bounds(camera_world_bounds: Vector2) -> void:
	var new_bounds := camera_world_bounds + Vector2(-WORLD_MARGIN, WORLD_MARGIN)
	var previous_bounds := _horizontal_bounds
	var had_bounds := _has_bounds
	if had_bounds:
		# A larger window may expose more world. Expand without moving existing clouds;
		# never shrink the loop back into a previously visible part of the world.
		new_bounds.x = minf(new_bounds.x, previous_bounds.x)
		new_bounds.y = maxf(new_bounds.y, previous_bounds.y)
	_horizontal_bounds = new_bounds
	_has_bounds = true
	var target_count := maxi(CLOUD_COUNT, ceili((new_bounds.y - new_bounds.x) / REFERENCE_WORLD_WIDTH * CLOUD_COUNT))
	var additional_count := target_count - _clouds.size()
	for index in additional_count:
		var x_position: float
		if not had_bounds:
			# Spread the initial clouds across the whole route instead of clustering.
			x_position = lerpf(new_bounds.x, new_bounds.y, (index + _random.randf()) / additional_count)
		else:
			# Populate newly added space only; existing clouds keep their positions.
			var left_extension := previous_bounds.x - new_bounds.x
			var right_extension := new_bounds.y - previous_bounds.y
			var offset := _random.randf() * (left_extension + right_extension)
			x_position = new_bounds.x + offset if offset < left_extension else previous_bounds.y + offset - left_extension
		_spawn_cloud(x_position)
	set_process(true)


func _spawn_cloud(x_position: float) -> void:
	var cloud := Sprite2D.new()
	_randomize_cloud(cloud)
	add_child(cloud)
	cloud.global_position = Vector2(x_position, _random.randf_range(MIN_HEIGHT, MAX_HEIGHT))
	_clouds.append(cloud)
	_speeds.append(_random.randf_range(MIN_SPEED, MAX_SPEED))


func _process(delta: float) -> void:
	for index in _clouds.size():
		var cloud := _clouds[index]
		cloud.global_position.x += _speeds[index] * delta
		if cloud.global_position.x - _get_half_width(cloud) > _horizontal_bounds.y:
			_randomize_cloud(cloud)
			# The entire new sprite starts beyond the leftmost possible view.
			cloud.global_position.x = _horizontal_bounds.x - _get_half_width(cloud) - _random.randf_range(0.0, 180.0)
			cloud.global_position.y = _random.randf_range(MIN_HEIGHT, MAX_HEIGHT)
			_speeds[index] = _random.randf_range(MIN_SPEED, MAX_SPEED)


func _randomize_cloud(cloud: Sprite2D) -> void:
	cloud.texture = CLOUD_TEXTURES[_random.randi_range(0, CLOUD_TEXTURES.size() - 1)]
	cloud.scale = Vector2.ONE * _random.randf_range(MIN_SCALE, MAX_SCALE)


func _get_half_width(cloud: Sprite2D) -> float:
	return cloud.texture.get_size().x * absf(cloud.global_scale.x) * 0.5
