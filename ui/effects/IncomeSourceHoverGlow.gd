extends Node2D

const BORDER_COLOR := Color(1.0, 0.78, 0.3)
const GLINT_COLOR := Color(1.0, 0.97, 0.78)
const FADE_SPEED: float = 8.0
const GLINT_SPEED: float = 150.0

var _bounds := Rect2()
var _hovered: bool = false
var _strength: float = 0.0
var _elapsed: float = 0.0


func _init() -> void:
	visible = false
	set_process(false)


func setup(bounds: Rect2) -> void:
	_bounds = bounds


func set_hovered(hovered: bool) -> void:
	if _hovered == hovered:
		return
	_hovered = hovered
	if hovered:
		_elapsed = 0.0
		show()
	set_process(true)


func clear() -> void:
	_hovered = false
	_strength = 0.0
	hide()
	set_process(false)


func _process(delta: float) -> void:
	_strength = move_toward(_strength, 1.0 if _hovered else 0.0, delta * FADE_SPEED)
	_elapsed += delta
	queue_redraw()
	if not _hovered and is_zero_approx(_strength):
		clear()


func _draw() -> void:
	if _strength <= 0.0 or not _bounds.has_area():
		return
	# Draw in viewport pixels so zooming never makes the border too thick or thin.
	var canvas_transform := get_global_transform_with_canvas()
	var bounds: Rect2 = canvas_transform * _bounds
	draw_set_transform_matrix(canvas_transform.affine_inverse())
	var pulse := 0.8 + 0.2 * sin(_elapsed * TAU * 1.2)
	var corners := PackedVector2Array([
		bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end,
		Vector2(bounds.position.x, bounds.end.y), bounds.position
	])
	for width in [10.0, 5.0, 1.5]:
		var alpha := 0.08 if width > 5.0 else (0.18 if width > 2.0 else 0.85)
		draw_polyline(corners, Color(BORDER_COLOR, alpha * pulse * _strength), width, true)
	var perimeter := 2.0 * (bounds.size.x + bounds.size.y)
	var head := fposmod(_elapsed * GLINT_SPEED, perimeter)
	var trail_length := minf(52.0, perimeter * 0.25)
	for step in range(16):
		var progress := float(step) / 16.0
		var start := _border_point(bounds, head - trail_length * (1.0 - progress))
		var end := _border_point(bounds, head - trail_length * (1.0 - float(step + 1) / 16.0))
		draw_line(start, end, Color(GLINT_COLOR, progress * _strength), 2.5, true)
	var tip := _border_point(bounds, head)
	draw_circle(tip, 4.0, Color(BORDER_COLOR, 0.22 * _strength), true, -1.0, true)
	draw_line(tip - Vector2(4.0, 0.0), tip + Vector2(4.0, 0.0), Color(GLINT_COLOR, _strength), 1.5, true)
	draw_line(tip - Vector2(0.0, 4.0), tip + Vector2(0.0, 4.0), Color(GLINT_COLOR, _strength), 1.5, true)


func _border_point(bounds: Rect2, distance: float) -> Vector2:
	var offset := fposmod(distance, 2.0 * (bounds.size.x + bounds.size.y))
	if offset < bounds.size.x:
		return bounds.position + Vector2(offset, 0.0)
	offset -= bounds.size.x
	if offset < bounds.size.y:
		return Vector2(bounds.end.x, bounds.position.y + offset)
	offset -= bounds.size.y
	if offset < bounds.size.x:
		return bounds.end - Vector2(offset, 0.0)
	return Vector2(bounds.position.x, bounds.end.y - (offset - bounds.size.x))
