class_name WorldPurchaseButton
extends Node2D

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")

@onready var purchased_sprite: Sprite2D = $PurchasedSprite
@onready var texture_button: TextureButton = $PurchaseButton
@onready var info_label: Label = $InfoLabel
@onready var hover_area: Area2D = $HoverArea
@onready var hover_collision: CollisionShape2D = $HoverArea/CollisionShape2D

var button_data: ButtonData
var world_position: Vector2 = Vector2.ZERO
var world_scale: Vector2 = Vector2.ONE
var world_texture: Texture2D
var _is_pointer_over_sprite: bool = false


func setup(data: ButtonData, layout_sprite: Sprite2D) -> void:
	button_data = data
	world_position = layout_sprite.position
	world_scale = layout_sprite.scale
	world_texture = layout_sprite.texture


func _ready() -> void:
	if button_data == null or not button_data.show_world_purchase_button:
		visible = false
		return
	if world_texture != null:
		purchased_sprite.texture = world_texture
		purchased_sprite.position = world_position
		purchased_sprite.scale = world_scale
		hover_area.position = world_position
		hover_area.scale = world_scale
		hover_area.input_pickable = true
		var hover_shape := RectangleShape2D.new()
		hover_shape.size = world_texture.get_size()
		hover_collision.shape = hover_shape
		hover_area.mouse_entered.connect(_on_mouse_entered_sprite)
		hover_area.mouse_exited.connect(_on_mouse_exited_sprite)
	texture_button.size = texture_button.texture_normal.get_size()
	texture_button.scale = button_data.world_purchase_button_scale
	texture_button.position = world_position + button_data.world_purchase_button_offset
	texture_button.position.x -= texture_button.size.x * texture_button.scale.x * 0.5
	info_label.position = world_position + button_data.world_purchase_info_offset
	info_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12, 1.0))
	info_label.add_theme_constant_override("outline_size", 3)
	texture_button.pressed.connect(_purchase)
	ButtonManager.button_state_changed.connect(_on_button_state_changed)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	EconomyManager.money_changed.connect(_on_money_changed)
	EconomyManager.multiplier_changed.connect(_refresh_purchased_tooltip)
	IncomeManager.income_changed.connect(_refresh_purchased_tooltip)
	_refresh()


func _refresh() -> void:
	if button_data == null:
		visible = false
		return
	visible = (not button_data.bought and ButtonManager.is_unlocked(button_data)) or (
		button_data.bought and world_texture != null
	)
	purchased_sprite.visible = button_data.bought and world_texture != null
	hover_area.visible = purchased_sprite.visible
	if not button_data.bought:
		TooltipManager.hide_tooltip(button_data.id)
	texture_button.visible = not button_data.bought
	info_label.visible = not button_data.bought
	info_label.text = "%s\n%s\n가격: %s" % [
		button_data.button_name,
		button_data.get_effect_description(),
		"무료" if is_zero_approx(button_data.price) else NUMBER_FORMATTER.format_number(button_data.price)
	]
	texture_button.disabled = not ButtonManager.can_purchase(button_data)
	# 구매 불가능시 버튼 음영 
	texture_button.modulate = Color(0.65, 0.65, 0.65) if texture_button.disabled else Color.WHITE


func _purchase() -> void:
	if button_data != null and ButtonManager.purchase(button_data):
		SoundManager.play_purchase_sound()


func _on_button_state_changed(changed_data: ButtonData) -> void:
	if button_data != null and changed_data.id == button_data.id:
		_refresh()


func _on_button_purchased(purchased_data: ButtonData) -> void:
	if button_data != null and purchased_data.id == button_data.id:
		_refresh()


func _on_money_changed(_new_money: float) -> void:
	_refresh()


func _on_mouse_entered_sprite() -> void:
	_is_pointer_over_sprite = true
	_refresh_purchased_tooltip()


func _on_mouse_exited_sprite() -> void:
	_is_pointer_over_sprite = false
	if button_data != null:
		TooltipManager.hide_tooltip(button_data.id)


func _refresh_purchased_tooltip() -> void:
	if not _is_pointer_over_sprite or button_data == null or not button_data.bought:
		return
	var tooltip_text := button_data.get_effect_description()
	if button_data.effect_type == ButtonData.EffectType.ACTIVATE_SOURCE:
		var source := IncomeManager.get_source(button_data.effect_target)
		if source != null:
			var payout := (
				(source.base_income + source.upgrade_income_per_level * (IncomeManager.get_source_level(source.id) - 1))
				* IncomeManager.get_source_multiplier(source.id)
				* EconomyManager.get_global_multiplier()
			)
			var production_time := IncomeManager.get_source_production_time(source.id)
			tooltip_text = "%s원/%ss" % [
				NUMBER_FORMATTER.format_number(payout),
				NUMBER_FORMATTER.format_number(production_time)
			]
	TooltipManager.show_tooltip(tooltip_text, button_data.id)
