extends CanvasLayer

const ARROW_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Arrow1.png")
const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const ARROW_WIDTH: float = 72.0
const TARGET_GAP: float = 12.0
const SHORT_SCALE := Vector2(0.72, 1.12)
const LONG_SCALE := Vector2(1.18, 0.94)

var _panel: JjamPrestigePanel
var _arrow: Node2D
var _sprite: Sprite2D
var _bounce: Tween


func _ready() -> void:
	# Sprites have no GUI hit area. This guide never handles input or opens UI.
	layer = RENDER_ORDER.ScreenLayer.SIDEBAR
	_panel = get_tree().get_first_node_in_group("jjam_prestige_panel") as JjamPrestigePanel
	_arrow = Node2D.new()
	_arrow.name = "Arrow"
	add_child(_arrow)
	_sprite = Sprite2D.new()
	_sprite.texture = ARROW_TEXTURE
	_sprite.centered = false
	# Anchor the arrow tip so stretching its body cannot cover the target button.
	_sprite.offset = Vector2(-ARROW_TEXTURE.get_width(), -ARROW_TEXTURE.get_height() * 0.5)
	_arrow.add_child(_sprite)
	_arrow.hide()
	set_process(false)
	EventManager.event_started.connect(_on_event_started)
	EventManager.event_finished.connect(_on_event_finished)
	EventManager.event_state_restored.connect(_reset)
	EventManager.set_jjam_shop_tutorial_ui_available(is_instance_valid(_panel))


func _exit_tree() -> void:
	_reset()
	EventManager.set_jjam_shop_tutorial_ui_available(false)


func _on_event_started(data: GameEventData) -> void:
	if data.id != EventManager.JJAM_SHOP_TUTORIAL_ID:
		return
	_reset()
	_play_bounce()
	set_process(true)
	_process(0.0)


func _process(_delta: float) -> void:
	if not EventManager.is_event_active(EventManager.JJAM_SHOP_TUTORIAL_ID):
		_reset()
		return
	if not is_instance_valid(_panel) or EventManager.presentation_locked or PrestigeManager.transition_in_progress:
		_arrow.hide()
		return
	if _panel.confirmation_layer.visible:
		_arrow.hide()
		return
	if _panel.is_visible_in_tree() and _panel.shop_content.is_visible_in_tree():
		EventManager.finish_event(EventManager.JJAM_SHOP_TUTORIAL_ID, "completed")
		return
	var target: Control = _panel.shop_tab if _panel.is_visible_in_tree() else _panel.prestige_preview
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		_arrow.hide()
		return
	var screen_rect: Rect2 = target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)
	if not get_viewport().get_visible_rect().intersects(screen_rect):
		_arrow.hide()
		return
	var direction := Vector2.UP if _panel.is_visible_in_tree() else Vector2.RIGHT
	var tip := Vector2(screen_rect.get_center().x, screen_rect.end.y + TARGET_GAP) if _panel.is_visible_in_tree() else Vector2(screen_rect.position.x - TARGET_GAP, screen_rect.get_center().y)
	_arrow.position = tip
	_arrow.rotation = direction.angle()
	_arrow.show()


func _play_bounce() -> void:
	var base_scale := Vector2.ONE * ARROW_WIDTH / ARROW_TEXTURE.get_width()
	_sprite.scale = base_scale * SHORT_SCALE
	_bounce = create_tween().set_loops()
	_bounce.tween_property(_sprite, "scale", base_scale * LONG_SCALE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_bounce.tween_interval(0.50)
	_bounce.tween_property(_sprite, "scale", base_scale * SHORT_SCALE, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_event_finished(event_id: String, _result: String) -> void:
	if event_id == EventManager.JJAM_SHOP_TUTORIAL_ID:
		_reset()


func _reset() -> void:
	if _bounce != null and _bounce.is_valid():
		_bounce.kill()
	if is_instance_valid(_arrow):
		_arrow.hide()
	set_process(false)
