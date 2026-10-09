class_name WorldPurchaseButton
extends Node2D

const SIZE_POP_MOTION = preload("res://scripts/SizePopMotion.gd")
const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const WORLD_UI_MINIMUM_SCALE = preload("res://scripts/WorldUIMinimumScale.gd")

var purchased_visuals_root: Node2D
var texture_button: TextureButton
var info_label: Label

var button_data: ButtonData
var layout_root: Node2D
var hover_areas: Array[Area2D] = []
var world_texture: Texture2D
var layout_visuals: Array[Node2D] = []
var purchased_visuals: Array[Node2D] = []
var _pointer_over_areas: Dictionary = {}
var _purchase_layout: TextureButton
var _info_layout: Label


func setup(data: ButtonData, layout_element: Node2D, object_hover_areas: Array[Area2D], ui_layout: Node2D) -> void:
	button_data = data
	layout_root = layout_element
	hover_areas = object_hover_areas
	if not ErrorManager.validate_instance(layout_root, "WorldPurchaseButton.setup"):
		return
	_collect_layout_visuals(layout_root)
	if not ErrorManager.validate_instance(ui_layout, "WorldPurchaseButton.setup.ButtonLayout"):
		return
	_purchase_layout = ErrorManager.require_node(ui_layout, ^"PurchaseButton", "TextureButton") as TextureButton
	_info_layout = ErrorManager.require_node(ui_layout, ^"InfoLabel", "Label") as Label


func _ready() -> void:
	if not ErrorManager.initialize_component(self, [layout_root, button_data, _purchase_layout, _info_layout]):
		return
	if _purchase_layout.texture_normal == null:
		ErrorManager.report_error("MISSING_TEXTURE", "구매 버튼 이미지가 없습니다.", "WorldPurchaseButton.PurchaseButton")
		process_mode = Node.PROCESS_MODE_DISABLED
		hide()
		return
	if not button_data.show_world_purchase_button:
		visible = false
		return
	purchased_visuals_root = Node2D.new()
	purchased_visuals_root.name = "PurchasedSprite"
	add_child(purchased_visuals_root)
	texture_button = _purchase_layout.duplicate() as TextureButton
	info_label = _info_layout.duplicate() as Label
	add_child(texture_button)
	add_child(info_label)
	texture_button.mouse_filter = Control.MOUSE_FILTER_STOP
	if layout_root != null:
		purchased_visuals_root.global_transform = layout_root.global_transform
		for source_visual in layout_visuals:
			_add_purchased_visual(source_visual)
	if not hover_areas.is_empty():
		_configure_hover_areas()
	_apply_control_layout(texture_button, _purchase_layout)
	_apply_control_layout(info_label, _info_layout)
	RENDER_ORDER.apply_world_layer(texture_button, RENDER_ORDER.WorldLayer.BUTTON)
	RENDER_ORDER.apply_world_layer(info_label, RENDER_ORDER.WorldLayer.DESCRIPTION)
	texture_button.pressed.connect(_purchase)
	button_data.changed.connect(_refresh)
	ButtonManager.button_state_changed.connect(_on_button_state_changed)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	EconomyManager.money_changed.connect(_on_money_changed)
	EconomyManager.multiplier_changed.connect(_refresh_purchased_tooltip)
	IncomeManager.income_changed.connect(_refresh_purchased_tooltip)
	_refresh()
	WORLD_UI_MINIMUM_SCALE.attach(texture_button, Vector2(0.5, 0.0))
	WORLD_UI_MINIMUM_SCALE.attach(info_label, Vector2(0.5, 1.0))


func _apply_control_layout(control: Control, preview: Control) -> void:
	var local_transform := global_transform.affine_inverse() * preview.get_global_transform()
	control.size = preview.size
	control.rotation = local_transform.get_rotation()
	control.scale = local_transform.get_scale()
	control.position = local_transform.origin


func _refresh() -> void:
	if not ErrorManager.initialize_component(self, [purchased_visuals_root, texture_button, info_label]):
		return
	if button_data == null:
		visible = false
		return
	visible = (not button_data.bought and ButtonManager.is_unlocked(button_data)) or (
		button_data.bought and world_texture != null
	)
	var has_purchased_visual := button_data.bought and not purchased_visuals.is_empty()
	for purchased_visual in purchased_visuals:
		if not ErrorManager.validate_instance(purchased_visual, "WorldPurchaseButton:" + button_data.id):
			continue
		purchased_visual.visible = button_data.bought
	for area in hover_areas:
		if not ErrorManager.validate_instance(area, "WorldPurchaseButton:" + button_data.id + ".HoverArea"):
			continue
		area.input_pickable = (
			has_purchased_visual
			and (
				button_data.show_purchased_tooltip
				or not button_data.click_dialogues.is_empty()
			)
		)
	if not button_data.bought:
		_pointer_over_areas.clear()
		TooltipManager.hide_tooltip(button_data.id)
	texture_button.visible = not button_data.bought
	info_label.visible = not button_data.bought
	info_label.text = button_data.get_purchase_label_text()
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
	RENDER_ORDER.apply_world_layer(purchased_visual, RENDER_ORDER.get_effective_z_index(source_visual))
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
		if not ErrorManager.validate_instance(area, "WorldPurchaseButton:" + button_data.id + ".HoverArea"):
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
	if button_data.effect_type == ButtonData.EffectType.ACTIVATE_SOURCE:
		var source := IncomeManager.get_source(button_data.effect_target)
		if source != null:
			tooltip_text = source.get_tooltip_text(button_data.tooltip_text)
	TooltipManager.show_tooltip(tooltip_text, button_data.id)
