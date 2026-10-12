extends Control

const ARROW_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Arrow1.png")
const DISPLAY_DURATION_MS: int = 50000
const ARROW_WIDTH: float = 72.0
const EDGE_INSET: float = 64.0
const SHORT_SCALE := Vector2(0.72, 1.12)
const LONG_SCALE := Vector2(1.18, 0.94)

class Guidance:
	var target: Control
	var arrow: Node2D
	var expires_at_ms: int

var _indicators: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func point_to_button(target: Control) -> void:
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	var viewport_rect := get_viewport_rect()
	if viewport_rect.intersects(_get_button_screen_rect(target)):
		return
	if _indicators.has(target):
		_remove_indicator(target)
	var guidance := Guidance.new()
	guidance.target = target
	guidance.expires_at_ms = Time.get_ticks_msec() + DISPLAY_DURATION_MS
	guidance.arrow = Node2D.new()
	add_child(guidance.arrow)
	var sprite := Sprite2D.new()
	sprite.texture = ARROW_TEXTURE
	sprite.scale = Vector2.ONE * ARROW_WIDTH / ARROW_TEXTURE.get_width()
	guidance.arrow.add_child(sprite)
	_play_bounce(sprite)
	_indicators[target] = guidance
	_update_indicator(guidance, viewport_rect)
	set_process(true)


func _process(_delta: float) -> void:
	var viewport_rect := get_viewport_rect()
	for target in _indicators.keys():
		var guidance: Guidance = _indicators[target]
		if (
			not is_instance_valid(guidance.target)
			or not guidance.target.is_visible_in_tree()
			or Time.get_ticks_msec() >= guidance.expires_at_ms
			or viewport_rect.intersects(_get_button_screen_rect(guidance.target))
		):
			_remove_indicator(target)
			continue
		_update_indicator(guidance, viewport_rect)
	if _indicators.is_empty():
		set_process(false)


func _get_button_screen_rect(target: Control) -> Rect2:
	# Include the live camera transform and the button's minimum readable scale.
	return target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)


func _update_indicator(guidance: Guidance, viewport_rect: Rect2) -> void:
	var center := viewport_rect.get_center()
	var direction := _get_button_screen_rect(guidance.target).get_center() - center
	var inset := minf(EDGE_INSET, minf(viewport_rect.size.x, viewport_rect.size.y) * 0.25)
	var half_size := viewport_rect.size * 0.5 - Vector2.ONE * inset
	var edge_distance := minf(
		half_size.x / maxf(absf(direction.x), 0.001),
		half_size.y / maxf(absf(direction.y), 0.001)
	)
	# Convert viewport coordinates to this HUD's coordinates, independent of zoom.
	var hud_inverse := get_global_transform_with_canvas().affine_inverse()
	guidance.arrow.position = hud_inverse * (center + direction * edge_distance)
	guidance.arrow.rotation = hud_inverse.basis_xform(direction).angle()


func _play_bounce(sprite: Sprite2D) -> void:
	var base_scale := sprite.scale
	sprite.scale = base_scale * SHORT_SCALE
	var bounce := sprite.create_tween().set_loops()
	# elastic stretch, a longer extended hold, then soft squash.
	bounce.tween_property(sprite, "scale", base_scale * LONG_SCALE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# bounce.tween_interval(0.50)
	bounce.tween_property(sprite, "scale", base_scale * SHORT_SCALE, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _remove_indicator(target: Variant) -> void:
	var guidance: Guidance = _indicators[target]
	guidance.arrow.hide()
	# The sprite-bound Tween is stopped automatically when the arrow is freed.
	guidance.arrow.queue_free()
	_indicators.erase(target)
