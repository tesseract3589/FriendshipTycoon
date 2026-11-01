class_name CatWatchingEvent
extends CanvasLayer

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const WINDOW_LAYOUT = preload("res://scripts/GameWindowLayout.gd")
const CONTENT_SIZE := Vector2(1000.0, 880.0)
const CAT_SIZE: float = 490.0
const SCREEN_MARGIN: float = 24.0

@export_range(0.0, 0.8, 0.05) var dim_opacity: float = 0.4
@export_range(0.1, 2.0, 0.05) var entrance_duration: float = 0.4
@export_range(0.1, 2.0, 0.05) var exit_duration: float = 0.5

@onready var overlay: Control = $Overlay
@onready var dim: ColorRect = $Overlay/Dim
@onready var content: Control = $Overlay/Content
@onready var cat_root: Node2D = $Overlay/Content/CatRoot
@onready var aura: Node2D = $Overlay/Content/CatRoot/Aura
@onready var smoke: CPUParticles2D = $Overlay/Content/CatRoot/Aura/Smoke
@onready var silhouette: Sprite2D = $Overlay/Content/CatRoot/Silhouette
@onready var caption: Label = $Overlay/Content/Caption
@onready var confirm: TextureButton = $Overlay/Content/Confirm

var _transition: Tween
var _cat_scale: Vector2


func _ready() -> void:
	layer = RENDER_ORDER.ScreenLayer.EVENT
	_cat_scale = Vector2.ONE * CAT_SIZE / maxf(silhouette.texture.get_width(), silhouette.texture.get_height())
	silhouette.scale = _cat_scale
	_configure_smoke()
	confirm.pressed.connect(_confirm)
	overlay.resized.connect(_fit_content)
	EventManager.event_started.connect(_on_event_started)
	EventManager.event_finished.connect(_on_event_finished)
	EventManager.event_state_restored.connect(_hide_immediately)
	_hide_immediately()
	_fit_content()
	EventManager.set_cat_watching_ui_available(true)


func _exit_tree() -> void:
	EventManager.event_started.disconnect(_on_event_started)
	EventManager.event_finished.disconnect(_on_event_finished)
	EventManager.event_state_restored.disconnect(_hide_immediately)
	EventManager.set_cat_watching_ui_available(false)


func is_blocking_input() -> bool:
	# Keep the world blocked throughout the exit animation as well.
	return is_instance_valid(overlay) and overlay.is_visible_in_tree()


func _configure_smoke() -> void:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	for index in range(48):
		var angle := TAU * index / 48.0
		var normal := Vector2.from_angle(angle)
		points.append(normal * Vector2(170.0, 190.0))
		normals.append(normal)
	smoke.emission_points = points
	smoke.emission_normals = normals
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	fade.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 0.85),
		Color(1, 1, 1, 0.5), Color(1, 1, 1, 0),
	])
	smoke.color_ramp = fade


func _fit_content() -> void:
	var available := (WINDOW_LAYOUT.get_ui_layout_size(overlay.size) - Vector2.ONE * SCREEN_MARGIN * 2.0).max(Vector2.ONE)
	var factor := minf(1.2, minf(available.x / CONTENT_SIZE.x, available.y / CONTENT_SIZE.y))
	content.scale = Vector2.ONE * factor
	content.position = (overlay.size - CONTENT_SIZE * factor) * 0.5


func _on_event_started(event_data: GameEventData) -> void:
	if event_data.id != EventManager.CAT_WATCHING_ID:
		return
	_hide_immediately()
	_fit_content()
	silhouette.scale = _cat_scale
	cat_root.scale = Vector2.ONE * 0.92
	cat_root.modulate = Color(1, 1, 1, 0)
	aura.modulate = Color.WHITE
	caption.modulate = Color(1, 1, 1, 0)
	confirm.modulate = Color(1, 1, 1, 0)
	dim.color.a = 0.0
	overlay.show()
	overlay.grab_focus()
	smoke.restart()
	smoke.emitting = true
	TooltipManager.hide_tooltip()
	_transition = create_tween().set_parallel()
	_transition.tween_property(dim, "color:a", dim_opacity, entrance_duration)
	_transition.tween_property(cat_root, "modulate:a", 1.0, entrance_duration)
	_transition.tween_property(cat_root, "scale", Vector2.ONE, entrance_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(caption, "modulate:a", 1.0, entrance_duration)
	_transition.tween_property(confirm, "modulate:a", 1.0, entrance_duration)
	_transition.chain().tween_callback(_enable_confirmation)


func _enable_confirmation() -> void:
	confirm.disabled = false
	# Do not steal focus if the developer window was opened during the entrance.
	if overlay.has_focus():
		confirm.grab_focus()


func _confirm() -> void:
	if not EventManager.is_event_active(EventManager.CAT_WATCHING_ID):
		return
	confirm.disabled = true
	EventManager.finish_event(EventManager.CAT_WATCHING_ID, "acknowledged")


func _on_event_finished(event_id: String, result: String) -> void:
	if event_id != EventManager.CAT_WATCHING_ID:
		return
	if result != "acknowledged":
		_hide_immediately()
		return
	_stop_transition()
	confirm.disabled = true
	smoke.emitting = false
	_transition = create_tween().set_parallel()
	_transition.tween_property(dim, "color:a", 0.0, exit_duration)
	_transition.tween_property(silhouette, "scale", Vector2.ZERO, exit_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition.tween_property(aura, "modulate:a", 0.0, exit_duration)
	_transition.tween_property(caption, "modulate:a", 0.0, exit_duration)
	_transition.tween_property(confirm, "modulate:a", 0.0, exit_duration)
	_transition.chain().tween_callback(_finish_exit)


func _finish_exit() -> void:
	_transition = null
	overlay.hide()
	confirm.release_focus()


func _hide_immediately() -> void:
	_stop_transition()
	overlay.hide()
	smoke.emitting = false
	confirm.disabled = true
	confirm.release_focus()


func _stop_transition() -> void:
	if _transition != null and _transition.is_valid():
		_transition.kill()
	_transition = null
