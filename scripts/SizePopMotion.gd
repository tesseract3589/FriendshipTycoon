class_name SizePopMotion
extends RefCounted

const DEFAULT_OVERSHOOT: float = 1.1
const DEFAULT_POP_DURATION: float = 0.1
const DEFAULT_SETTLE_DURATION: float = 0.05


static func play(
	visuals: Array[Node2D],
	overshoot: float = DEFAULT_OVERSHOOT,
	pop_duration: float = DEFAULT_POP_DURATION,
	settle_duration: float = DEFAULT_SETTLE_DURATION
) -> void:
	for visual in visuals:
		if not is_instance_valid(visual):
			continue
		var final_scale := visual.scale
		visual.scale = Vector2.ZERO
		var tween := visual.create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "scale", final_scale * overshoot, pop_duration)
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "scale", final_scale, settle_duration)
