class_name JjamCatEffect
extends Node2D

@onready var sprite: Sprite2D = $Sprite

var _origin := Vector2.ZERO
var _curve := Vector2.ZERO
var _destination: Callable
var _base_scale := Vector2.ONE
var _initial_rotation: float = 0.0


func play(origin: Vector2, destination: Callable, settings: JjamCatEffectData, rng: RandomNumberGenerator) -> void:
	_origin = origin
	_destination = destination
	position = origin
	_curve = origin + Vector2(rng.randf_range(-160.0, 160.0), rng.randf_range(-180.0, -80.0))
	var height := rng.randf_range(settings.size_range.x, settings.size_range.y)
	_base_scale = Vector2.ONE * height / sprite.texture.get_height()
	_initial_rotation = rng.randf_range(-0.45, 0.45)
	sprite.rotation = _initial_rotation
	sprite.scale = Vector2.ZERO
	var tween := create_tween()
	tween.tween_method(_pop, 0.0, 1.0, settings.pop_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(_absorb, 0.0, 1.0, settings.absorption_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _pop(progress: float) -> void:
	sprite.scale = _base_scale * progress


func _absorb(progress: float) -> void:
	if not _destination.is_valid():
		queue_free()
		return
	# A moving destination keeps the effect aligned during resizes and hover tweens.
	var target: Vector2 = _destination.call()
	var remaining := 1.0 - progress
	position = remaining * remaining * _origin + 2.0 * remaining * progress * _curve + progress * progress * target
	sprite.scale = _base_scale * (1.0 - smoothstep(0.25, 1.0, progress))
	sprite.rotation = lerpf(_initial_rotation, 0.0, progress)
	modulate.a = 1.0 - smoothstep(0.85, 1.0, progress)
