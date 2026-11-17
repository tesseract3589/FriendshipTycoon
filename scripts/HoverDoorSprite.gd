class_name HoverDoorSprite
extends AnimatedSprite2D

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")

@export var motion: HoverDoorMotionData
@export var render_layer: RENDER_ORDER.WorldLayer = RENDER_ORDER.WorldLayer.OBJECT

var _active: bool = false
var _target_open: bool = false
var _pose: float = 0.0

signal openness_changed(amount: float)


func _ready() -> void:
	RENDER_ORDER.apply_world_layer(self, render_layer)
	if motion == null or sprite_frames == null or not sprite_frames.has_animation(motion.animation) or motion.open_frame <= motion.closed_frame or motion.open_frame >= sprite_frames.get_frame_count(motion.animation):
		ErrorManager.report_error("INVALID_ANIMATION", "문 열기 애니메이션 설정이 올바르지 않습니다.", str(get_path()))
		set_process(false)
		return
	animation = motion.animation
	visibility_changed.connect(_on_visibility_changed)
	_reset()


func set_purchase_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	if not active:
		_reset()


func set_hovered(hovered: bool) -> void:
	if not _active or not is_visible_in_tree():
		_reset()
		return
	# Reversals retain the fractional pose; no queued tweens or restart delays.
	_target_open = hovered
	set_process(not is_equal_approx(_pose, _get_target_pose()))


func _process(delta: float) -> void:
	_pose = move_toward(_pose, _get_target_pose(), motion.frames_per_second * delta)
	_apply_pose()
	if is_equal_approx(_pose, _get_target_pose()):
		set_process(false)


func get_open_amount() -> float:
	if motion == null:
		return 0.0
	return clampf((_pose - motion.closed_frame) / (motion.open_frame - motion.closed_frame), 0.0, 1.0)


func _get_target_pose() -> float:
	return float(motion.open_frame if _target_open else motion.closed_frame)


func _apply_pose() -> void:
	pause()
	set_frame_and_progress(roundi(_pose), 0.0)
	openness_changed.emit(get_open_amount())


func _reset() -> void:
	_target_open = false
	set_process(false)
	if motion != null and sprite_frames != null and sprite_frames.has_animation(motion.animation):
		_pose = float(motion.closed_frame)
		_apply_pose()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_reset()
