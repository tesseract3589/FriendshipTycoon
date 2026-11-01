class_name BatchUpgradePanel
extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const BIG = preload("res://scripts/BigNumber.gd")
const UPGRADE_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_Upgrade.png")
const UPGRADE_BUTTON_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_UI_Upgrade.png")
const UPGRADE_HOLD = preload("res://scripts/UpgradeHoldRepeater.gd")
const UPGRADE_MODE_BADGE = preload("res://ui/UpgradeModeBadge.gd")
const UPGRADE_REPEAT_INITIAL_DELAY: float = UPGRADE_HOLD.INITIAL_DELAY
const PANEL_BASE_SIZE := Vector2(395.0, 404.0)
const PRICE_COLUMN_BASE_WIDTH: float = 85.0
const SCREEN_MARGIN: float = 12.0
const PANEL_RIGHT_INSET: float = 135.0
const ROW_SEPARATION: int = 20
const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")

@onready var list := ErrorManager.require_node(self, ^"Panel/Margin/VBox/Scroll/List", "VBoxContainer") as VBoxContainer
@onready var panel := ErrorManager.require_node(self, ^"Panel", "PanelContainer") as PanelContainer
@onready var open_button := ErrorManager.require_node(self, ^"OpenButton", "TextureButton") as TextureButton
@onready var close_button := ErrorManager.require_node(self, ^"Panel/Margin/VBox/CloseButton", "Button") as Button
@onready var scroll: ScrollContainer = $Panel/Margin/VBox/Scroll
@onready var panel_margin: MarginContainer = $Panel/Margin

var _held_source_id: String = ""
var _upgrade_repeat := UPGRADE_HOLD.new()
var _upgrade_click_mask: BitMap


func _ready() -> void:
	if not ErrorManager.initialize_component(self, [list, panel, open_button, close_button]):
		return
	_apply_panel_border()
	_upgrade_click_mask = BitMap.new()
	_upgrade_click_mask.create_from_image_alpha(UPGRADE_TEXTURE.get_image())
	open_button.texture_normal = UPGRADE_BUTTON_TEXTURE
	# Sidebar entries stay accessible above any registered panel's input backdrop.
	var sidebar_layer := CanvasLayer.new()
	sidebar_layer.name = "SidebarLayer"
	sidebar_layer.layer = RENDER_ORDER.ScreenLayer.SIDEBAR
	add_child(sidebar_layer)
	var sidebar := Control.new()
	sidebar.name = "Sidebar"
	sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar_layer.add_child(sidebar)
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	open_button.reparent(sidebar, false)
	RightPanelManager.register_sidebar_entry(open_button, 0)
	open_button.pressed.connect(_toggle_panel)
	close_button.pressed.connect(_toggle_panel)
	RightPanelManager.register_panel(panel)
	panel.visibility_changed.connect(_on_panel_visibility_changed)
	PrestigeManager.shop_changed.connect(_refresh_shop_unlock)
	IncomeManager.source_activation_changed.connect(_on_sources_changed)
	IncomeManager.income_changed.connect(_refresh_rows)
	PrestigeManager.upgrade_mode_changed.connect(_refresh_rows)
	EconomyManager.money_changed.connect(_refresh_rows)
	resized.connect(_fit_panel_to_viewport)
	SaveManager.progress_loaded.connect(func(_slot: int) -> void: RightPanelManager.close_all())
	_refresh_shop_unlock()
	_rebuild_rows()
	_fit_panel_to_viewport()


func _apply_panel_border() -> void:
	var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	# Keep the inherited background and padding so the border does not resize the panel.
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, style.get_content_margin(side))
	style.set_border_width_all(4)
	style.border_color = Color("#2cff21")
	panel.add_theme_stylebox_override("panel", style)


func _refresh_shop_unlock() -> void:
	var unlocked := PrestigeManager.is_feature_unlocked(&"batch_upgrade_panel")
	open_button.visible = unlocked
	open_button.disabled = not unlocked
	open_button.modulate = Color.WHITE if unlocked else Color(0.4, 0.4, 0.4)
	open_button.tooltip_text = "수입원 업그레이드" if unlocked else "짬 상점에서 수입원 업그레이드 패널을 구매해 주세요."
	if not unlocked:
		panel.hide()
		_stop_upgrade_hold()


func _fit_panel_to_viewport() -> void:
	if not is_instance_valid(panel) or not is_instance_valid(list):
		return
	var available_size := size - Vector2.ONE * SCREEN_MARGIN * 2.0
	var widest_price := PRICE_COLUMN_BASE_WIDTH
	var widest_info := 0.0
	for row in list.get_children():
		var info := row.get_node("Info") as Label
		var price := row.get_node("Purchase/Price") as Label
		widest_info = maxf(widest_info, ceilf(info.get_minimum_size().x))
		widest_price = maxf(widest_price, ceilf(price.get_minimum_size().x) + 8.0)
	var horizontal_padding := (
		panel_margin.get_theme_constant("margin_left")
		+ panel_margin.get_theme_constant("margin_right")
		+ panel.get_theme_stylebox("panel").get_minimum_size().x
		+ scroll.get_v_scroll_bar().get_combined_minimum_size().x
	)
	var desired_width := maxf(PANEL_BASE_SIZE.x, widest_info + ROW_SEPARATION + widest_price + horizontal_padding)
	var panel_size := Vector2(minf(desired_width, available_size.x), minf(PANEL_BASE_SIZE.y, available_size.y))
	# Keep both columns unwrapped; small screens can scroll horizontally instead.
	for row in list.get_children():
		var purchase := row.get_node("Purchase") as VBoxContainer
		purchase.custom_minimum_size.x = widest_price
	var right_inset := PANEL_RIGHT_INSET if panel_size.x + PANEL_RIGHT_INSET + SCREEN_MARGIN <= size.x else SCREEN_MARGIN
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = panel_size
	panel.position = Vector2(size.x - right_inset - panel.size.x, maxf(SCREEN_MARGIN, (size.y - panel.size.y) * 0.5))


func _process(delta: float) -> void:
	if _held_source_id.is_empty():
		return
	if not panel.is_visible_in_tree() or EventManager.presentation_locked or PrestigeManager.transition_in_progress:
		_stop_upgrade_hold()
		return
	_upgrade_repeat.advance(delta, _upgrade_source.bind(_held_source_id))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_stop_upgrade_hold()
	elif event is InputEventScreenTouch and not event.pressed:
		_stop_upgrade_hold()


func _toggle_panel() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED or not PrestigeManager.is_feature_unlocked(&"batch_upgrade_panel"):
		return
	RightPanelManager.toggle_panel(panel)


func _on_panel_visibility_changed() -> void:
	if panel.visible:
		_rebuild_rows()
		_fit_panel_to_viewport()
	else:
		_stop_upgrade_hold()


func _on_sources_changed(_source_id: String, _active: bool) -> void:
	_rebuild_rows()


func _rebuild_rows() -> void:
	if not ErrorManager.initialize_component(self, [list, panel, open_button, close_button]):
		return
	_stop_upgrade_hold()
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for source in IncomeManager.sources:
		if source == null or not IncomeManager.source_active.get(source.id, false):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", ROW_SEPARATION)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_OFF
		info.name = "Info"
		row.add_child(info)
		var purchase := VBoxContainer.new()
		purchase.name = "Purchase"
		purchase.custom_minimum_size.x = PRICE_COLUMN_BASE_WIDTH
		purchase.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		purchase.add_theme_constant_override("separation", -20)
		row.add_child(purchase)
		var price := Label.new()
		price.name = "Price"
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.autowrap_mode = TextServer.AUTOWRAP_OFF
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		purchase.add_child(price)
		var upgrade := TextureButton.new()
		upgrade.name = "Upgrade"
		upgrade.texture_normal = UPGRADE_TEXTURE
		# Match the rendered texture, excluding transparent pixels and aspect-fit padding.
		upgrade.texture_click_mask = _upgrade_click_mask
		upgrade.custom_minimum_size = Vector2(67.2, 67.2)
		upgrade.ignore_texture_size = true
		upgrade.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		upgrade.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		upgrade.button_down.connect(_on_upgrade_button_down.bind(source.id))
		upgrade.button_up.connect(_on_upgrade_button_up)
		purchase.add_child(upgrade)
		upgrade.add_child(UPGRADE_MODE_BADGE.new())
		list.add_child(row)
		_refresh_row(row, source)
	_fit_panel_to_viewport()


func _refresh_rows(_value = null) -> void:
	if not ErrorManager.initialize_component(self, [list]):
		return
	for row in list.get_children():
		var source_id: String = row.get_meta("source_id", "")
		var source := IncomeManager.get_source(source_id)
		if source != null:
			_refresh_row(row, source)
	_fit_panel_to_viewport()


func _refresh_row(row: HBoxContainer, source: IncomeSourceData) -> void:
	row.set_meta("source_id", source.id)
	var level := IncomeManager.get_source_level(source.id)
	var payout: Variant = IncomeManager.get_source_cycle_payout(source.id)
	var income_per_second: Variant = IncomeManager.get_source_income_unrounded(source.id)
	var cost: Variant = IncomeManager.get_upgrade_cost(source.id)
	var payout_gain: Variant = IncomeManager.get_upgrade_cycle_payout_gain(source.id)
	var next_label := "다음 %d레벨" % PrestigeManager.get_upgrade_mode() if PrestigeManager.get_upgrade_mode() > 1 else "다음 레벨"
	row.get_node("Info").text = "%s Lv.%d\n%s원/회\n%s +%s원/회\n초당 %s원" % [source.source_name, level, NUMBER_FORMATTER.format_number(payout), next_label, NUMBER_FORMATTER.format_number(payout_gain), NUMBER_FORMATTER.format_income_per_second(income_per_second)]
	row.get_node("Purchase/Price").text = "%s원" % NUMBER_FORMATTER.format_number(cost)
	var upgrade_button := row.get_node("Purchase/Upgrade") as TextureButton
	upgrade_button.disabled = BIG.compare(cost, 0.0) <= 0
	upgrade_button.modulate = Color(0.55, 0.55, 0.55) if upgrade_button.disabled or not EconomyManager.can_afford(cost) else Color.WHITE


func _on_upgrade_button_down(source_id: String) -> void:
	_held_source_id = source_id
	_upgrade_repeat.start(_upgrade_source.bind(source_id))


func _on_upgrade_button_up() -> void:
	_stop_upgrade_hold()


func _stop_upgrade_hold() -> void:
	_held_source_id = ""
	_upgrade_repeat.stop()


func _upgrade_source(source_id: String) -> bool:
	if not IncomeManager.source_active.get(source_id, false) or not panel.is_visible_in_tree() or EventManager.presentation_locked or PrestigeManager.transition_in_progress:
		_stop_upgrade_hold()
		return false
	if not IncomeManager.upgrade_source(source_id):
		return false
	SoundManager.play_income_upgrade_sound(IncomeManager.get_source_level(source_id))
	_refresh_rows()
	return true
