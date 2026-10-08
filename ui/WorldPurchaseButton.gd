class_name WorldPurchaseButton
extends Node2D

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const SIZE_POP_MOTION = preload("res://scripts/SizePopMotion.gd")

@onready var purchased_visuals_root: Node2D = $PurchasedSprite
@onready var texture_button: TextureButton = $PurchaseButton
@onready var info_label: Label = $InfoLabel

var button_data: ButtonData
var layout_root: Node2D
var hover_areas: Array[Area2D] = []
var world_position: Vector2 = Vector2.ZERO
var world_texture: Texture2D
var layout_visuals: Array[Node2D] = []
var purchased_visuals: Array[Node2D] = []
var _pointer_over_areas: Dictionary = {}


func setup(data: ButtonData, layout_element: Node2D, object_hover_areas: Array[Area2D]) -> void:
	button_data = data
	layout_root = layout_element
	hover_areas = object_hover_areas
	world_position = layout_root.global_position
	_collect_layout_visuals(layout_root)


func _ready() -> void:
	if button_data == null or not button_data.show_world_purchase_button:
		visible = false
		return
	if layout_root != null:
		purchased_visuals_root.global_transform = layout_root.global_transform
		for source_visual in layout_visuals:
			_add_purchased_visual(source_visual)
	if not hover_areas.is_empty():
		_configure_hover_areas()
	texture_button.size = texture_button.texture_normal.get_size()
	texture_button.scale = button_data.world_purchase_button_scale
	texture_button.z_as_relative = false
	texture_button.z_index = 30
	texture_button.position = world_position + button_data.world_purchase_button_offset
	texture_button.position.x -= texture_button.size.x * texture_button.scale.x * 0.5
	info_label.position = world_position + button_data.world_purchase_info_offset
	info_label.z_as_relative = false
	info_label.z_index = 40
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
	var has_purchased_visual := button_data.bought and not purchased_visuals.is_empty()
	for purchased_visual in purchased_visuals:
		purchased_visual.visible = button_data.bought
	for area in hover_areas:
		if area == null:
			continue
		area.input_pickable = (
			has_purchased_visual
			and (
				button_data.show_purchased_tooltip
				or not button_data.click_dialogues.is_empty()
			)
		)
	if not button_data.bought:
		TooltipManager.hide_tooltip(button_data.id)
	texture_button.visible = not button_data.bought
	info_label.visible = not button_data.bought
	info_label.text = "%s\n%s\n가격: %s" % [
		button_data.button_name,
		button_data.get_purchase_description(),
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
		SIZE_POP_MOTION.play(purchased_visuals)


func _on_money_changed(_new_money: float) -> void:
	_refresh()


func _collect_layout_visuals(node: Node) -> void:
	if node is Sprite2D or node is AnimatedSprite2D:
		var visual := node as Node2D
		layout_visuals.append(visual)
		if world_texture == null:
			world_texture = _get_visual_texture(visual)
		return
	for child in node.get_children():
		_collect_layout_visuals(child)


func _get_visual_texture(visual: Node2D) -> Texture2D:
	if visual is Sprite2D:
		return (visual as Sprite2D).texture
	if visual is AnimatedSprite2D:
		var animated_visual := visual as AnimatedSprite2D
		var frames := animated_visual.sprite_frames
		if frames != null and frames.has_animation(animated_visual.animation):
			return frames.get_frame_texture(animated_visual.animation, animated_visual.frame)
	return null


func _add_purchased_visual(source_visual: Node2D) -> void:
	var purchased_visual := source_visual.duplicate() as Node2D
	if purchased_visual == null:
		return
	purchased_visual.transform = layout_root.global_transform.affine_inverse() * source_visual.global_transform
	purchased_visual.z_as_relative = false
	purchased_visual.z_index = (
		source_visual.z_index
		if button_data.world_visual_layer == ButtonData.WorldVisualLayer.OBJECT
		else button_data.world_visual_layer
	)
	purchased_visual.visible = false
	purchased_visuals_root.add_child(purchased_visual)
	purchased_visuals.append(purchased_visual)
	for area_node in purchased_visual.find_children("*", "Area2D", true, false):
		var copied_area := area_node as Area2D
		copied_area.input_pickable = false
		copied_area.monitoring = false
		copied_area.monitorable = false
	if purchased_visual is AnimatedSprite2D:
		var animated_visual := purchased_visual as AnimatedSprite2D
		if animated_visual.sprite_frames != null:
			animated_visual.play(animated_visual.animation)


func _configure_hover_areas() -> void:
	for area in hover_areas:
		if area == null:
			continue
		area.input_pickable = false
		area.collision_layer = 1
		area.mouse_entered.connect(_on_mouse_entered_sprite.bind(area.get_instance_id()))
		area.mouse_exited.connect(_on_mouse_exited_sprite.bind(area.get_instance_id()))


func _on_mouse_entered_sprite(area_id: int) -> void:
	_pointer_over_areas[area_id] = true
	_refresh_purchased_tooltip()


func _on_mouse_exited_sprite(area_id: int) -> void:
	_pointer_over_areas.erase(area_id)
	if _pointer_over_areas.is_empty() and button_data != null:
		TooltipManager.hide_tooltip(button_data.id)


func _refresh_purchased_tooltip() -> void:
	if (
		_pointer_over_areas.is_empty()
		or button_data == null
		or not button_data.bought
		or not button_data.show_purchased_tooltip
	):
		if button_data != null:
			TooltipManager.hide_tooltip(button_data.id)
		return
	var tooltip_text := button_data.get_purchased_tooltip_text()
	if (
		button_data.tooltip_text.is_empty()
		and button_data.effect_type == ButtonData.EffectType.ACTIVATE_SOURCE
	):
		var source := IncomeManager.get_source(button_data.effect_target)
		if source != null:
			var payout := IncomeManager.get_source_cycle_payout(source.id)
			var production_time := IncomeManager.get_source_production_time(source.id)
			tooltip_text = "%s원/%ss" % [
				NUMBER_FORMATTER.format_number(payout),
				NUMBER_FORMATTER.format_number(production_time)
			]
	TooltipManager.show_tooltip(tooltip_text, button_data.id)
