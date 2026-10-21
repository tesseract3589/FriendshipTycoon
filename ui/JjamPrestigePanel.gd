class_name JjamPrestigePanel
extends Control

const FORMAT = preload("res://scripts/NumberFormatter.gd")
const BIG = preload("res://scripts/BigNumber.gd")
const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const YELLOW := Color(1.0, 0.85, 0.12)
const ORANGE := Color(1.0, 0.48, 0.05)
const LIGHT_GREEN := Color(0.65, 1.0, 0.35)
const SCREEN_MARGIN: float = 16.0
const PANEL_MAX_SIZE := Vector2(1100.0, 680.0)
const TWO_COLUMN_MIN_WIDTH: float = 760.0
const SINGLE_COLUMN_MIN_WIDTH: float = 320.0
const WARNING_MAX_FONT_SIZE: int = 22
const WARNING_MAX_OUTLINE_SIZE: int = 8

@onready var panel: PanelContainer = $Panel
@onready var columns: BoxContainer = $Panel/Margin/VBox/Scroll/Columns
@onready var left: VBoxContainer = $Panel/Margin/VBox/Scroll/Columns/Left
@onready var right: VBoxContainer = $Panel/Margin/VBox/Scroll/Columns/Right
@onready var quote: RichTextLabel = $Panel/Margin/VBox/Scroll/Columns/Left/Quote
@onready var boost: Label = $Panel/Margin/VBox/Scroll/Columns/Left/Boost
@onready var banked: Label = $Panel/Margin/VBox/Scroll/Columns/Right/Banked
@onready var live: Label = $Panel/Margin/VBox/Scroll/Columns/Right/Live
@onready var prestige_button: TextureButton = $Panel/Margin/VBox/Scroll/Columns/Right/Prestige
@onready var warning: RichTextLabel = $Panel/Margin/VBox/Scroll/Columns/Right/Warning
@onready var confirmation_layer: CanvasLayer = $PrestigeConfirmation
@onready var confirmation_panel: PanelContainer = $PrestigeConfirmation/Overlay/Panel
@onready var confirmation_question: Label = $PrestigeConfirmation/Overlay/Panel/Margin/VBox/Scroll/Text/Question
@onready var confirmation_hint: Label = $PrestigeConfirmation/Overlay/Panel/Margin/VBox/Scroll/Text/Hint
@onready var confirmation_yes: Button = $PrestigeConfirmation/Overlay/Panel/Margin/VBox/Actions/Yes
@onready var confirmation_no: Button = $PrestigeConfirmation/Overlay/Panel/Margin/VBox/Actions/No

var _color_tween: Tween
var _dismissed_pointer_active: bool = false


func _ready() -> void:
	add_to_group("jjam_prestige_panel")
	RightPanelManager.register_panel(self)
	$Panel/Margin/VBox/Header/Close.pressed.connect(hide)
	prestige_button.pressed.connect(_prestige)
	confirmation_layer.layer = RENDER_ORDER.ScreenLayer.EVENT
	confirmation_yes.pressed.connect(_confirm_prestige)
	confirmation_no.pressed.connect(_close_confirmation)
	var quote_padding := StyleBoxEmpty.new()
	quote_padding.content_margin_top = 12.0
	quote_padding.content_margin_bottom = 12.0
	quote.add_theme_stylebox_override("normal", quote_padding)
	warning.resized.connect(_fit_warning_text)
	PrestigeManager.jjam_changed.connect(_refresh)
	PrestigeManager.jjam_unlocked_changed.connect(_refresh)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_fit.call_deferred)
	_observe_fixed_ui.call_deferred()
	_refresh()
	_fit()


func open_panel() -> void:
	if PrestigeManager.jjam_unlocked and not PrestigeManager.transition_in_progress and not _dismissed_pointer_active:
		RightPanelManager.open_panel(self)


func toggle_panel() -> void:
	if PrestigeManager.jjam_unlocked and not PrestigeManager.transition_in_progress:
		RightPanelManager.toggle_panel(self)


func _input(event: InputEvent) -> void:
	if confirmation_layer.visible and event.is_action_pressed("ui_cancel"):
		_close_confirmation()
		get_viewport().set_input_as_handled()
		return
	var pointer_position := Vector2.ZERO
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if not event.pressed:
			_clear_pointer_dismissal.call_deferred()
			return
		pointer_position = event.position
	elif event is InputEventScreenTouch:
		if not event.pressed:
			_clear_pointer_dismissal.call_deferred()
			return
		pointer_position = event.position
	else:
		return
	if not is_visible_in_tree() or EventManager.presentation_locked:
		return
	if _contains_pointer(panel, pointer_position) or _higher_ui_contains_pointer(pointer_position):
		return
	_dismissed_pointer_active = true
	hide()
	# Leave the event available to the clicked world object or UI. Only suppress
	# reopening from the bin on this same gesture's release.


func _clear_pointer_dismissal() -> void:
	_dismissed_pointer_active = false


func _contains_pointer(control: Control, viewport_position: Vector2) -> bool:
	var local_position := control.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Rect2(Vector2.ZERO, control.size).has_point(local_position)


func _higher_ui_contains_pointer(viewport_position: Vector2) -> bool:
	var own_layer := get_canvas_layer_node()
	var own_order := own_layer.layer if own_layer != null else 0
	# Higher HUD layers own their clicks: the sidebar toggles panels itself, while
	# developer tools and event dialogs leave the panel underneath them intact.
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer_node := node as CanvasLayer
		if not layer_node.visible or layer_node.layer <= own_order:
			continue
		for child in layer_node.find_children("*", "Control", true, false):
			var control := child as Control
			if control.get_canvas_layer_node() != layer_node or not control.is_visible_in_tree():
				continue
			if control.mouse_filter != Control.MOUSE_FILTER_IGNORE and _contains_pointer(control, viewport_position):
				return true
	return false


func _prestige() -> void:
	if not PrestigeManager.can_prestige() or EventManager.presentation_locked:
		return
	_refresh_confirmation()
	_fit_confirmation()
	confirmation_layer.show()
	confirmation_no.grab_focus()


func _confirm_prestige() -> void:
	if not confirmation_layer.visible or not is_visible_in_tree():
		return
	# Close before requesting the animation so repeated input cannot confirm twice.
	_close_confirmation()
	if PrestigeManager.can_prestige():
		PrestigeManager.request_prestige()
	_refresh()


func _close_confirmation() -> void:
	confirmation_layer.hide()
	confirmation_yes.release_focus()
	confirmation_no.release_focus()


func _refresh_confirmation() -> void:
	var earned: Variant = PrestigeManager.live_jjam
	var current: Variant = PrestigeManager.banked_jjam
	confirmation_question.text = "%s짬을 얻는 대가로 환생하시겠습니까?" % FORMAT.format_number(earned)
	confirmation_yes.disabled = not PrestigeManager.can_prestige()
	confirmation_hint.hide()
	confirmation_hint.text = ""
	if BIG.compare(current, 0) <= 0:
		return
	if BIG.compare(earned, BIG.multiply(current, 10)) >= 0:
		confirmation_hint.text = "(와우, 정말 많군요!)"
		confirmation_hint.add_theme_color_override("font_color", LIGHT_GREEN)
	elif BIG.compare(BIG.multiply(earned, 3), current) <= 0:
		confirmation_hint.text = "(별로 안 되는데요...)"
		confirmation_hint.add_theme_color_override("font_color", ORANGE)
	confirmation_hint.visible = not confirmation_hint.text.is_empty()


func _fit_confirmation() -> void:
	var available_size := (size - Vector2.ONE * SCREEN_MARGIN * 2.0).max(Vector2.ONE)
	confirmation_panel.size = available_size.min(Vector2(600.0, 240.0))
	confirmation_panel.position = (size - confirmation_panel.size) * 0.5


func _refresh() -> void:
	banked.text = FORMAT.format_number(PrestigeManager.banked_jjam) + "짬"
	live.text = FORMAT.format_number(PrestigeManager.live_jjam) + "짬"
	boost.text = "1짬당 전체 수입 +%s%%" % FORMAT.format_number(PrestigeManager.boost_per_jjam)
	prestige_button.disabled = not PrestigeManager.can_prestige()
	prestige_button.modulate = Color.WHITE if not prestige_button.disabled else Color(0.55, 0.55, 0.55)
	if confirmation_layer.visible:
		_refresh_confirmation()


func _fit() -> void:
	if not is_instance_valid(panel):
		return
	var available := _get_available_panel_rect()
	var panel_size := (available.size * 0.94).min(PANEL_MAX_SIZE)
	var narrow := panel_size.x < TWO_COLUMN_MIN_WIDTH
	columns.vertical = narrow
	left.custom_minimum_size.x = 0.0 if narrow else 300.0
	right.custom_minimum_size.x = 0.0 if narrow else 340.0
	# Scroll vertically on narrow/mobile windows while preserving readable text.
	columns.custom_minimum_size.x = minf(SINGLE_COLUMN_MIN_WIDTH, maxf(1.0, panel_size.x - 56.0))
	panel.size = panel_size
	panel.position = available.position + (available.size - panel.size) * 0.5
	_fit_warning_text.call_deferred()
	_fit_confirmation()


func _observe_fixed_ui() -> void:
	# Layout groups avoid depending on sibling scene paths or individual panel names.
	for group in [&"panel_top_obstacle", &"panel_right_obstacle"]:
		for item in get_tree().get_nodes_in_group(group):
			var control := item as Control
			if control == null:
				continue
			control.item_rect_changed.connect(_fit.call_deferred)
			control.visibility_changed.connect(_fit.call_deferred)
	_fit()


func _get_available_panel_rect() -> Rect2:
	var top := SCREEN_MARGIN
	var right_edge := size.x - SCREEN_MARGIN
	for item in get_tree().get_nodes_in_group(&"panel_top_obstacle"):
		var control := item as Control
		if control != null and control.is_visible_in_tree():
			top = maxf(top, _get_control_rect(control).end.y + SCREEN_MARGIN)
	# Keep enough room for readable content on small portrait screens. The close
	# control stays at the left of the fixed header, outside the right sidebar.
	for item in get_tree().get_nodes_in_group(&"panel_right_obstacle"):
		var control := item as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var edge := _get_control_rect(control).position.x - SCREEN_MARGIN
		if edge - SCREEN_MARGIN >= SINGLE_COLUMN_MIN_WIDTH:
			right_edge = minf(right_edge, edge)
	# Very short windows retain a fixed header and scroll the body.
	top = minf(top, maxf(SCREEN_MARGIN, size.y - 128.0))
	return Rect2(Vector2(SCREEN_MARGIN, top), Vector2(maxf(1.0, right_edge - SCREEN_MARGIN), maxf(1.0, size.y - top - SCREEN_MARGIN)))


func _get_control_rect(control: Control) -> Rect2:
	# Reserve the layout bounds; a sidebar hover squash must not resize the panel.
	var parent_canvas := control.get_global_transform_with_canvas() * control.get_transform().affine_inverse()
	var to_local := get_global_transform_with_canvas().affine_inverse() * parent_canvas
	return to_local * Rect2(control.position, control.size)


func _fit_warning_text() -> void:
	if not is_instance_valid(warning) or warning.size.x <= 0.0:
		return
	# Keep the original theme font and render every word at the same weight/size.
	# Measure the complete plain text so the colored span stays on the same line.
	var font := warning.get_theme_font("normal_font")
	var text := warning.get_parsed_text()
	var padding := warning.get_theme_stylebox("normal").get_minimum_size().x
	var available_width := maxf(1.0, floorf(warning.size.x - padding - 2.0))
	var font_size := WARNING_MAX_FONT_SIZE
	while font_size > 1 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available_width:
		font_size -= 1
	warning.add_theme_font_size_override("normal_font_size", font_size)
	warning.add_theme_constant_override("outline_size", maxi(1, roundi(float(WARNING_MAX_OUTLINE_SIZE) * font_size / WARNING_MAX_FONT_SIZE)))


func _on_visibility_changed() -> void:
	if _color_tween != null:
		_color_tween.kill()
	if not visible:
		_close_confirmation()
		return
	_refresh()
	_fit()
	_set_quote_color(YELLOW)
	_color_tween = create_tween().set_loops()
	_color_tween.tween_method(_set_quote_color, YELLOW, ORANGE, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_color_tween.tween_method(_set_quote_color, ORANGE, YELLOW, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_quote_color(color: Color) -> void:
	quote.add_theme_color_override("default_color", color)
