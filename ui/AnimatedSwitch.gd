@tool
class_name AnimatedSwitch
extends Button

## Reusable toggle: normal Button input/signals, separate track and sliding oval thumb.
@export var track_texture: Texture2D = preload("res://assets/sprites/Interfaces/switch_track.svg")
@export var thumb_texture: Texture2D = preload("res://assets/sprites/Interfaces/switch_thumb.svg")
@export_range(0.0, 1.0, 0.01) var animation_duration: float = 0.2
@export var off_track_color := Color("bfc2bd")
@export var on_track_color := Color("e3efd9")
@export var off_thumb_color := Color("aaaaa6")
@export var on_thumb_color := Color("99d34e")

var _motion: Tween
var _position: float = 0.0:
	set(value):
		_position = value
		queue_redraw()


func _ready() -> void:
	toggle_mode = true
	toggled.connect(_animate)
	visibility_changed.connect(_snap)
	_snap()


## Synchronize model state without emitting toggled or playing an entry animation.
func set_value_no_signal(enabled: bool) -> void:
	set_pressed_no_signal(enabled)
	_snap()


func _snap() -> void:
	if _motion != null:
		_motion.kill()
	_position = 1.0 if button_pressed else 0.0


func _animate(enabled: bool) -> void:
	if _motion != null:
		_motion.kill()
	_motion = create_tween()
	_motion.tween_property(self, "_position", 1.0 if enabled else 0.0, animation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if track_texture == null or thumb_texture == null:
		return
	var fit := minf(size.x / 112.0, size.y / 60.0)
	var origin := (size - Vector2(112.0, 60.0) * fit) * 0.5
	var tint := Color(1, 1, 1, 0.45) if disabled else Color.WHITE
	draw_texture_rect(track_texture, Rect2(origin, Vector2(112, 60) * fit), false, off_track_color.lerp(on_track_color, _position) * tint)
	var thumb_origin := origin + Vector2(58.0 * _position, 0) * fit
	draw_texture_rect(thumb_texture, Rect2(thumb_origin, Vector2(54, 60) * fit), false, off_thumb_color.lerp(on_thumb_color, _position) * tint)
