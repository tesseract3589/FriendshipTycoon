class_name JjamPrestigePresentation
extends Node

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const CAT_EFFECT_DATA = preload("res://data/effects/jjam_prestige_cats.tres")

@export var prestige_cat_effect: JjamCatEffectData = CAT_EFFECT_DATA

var _main: Node2D
var _camera: Camera2D
var _tween: Tween
var _generation: int = 0
var _original_zoom := Vector2.ONE
var _peek: HoverPeekSprite
var _hidden_layers: Dictionary = {}
var _hidden_controls: Dictionary = {}
var _transition_layer: CanvasLayer
var _shade: ColorRect
var _effect_container: Node2D
var _effect_emitter: Tween
var _rng := RandomNumberGenerator.new()


func setup(main: Node2D, camera: Camera2D) -> void:
	_main = main
	_camera = camera


func _ready() -> void:
	_rng.randomize()
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = RENDER_ORDER.ScreenLayer.EVENT + 1
	add_child(_transition_layer)
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shade.mouse_force_pass_scroll_events = false
	_shade.hide()
	_transition_layer.add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_effect_container = Node2D.new()
	_effect_container.name = "PrestigeCatEffects"
	_transition_layer.add_child(_effect_container)
	EventManager.event_started.connect(_on_event_started)
	EventManager.event_state_restored.connect(_cancel)
	PrestigeManager.prestige_animation_requested.connect(_animate_prestige)
	EventManager.set_jjamtong_intro_ui_available(true)


func _on_event_started(data: GameEventData) -> void:
	if data.id != EventManager.JJAMTONG_INTRO_ID:
		return
	_generation += 1
	_original_zoom = _camera.zoom
	_lock()
	_hide_ui()
	# Purchase pop finishes before measuring the bin's actual world size.
	_tween = create_tween()
	_tween.tween_interval(0.18)
	_tween.tween_callback(_focus_bin.bind(_generation))


func _focus_bin(generation: int) -> void:
	if generation != _generation:
		return
	_peek = _main.get_jjamtong_visual() as HoverPeekSprite
	if not is_instance_valid(_peek):
		_end_intro()
		return
	var texture_size := _peek.texture.get_size()
	var head := _peek.peek_frames.get_frame_texture(&"open", _peek.peek_frames.get_frame_count(&"open") - 1)
	var top := -texture_size.y * 0.5 + _peek.body_start_y - head.get_height() * _peek.peek_scale
	var local_bounds := Rect2(Vector2(-texture_size.x * 0.5, top), Vector2(texture_size.x, texture_size.y * 0.5 - top))
	var bounds: Rect2 = _peek.global_transform * local_bounds
	var viewport_size := _main.get_viewport_rect().size
	var zoom := clampf(minf(viewport_size.x * 0.7 / bounds.size.x, viewport_size.y * 0.74 / bounds.size.y), 0.4, 4.0)
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_camera, "global_position", bounds.get_center(), 0.7)
	_tween.tween_property(_camera, "zoom", Vector2.ONE * zoom, 0.7)
	_tween.chain().tween_callback(_start_peek.bind(generation))


func _start_peek(generation: int) -> void:
	if generation != _generation or not is_instance_valid(_peek):
		return
	_peek.introduction_finished.connect(_on_peek_finished.bind(generation), CONNECT_ONE_SHOT)
	_peek.play_introduction()


func _on_peek_finished(generation: int) -> void:
	if generation != _generation:
		return
	# Compute a valid return position at the old zoom, then interpolate both.
	var position := _camera.global_position
	var zoom := _camera.zoom
	_camera.zoom = _original_zoom
	_main.clamp_camera_after_presentation()
	var destination := _camera.global_position
	_camera.zoom = zoom
	_camera.global_position = position
	_tween = create_tween()
	_tween.tween_interval(1.0)
	_tween.tween_property(_camera, "zoom", _original_zoom, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_camera, "global_position", destination, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_end_intro)


func _end_intro() -> void:
	if is_instance_valid(_peek):
		_peek.finish_introduction()
	_main.clamp_camera_after_presentation()
	_restore_ui()
	_unlock()
	EventManager.finish_event(EventManager.JJAMTONG_INTRO_ID, "completed")


func _animate_prestige() -> void:
	_generation += 1
	_clear_cat_effects()
	_lock()
	_shade.color.a = 0.0
	_shade.show()
	_tween = create_tween()
	_tween.tween_property(_shade, "color:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_commit_prestige)
	_tween.tween_interval(0.3)
	_tween.tween_property(_shade, "color:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_finish_prestige)


func _commit_prestige() -> void:
	PrestigeManager.jjam_prestige()
	RightPanelManager.close_all()
	_main.reset_camera_to_initial()


func _finish_prestige() -> void:
	_shade.hide()
	PrestigeManager.transition_in_progress = false
	PrestigeManager.jjam_changed.emit()
	_unlock()
	_show_cat_absorption()


func _show_cat_absorption() -> void:
	if prestige_cat_effect == null or prestige_cat_effect.effect_scene == null:
		return
	var count: int = prestige_cat_effect.count
	var interval: float = prestige_cat_effect.spawn_duration / maxf(1.0, count - 1.0)
	_effect_emitter = create_tween()
	for index in range(count):
		if index > 0:
			_effect_emitter.tween_interval(interval)
		_effect_emitter.tween_callback(_spawn_cat)


func _spawn_cat() -> void:
	var effect := prestige_cat_effect.effect_scene.instantiate() as JjamCatEffect
	if effect == null:
		return
	var viewport_size := _main.get_viewport_rect().size
	var margin := viewport_size.min(Vector2.ONE * 640.0) * 0.1
	var origin := Vector2(
		_rng.randf_range(margin.x, viewport_size.x - margin.x),
		_rng.randf_range(margin.y, viewport_size.y - margin.y)
	)
	_effect_container.add_child(effect)
	effect.play(origin, _get_prestige_entry_center, prestige_cat_effect, _rng)


func _get_prestige_entry_center() -> Vector2:
	var entry := get_tree().get_first_node_in_group("jjam_prestige_entry") as Control
	if is_instance_valid(entry):
		return entry.get_global_transform_with_canvas() * (entry.size * 0.5)
	var viewport_size := _main.get_viewport_rect().size
	return Vector2(viewport_size.x - 69.0, viewport_size.y * 0.5)


func _clear_cat_effects() -> void:
	if _effect_emitter != null:
		_effect_emitter.kill()
	if is_instance_valid(_effect_container):
		for effect in _effect_container.get_children():
			effect.queue_free()


func _lock() -> void:
	EventManager.presentation_locked = true
	_main.set_camera_input_locked(true)
	TooltipManager.hide_tooltip()


func _unlock() -> void:
	EventManager.presentation_locked = false
	_main.set_camera_input_locked(false)


func _hide_ui() -> void:
	for layer_node in _main.find_children("*", "CanvasLayer", true, false):
		if layer_node == _transition_layer:
			continue
		_hidden_layers[layer_node] = layer_node.visible
		layer_node.hide()
	# World-space prices, timers and speech bubbles are also UI.
	for control in _main.get_node("World/IncomeSourceViews").find_children("*", "Control", true, false):
		_hidden_controls[control] = control.visibility_layer
		control.visibility_layer = 0
	_hidden_layers[TooltipManager] = TooltipManager.visible
	TooltipManager.hide()


func _restore_ui() -> void:
	for layer_node in _hidden_layers:
		if is_instance_valid(layer_node):
			layer_node.visible = _hidden_layers[layer_node]
	_hidden_layers.clear()
	for control in _hidden_controls:
		if is_instance_valid(control):
			control.visibility_layer = _hidden_controls[control]
	_hidden_controls.clear()


func _cancel() -> void:
	_generation += 1
	_clear_cat_effects()
	if _tween != null:
		_tween.kill()
	if is_instance_valid(_peek):
		_peek.finish_introduction()
	if not _hidden_layers.is_empty():
		_camera.zoom = _original_zoom
	_restore_ui()
	_shade.hide()
	PrestigeManager.transition_in_progress = false
	_unlock()


func _exit_tree() -> void:
	_cancel()
	EventManager.set_jjamtong_intro_ui_available(false)
