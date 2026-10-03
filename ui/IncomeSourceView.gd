class_name IncomeSourceView
extends Node2D

@export var source_data: IncomeSourceData

@onready var sprite: Sprite2D = $Sprite
@onready var hover_area: Area2D = $HoverArea
@onready var hover_collision: CollisionShape2D = $HoverArea/CollisionShape2D
@onready var timer_label: Label = $TimerLabel
@onready var purchase_info_label: Label = $PurchaseInfoLabel
@onready var purchase_button: TextureButton = $PurchaseButton

var purchase_data: ButtonData
var source_is_active: bool = false
var _is_pointer_over_source: bool = false


func setup(data: IncomeSourceData, source_purchase_data: ButtonData) -> void:
	source_data = data
	purchase_data = source_purchase_data


func _ready() -> void:
	if source_data == null:
		return

	sprite.texture = source_data.display_texture
	sprite.position = source_data.display_position
	sprite.scale = source_data.display_scale
	hover_area.position = source_data.display_position
	hover_area.scale = source_data.display_scale
	hover_area.input_pickable = true
	if source_data.display_texture != null:
		var hover_shape := RectangleShape2D.new()
		hover_shape.size = source_data.display_texture.get_size()
		hover_collision.shape = hover_shape
	timer_label.position = source_data.display_position + source_data.timer_offset
	purchase_info_label.position = source_data.display_position + source_data.purchase_info_offset
	purchase_button.position = source_data.display_position + source_data.purchase_button_offset
	purchase_button.size = source_data.purchase_button_size
	purchase_button.pressed.connect(_purchase_source)
	_style_text_label(timer_label)
	_style_text_label(purchase_info_label)
	hover_area.mouse_entered.connect(_on_mouse_entered_source)
	hover_area.mouse_exited.connect(_on_mouse_exited_source)
	IncomeManager.source_activation_changed.connect(_on_source_activation_changed)
	IncomeManager.source_timer_changed.connect(_on_source_timer_changed)
	IncomeManager.source_multiplier_changed.connect(_on_source_multiplier_changed)
	EconomyManager.money_changed.connect(_on_money_changed)
	EconomyManager.multiplier_changed.connect(_on_multiplier_changed)
	ButtonManager.button_state_changed.connect(_on_button_state_changed)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	_set_active(IncomeManager.source_active.get(source_data.id, false))
	_update_timer(IncomeManager.get_source_time_remaining(source_data.id))
	_refresh_purchase_button()


func _on_source_activation_changed(source_id: String, is_active: bool) -> void:
	if source_data != null and source_id == source_data.id:
		_set_active(is_active)


func _on_source_timer_changed(source_id: String, seconds_remaining: float) -> void:
	if source_data != null and source_id == source_data.id:
		_update_timer(seconds_remaining)


func _set_active(is_active: bool) -> void:
	source_is_active = is_active
	sprite.visible = is_active
	hover_area.visible = is_active and source_data.display_texture != null
	hover_area.input_pickable = is_active
	timer_label.visible = is_active
	if not is_active:
		_is_pointer_over_source = false
		TooltipManager.hide_tooltip(source_data.id)
	_refresh_purchase_button()


func _update_timer(seconds_remaining: float) -> void:
	if seconds_remaining <= 0.0:
		timer_label.text = ""
		return
	if seconds_remaining > 1.0:
		timer_label.text = "%ds" % ceili(seconds_remaining)
	else:
		timer_label.text = "%.2fs" % maxf(seconds_remaining, 0.01)


func _refresh_purchase_button() -> void:
	if purchase_data == null:
		purchase_info_label.visible = false
		purchase_button.visible = false
		return
	var can_show_purchase := not purchase_data.bought and not source_is_active
	purchase_button.visible = can_show_purchase
	purchase_info_label.visible = can_show_purchase
	purchase_button.disabled = not ButtonManager.can_purchase(purchase_data)
	purchase_info_label.text = _get_purchase_info()
	purchase_info_label.modulate = Color.WHITE if not purchase_button.disabled else Color(0.65, 0.65, 0.65)


func _get_purchase_info() -> String:
	var item_name := source_data.source_name if source_data != null else purchase_data.button_name
	if is_zero_approx(purchase_data.price):
		return "%s\nfree" % item_name
	return "%s\n%s원" % [item_name, _format_number(purchase_data.price)]


func _get_source_info() -> String:
	var production_time := source_data.base_time * source_data.time_multiplier
	var payout := (
		source_data.base_income
		* IncomeManager.get_source_multiplier(source_data.id)
		* EconomyManager.get_global_multiplier()
	)
	return source_data.tooltip_text \
		.replace("{source_name}", source_data.source_name) \
		.replace("{payout}", _format_number(payout)) \
		.replace("{time}", _format_number(production_time))


func _style_text_label(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 1.0))
	label.add_theme_constant_override("outline_size", 3)


func _on_mouse_entered_source() -> void:
	_is_pointer_over_source = true
	_refresh_tooltip()


func _on_mouse_exited_source() -> void:
	_is_pointer_over_source = false
	TooltipManager.hide_tooltip(source_data.id)


func _refresh_tooltip() -> void:
	if not source_is_active or not _is_pointer_over_source:
		return
	TooltipManager.show_tooltip(_get_source_info(), source_data.id)


func _on_source_multiplier_changed(changed_source_id: String) -> void:
	if source_data != null and changed_source_id == source_data.id:
		_refresh_tooltip()


func _on_multiplier_changed() -> void:
	_refresh_tooltip()


func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.2f" % value


func _purchase_source() -> void:
	if purchase_data != null:
		ButtonManager.purchase(purchase_data)


func _on_money_changed(_new_money: float) -> void:
	_refresh_purchase_button()


func _on_button_state_changed(changed_data: ButtonData) -> void:
	if purchase_data != null and changed_data.id == purchase_data.id:
		_refresh_purchase_button()


func _on_button_purchased(purchased_data: ButtonData) -> void:
	if purchase_data != null and purchased_data.id == purchase_data.id:
		_refresh_purchase_button()
