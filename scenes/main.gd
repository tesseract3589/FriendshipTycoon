extends Node2D

const INCOME_SOURCE_VIEW_SCENE: PackedScene = preload("res://ui/income_source_view.tscn")
const WORLD_CLICK_DIALOGUE_SCENE: PackedScene = preload("res://ui/world_click_dialogue.tscn")
const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const CAMERA_MIN_ZOOM: float = 0.4
const CAMERA_MAX_ZOOM: float = 2.5
const CAMERA_ZOOM_STEP: float = 1.1
const GROUND_BOTTOM_SCREEN_MARGIN: float = 24.0

@onready var camera := ErrorManager.require_node(self, ^"Camera2D", "Camera2D") as Camera2D
@onready var wallpaper := ErrorManager.require_node(self, ^"World/WallPaper", "Sprite2D") as Sprite2D
@onready var ground := ErrorManager.require_node(self, ^"World/Ground/Ground1", "Sprite2D") as Sprite2D
@onready var money_label := ErrorManager.require_node(self, ^"HUD/Panel/VBoxContainer/MoneyLabel", "Label") as Label
@onready var income_label := ErrorManager.require_node(self, ^"HUD/Panel/VBoxContainer/IncomeLabel", "Label") as Label
@onready var income_source_views := ErrorManager.require_node(self, ^"World/IncomeSourceViews", "Node2D") as Node2D
@onready var world_layout := ErrorManager.require_node(self, ^"World/WorldLayout", "Node2D") as Node2D
@onready var button_layout := ErrorManager.require_node(self, ^"World/ButtonLayout/Buttons", "Node2D") as Node2D
@onready var developer_tools := ErrorManager.require_node(self, ^"HUD/DeveloperTools", "Control") as DeveloperToolsPanel
@onready var camera_tutorial := ErrorManager.require_node(self, ^"HUD/CameraTutorial", "Control") as Control
@onready var camera_tutorial_label := ErrorManager.require_node(self, ^"HUD/CameraTutorial/Label", "Label") as Label
@onready var clouds := ErrorManager.require_node(self, ^"World/Clouds", "Node2D") as Node2D
@onready var ground_layer := ErrorManager.require_node(self, ^"World/Ground", "Node2D") as Node2D
@onready var hud := ErrorManager.require_node(self, ^"HUD", "CanvasLayer") as CanvasLayer

var _dragging_camera: bool = false
var _touch_points: Dictionary = {}
var _pinch_zoom_enabled: bool = false
var _last_pinch_distance: float = 0.0
var _camera_tutorial_dismissed: bool = false
var _world_hover_areas: Dictionary = {}
var _layout_elements: Dictionary = {}
var _button_layout_elements: Dictionary = {}


func _ready() -> void:
	if [camera, wallpaper, ground, money_label, income_label, income_source_views, world_layout, button_layout, developer_tools, camera_tutorial, camera_tutorial_label, clouds, ground_layer, hud].has(null):
		ErrorManager.report_error("SCENE_INITIALIZATION", "메인 장면을 구성할 수 없어 실행을 중단했습니다.", "Main")
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	camera.make_current()
	RENDER_ORDER.apply_world_layer(wallpaper, RENDER_ORDER.WorldLayer.SKY)
	RENDER_ORDER.apply_world_layer(clouds, RENDER_ORDER.WorldLayer.CLOUDS)
	RENDER_ORDER.apply_world_layer(ground_layer, RENDER_ORDER.WorldLayer.GROUND)
	hud.layer = RENDER_ORDER.ScreenLayer.HUD
	ErrorManager.validate_visuals(wallpaper, "Main.WallPaper")
	ErrorManager.validate_visuals(ground_layer, "Main.Ground")
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	IncomeManager.source_activation_changed.connect(_on_source_activation_changed)
	EconomyManager.money_changed.connect(_refresh_finances)
	IncomeManager.income_changed.connect(_refresh_finances)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	world_layout.visible = true
	_validate_world_layout()
	_prepare_world_hover_areas()
	_hide_world_layout_sprites()
	_create_income_source_views()
	_create_world_purchase_buttons()
	_create_world_click_dialogues()
	_refresh_finances()
	_clamp_camera_position()


func _on_viewport_size_changed() -> void:
	_clamp_camera_position()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
		return
	if (
		event.device == InputEvent.DEVICE_ID_EMULATION
		and _touch_points.size() >= 2
	):
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			var was_dragging := _dragging_camera
			_dragging_camera = mouse_button.pressed and _is_pointer_over_world()
			# Let world Area2D click handlers receive presses; consume only the drag release.
			if not mouse_button.pressed and was_dragging:
				get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _is_pointer_over_world():
				_zoom_camera(mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging_camera:
		var mouse_motion := event as InputEventMouseMotion
		if not mouse_motion.relative.is_zero_approx():
			_dismiss_camera_tutorial()
		camera.global_position -= mouse_motion.relative / camera.zoom
		_clamp_camera_position()
		get_viewport().set_input_as_handled()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_dismiss_camera_tutorial()
		_touch_points[event.index] = event.position
		if _touch_points.size() == 2:
			_pinch_zoom_enabled = _is_pointer_over_world()
			_last_pinch_distance = _get_pinch_distance()
			_dragging_camera = false
	else:
		_touch_points.erase(event.index)
		if _touch_points.size() < 2:
			_pinch_zoom_enabled = false
			_last_pinch_distance = 0.0


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touch_points.has(event.index):
		return
	_touch_points[event.index] = event.position
	if not _pinch_zoom_enabled or _touch_points.size() != 2:
		return

	var pinch_distance := _get_pinch_distance()
	if _last_pinch_distance > 0.0 and pinch_distance > 0.0:
		var new_zoom := clampf(
			camera.zoom.x * pinch_distance / _last_pinch_distance,
			CAMERA_MIN_ZOOM,
			CAMERA_MAX_ZOOM
		)
		camera.zoom = Vector2.ONE * new_zoom
		_clamp_camera_position()
	_last_pinch_distance = pinch_distance
	get_viewport().set_input_as_handled()


func _get_pinch_distance() -> float:
	if _touch_points.size() != 2:
		return 0.0
	var positions: Array = _touch_points.values()
	return positions[0].distance_to(positions[1])


func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		developer_tools.toggle()
		get_viewport().set_input_as_handled()


func _is_pointer_over_world() -> bool:
	return get_viewport().gui_get_hovered_control() == null


func _zoom_camera(zoom_in: bool) -> void:
	var old_zoom := camera.zoom.x
	var new_zoom := clampf(
		old_zoom * CAMERA_ZOOM_STEP if zoom_in else old_zoom / CAMERA_ZOOM_STEP,
		CAMERA_MIN_ZOOM,
		CAMERA_MAX_ZOOM
	)
	if is_equal_approx(old_zoom, new_zoom):
		return

	_dismiss_camera_tutorial()
	camera.zoom = Vector2.ONE * new_zoom
	_clamp_camera_position()


func _on_button_purchased(button_data: ButtonData) -> void:
	if button_data != null and button_data.id == "hall_foundation":
		_show_camera_tutorial()


func _show_camera_tutorial() -> void:
	_camera_tutorial_dismissed = false
	TooltipManager.hide_tooltip()
	camera_tutorial_label.text = (
		"터치 및 드래그로 카메라 조정"
		if OS.has_feature("mobile")
		else "마우스 드래그/휠로 카메라 조정"
	)
	camera_tutorial.modulate = Color.WHITE
	camera_tutorial.visible = true


func _dismiss_camera_tutorial() -> void:
	if _camera_tutorial_dismissed or not camera_tutorial.visible:
		return
	_camera_tutorial_dismissed = true
	var fade := create_tween()
	fade.tween_property(camera_tutorial, "modulate:a", 0.0, 1.5)
	fade.tween_callback(camera_tutorial.hide)


func _clamp_camera_position() -> void:
	# Preserve the outer visible edges reached at max zoom-out, rather than camera centers.
	var max_zoom_out_half_width := get_viewport_rect().size.x * 0.5 / CAMERA_MIN_ZOOM
	var viewport_half_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var horizontal_bounds := _get_unlocked_source_horizontal_bounds()
	var world_left := horizontal_bounds.x - 2.0 * max_zoom_out_half_width
	var world_right := horizontal_bounds.y + 2.0 * max_zoom_out_half_width
	camera.global_position.x = clampf(
		camera.global_position.x,
		world_left + viewport_half_width,
		world_right - viewport_half_width
	)
	# Godot's positive Y axis points down. Let the camera descend far enough to show the
	# ground's top, while keeping the ground's lower edge outside the viewport.
	var viewport_half_height := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var ground_bottom := ground.global_position.y
	if ground.texture != null:
		ground_bottom += ground.texture.get_size().y * absf(ground.global_scale.y) * 0.5
	var max_camera_y := ground_bottom - viewport_half_height - GROUND_BOTTOM_SCREEN_MARGIN
	camera.global_position.y = minf(camera.global_position.y, max_camera_y)
	if wallpaper.texture != null:
		var wallpaper_top := (
			wallpaper.global_position.y
			- wallpaper.texture.get_size().y * absf(wallpaper.global_scale.y) * 0.5
		)
		var min_camera_y := wallpaper_top + viewport_half_height
		camera.global_position.y = maxf(camera.global_position.y, min_camera_y)


func _get_unlocked_source_horizontal_bounds() -> Vector2:
	var min_x := 0.0
	var max_x := 0.0
	var has_unlocked_source := false
	for source_data in IncomeManager.sources:
		if source_data == null or not IncomeManager.source_active.get(source_data.id, false):
			continue
		var layout_sprite := _get_layout_sprite(source_data.id)
		if layout_sprite == null or layout_sprite.texture == null:
			continue
		var source_bounds: Rect2 = layout_sprite.global_transform * layout_sprite.get_rect()
		var source_left := source_bounds.position.x
		var source_right := source_bounds.end.x
		if not has_unlocked_source:
			min_x = source_left
			max_x = source_right
			has_unlocked_source = true
		else:
			min_x = minf(min_x, source_left)
			max_x = maxf(max_x, source_right)
	if not has_unlocked_source:
		return Vector2.ZERO
	return Vector2(min_x, max_x)


func _on_source_activation_changed(_source_id: String, _is_active: bool) -> void:
	_clamp_camera_position()


func _create_income_source_views() -> void:
	for source_data in IncomeManager.sources:
		if source_data == null:
			continue
		var layout_sprite := _get_layout_sprite(source_data.id)
		if layout_sprite == null:
			continue
		var source_view := INCOME_SOURCE_VIEW_SCENE.instantiate() as IncomeSourceView
		source_view.setup(
			source_data,
			income_source_views.to_local(layout_sprite.global_position),
			layout_sprite.global_scale / income_source_views.global_scale
		)
		income_source_views.add_child(source_view)


func _create_world_purchase_buttons() -> void:
	var buttons_by_layout_node: Dictionary = {}
	for button_data in ButtonManager.buttons:
		if button_data == null or not button_data.show_world_purchase_button:
			continue
		var layout_sprite := _get_layout_element(button_data.id)
		if layout_sprite == null:
			continue
		buttons_by_layout_node[layout_sprite.get_instance_id()] = button_data
	# Keep equal-depth visuals in layout tree order, regardless of the button registry order.
	for layout_node in world_layout.find_children("*", "Node2D", true, false):
		var button_data := buttons_by_layout_node.get(layout_node.get_instance_id()) as ButtonData
		if button_data == null:
			continue
		var hover_areas := _get_world_hover_areas(button_data.id)
		var world_button := WorldPurchaseButton.new()
		world_button.name = button_data.id + "_PurchaseView"
		world_button.setup(button_data, layout_node as Node2D, hover_areas, _button_layout_elements[button_data.id])
		income_source_views.add_child(world_button)


func _get_layout_sprite(element_id: String) -> Sprite2D:
	return _get_layout_element(element_id) as Sprite2D


func _get_layout_element(element_id: String) -> Node2D:
	var element: Variant = _layout_elements.get(element_id)
	if _layout_elements.has(element_id) and not is_instance_valid(element):
		ErrorManager.report_error("FREED_WORLD_NODE", "사용 중인 월드 배치 노드가 삭제되었습니다.", "WorldLayout:" + element_id)
		return null
	return element as Node2D


func _validate_world_layout() -> void:
	_layout_elements.clear()
	_button_layout_elements.clear()
	var invalid_sources: Dictionary = {}
	var invalid_buttons: Array[String] = []
	ErrorManager.validate_buttons(ButtonManager.buttons, IncomeManager.sources)
	for source in IncomeManager.sources:
		if source == null or IncomeManager.get_source(source.id) != source or not ErrorManager.validate_income_source(source):
			continue
		var element := ErrorManager.find_world_element(world_layout, source.id, "Sprite2D")
		if element == null or not ErrorManager.validate_visuals(element, "IncomeSourceData:" + source.id):
			invalid_sources[source.id] = true
			continue
		_layout_elements[source.id] = element
	for data in ButtonManager.buttons:
		if data == null:
			continue
		if not ErrorManager.validate_button(data, ButtonManager.buttons, IncomeManager.sources) or invalid_sources.has(data.effect_target):
			invalid_buttons.append(data.id)
			_layout_elements.erase(data.id)
			continue
		if not data.show_world_purchase_button and data.click_dialogues.is_empty():
			continue
		var element := ErrorManager.find_world_element(world_layout, data.id)
		if element == null or not ErrorManager.validate_visuals(element, "ButtonData:" + data.id):
			invalid_buttons.append(data.id)
			_layout_elements.erase(data.id)
			continue
		if (data.show_purchased_tooltip or not data.click_dialogues.is_empty()) and not ErrorManager.validate_hover_areas(element, "ButtonData:" + data.id):
			invalid_buttons.append(data.id)
			_layout_elements.erase(data.id)
			continue
		if data.show_world_purchase_button:
			var ui_layout := ErrorManager.find_world_element(button_layout, data.id, "Node2D")
			if ui_layout == null:
				invalid_buttons.append(data.id)
				_layout_elements.erase(data.id)
				continue
			var purchase_preview := ErrorManager.require_node(ui_layout, ^"PurchaseButton", "TextureButton") as TextureButton
			var info_preview := ErrorManager.require_node(ui_layout, ^"InfoLabel", "Label") as Label
			if purchase_preview == null or info_preview == null:
				invalid_buttons.append(data.id)
				_layout_elements.erase(data.id)
				continue
			if purchase_preview.texture_normal == null:
				ErrorManager.report_error("MISSING_TEXTURE", "구매 버튼 이미지가 없습니다.", "ButtonLayout:" + data.id)
				invalid_buttons.append(data.id)
				_layout_elements.erase(data.id)
				continue
			_button_layout_elements[data.id] = ui_layout
		_layout_elements[data.id] = element
	ButtonManager.set_world_invalid_buttons(invalid_buttons)


func _get_world_hover_areas(button_id: String) -> Array[Area2D]:
	var result: Array[Area2D] = []
	var stored_areas: Variant = _world_hover_areas.get(button_id, [])
	if stored_areas is Array:
		for area in stored_areas:
			if area is Area2D:
				result.append(area as Area2D)
	return result


func _prepare_world_hover_areas() -> void:
	_world_hover_areas.clear()
	for button_data in ButtonManager.buttons:
		if button_data == null:
			continue
		var layout_element := _get_layout_element(button_data.id)
		if layout_element == null:
			continue
		var hover_areas: Array[Area2D] = []
		for area_node in layout_element.find_children("HoverArea", "Area2D", true, false):
			var hover_area := area_node as Area2D
			var original_transform := hover_area.global_transform
			hover_area.reparent(world_layout, true)
			hover_area.global_transform = original_transform
			hover_area.input_pickable = false
			hover_area.collision_layer = 1
			hover_areas.append(hover_area)
		if not hover_areas.is_empty():
			_world_hover_areas[button_data.id] = hover_areas


func _hide_world_layout_sprites() -> void:
	for node in world_layout.find_children("*", "Sprite2D", true, false):
		(node as CanvasItem).visible = false
	for node in world_layout.find_children("*", "AnimatedSprite2D", true, false):
		(node as CanvasItem).visible = false


func _create_world_click_dialogues() -> void:
	for button_data in ButtonManager.buttons:
		if button_data == null or button_data.click_dialogues.is_empty():
			continue
		var layout_element := _get_layout_element(button_data.id)
		if layout_element == null:
			continue
		var hover_areas := _get_world_hover_areas(button_data.id)
		if hover_areas.is_empty():
			ErrorManager.report_error("MISSING_HOVER_AREA", "대사를 표시할 클릭 영역을 찾을 수 없습니다.", "ButtonData:" + button_data.id)
			continue
		var dialogue_component := WORLD_CLICK_DIALOGUE_SCENE.instantiate() as WorldClickDialogue
		dialogue_component.setup(button_data, layout_element, hover_areas)
		income_source_views.add_child(dialogue_component)


func _refresh_finances(_value = null) -> void:
	money_label.text = "자금: %s원" % NUMBER_FORMATTER.format_number(EconomyManager.money)
	income_label.text = "수입: %s원 / 초" % NUMBER_FORMATTER.format_income_per_second(IncomeManager.get_total_income_per_second())
