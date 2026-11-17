class_name ColdMist
extends Node2D

@export var settings: ColdMistData

var _wisps: Array[Dictionary] = []
var _elapsed: float = 0.0
var _openness: float = 0.0


func _ready() -> void:
	if settings == null:
		set_process(false)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.random_seed
	for index in settings.wisp_count:
		_wisps.append({
			"origin": settings.emission_rect.position + Vector2(rng.randf(), rng.randf()) * settings.emission_rect.size,
			"phase": rng.randf(),
			"velocity": Vector2(rng.randf_range(settings.horizontal_speed.x, settings.horizontal_speed.y), rng.randf_range(settings.downward_speed.x, settings.downward_speed.y))
		})
	if get_parent().has_signal("openness_changed"):
		get_parent().connect("openness_changed", set_openness)
	visibility_changed.connect(_on_visibility_changed)
	set_openness(0.0)


func set_openness(amount: float) -> void:
	_openness = clampf(amount, 0.0, 1.0)
	if is_zero_approx(_openness):
		_elapsed = 0.0
	set_process(settings != null and _openness > 0.0 and is_visible_in_tree())
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed = fposmod(_elapsed + delta, settings.lifetime)
	queue_redraw()


func _draw() -> void:
	if settings == null or _openness <= 0.0:
		return
	for wisp in _wisps:
		var progress := fposmod(float(wisp.phase) + _elapsed / settings.lifetime, 1.0)
		var center: Vector2 = wisp.origin + wisp.velocity * progress * settings.lifetime
		var radius := lerpf(settings.radius_range.x, settings.radius_range.y, progress)
		var tint := settings.color
		tint.a *= sin(PI * progress) * _openness
		draw_set_transform(center, 0.0, Vector2(1.7, 0.48))
		# Nested translucent ellipses soften the edge without textures or particle churn.
		for ring in range(3, 0, -1):
			var layer_color := tint
			layer_color.a *= 0.22
			draw_circle(Vector2.ZERO, radius * float(ring) / 3.0, layer_color)
	draw_set_transform(Vector2.ZERO)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		set_openness(0.0)
