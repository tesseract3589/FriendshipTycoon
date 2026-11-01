@tool
extends Node2D

@export var window_size: Vector2 = Vector2(197.0, 453.0)
@export var corner_radius: float = 34.0
@export_range(1, 32, 1) var bubble_count: int = 12
@export var bubble_seed: int = 1
@export var rise_speed: Vector2 = Vector2(35.0, 65.0)
@export var radius_range: Vector2 = Vector2(3.0, 7.0)
@export var sway: float = 5.0
@export var line_width: float = 2.0
@export var bubble_color: Color = Color(0.82, 0.97, 1.0, 0.85)

var _bubbles: Array[Dictionary] = []


func _ready() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = bubble_seed
	_bubbles.clear()
	for index in range(bubble_count):
		_bubbles.append({
			"radius": random.randf_range(radius_range.x, radius_range.y),
			"x": random.randf_range(-window_size.x * 0.4, window_size.x * 0.4),
			"progress": random.randf(),
			"speed": random.randf_range(rise_speed.x, rise_speed.y),
			"phase": random.randf() * TAU,
		})
	# The editor shows a still preview; game instances animate independently.
	set_process(not Engine.is_editor_hint())
	queue_redraw()


func _process(delta: float) -> void:
	for bubble in _bubbles:
		var travel := window_size.y - 2.0 * (float(bubble.radius) + line_width * 0.5)
		bubble.progress = fposmod(float(bubble.progress) + delta * float(bubble.speed) / travel, 1.0)
	queue_redraw()


func _bubble_position(bubble: Dictionary) -> Vector2:
	var margin := float(bubble.radius) + line_width * 0.5
	var half := window_size * 0.5
	var progress := float(bubble.progress)
	var y := lerpf(half.y - margin, -half.y + margin, progress)
	var max_x := half.x - margin
	var corner_y := half.y - corner_radius
	if absf(y) > corner_y:
		var inner_radius := maxf(0.0, corner_radius - margin)
		var dy := absf(y) - corner_y
		max_x = half.x - corner_radius + sqrt(maxf(0.0, inner_radius * inner_radius - dy * dy))
	var x := float(bubble.x) + sin(progress * TAU * 2.0 + float(bubble.phase)) * sway
	return Vector2(clampf(x, -max_x, max_x), y)


func _draw() -> void:
	for bubble in _bubbles:
		var progress := float(bubble.progress)
		var fade := minf(clampf(progress / 0.08, 0.0, 1.0), clampf((1.0 - progress) / 0.15, 0.0, 1.0))
		var outline := bubble_color
		outline.a *= fade
		var fill := outline
		fill.a *= 0.18
		var center := _bubble_position(bubble)
		var radius := float(bubble.radius)
		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0.0, TAU, 24, outline, line_width, true)
