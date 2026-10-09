extends Node2D

const CLOUD_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Cloud1.png"),
	preload("res://assets/sprites/Cloud2.png"),
]
const CLOUD_COUNT: int = 14
const MIN_SCALE: float = 0.22
const MAX_SCALE: float = 0.32
const MIN_SPEED: float = 8.0
const MAX_SPEED: float = 18.0
const MIN_HEIGHT: float = -1300.0
const MAX_HEIGHT: float = -300.0
const SCREEN_MARGIN: float = 500.0

@onready var camera := ErrorManager.require_node(self, ^"../../Camera2D", "Camera2D") as Camera2D

var _random := RandomNumberGenerator.new()
var _clouds: Array[Sprite2D] = []
var _speeds: Array[float] = []


func _ready() -> void:
	if camera == null:
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	_random.randomize()
	for _index in CLOUD_COUNT:
		var cloud := Sprite2D.new()
		cloud.texture = CLOUD_TEXTURES[_random.randi_range(0, CLOUD_TEXTURES.size() - 1)]
		cloud.scale = Vector2.ONE * _random.randf_range(MIN_SCALE, MAX_SCALE)
		cloud.position = Vector2(
			_random.randf_range(-_get_horizontal_range(), _get_horizontal_range()),
			_random.randf_range(MIN_HEIGHT, MAX_HEIGHT)
		)
		add_child(cloud)
		_clouds.append(cloud)
		_speeds.append(_random.randf_range(MIN_SPEED, MAX_SPEED))


func _process(delta: float) -> void:
	var half_view_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var left_edge := camera.global_position.x - half_view_width - SCREEN_MARGIN
	var right_edge := camera.global_position.x + half_view_width + SCREEN_MARGIN
	for index in _clouds.size():
		var cloud := _clouds[index]
		cloud.position.x += _speeds[index] * delta
		if cloud.position.x - cloud.texture.get_size().x * cloud.scale.x * 0.5 > right_edge:
			cloud.position.x = left_edge - _random.randf_range(0.0, 180.0)
			cloud.position.y = _random.randf_range(MIN_HEIGHT, MAX_HEIGHT)
			cloud.texture = CLOUD_TEXTURES[_random.randi_range(0, CLOUD_TEXTURES.size() - 1)]
			cloud.scale = Vector2.ONE * _random.randf_range(MIN_SCALE, MAX_SCALE)
			_speeds[index] = _random.randf_range(MIN_SPEED, MAX_SPEED)


func _get_horizontal_range() -> float:
	return get_viewport_rect().size.x * 0.5 / camera.zoom.x + SCREEN_MARGIN
