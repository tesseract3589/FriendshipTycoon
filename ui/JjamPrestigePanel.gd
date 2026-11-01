class_name JjamPrestigePanel
extends Control

const FORMAT = preload("res://scripts/NumberFormatter.gd")
const BIG = preload("res://scripts/BigNumber.gd")
const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const WINDOW_LAYOUT = preload("res://scripts/GameWindowLayout.gd")
const YELLOW := Color(1.0, 0.85, 0.12)
const ORANGE := Color(1.0, 0.48, 0.05)
const LIGHT_GREEN := Color(0.65, 1.0, 0.35)
const RED := Color(1.0, 0.25, 0.2)
const SCREEN_MARGIN: float = 16.0
const PANEL_MAX_SIZE := Vector2(1600.0, 1000.0)
const LANDSCAPE_CONTENT_SIZE := Vector2(1080.0, 460.0)
const PORTRAIT_CONTENT_SIZE := Vector2(560.0, 820.0)
const SINGLE_COLUMN_MIN_WIDTH: float = 320.0
const WARNING_MAX_FONT_SIZE: int = 22
const WARNING_MAX_OUTLINE_SIZE: int = 8
const PRESTIGE_LOCKED_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_jjamtiger_locked.png")
const PRESTIGE_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_jjamtiger.png")
const SHOP_BUY_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_buy_Blue.png")
const DISTANT_PRICE_HINT := "감히 넘볼 수 없는 짬입니다..."
const MEOW_SOUND: AudioStream = preload("res://assets/SE/meow.mp3")

@onready var prestige_preview: TextureButton = $JjamPrestigePreview

@onready var panel: PanelContainer = $Panel
@onready var columns: BoxContainer = $Panel/Margin/VBox/PrestigeContent/Columns
@onready var left: VBoxContainer = $Panel/Margin/VBox/PrestigeContent/Columns/Left
@onready var cat: TextureRect = $Panel/Margin/VBox/PrestigeContent/Columns/Left/Cat
@onready var right: VBoxContainer = $Panel/Margin/VBox/PrestigeContent/Columns/Right
@onready var quote: RichTextLabel = $Panel/Margin/VBox/PrestigeContent/Columns/Left/Quote
@onready var boost: Label = $Panel/Margin/VBox/PrestigeContent/Columns/Left/Boost
@onready var banked: Label = $Panel/Margin/VBox/PrestigeContent/Columns/Right/Banked
@onready var live: Label = $Panel/Margin/VBox/PrestigeContent/Columns/Right/Live
@onready var prestige_button: TextureButton = $Panel/Margin/VBox/PrestigeContent/Columns/Right/Prestige
@onready var warning: RichTextLabel = $Panel/Margin/VBox/PrestigeContent/Columns/Right/Warning
@onready var confirmation_layer: CanvasLayer = $PrestigeConfirmation
@onready var confirmation_panel: PanelContainer = $PrestigeConfirmation/Overlay/Panel
@onready var confirmation_question: Label = $PrestigeConfirmation/Overlay/Panel/Margin/VBox/Text/Question
@onready var confirmation_hint: Label = $PrestigeConfirmation/Overlay/Panel/Margin/VBox/Text/Hint
@onready var confirmation_yes: Button = $PrestigeConfirmation/Overlay/Panel/Margin/VBox/Actions/Yes
@onready var confirmation_no: Button = $PrestigeConfirmation/Overlay/Panel/Margin/VBox/Actions/No
@onready var prestige_tab: Button = $Panel/Margin/VBox/Tabs/PrestigeTab
@onready var shop_tab: Button = $Panel/Margin/VBox/Tabs/ShopTab
@onready var prestige_content: Control = $Panel/Margin/VBox/PrestigeContent
@onready var shop_content: VBoxContainer = $Panel/Margin/VBox/Shop
@onready var shop_balance: Label = $Panel/Margin/VBox/Shop/Balance
@onready var shop_list: VBoxContainer = $Panel/Margin/VBox/Shop/Scroll/List
@onready var title: Label = $Panel/Margin/VBox/Header/Title

var _color_tween: Tween
var _dismissed_pointer_active: bool = false
var _pending_shop_item: String = ""
var _shop_buttons: Dictionary = {}
var _shop_rows: Dictionary = {}
var _hovered_shop_price: String = ""
var _cat_tween: Tween
var _panel_cat_tween: Tween


func _ready() -> void:
	add_to_group("jjam_prestige_panel")
	_setup_prestige_preview()
	cat.gui_input.connect(_on_cat_gui_input)
	RightPanelManager.register_panel(self)
	$Panel/Margin/VBox/Header/Close.pressed.connect(hide)
	prestige_button.pressed.connect(_prestige)
	confirmation_layer.layer = RENDER_ORDER.ScreenLayer.EVENT
	confirmation_yes.pressed.connect(_confirm_action)
	confirmation_no.pressed.connect(_close_confirmation)
	prestige_tab.pressed.connect(_select_tab.bind(false))
	shop_tab.pressed.connect(_select_tab.bind(true))
	_build_shop_rows()
	var shop_scroll := $Panel/Margin/VBox/Shop/Scroll as ScrollContainer
	shop_scroll.get_v_scroll_bar().value_changed.connect(_on_shop_scroll)
	shop_scroll.get_h_scroll_bar().value_changed.connect(_on_shop_scroll)
	_select_tab(false)
	var quote_padding := StyleBoxEmpty.new()
	quote_padding.content_margin_top = 12.0
	quote_padding.content_margin_bottom = 12.0
	quote.add_theme_stylebox_override("normal", quote_padding)
	warning.resized.connect(_fit_warning_text)
	prestige_content.resized.connect(_fit_prestige_content.call_deferred)
	columns.minimum_size_changed.connect(_fit_prestige_content.call_deferred)
	confirmation_question.resized.connect(_fit_confirmation.call_deferred)
	confirmation_hint.resized.connect(_fit_confirmation.call_deferred)
	PrestigeManager.jjam_changed.connect(_refresh)
	PrestigeManager.jjam_unlocked_changed.connect(_refresh)
	PrestigeManager.shop_changed.connect(_refresh)
	PrestigeManager.upgrade_mode_changed.connect(_refresh_shop)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_fit.call_deferred)
	_observe_fixed_ui.call_deferred()
	_refresh()
	_fit()


func _setup_prestige_preview() -> void:
	# Its own layer keeps this scene's entry accessible while its panel is closed.
	var sidebar_layer := CanvasLayer.new()
	sidebar_layer.name = "SidebarLayer"
	sidebar_layer.layer = RENDER_ORDER.ScreenLayer.SIDEBAR
	add_child(sidebar_layer)
	var sidebar := Control.new()
	sidebar.name = "Sidebar"
	sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar_layer.add_child(sidebar)
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prestige_preview.reparent(sidebar, false)
	prestige_preview.add_to_group("jjam_prestige_entry")
	RightPanelManager.register_sidebar_entry(prestige_preview, 1)
	prestige_preview.pressed.connect(toggle_panel)
	prestige_preview.mouse_entered.connect(_animate_cat.bind(true))
	prestige_preview.mouse_exited.connect(_animate_cat.bind(false))
	PrestigeManager.jjam_unlocked_changed.connect(_refresh_prestige_preview)
	EventManager.event_finished.connect(_on_preview_event_finished)
	EventManager.event_state_restored.connect(_refresh_prestige_preview)
	SaveManager.progress_loaded.connect(_refresh_prestige_preview)
	_refresh_prestige_preview()


func _on_preview_event_finished(event_id: String, _result: String) -> void:
	if event_id == EventManager.CAT_WATCHING_ID:
		_refresh_prestige_preview()


func _refresh_prestige_preview(_slot: int = -1) -> void:
	var unlocked := PrestigeManager.jjam_unlocked
	prestige_preview.visible = unlocked or EventManager.get_event_result(EventManager.CAT_WATCHING_ID) == "acknowledged"
	prestige_preview.texture_normal = PRESTIGE_TEXTURE if unlocked else PRESTIGE_LOCKED_TEXTURE
	prestige_preview.disabled = not unlocked
	prestige_preview.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
	if _cat_tween != null:
		_cat_tween.kill()
	prestige_preview.scale = Vector2.ONE


func _animate_cat(hovered: bool) -> void:
	if prestige_preview.disabled:
		return
	if _cat_tween != null:
		_cat_tween.kill()
	var target := Vector2.ONE * (1.08 if hovered else 1.0)
	var bounce := Vector2(0.94, 1.15) if hovered else Vector2(1.04, 0.89)
	_cat_tween = _play_cat_bounce(prestige_preview, target, bounce)


func _play_cat_bounce(visual: Control, target: Vector2, bounce: Vector2) -> Tween:
	visual.pivot_offset = visual.size * 0.5
	var tween := create_tween()
	tween.tween_property(visual, "scale", target * bounce, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "scale", target, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tween


func _on_cat_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	cat.accept_event()
	if EventManager.presentation_locked:
		return
	if _panel_cat_tween != null:
		_panel_cat_tween.kill()
	_panel_cat_tween = _play_cat_bounce(cat, Vector2.ONE, Vector2(0.94, 1.15))
	SoundManager.play_se(MEOW_SOUND)


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
	_pending_shop_item = ""
	_refresh_confirmation()
	_fit_confirmation()
	confirmation_layer.show()
	confirmation_no.grab_focus()


func _confirm_action() -> void:
	if not confirmation_layer.visible or not is_visible_in_tree():
		return
	# Close before requesting the animation so repeated input cannot confirm twice.
	var item_id := _pending_shop_item
	_close_confirmation()
	if not item_id.is_empty():
		PrestigeManager.purchase_shop_item(item_id)
	elif PrestigeManager.can_prestige():
		PrestigeManager.request_prestige()
	_refresh()


func _close_confirmation() -> void:
	confirmation_layer.hide()
	_pending_shop_item = ""
	confirmation_yes.release_focus()
	confirmation_no.release_focus()


func _refresh_confirmation() -> void:
	if not _pending_shop_item.is_empty():
		_refresh_shop_confirmation()
		return
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
	var logical_size := Vector2(clampf(available_size.x, 320.0, 600.0), 240.0)
	confirmation_panel.size = logical_size
	logical_size = confirmation_panel.size.max(confirmation_panel.get_combined_minimum_size())
	var fit_scale := minf(1.0, minf(available_size.x / logical_size.x, available_size.y / logical_size.y))
	confirmation_panel.scale = Vector2.ONE * fit_scale
	confirmation_panel.position = (size - logical_size * fit_scale) * 0.5


func _refresh() -> void:
	banked.text = FORMAT.format_number(PrestigeManager.banked_jjam) + "짬"
	live.text = FORMAT.format_current_money(PrestigeManager.live_jjam) + "짬"
	boost.text = "1짬당 전체 수입 +%s%%" % FORMAT.format_number(PrestigeManager.boost_per_jjam)
	prestige_button.disabled = not PrestigeManager.can_prestige()
	prestige_button.modulate = Color.WHITE if not prestige_button.disabled else Color(0.55, 0.55, 0.55)
	_refresh_shop()
	if confirmation_layer.visible:
		_refresh_confirmation()


func _fit() -> void:
	if not is_instance_valid(panel):
		return
	var available := _get_available_panel_rect()
	var viewport_growth := size - WINDOW_LAYOUT.get_ui_layout_size(size)
	var reference_available := (available.size - viewport_growth).max(Vector2.ONE)
	panel.size = reference_available.min(PANEL_MAX_SIZE)
	panel.position = available.position + (available.size - panel.size) * 0.5
	_fit_prestige_content.call_deferred()
	_fit_confirmation()


func _fit_prestige_content() -> void:
	if not prestige_content.is_visible_in_tree() or prestige_content.size.x <= 0.0 or prestige_content.size.y <= 0.0:
		return
	# A plain Control isolates the content's logical size from the outer panel's
	# minimum size. Fit the entire layout instead of introducing a scroll area.
	var portrait := prestige_content.size.y > prestige_content.size.x * 1.1
	columns.vertical = portrait
	left.custom_minimum_size.x = 0.0 if portrait else 300.0
	right.custom_minimum_size.x = 0.0 if portrait else 340.0
	var logical_size := PORTRAIT_CONTENT_SIZE if portrait else LANDSCAPE_CONTENT_SIZE
	columns.size = logical_size
	logical_size = columns.size.max(columns.get_combined_minimum_size())
	var fit_scale := minf(1.5, minf(prestige_content.size.x / logical_size.x, prestige_content.size.y / logical_size.y))
	columns.scale = Vector2.ONE * fit_scale
	columns.position = (prestige_content.size - logical_size * fit_scale) * 0.5
	_fit_warning_text.call_deferred()


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
	# Preserve room below the fixed header even in short windows.
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
	# Avoid repeatedly invalidating the content layout after it has settled.
	if warning.get_theme_font_size("normal_font_size") != font_size:
		warning.add_theme_font_size_override("normal_font_size", font_size)
	var outline_size := maxi(1, roundi(float(WARNING_MAX_OUTLINE_SIZE) * font_size / WARNING_MAX_FONT_SIZE))
	if warning.get_theme_constant("outline_size") != outline_size:
		warning.add_theme_constant_override("outline_size", outline_size)


func _on_visibility_changed() -> void:
	if _color_tween != null:
		_color_tween.kill()
	if not visible:
		_clear_shop_price_tooltip()
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


func _select_tab(show_shop: bool) -> void:
	_clear_shop_price_tooltip()
	_close_confirmation()
	prestige_tab.set_pressed_no_signal(not show_shop)
	shop_tab.set_pressed_no_signal(show_shop)
	prestige_content.visible = not show_shop
	shop_content.visible = show_shop
	title.text = "짬 상점" if show_shop else "짬 환생"
	_fit.call_deferred()


func _build_shop_rows() -> void:
	var buy_click_mask := BitMap.new()
	buy_click_mask.create_from_image_alpha(SHOP_BUY_TEXTURE.get_image())
	for item in PrestigeManager.shop_items:
		if item == null or not item.prerequisite_item_id.is_empty():
			continue
		var card := PanelContainer.new()
		var margin := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 18)
		card.add_child(margin)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 14)
		margin.add_child(content)
		var item_header := HBoxContainer.new()
		item_header.add_theme_constant_override("separation", 16)
		content.add_child(item_header)
		var item_icon := TextureRect.new()
		item_icon.custom_minimum_size = Vector2(64.0, 64.0)
		item_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_icon.texture = item.icon
		item_icon.visible = item.icon != null
		item_header.add_child(item_icon)
		var item_title := Label.new()
		item_title.text = item.item_name
		item_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item_title.add_theme_font_size_override("font_size", 28)
		item_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_header.add_child(item_title)
		var details := HBoxContainer.new()
		details.add_theme_constant_override("separation", 16)
		content.add_child(details)
		var description := Label.new()
		description.text = item.description
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		description.add_theme_color_override("font_color", Color.WHITE)
		description.add_theme_font_size_override("font_size", 22)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(description)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 16)
		actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		details.add_child(actions)
		var mode_column := VBoxContainer.new()
		mode_column.name = "Mode"
		mode_column.custom_minimum_size.x = 128.0
		mode_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mode_column.add_theme_constant_override("separation", 4)
		mode_column.hide()
		actions.add_child(mode_column)
		var mode_hint := Label.new()
		mode_hint.text = "클릭하여 모드 전환"
		mode_hint.add_theme_font_size_override("font_size", 14)
		mode_hint.add_theme_constant_override("outline_size", 2)
		mode_hint.add_theme_color_override("font_color", Color.WHITE)
		mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mode_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mode_column.add_child(mode_hint)
		var mode_button := TextureButton.new()
		mode_button.name = "UpgradeMode"
		mode_button.custom_minimum_size = Vector2(128.0, 72.0)
		mode_button.ignore_texture_size = true
		mode_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		mode_button.pressed.connect(PrestigeManager.toggle_upgrade_mode)
		mode_column.add_child(mode_button)
		var purchase_column := VBoxContainer.new()
		purchase_column.custom_minimum_size.x = 128.0
		purchase_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		purchase_column.add_theme_constant_override("separation", 4)
		actions.add_child(purchase_column)
		var purchase := TextureButton.new()
		purchase.texture_normal = SHOP_BUY_TEXTURE
		purchase.texture_click_mask = buy_click_mask
		purchase.custom_minimum_size = Vector2(128.0, 72.0)
		purchase.ignore_texture_size = true
		purchase.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		purchase.pressed.connect(_request_shop_row_purchase.bind(item.id))
		purchase_column.add_child(purchase)
		var price := Label.new()
		price.name = "Price"
		price.text = "%s짬" % FORMAT.format_number(item.get_price())
		price.add_theme_font_size_override("font_size", 22)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		price.mouse_filter = Control.MOUSE_FILTER_PASS
		price.mouse_entered.connect(_on_shop_price_entered.bind(item.id))
		price.mouse_exited.connect(_on_shop_price_exited.bind(item.id))
		purchase_column.add_child(price)
		_shop_buttons[item.id] = purchase
		_shop_rows[item.id] = {"icon": item_icon, "title": item_title, "description": description, "mode": mode_column, "mode_button": mode_button}
		shop_list.add_child(card)


func _refresh_shop() -> void:
	shop_balance.text = "현재 짬: %s짬" % FORMAT.format_number(PrestigeManager.banked_jjam)
	for root_item_id: String in _shop_buttons:
		var item := PrestigeManager.get_shop_display_item(root_item_id)
		var purchase: TextureButton = _shop_buttons[root_item_id]
		var row: Dictionary = _shop_rows[root_item_id]
		var owned := PrestigeManager.owns_shop_item(item.id)
		row.icon.texture = item.icon
		row.icon.visible = item.icon != null
		row.title.text = item.item_name
		row.description.text = item.description
		var price := purchase.get_parent().get_node("Price") as Label
		price.text = "구매 완료" if owned else ("???짬" if PrestigeManager.is_shop_price_distant(item.id) else "%s짬" % FORMAT.format_number(item.get_price()))
		purchase.disabled = not PrestigeManager.can_purchase_shop_item(item.id)
		purchase.modulate = Color(0.55, 0.55, 0.55) if purchase.disabled else Color.WHITE
		purchase.tooltip_text = "구매 완료" if owned else "환생으로 확보한 현재 짬을 사용합니다."
		var root_item := PrestigeManager.get_shop_item(root_item_id)
		row.mode.visible = root_item.upgrade_levels > 1 and PrestigeManager.owns_shop_item(root_item_id)
		row.mode_button.texture_normal = PrestigeManager.get_upgrade_mode_icon()
		row.mode_button.tooltip_text = "현재 +%d 모드 · 클릭하여 +%d 모드로 전환" % [PrestigeManager.get_upgrade_mode(), PrestigeManager.get_next_upgrade_mode()]
	_update_shop_price_tooltip()


func _request_shop_row_purchase(root_item_id: String) -> void:
	var item := PrestigeManager.get_shop_display_item(root_item_id)
	if item != null:
		_request_shop_purchase(item.id)


func _on_shop_price_entered(root_item_id: String) -> void:
	_hovered_shop_price = root_item_id
	_update_shop_price_tooltip()


func _on_shop_price_exited(root_item_id: String) -> void:
	TooltipManager.hide_tooltip(_shop_price_tooltip_owner(root_item_id))
	if _hovered_shop_price == root_item_id:
		_hovered_shop_price = ""


func _shop_price_tooltip_owner(root_item_id: String) -> String:
	return "jjam_shop_price:%d:%s" % [get_instance_id(), root_item_id]


func _update_shop_price_tooltip() -> void:
	if _hovered_shop_price.is_empty():
		return
	var owner_id := _shop_price_tooltip_owner(_hovered_shop_price)
	var item := PrestigeManager.get_shop_display_item(_hovered_shop_price)
	if item == null or not shop_content.is_visible_in_tree() or EventManager.presentation_locked or not PrestigeManager.is_shop_price_distant(item.id):
		TooltipManager.hide_tooltip(owner_id)
		return
	var own_layer := get_canvas_layer_node()
	var tooltip_layer := maxi(RENDER_ORDER.ScreenLayer.HUD, own_layer.layer if own_layer != null else 0) + 1
	TooltipManager.show_tooltip(DISTANT_PRICE_HINT, owner_id, tooltip_layer)


func _clear_shop_price_tooltip() -> void:
	if not _hovered_shop_price.is_empty():
		_on_shop_price_exited(_hovered_shop_price)


func _on_shop_scroll(_value: float) -> void:
	_clear_shop_price_tooltip()


func _exit_tree() -> void:
	_clear_shop_price_tooltip()


func _request_shop_purchase(item_id: String) -> void:
	if EventManager.presentation_locked or not PrestigeManager.can_purchase_shop_item(item_id):
		return
	_pending_shop_item = item_id
	_refresh_confirmation()
	_fit_confirmation()
	confirmation_layer.show()
	confirmation_no.grab_focus()


func _refresh_shop_confirmation() -> void:
	var item := PrestigeManager.get_shop_item(_pending_shop_item)
	if item == null:
		_close_confirmation()
		return
	confirmation_question.text = "%s짬을 소모하여 [%s]을 구매하시겠습니까?" % [FORMAT.format_number(item.get_price()), item.item_name]
	confirmation_yes.disabled = not PrestigeManager.can_purchase_shop_item(item.id)
	confirmation_hint.text = "현재 짬의 절반 이상을 소모합니다!"
	confirmation_hint.add_theme_color_override("font_color", RED)
	confirmation_hint.visible = BIG.compare(BIG.multiply(item.get_price(), 2), PrestigeManager.banked_jjam) > 0
