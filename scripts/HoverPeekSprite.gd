class_name HoverPeekSprite
extends Sprite2D

@export var peek_frames: SpriteFrames
@export var body_start_y: float = 62.0
@export var peek_scale: float = 0.56

var peek_frame: int = 0
var _target_frame: int = 0
var _elapsed: float = 0.0
var _introduction_playing: bool = false

signal introduction_finished()


func _ready() -> void:
	# Keep the original bin body in every frame; generated art supplies only its top.
	if texture == null or peek_frames == null or not peek_frames.has_animation(&"open"):
		ErrorManager.report_error("INVALID_ANIMATION", "고양이 짬통 애니메이션 이미지가 없습니다.", str(get_path()))
		set_process(false)
		return
	region_enabled = true
	region_rect = Rect2(0.0, body_start_y, texture.get_width(), texture.get_height() - body_start_y)
	offset = Vector2(0.0, body_start_y * 0.5)
	visibility_changed.connect(_on_visibility_changed)
	_reset()


func set_hovered(hovered: bool) -> void:
	if _introduction_playing:
		return
	if not is_visible_in_tree():
		_reset()
		return
	var target := peek_frames.get_frame_count(&"open") if hovered else 0
	if target != _target_frame:
		_target_frame = target
		_elapsed = 0.0
	set_process(peek_frame != _target_frame)


func _process(delta: float) -> void:
	var frame_seconds := 1.0 / peek_frames.get_animation_speed(&"open")
	_elapsed += delta
	while _elapsed >= frame_seconds and peek_frame != _target_frame:
		_elapsed -= frame_seconds
		peek_frame += 1 if _target_frame > peek_frame else -1
		queue_redraw()
	if peek_frame == _target_frame:
		_elapsed = 0.0
		set_process(false)
		if _introduction_playing:
			introduction_finished.emit()


func play_introduction() -> void:
	_reset()
	_introduction_playing = true
	_target_frame = peek_frames.get_frame_count(&"open")
	set_process(true)


func finish_introduction() -> void:
	_introduction_playing = false
	set_hovered(false)


func _draw() -> void:
	if texture == null or peek_frames == null:
		return
	var body_top := -texture.get_height() * 0.5 + body_start_y
	if peek_frame == 0:
		var lid_size := Vector2(texture.get_width(), body_start_y)
		draw_texture_rect_region(texture, Rect2(-texture.get_size() * 0.5, lid_size), Rect2(Vector2.ZERO, lid_size))
	else:
		var top_texture := peek_frames.get_frame_texture(&"open", peek_frame - 1)
		var top_size := top_texture.get_size() * peek_scale
		draw_texture_rect(top_texture, Rect2(Vector2(-top_size.x * 0.5, body_top - top_size.y), top_size), false)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_reset()


func _reset() -> void:
	_introduction_playing = false
	peek_frame = 0
	_target_frame = 0
	_elapsed = 0.0
	set_process(false)
	queue_redraw()
