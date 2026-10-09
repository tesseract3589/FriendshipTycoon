class_name SizePopMotion
extends RefCounted

const DEFAULT_OVERSHOOT: float = 1.1
const DEFAULT_POP_DURATION: float = 0.1
const DEFAULT_SETTLE_DURATION: float = 0.05
const SCALE_METADATA: StringName = &"_size_pop_scale"
const TWEEN_METADATA: StringName = &"_size_pop_tween"


static func play(
	visuals: Array[Node2D],
	overshoot: float = DEFAULT_OVERSHOOT,
	pop_duration: float = DEFAULT_POP_DURATION,
	settle_duration: float = DEFAULT_SETTLE_DURATION
) -> void:
	for visual in visuals:
		if not ErrorManager.validate_instance(visual, "SizePopMotion.play"):
			continue
		var final_scale: Vector2 = visual.get_meta(SCALE_METADATA, visual.scale)
		var previous_tween: Tween
		if visual.has_meta(TWEEN_METADATA):
			previous_tween = visual.get_meta(TWEEN_METADATA) as Tween
		if previous_tween != null and previous_tween.is_valid():
			previous_tween.kill()
		visual.set_meta(SCALE_METADATA, final_scale)
		visual.scale = Vector2.ZERO
		var tween := visual.create_tween()
		visual.set_meta(TWEEN_METADATA, tween)
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "scale", final_scale * overshoot, pop_duration)
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "scale", final_scale, settle_duration)
		tween.tween_callback(_clear_motion_metadata.bind(visual))


static func _clear_motion_metadata(visual: Node2D) -> void:
	visual.remove_meta(SCALE_METADATA)
	visual.remove_meta(TWEEN_METADATA)
