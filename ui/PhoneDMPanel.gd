class_name PhoneDMPanel
extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const PHONE_BASE_SIZE := Vector2(576.0, 1040.0)
const SCREEN_MARGIN: float = 16.0
const MAX_PHONE_HEIGHT: float = 940.0
const BUBBLE_FONT_SIZE: int = 26

@onready var phone: Control = $Phone
@onready var contact: Label = $Phone/Screen/VBox/Contact
@onready var scroll: ScrollContainer = $Phone/Screen/VBox/Scroll
@onready var messages: VBoxContainer = $Phone/Screen/VBox/Scroll/Messages
@onready var status: Label = $Phone/Screen/VBox/Status
@onready var accept_button: Button = $Phone/Screen/VBox/Choices/Accept
@onready var bargain_button: Button = $Phone/Screen/VBox/Choices/Bargain
@onready var reject_button: Button = $Phone/Screen/VBox/Choices/Reject

var _slide_tween: Tween
var _scroll_tween: Tween
var _is_open: bool = false
var _conversation_generation: int = 0
var _event_id: String = ""


func _ready() -> void:
	EventManager.event_started.connect(_on_event_started)
	EventManager.event_finished.connect(_on_event_finished)
	EventManager.phone_dm_message.connect(_append_message)
	EventManager.phone_dm_choices_changed.connect(_on_choices_changed)
	EventManager.phone_dm_resolved.connect(_on_resolved)
	accept_button.pressed.connect(_choose.bind(EventManager.Choice.ACCEPT))
	bargain_button.pressed.connect(_choose.bind(EventManager.Choice.BARGAIN))
	reject_button.pressed.connect(_choose.bind(EventManager.Choice.REJECT))
	resized.connect(_fit_phone)
	_on_choices_changed(false, true, 0.0)
	_fit_phone()
	EventManager.set_phone_dm_ui_available(true)


func _exit_tree() -> void:
	EventManager.event_started.disconnect(_on_event_started)
	EventManager.event_finished.disconnect(_on_event_finished)
	EventManager.phone_dm_message.disconnect(_append_message)
	EventManager.phone_dm_choices_changed.disconnect(_on_choices_changed)
	EventManager.phone_dm_resolved.disconnect(_on_resolved)
	EventManager.set_phone_dm_ui_available(false)


## Main also checks this before its _input camera handler (GUI receives events later).
func blocks_pointer(viewport_position: Vector2) -> bool:
	if not is_instance_valid(phone) or not phone.is_visible_in_tree():
		return false
	var local_point := phone.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Rect2(Vector2.ZERO, phone.size).has_point(local_point)


func _fit_phone() -> void:
	if not is_instance_valid(phone):
		return
	var available := (size - Vector2.ONE * SCREEN_MARGIN * 2.0).max(Vector2.ONE)
	var phone_scale := minf(minf(available.y, MAX_PHONE_HEIGHT) / PHONE_BASE_SIZE.y, available.x / PHONE_BASE_SIZE.x)
	phone.size = PHONE_BASE_SIZE
	phone.scale = Vector2.ONE * phone_scale
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	phone.position = _open_position() if _is_open else _closed_position()


func _open_position() -> Vector2:
	return Vector2(SCREEN_MARGIN, size.y - PHONE_BASE_SIZE.y * phone.scale.y - SCREEN_MARGIN)


func _closed_position() -> Vector2:
	return Vector2(SCREEN_MARGIN, size.y + SCREEN_MARGIN)


func _on_event_started(event_data: GameEventData) -> void:
	if not event_data is PhoneDMEventData:
		return
	_event_id = event_data.id
	_conversation_generation += 1
	for child in messages.get_children():
		messages.remove_child(child)
		child.queue_free()
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	scroll.scroll_vertical = 0
	contact.text = EventManager.get_phone_dm_contact()
	status.text = "메시지가 도착했어요"
	_on_choices_changed(false, true, 0.0)
	_is_open = true
	_fit_phone()
	phone.position = _closed_position()
	phone.show()
	TooltipManager.hide_tooltip()
	_slide_tween = create_tween()
	_slide_tween.tween_property(phone, "position", _open_position(), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_event_finished(event_id: String, result: String) -> void:
	if event_id != _event_id:
		return
	_event_id = ""
	_conversation_generation += 1
	_is_open = false
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if result == "cancelled":
		phone.hide()
		return
	_slide_tween = create_tween()
	_slide_tween.tween_property(phone, "position", _closed_position(), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_slide_tween.tween_callback(phone.hide)


func _choose(choice: EventManager.Choice) -> void:
	EventManager.choose_phone_dm(choice)


func _on_choices_changed(available: bool, can_bargain: bool, offer: Variant) -> void:
	accept_button.disabled = not available
	bargain_button.disabled = not available
	reject_button.disabled = not available
	bargain_button.visible = can_bargain
	if available:
		status.text = "현재 제안 · %s원\n수락하거나 한 번 더 흥정해 보세요." % NUMBER_FORMATTER.format_number(offer) if can_bargain else "마지막 제안 · %s원\n수락 또는 거절을 선택하세요." % NUMBER_FORMATTER.format_number(offer)
	elif _is_open and EventManager.is_event_active(_event_id):
		status.text = "대화 중…"


func _on_resolved(accepted: bool, reward: Variant) -> void:
	status.text = "거래 성립 · %s원 입금 예정" % NUMBER_FORMATTER.format_current_money(reward) if accepted else "거래가 종료되었습니다."


func _append_message(text: String, from_player: bool) -> void:
	var generation := _conversation_generation
	var row := HBoxContainer.new()
	row.name = "PlayerMessage" if from_player else "ContactMessage"
	row.alignment = BoxContainer.ALIGNMENT_END if from_player else BoxContainer.ALIGNMENT_BEGIN
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	messages.add_child(row)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	row.add_child(margin)
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_PASS
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", BUBBLE_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(0.04, 0.08, 0.05))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(bubble)
	bubble.add_child(label)
	var color := Color(1.0, 0.94, 0.64) if from_player else Color.WHITE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.12, 0.17, 0.13)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	bubble.add_theme_stylebox_override("panel", style)
	# Natural text width, capped within the phone screen so every bubble wraps inside it.
	var font := label.get_theme_font("font")
	var text_width := 0.0
	for line in text.split("\n"):
		text_width = maxf(text_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT_SIZE).x)
	bubble.custom_minimum_size.x = minf(ceilf(text_width) + 28.0, maxf(80.0, scroll.size.x - 70.0))
	row.modulate.a = 0.0
	var fade := row.create_tween()
	fade.tween_property(row, "modulate:a", 1.0, 0.18)
	# Containers and the scrollbar finish their layout on deferred frames.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _conversation_generation or not is_instance_valid(bubble):
		return
	_add_tail(bubble, from_player, color)
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	var bar := scroll.get_v_scroll_bar()
	var bottom := maxi(0, ceili(bar.max_value - bar.page))
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(scroll, "scroll_vertical", bottom, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _add_tail(bubble: PanelContainer, from_player: bool, color: Color) -> void:
	var edge := bubble.size.x if from_player else 0.0
	var direction := 1.0 if from_player else -1.0
	var outline := Polygon2D.new()
	outline.color = Color(0.12, 0.17, 0.13)
	outline.polygon = PackedVector2Array([Vector2(edge, 14), Vector2(edge + direction * 12.0, 24), Vector2(edge, 32)])
	bubble.add_child(outline)
	var tail := Polygon2D.new()
	tail.color = color
	tail.polygon = PackedVector2Array([Vector2(edge - direction * 2.0, 16), Vector2(edge + direction * 9.0, 24), Vector2(edge - direction * 2.0, 30)])
	bubble.add_child(tail)
