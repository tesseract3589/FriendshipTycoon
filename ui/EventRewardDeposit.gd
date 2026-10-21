extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const PHONE_EXIT_DELAY: float = 0.35
const AMOUNT_HOLD: float = 0.4
const TRANSFER_DURATION: float = 0.85

@export_node_path("Label") var money_label_path: NodePath = ^"../Panel/VBoxContainer/MoneyLabel"
@export_node_path("Control") var funds_panel_path: NodePath = ^"../Panel"

@onready var money_label := get_node(money_label_path) as Label
@onready var funds_panel := get_node(funds_panel_path) as Control
@onready var pending_label: Label = $PendingAmount

var _queue: Array[int] = []
var _current_reward: int = -1
var _sequence: Tween
var _absorb_progress: float = 0.0
var _money_base_modulate := Color.WHITE


func _ready() -> void:
	_money_base_modulate = money_label.modulate
	EventManager.reward_deposit_requested.connect(_queue_deposit)
	EventManager.reward_deposits_cancelled.connect(_cancel_deposits)
	set_process(false)
	EventManager.set_reward_deposit_ui_available(true)


func _exit_tree() -> void:
	EventManager.reward_deposit_requested.disconnect(_queue_deposit)
	EventManager.reward_deposits_cancelled.disconnect(_cancel_deposits)
	EventManager.set_reward_deposit_ui_available(false)
	if is_instance_valid(money_label):
		money_label.modulate = _money_base_modulate


func _queue_deposit(reward_id: int) -> void:
	if reward_id == _current_reward or reward_id in _queue:
		return
	_queue.append(reward_id)
	_play_next()


func _play_next() -> void:
	if _current_reward != -1 or _queue.is_empty():
		return
	_current_reward = _queue.pop_front()
	_absorb_progress = 0.0
	pending_label.hide()
	set_process(true)
	_sequence = create_tween()
	_sequence.tween_interval(PHONE_EXIT_DELAY)
	_sequence.tween_callback(_show_amount)
	_sequence.tween_property(pending_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sequence.tween_interval(AMOUNT_HOLD)
	_sequence.tween_method(_absorb_amount, 0.0, 1.0, TRANSFER_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_sequence.tween_property(pending_label, "modulate:a", 0.0, 0.16)
	_sequence.tween_callback(_finish_deposit)


func _show_amount() -> void:
	pending_label.text = "+%s원" % NUMBER_FORMATTER.format_current_money(EventManager.get_reward_remaining(_current_reward))
	pending_label.modulate = Color.WHITE
	pending_label.scale = Vector2.ONE * 0.82
	pending_label.show()
	_position_amount()


func _absorb_amount(progress: float) -> void:
	var reward_id := _current_reward
	var remaining: Variant = EventManager.advance_reward_deposit(reward_id, progress)
	if _current_reward != reward_id:
		return
	_absorb_progress = progress
	pending_label.text = "+%s원" % NUMBER_FORMATTER.format_current_money(remaining)
	pending_label.scale = Vector2.ONE * lerpf(1.0, 0.72, progress)
	money_label.modulate = _money_base_modulate * (1.0 + sin(progress * PI) * 0.35)
	_position_amount()


func _process(_delta: float) -> void:
	if pending_label.visible:
		_position_amount()


func _position_amount() -> void:
	var font := money_label.get_theme_font("font")
	var font_size := money_label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(money_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var viewport_to_local := get_global_transform_with_canvas().affine_inverse()
	var anchor := viewport_to_local * (money_label.get_global_transform_with_canvas() * Vector2(text_width + 18.0, money_label.size.y * 0.5))
	pending_label.reset_size()
	var scaled_size := pending_label.size * pending_label.scale
	# On narrow windows, keep the amount readable just below the funds panel.
	if anchor.x + scaled_size.x > size.x - 16.0:
		var panel_bottom := viewport_to_local * (funds_panel.get_global_transform_with_canvas() * Vector2(0.0, funds_panel.size.y + 12.0))
		anchor = panel_bottom + Vector2(0.0, scaled_size.y * 0.5)
		var fit_scale := minf(pending_label.scale.x, maxf(1.0, size.x - anchor.x - 16.0) / maxf(1.0, pending_label.size.x))
		pending_label.scale = Vector2.ONE * fit_scale
		scaled_size = pending_label.size * pending_label.scale
	anchor.x -= 28.0 * _absorb_progress
	anchor.x = clampf(anchor.x, 12.0, maxf(12.0, size.x - scaled_size.x - 12.0))
	pending_label.position = anchor - Vector2(0.0, scaled_size.y * 0.5)


func _finish_deposit() -> void:
	var reward_id := _current_reward
	# A final exact transfer absorbs any rounding remainder once.
	EventManager.advance_reward_deposit(reward_id, 1.0)
	if _current_reward != reward_id:
		return
	pending_label.hide()
	money_label.modulate = _money_base_modulate
	_current_reward = -1
	set_process(false)
	_play_next()


func _cancel_deposits() -> void:
	if _sequence != null and _sequence.is_valid():
		_sequence.kill()
	_queue.clear()
	_current_reward = -1
	pending_label.hide()
	money_label.modulate = _money_base_modulate
	set_process(false)
