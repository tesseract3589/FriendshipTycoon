class_name IncomeUpgradePanel
extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const UPGRADE_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_Upgrade.png")
const UPGRADE_BUTTON_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_UI_Upgrade.png")
const UPGRADE_REPEAT_INITIAL_DELAY: float = 0.4
const UPGRADE_REPEAT_ACCELERATION: float = 0.82
const UPGRADE_REPEAT_MIN_INTERVAL: float = 0.06
const PANEL_BASE_SIZE := Vector2(395.0, 404.0)
const PRICE_COLUMN_BASE_WIDTH: float = 85.0
const SCREEN_MARGIN: float = 12.0
const PANEL_RIGHT_INSET: float = 135.0

@onready var list := ErrorManager.require_node(self, ^"Panel/Margin/VBox/Scroll/List", "VBoxContainer") as VBoxContainer
@onready var panel := ErrorManager.require_node(self, ^"Panel", "PanelContainer") as PanelContainer
@onready var open_button := ErrorManager.require_node(self, ^"OpenButton", "TextureButton") as TextureButton
@onready var close_button := ErrorManager.require_node(self, ^"Panel/Margin/VBox/CloseButton", "Button") as Button

var _held_source_id: String = ""
var _repeat_timer: float = 0.0
var _repeat_interval: float = UPGRADE_REPEAT_INITIAL_DELAY


func _ready() -> void:
	if not ErrorManager.initialize_component(self, [list, panel, open_button, close_button]):
		return
	open_button.texture_normal = UPGRADE_BUTTON_TEXTURE
	open_button.pressed.connect(_toggle_panel)
	close_button.pressed.connect(_toggle_panel)
	IncomeManager.source_activation_changed.connect(_on_sources_changed)
	IncomeManager.income_changed.connect(_refresh_rows)
	EconomyManager.money_changed.connect(_refresh_rows)
	resized.connect(_fit_panel_to_viewport)
	_rebuild_rows()
	_fit_panel_to_viewport()


func _fit_panel_to_viewport() -> void:
	if not is_instance_valid(panel) or not is_instance_valid(list):
		return
	var available_size := size - Vector2.ONE * SCREEN_MARGIN * 2.0
	var widest_price := PRICE_COLUMN_BASE_WIDTH
	for row in list.get_children():
		var price := row.get_node("Purchase/Price") as Label
		var font := price.get_theme_font("font")
		var price_width := ceilf(font.get_string_size(price.text, HORIZONTAL_ALIGNMENT_LEFT, -1, price.get_theme_font_size("font_size")).x) + 8.0
		row.set_meta("price_width", maxf(PRICE_COLUMN_BASE_WIDTH, price_width))
		widest_price = maxf(widest_price, price_width)
	var desired_width := PANEL_BASE_SIZE.x + widest_price - PRICE_COLUMN_BASE_WIDTH
	var panel_size := Vector2(minf(desired_width, available_size.x), minf(PANEL_BASE_SIZE.y, available_size.y))
	# Reserve room for the information, row spacing, margins and a scrollbar.
	var price_width_limit := maxf(PRICE_COLUMN_BASE_WIDTH, panel_size.x - 162.0)
	for row in list.get_children():
		var purchase := row.get_node("Purchase") as VBoxContainer
		purchase.custom_minimum_size.x = minf(float(row.get_meta("price_width")), price_width_limit)
	var right_inset := PANEL_RIGHT_INSET if panel_size.x + PANEL_RIGHT_INSET + SCREEN_MARGIN <= size.x else SCREEN_MARGIN
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = panel_size
	panel.position = Vector2(size.x - right_inset - panel.size.x, maxf(SCREEN_MARGIN, (size.y - panel.size.y) * 0.5))


func _process(delta: float) -> void:
	if _held_source_id.is_empty() or not panel.visible:
		return
	_repeat_timer -= delta
	if _repeat_timer > 0.0:
		return
	if not _upgrade_source(_held_source_id):
		_stop_upgrade_hold()
		return
	_repeat_interval = maxf(UPGRADE_REPEAT_MIN_INTERVAL, _repeat_interval * UPGRADE_REPEAT_ACCELERATION)
	_repeat_timer = _repeat_interval


func _toggle_panel() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	panel.visible = not panel.visible
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
		row.add_theme_constant_override("separation", 20)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		purchase.add_child(price)
		var upgrade := TextureButton.new()
		upgrade.name = "Upgrade"
		upgrade.texture_normal = UPGRADE_TEXTURE
		upgrade.custom_minimum_size = Vector2(67.2, 67.2)
		upgrade.ignore_texture_size = true
		upgrade.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		upgrade.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		upgrade.button_down.connect(_on_upgrade_button_down.bind(source.id))
		upgrade.button_up.connect(_on_upgrade_button_up)
		purchase.add_child(upgrade)
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
	var payout := IncomeManager.get_source_cycle_payout(source.id)
	var cost := IncomeManager.get_upgrade_cost(source.id)
	var payout_gain := IncomeManager.get_upgrade_cycle_payout_gain(source.id)
	row.get_node("Info").text = "%s  Lv.%d\n%s원 / 회\n다음 레벨 +%s원/회" % [source.source_name, level, NUMBER_FORMATTER.format_number(payout), NUMBER_FORMATTER.format_number(payout_gain)]
	row.get_node("Purchase/Price").text = "%s원" % NUMBER_FORMATTER.format_number(cost)
	var upgrade_button := row.get_node("Purchase/Upgrade") as TextureButton
	upgrade_button.disabled = cost <= 0.0 or not EconomyManager.can_afford(cost)
	upgrade_button.modulate = Color(0.65, 0.65, 0.65) if upgrade_button.disabled else Color.WHITE


func _on_upgrade_button_down(source_id: String) -> void:
	_held_source_id = source_id
	_repeat_interval = UPGRADE_REPEAT_INITIAL_DELAY
	if not _upgrade_source(source_id):
		_stop_upgrade_hold()
		return
	_repeat_timer = _repeat_interval


func _on_upgrade_button_up() -> void:
	_stop_upgrade_hold()


func _stop_upgrade_hold() -> void:
	_held_source_id = ""
	_repeat_timer = 0.0


func _upgrade_source(source_id: String) -> bool:
	if not IncomeManager.upgrade_source(source_id):
		return false
	SoundManager.play_purchase_sound()
	_refresh_rows()
	return true
