class_name IncomeUpgradeTutorial
extends Label

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const FADE_DURATION: float = 1.0

var _anchor: Vector2
var _has_anchor: bool = false
var _bob_offset: float = 0.0
var _bob_tween: Tween
var _fade_tween: Tween


func setup(anchor: Vector2) -> void:
	_anchor = anchor
	_has_anchor = true
	if is_node_ready():
		EventManager.set_income_upgrade_tutorial_ui_available(true)


func _ready() -> void:
	text = "눌러서 업그레이드 패널 열기" if OS.has_feature("mobile") else "클릭하여 업그레이드 패널 열기"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 18)
	add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 1.0))
	add_theme_constant_override("outline_size", 6)
	size = get_combined_minimum_size()
	RENDER_ORDER.apply_world_layer(self, RENDER_ORDER.WorldLayer.DESCRIPTION + 10)
	hide()
	EventManager.event_started.connect(_on_event_started)
	EventManager.event_finished.connect(_on_event_finished)
	EventManager.event_state_restored.connect(_reset)
	if _has_anchor:
		EventManager.set_income_upgrade_tutorial_ui_available(true)


func _exit_tree() -> void:
	EventManager.set_income_upgrade_tutorial_ui_available(false)
	_stop_tweens()


func _process(_delta: float) -> void:
	if not visible:
		return
	# Stay attached to the vending machine in world space, including off screen.
	global_position = _anchor - Vector2(size.x * 0.5, size.y + 8.0 - _bob_offset)


func _on_event_started(event_data: GameEventData) -> void:
	if event_data.id != EventManager.INCOME_UPGRADE_TUTORIAL_ID:
		return
	_reset()
	modulate = Color.WHITE
	_bob_offset = 0.0
	show()
	_bob_tween = create_tween().set_loops()
	_bob_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(self, "_bob_offset", -10.0, 0.8)
	_bob_tween.tween_property(self, "_bob_offset", 0.0, 0.8)
	_process(0.0)
	TooltipManager.hide_tooltip()


func _on_event_finished(event_id: String, result: String) -> void:
	if event_id != EventManager.INCOME_UPGRADE_TUTORIAL_ID:
		return
	if result != "dismissed":
		_reset()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	_fade_tween.tween_callback(_reset)


func _stop_tweens() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()


func _reset() -> void:
	_stop_tweens()
	hide()
