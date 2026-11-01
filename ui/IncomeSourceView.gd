class_name IncomeSourceView
extends Node2D

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const WORLD_UI_MINIMUM_SCALE = preload("res://scripts/WorldUIMinimumScale.gd")
const BIG = preload("res://scripts/BigNumber.gd")
const UPGRADE_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_Upgrade.png")
const UPGRADE_HOLD = preload("res://scripts/UpgradeHoldRepeater.gd")
const HOVER_GLOW = preload("res://ui/effects/IncomeSourceHoverGlow.gd")
const UPGRADE_MODE_BADGE = preload("res://ui/UpgradeModeBadge.gd")

@export var source_data: IncomeSourceData

@onready var sprite := ErrorManager.require_node(self, ^"Sprite", "Sprite2D") as Sprite2D
@onready var hover_area := ErrorManager.require_node(self, ^"HoverArea", "Area2D") as Area2D
@onready var hover_collision := ErrorManager.require_node(self, ^"HoverArea/CollisionShape2D", "CollisionShape2D") as CollisionShape2D
@onready var timer_label := ErrorManager.require_node(self, ^"TimerLabel", "Label") as Label
@onready var upgrade_panel: PanelContainer = $UpgradeLayer/UpgradePanel
@onready var level_label: Label = $UpgradeLayer/UpgradePanel/UpgradeControls/Level
@onready var cycle_income_label: Label = $UpgradeLayer/UpgradePanel/UpgradeControls/CycleIncome
@onready var income_per_second_label: Label = $UpgradeLayer/UpgradePanel/UpgradeControls/IncomePerSecond
@onready var next_level_gain_label: Label = $UpgradeLayer/UpgradePanel/UpgradeControls/NextLevelGain
@onready var upgrade_button: TextureButton = $UpgradeLayer/UpgradePanel/UpgradeControls/Upgrade
@onready var upgrade_price: Label = $UpgradeLayer/UpgradePanel/UpgradeControls/Price

var source_is_active: bool = false
var _display_position: Vector2 = Vector2.ZERO
var _display_scale: Vector2 = Vector2.ONE
var _display_bounds: Rect2
var _dismissed_pointer_active: bool = false
var _upgrade_repeat := UPGRADE_HOLD.new()
var _hover_glow: HOVER_GLOW


func setup(data: IncomeSourceData, display_position: Vector2, display_scale: Vector2, display_bounds: Rect2 = Rect2()) -> void:
	source_data = data
	_display_position = display_position
	_display_scale = display_scale
	_display_bounds = display_bounds


func _ready() -> void:
	if not ErrorManager.initialize_component(self, [sprite, hover_area, hover_collision, timer_label]):
		return
	if not ErrorManager.validate_income_source(source_data):
		process_mode = Node.PROCESS_MODE_DISABLED
		hide()
		return

	sprite.position = _display_position
	sprite.scale = _display_scale
	hover_area.position = _display_position
	hover_area.scale = _display_scale
	# Main resolves source clicks on release, after distinguishing a click from a drag.
	hover_area.input_pickable = false
	if source_data.display_texture != null:
		var hover_shape := RectangleShape2D.new()
		hover_shape.size = source_data.display_texture.get_size()
		hover_collision.shape = hover_shape
	timer_label.position = _display_position + source_data.timer_offset
	RENDER_ORDER.apply_world_layer(timer_label, RENDER_ORDER.WorldLayer.DESCRIPTION)
	_style_text_label(timer_label)
	_style_text_label(level_label)
	_style_text_label(upgrade_price)
	_style_text_label(cycle_income_label)
	_style_text_label(income_per_second_label)
	_style_text_label(next_level_gain_label)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Main's layout sprite owns the visuals; source resources may have no texture.
	if not _display_bounds.has_area():
		var display_size := source_data.display_texture.get_size() * _display_scale.abs() if source_data.display_texture != null else Vector2.ZERO
		_display_bounds = Rect2(_display_position - display_size * 0.5, display_size)
	_hover_glow = HOVER_GLOW.new()
	_hover_glow.name = "HoverGlow"
	_hover_glow.setup(_display_bounds)
	RENDER_ORDER.apply_world_layer(_hover_glow, RENDER_ORDER.WorldLayer.HOVER_BORDER)
	add_child(_hover_glow)
	$UpgradeLayer.layer = RENDER_ORDER.ScreenLayer.WORLD_DESCRIPTION
	add_to_group("income_source_upgrade_views")
	var click_mask := BitMap.new()
	click_mask.create_from_image_alpha(UPGRADE_TEXTURE.get_image())
	upgrade_button.texture_click_mask = click_mask
	upgrade_button.add_child(UPGRADE_MODE_BADGE.new())
	upgrade_button.button_down.connect(_on_upgrade_button_down)
	upgrade_button.button_up.connect(_stop_upgrade_hold)
	IncomeManager.source_activation_changed.connect(_on_source_activation_changed)
	IncomeManager.source_timer_changed.connect(_on_source_timer_changed)
	IncomeManager.source_multiplier_changed.connect(_on_source_multiplier_changed)
	IncomeManager.source_speed_multiplier_changed.connect(_on_source_speed_multiplier_changed)
	IncomeManager.source_level_changed.connect(_on_source_level_changed)
	IncomeManager.income_changed.connect(_refresh_upgrade)
	PrestigeManager.upgrade_mode_changed.connect(_refresh_upgrade)
	EconomyManager.money_changed.connect(_refresh_upgrade)
	EconomyManager.multiplier_changed.connect(_on_multiplier_changed)
	EventManager.event_state_restored.connect(close_upgrade_panel)
	SaveManager.progress_loaded.connect(_on_progress_loaded)
	_set_active(IncomeManager.source_active.get(source_data.id, false))
	_update_timer(IncomeManager.get_source_time_remaining(source_data.id))
	WORLD_UI_MINIMUM_SCALE.attach(timer_label, Vector2(0.5, 1.0))
	_refresh_upgrade()


func get_upgrade_tutorial_anchor() -> Vector2:
	return to_global(Vector2(_display_bounds.get_center().x, minf(_display_bounds.position.y, timer_label.position.y)))


func _process(delta: float) -> void:
	if not _upgrade_repeat.active:
		return
	if not upgrade_panel.is_visible_in_tree() or EventManager.presentation_locked or PrestigeManager.transition_in_progress:
		_stop_upgrade_hold()
		return
	_upgrade_repeat.advance(delta, _upgrade_source)


func _input(event: InputEvent) -> void:
	var pointer_position := Vector2.ZERO
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if not event.pressed:
			_stop_upgrade_hold()
			_clear_pointer_dismissal.call_deferred()
			return
		pointer_position = event.position
	elif event is InputEventScreenTouch:
		if not event.pressed:
			_stop_upgrade_hold()
			_clear_pointer_dismissal.call_deferred()
			return
		pointer_position = event.position
	else:
		return
	if not upgrade_panel.is_visible_in_tree():
		return
	var local_point := upgrade_panel.get_global_transform_with_canvas().affine_inverse() * pointer_position
	if Rect2(Vector2.ZERO, upgrade_panel.size).has_point(local_point):
		return
	_dismissed_pointer_active = true
	close_upgrade_panel()
	# Let the clicked UI or world object handle this input, but prevent this same
	# source from reopening its panel when the outside click is released.


func _clear_pointer_dismissal() -> void:
	_dismissed_pointer_active = false


func contains_screen_point(screen_point: Vector2) -> bool:
	return source_is_active and _display_bounds.has_point(get_global_transform_with_canvas().affine_inverse() * screen_point)


func set_upgrade_hovered(hovered: bool) -> void:
	_hover_glow.set_hovered(hovered and source_is_active)


func toggle_upgrade_panel() -> void:
	if _dismissed_pointer_active:
		return
	if upgrade_panel.visible:
		close_upgrade_panel()
		return
	if not source_is_active or EventManager.presentation_locked or PrestigeManager.transition_in_progress:
		return
	get_tree().call_group("income_source_upgrade_views", "close_upgrade_panel")
	_refresh_upgrade()
	upgrade_panel.reset_size()
	upgrade_panel.show()
	# Position only on open so changing text cannot move an already open panel.
	_position_upgrade_panel()
	TooltipManager.hide_tooltip()
	EventManager.notify_income_upgrade_panel_opened(source_data.id)


func close_upgrade_panel() -> void:
	_stop_upgrade_hold()
	upgrade_panel.hide()


func _on_progress_loaded(_slot: int) -> void:
	close_upgrade_panel()


func _position_upgrade_panel() -> void:
	var viewport_size := get_viewport_rect().size
	var screen_bounds: Rect2 = get_global_transform_with_canvas() * _display_bounds
	var panel_scale := minf(1.0, minf(maxf(1.0, viewport_size.x - 24.0) / upgrade_panel.size.x, maxf(1.0, viewport_size.y - 24.0) / upgrade_panel.size.y))
	upgrade_panel.scale = Vector2.ONE * panel_scale
	var panel_size := upgrade_panel.size * panel_scale
	var panel_position := Vector2(screen_bounds.end.x + 12.0, screen_bounds.position.y)
	if panel_position.x + panel_size.x > viewport_size.x - 12.0:
		panel_position.x = screen_bounds.position.x - panel_size.x - 12.0
	panel_position.x = clampf(panel_position.x, 12.0, maxf(12.0, viewport_size.x - panel_size.x - 12.0))
	panel_position.y = clampf(panel_position.y, 12.0, maxf(12.0, viewport_size.y - panel_size.y - 12.0))
	upgrade_panel.position = panel_position


func _on_source_activation_changed(source_id: String, is_active: bool) -> void:
	if source_data != null and source_id == source_data.id:
		_set_active(is_active)


func _on_source_timer_changed(source_id: String, seconds_remaining: float) -> void:
	if source_data != null and source_id == source_data.id:
		_update_timer(seconds_remaining)


func _set_active(is_active: bool) -> void:
	source_is_active = is_active
	if not is_active:
		_hover_glow.clear()
	sprite.visible = is_active
	hover_area.visible = is_active and source_data.display_texture != null
	timer_label.visible = is_active
	close_upgrade_panel()
	if is_active:
		_refresh_upgrade()
	if not is_active:
		TooltipManager.hide_tooltip(source_data.id)


func _update_timer(seconds_remaining: float) -> void:
	if seconds_remaining <= 0.0:
		timer_label.text = ""
		return
	var production_time := IncomeManager.get_source_production_time(source_data.id)
	if production_time < 0.1:
		timer_label.text = "매 %s" % NUMBER_FORMATTER.format_time(production_time)
	elif seconds_remaining >= 10.0:
		timer_label.text = "%ds" % ceili(seconds_remaining)
	elif seconds_remaining >= 1.0:
		timer_label.text = "%.1fs" % seconds_remaining
	else:
		timer_label.text = "%.2fs" % maxf(seconds_remaining, 0.01)


func _style_text_label(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 1.0))
	label.add_theme_constant_override("outline_size", 4)


func _on_source_multiplier_changed(changed_source_id: String) -> void:
	if source_data != null and changed_source_id == source_data.id:
		_refresh_upgrade()


func _on_source_speed_multiplier_changed(changed_source_id: String) -> void:
	if source_data != null and changed_source_id == source_data.id:
		_refresh_upgrade()


func _on_multiplier_changed() -> void:
	_refresh_upgrade()


func _on_source_level_changed(source_id: String, _level: int) -> void:
	if source_data != null and source_id == source_data.id:
		_refresh_upgrade()


func _refresh_upgrade(_money: Variant = null) -> void:
	if not source_is_active:
		return
	level_label.text = "Lv.%d" % IncomeManager.get_source_level(source_data.id)
	$UpgradeLayer/UpgradePanel/UpgradeControls/NextHeading.text = "다음 %d레벨:" % PrestigeManager.get_upgrade_mode() if PrestigeManager.get_upgrade_mode() > 1 else "다음 레벨:"
	var cost: Variant = IncomeManager.get_upgrade_cost(source_data.id)
	upgrade_price.text = "%s원" % NUMBER_FORMATTER.format_number(cost)
	cycle_income_label.text = "%s초마다 %s원" % [NUMBER_FORMATTER.format_number(IncomeManager.get_source_production_time(source_data.id)), NUMBER_FORMATTER.format_number(IncomeManager.get_source_cycle_payout(source_data.id))]
	income_per_second_label.text = "초당 %s원" % NUMBER_FORMATTER.format_income_per_second(IncomeManager.get_source_income_unrounded(source_data.id))
	next_level_gain_label.text = "+%s원/회" % NUMBER_FORMATTER.format_number(IncomeManager.get_upgrade_cycle_payout_gain(source_data.id))
	upgrade_button.disabled = BIG.compare(cost, 0) <= 0
	upgrade_button.modulate = Color(0.55, 0.55, 0.55) if upgrade_button.disabled or not EconomyManager.can_afford(cost) else Color.WHITE


func _on_upgrade_button_down() -> void:
	_upgrade_repeat.start(_upgrade_source)


func _stop_upgrade_hold() -> void:
	_upgrade_repeat.stop()


func _upgrade_source() -> bool:
	if not source_is_active or not upgrade_panel.is_visible_in_tree() or EventManager.presentation_locked or PrestigeManager.transition_in_progress:
		_stop_upgrade_hold()
		return false
	if not IncomeManager.upgrade_source(source_data.id):
		return false
	SoundManager.play_income_upgrade_sound(IncomeManager.get_source_level(source_data.id))
	return true
