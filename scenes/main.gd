extends Node2D

const INCOME_SOURCE_VIEW_SCENE: PackedScene = preload("res://ui/income_source_view.tscn")
const WORLD_CLICK_DIALOGUE_SCENE: PackedScene = preload("res://ui/world_click_dialogue.tscn")
const OFFSCREEN_BUTTON_INDICATORS = preload("res://ui/OffscreenButtonIndicators.gd")
const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const JJAM_PRESENTATION = preload("res://scripts/JjamPrestigePresentation.gd")
const CAMERA_MIN_ZOOM: float = 0.4
const CAMERA_MAX_ZOOM: float = 2.5
const CAMERA_ZOOM_STEP: float = 1.1
const GROUND_BOTTOM_SCREEN_MARGIN: float = 24.0
const ENVIRONMENT_EDGE_MARGIN: float = 24.0

@onready var camera := ErrorManager.require_node(self, ^"Camera2D", "Camera2D") as Camera2D
@onready var wallpaper := ErrorManager.require_node(self, ^"World/WallPaper", "Sprite2D") as Sprite2D
@onready var ground := ErrorManager.require_node(self, ^"World/Ground/Ground1", "Sprite2D") as Sprite2D
@onready var money_label := ErrorManager.require_node(self, ^"HUD/Panel/VBoxContainer/MoneyLabel", "Label") as Label
@onready var income_label := ErrorManager.require_node(self, ^"HUD/Panel/VBoxContainer/IncomeLabel", "Label") as Label
@onready var income_source_views := ErrorManager.require_node(self, ^"World/IncomeSourceViews", "Node2D") as Node2D
@onready var world_layout := ErrorManager.require_node(self, ^"World/WorldLayout", "Node2D") as Node2D
@onready var button_layout := ErrorManager.require_node(self, ^"World/ButtonLayout/Buttons", "Node2D") as Node2D
@onready var developer_tools := ErrorManager.require_node(self, ^"DeveloperHUD/DeveloperTools", "Control") as DeveloperToolsPanel
@onready var clouds := ErrorManager.require_node(self, ^"World/Clouds", "Node2D") as CloudLayer
@onready var ground_layer := ErrorManager.require_node(self, ^"World/Ground", "Node2D") as Node2D
@onready var hud := ErrorManager.require_node(self, ^"HUD", "CanvasLayer") as CanvasLayer
@onready var developer_hud := ErrorManager.require_node(self, ^"DeveloperHUD", "CanvasLayer") as CanvasLayer
@onready var phone_dm_panel := ErrorManager.require_node(self, ^"HUD/PhoneDMPanel", "Control") as PhoneDMPanel
@onready var cat_watching_event := ErrorManager.require_node(self, ^"CatWatchingEvent", "CanvasLayer") as CatWatchingEvent

var _dragging_camera: bool = false
var _touch_points: Dictionary = {}
var _pinch_zoom_enabled: bool = false
var _last_pinch_distance: float = 0.0
var _world_hover_areas: Dictionary = {}
var _layout_elements: Dictionary = {}
var _button_layout_elements: Dictionary = {}
var _world_purchase_buttons: Dictionary = {}
var _offscreen_button_indicators := OFFSCREEN_BUTTON_INDICATORS.new()
var _camera_input_locked: bool = false
var _initial_camera_position := Vector2.ZERO
var _initial_camera_zoom := Vector2.ONE
var _camera_drag_distance: float = 0.0
var _jjam_click_candidate: bool = false


func _ready() -> void:
	if [camera, wallpaper, ground, money_label, income_label, income_source_views, world_layout, button_layout, developer_tools, clouds, ground_layer, hud, developer_hud, phone_dm_panel, cat_watching_event].has(null):
		ErrorManager.report_error("SCENE_INITIALIZATION", "메인 장면을 구성할 수 없어 실행을 중단했습니다.", "Main")
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	SaveManager.initialize()
	get_viewport().physics_object_picking_sort = true
	get_viewport().physics_object_picking_first_only = true
	camera.make_current()
	RENDER_ORDER.apply_world_layer(wallpaper, RENDER_ORDER.WorldLayer.SKY)
	RENDER_ORDER.apply_world_layer(clouds, RENDER_ORDER.WorldLayer.CLOUDS)
	RENDER_ORDER.apply_world_layer(ground_layer, RENDER_ORDER.WorldLayer.GROUND)
	hud.layer = RENDER_ORDER.ScreenLayer.HUD
	developer_hud.layer = RENDER_ORDER.ScreenLayer.DEVELOPER
	_offscreen_button_indicators.name = "OffscreenButtonIndicators"
	hud.add_child(_offscreen_button_indicators)
	ErrorManager.validate_visuals(wallpaper, "Main.WallPaper")
	ErrorManager.validate_visuals(ground_layer, "Main.Ground")
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	IncomeManager.source_activation_changed.connect(_on_source_activation_changed)
	EconomyManager.money_changed.connect(_refresh_finances)
	IncomeManager.income_changed.connect(_refresh_finances)
	ButtonManager.button_unlocked_by_purchase.connect(_on_button_unlocked_by_purchase)
	world_layout.visible = true
	_validate_world_layout()
	_prepare_world_hover_areas()
	_hide_world_layout_sprites()
	_create_income_source_views()
	_create_world_purchase_buttons()
	_create_world_click_dialogues()
	_refresh_finances()
	_clamp_camera_position()
	_initial_camera_position = camera.global_position
	_initial_camera_zoom = camera.zoom
	clouds.configure_world_bounds(_get_camera_horizontal_world_bounds(true))
	var presentation := JJAM_PRESENTATION.new()
	presentation.name = "JjamPrestigePresentation"
	presentation.setup(self, camera)
	add_child(presentation)
	SaveManager.progress_loaded.connect(_on_progress_loaded)


func _on_viewport_size_changed() -> void:
	_clamp_camera_position()
	clouds.configure_world_bounds(_get_camera_horizontal_world_bounds(true))


func _input(event: InputEvent) -> void:
	if _camera_input_locked:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		if developer_tools.is_visible_in_tree() or cat_watching_event.is_blocking_input() or phone_dm_panel.blocks_pointer(event.position):
			_dragging_camera = false
			_pinch_zoom_enabled = false
			if event is InputEventScreenTouch or event is InputEventScreenDrag:
				_touch_points.erase(event.index)
			# Let the topmost GUI handle clicks and scroll without moving the world camera.
			return
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
			if mouse_button.pressed:
				_camera_drag_distance = 0.0
				_jjam_click_candidate = _dragging_camera and _is_pointer_on_jjamtong()
			elif was_dragging and _jjam_click_candidate and _camera_drag_distance < 8.0 and _is_pointer_on_jjamtong():
				get_tree().call_group("jjam_prestige_panel", "open_panel")
			# Let world Area2D click handlers receive presses; consume only the drag release.
			if not mouse_button.pressed and was_dragging:
				get_viewport().set_input_as_handled()
		elif mouse_button.pressed and mouse_button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _is_pointer_over_world():
				_zoom_camera(mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging_camera:
		var mouse_motion := event as InputEventMouseMotion
		_camera_drag_distance += mouse_motion.relative.length()
		if not mouse_motion.relative.is_zero_approx():
			EventManager.notify_camera_interaction()
		camera.global_position -= mouse_motion.relative / camera.zoom
		_clamp_camera_position()
		get_viewport().set_input_as_handled()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		EventManager.notify_camera_interaction()
		_touch_points[event.index] = event.position
		if _touch_points.size() == 2:
			_jjam_click_candidate = false
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
		var minimum_zoom := _get_camera_minimum_zoom()
		var new_zoom := clampf(
			camera.zoom.x * pinch_distance / _last_pinch_distance,
			minimum_zoom,
			maxf(CAMERA_MAX_ZOOM, minimum_zoom)
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
	var minimum_zoom := _get_camera_minimum_zoom()
	var new_zoom := clampf(
		old_zoom * CAMERA_ZOOM_STEP if zoom_in else old_zoom / CAMERA_ZOOM_STEP,
		minimum_zoom,
		maxf(CAMERA_MAX_ZOOM, minimum_zoom)
	)
	if is_equal_approx(old_zoom, new_zoom):
		return

	EventManager.notify_camera_interaction()
	camera.zoom = Vector2.ONE * new_zoom
	_clamp_camera_position()


func _on_button_unlocked_by_purchase(button_data: ButtonData) -> void:
	var world_button := _world_purchase_buttons.get(button_data.id) as WorldPurchaseButton
	if is_instance_valid(world_button):
		_offscreen_button_indicators.point_to_button(world_button.texture_button)


func _clamp_camera_position() -> void:
	if _camera_input_locked:
		return
	_apply_camera_bounds()


func _apply_camera_bounds() -> void:
	# Even a wide/tall resized window must fit entirely inside the environment.
	var minimum_zoom := _get_camera_minimum_zoom()
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x, minimum_zoom, maxf(CAMERA_MAX_ZOOM, minimum_zoom))
	# Preserve the outer visible edges reached at max zoom-out, rather than camera centers.
	var viewport_half_width := get_viewport_rect().size.x * 0.5 / camera.zoom.x
	var world_bounds := _get_camera_horizontal_world_bounds()
	var environment := _get_environment_world_bounds()
	var min_camera_x := world_bounds.x + viewport_half_width
	var max_camera_x := world_bounds.y - viewport_half_width
	if min_camera_x <= max_camera_x:
		camera.global_position.x = clampf(camera.global_position.x, min_camera_x, max_camera_x)
	else:
		# A source near an outer edge can leave a smaller interval than the viewport.
		camera.global_position.x = clampf(camera.global_position.x, environment.position.x + viewport_half_width, environment.end.x - viewport_half_width)
	# Godot's positive Y axis points down. Let the camera descend far enough to show the
	# ground's top, while keeping the ground's lower edge outside the viewport.
	var viewport_half_height := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var min_camera_y := environment.position.y + viewport_half_height
	var max_camera_y := environment.end.y - viewport_half_height
	if min_camera_y <= max_camera_y:
		camera.global_position.y = clampf(camera.global_position.y, min_camera_y, max_camera_y)
	else:
		camera.global_position.y = environment.get_center().y


func _get_environment_world_bounds() -> Rect2:
	# Ground is a container of tiles; use their world-space union, not Ground1's width.
	var ground_bounds: Rect2 = ground.global_transform * ground.get_rect()
	for node in ground_layer.find_children("*", "Sprite2D", true, false):
		var sprite := node as Sprite2D
		if sprite.texture != null and sprite.is_visible_in_tree():
			var sprite_bounds: Rect2 = sprite.global_transform * sprite.get_rect()
			ground_bounds = ground_bounds.merge(sprite_bounds)
	var sky_bounds: Rect2 = wallpaper.global_transform * wallpaper.get_rect()
	var ground_surface_bounds: Rect2 = ground.global_transform * ground.get_rect()
	var left := maxf(ground_bounds.position.x, sky_bounds.position.x) + ENVIRONMENT_EDGE_MARGIN
	var right := minf(ground_bounds.end.x, sky_bounds.end.x) - ENVIRONMENT_EDGE_MARGIN
	var top := sky_bounds.position.y + ENVIRONMENT_EDGE_MARGIN
	var bottom := ground_surface_bounds.end.y - GROUND_BOTTOM_SCREEN_MARGIN
	return Rect2(Vector2(left, top), Vector2(maxf(1.0, right - left), maxf(1.0, bottom - top)))


func _get_camera_minimum_zoom() -> float:
	var environment := _get_environment_world_bounds()
	var viewport_size := get_viewport_rect().size
	return maxf(CAMERA_MIN_ZOOM, maxf(viewport_size.x / environment.size.x, viewport_size.y / environment.size.y))


func clamp_camera_after_presentation() -> void:
	_apply_camera_bounds()


func set_camera_input_locked(locked: bool) -> void:
	_camera_input_locked = locked
	_dragging_camera = false
	_pinch_zoom_enabled = false
	_jjam_click_candidate = false
	_touch_points.clear()
	get_viewport().physics_object_picking = not locked


func reset_camera_to_initial() -> void:
	camera.zoom = _initial_camera_zoom
	camera.global_position = _initial_camera_position
	_apply_camera_bounds()
	clouds.configure_world_bounds(_get_camera_horizontal_world_bounds(true))


func _on_progress_loaded(_slot: int) -> void:
	reset_camera_to_initial()


func get_jjamtong_visual() -> Node2D:
	var button := _world_purchase_buttons.get("jjamtong") as WorldPurchaseButton
	if is_instance_valid(button):
		for visual in button.purchased_visuals:
			if visual is HoverPeekSprite:
				return visual
	return null


func _is_pointer_on_jjamtong() -> bool:
	var bin := ButtonManager.get_button("jjamtong")
	if not PrestigeManager.jjam_unlocked or bin == null or not bin.bought:
		return false
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 1
	var areas := _get_world_hover_areas("jjamtong")
	for hit in get_world_2d().direct_space_state.intersect_point(query, 64):
		if areas.has(hit.collider):
			return true
	return false


func _get_camera_horizontal_world_bounds(include_locked_sources: bool = false) -> Vector2:
	var max_zoom_out_half_width := get_viewport_rect().size.x * 0.5 / CAMERA_MIN_ZOOM
	var source_bounds := _get_source_horizontal_bounds(include_locked_sources)
	if include_locked_sources:
		# Also cover the initial camera range before any source is purchased.
		source_bounds.x = minf(source_bounds.x, 0.0)
		source_bounds.y = maxf(source_bounds.y, 0.0)
	var source_limits := source_bounds + Vector2(-2.0 * max_zoom_out_half_width, 2.0 * max_zoom_out_half_width)
	var environment := _get_environment_world_bounds()
	var limited := Vector2(maxf(source_limits.x, environment.position.x), minf(source_limits.y, environment.end.x))
	if limited.x < limited.y:
		return limited
	return Vector2(environment.position.x, environment.end.x)


func _get_source_horizontal_bounds(include_locked_sources: bool = false) -> Vector2:
	var min_x := 0.0
	var max_x := 0.0
	var has_unlocked_source := false
	for source_data in IncomeManager.sources:
		if source_data == null:
			continue
		if not include_locked_sources and not IncomeManager.source_active.get(source_data.id, false):
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
		_world_purchase_buttons[button_data.id] = world_button


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
	var ordered_areas: Array[Area2D] = []
	for button_data in ButtonManager.buttons:
		if button_data == null:
			continue
		var layout_element := _get_layout_element(button_data.id)
		if layout_element == null:
			continue
		var hover_areas: Array[Area2D] = []
		for area_node in layout_element.find_children("HoverArea", "Area2D", true, false):
			var hover_area := area_node as Area2D
			ordered_areas.append(hover_area)
			hover_areas.append(hover_area)
		if not hover_areas.is_empty():
			_world_hover_areas[button_data.id] = hover_areas
	# Keep visual depth and layout tree order when detaching the input areas.
	ordered_areas.sort_custom(func(a: Area2D, b: Area2D) -> bool: return b.is_greater_than(a))
	for hover_area in ordered_areas:
		var original_transform := hover_area.global_transform
		var original_depth := RENDER_ORDER.get_effective_z_index(hover_area)
		hover_area.reparent(world_layout, true)
		hover_area.global_transform = original_transform
		RENDER_ORDER.apply_world_layer(hover_area, original_depth)
		hover_area.input_pickable = false
		hover_area.collision_layer = 1


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
	money_label.text = "자금: %s원" % NUMBER_FORMATTER.format_current_money(EconomyManager.money)
	income_label.text = "수입: %s원 / 초" % NUMBER_FORMATTER.format_income_per_second(IncomeManager.get_total_income_per_second())
