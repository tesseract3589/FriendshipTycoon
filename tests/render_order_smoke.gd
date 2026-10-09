extends Node

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")

var _failures: int = 0
@onready var scene_root: Window = get_tree().root


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var button_manager := scene_root.get_node("ButtonManager")
	var economy_manager := scene_root.get_node("EconomyManager")
	# Neither purchase list order nor gameplay categories may choose visual depth.
	button_manager.buttons.reverse()
	for data in button_manager.buttons:
		data.type = ButtonData.Type.STRUCTURE
	var main: Node = load("res://scenes/main.tscn").instantiate()
	scene_root.add_child(main)
	await get_tree().process_frame

	economy_manager.add_money(1.0e12)
	var pending: Array = button_manager.buttons.duplicate()
	# Editor presets may already mark some elements as purchased.
	for data in pending.duplicate():
		if data.bought:
			pending.erase(data)
	while not pending.is_empty():
		var progressed := false
		for data in pending.duplicate():
			var previous_bike_cycle: float = 0.0
			var previous_wireless_payout: float = 0.0
			var previous_wireless_cycle: float = 0.0
			if data.id == "wireless_antenna":
				_check(button_manager.is_unlocked(data) == button_manager.get_button("bike_delivery").bought, "Wireless antenna prerequisite is not respected")
				previous_wireless_payout = IncomeManager.get_source_cycle_payout("vending_machine")
				previous_wireless_cycle = IncomeManager.get_source_production_time("vending_machine")
			if data.id == "bike_delivery":
				_check(button_manager.is_unlocked(data) == button_manager.get_button("promo_sign").bought, "Bike delivery prerequisite is not respected")
				previous_bike_cycle = IncomeManager.get_source_production_time("vending_machine")
			if button_manager.purchase(data):
				if data.id == "wireless_antenna":
					_check(is_equal_approx(IncomeManager.get_source_cycle_payout("vending_machine"), previous_wireless_payout * 7.0), "Wireless antenna did not multiply vending payout sevenfold")
					_check(is_equal_approx(IncomeManager.get_source_production_time("vending_machine"), previous_wireless_cycle), "Wireless antenna changed production speed")
				if data.id == "bike_delivery":
					_check(is_equal_approx(IncomeManager.get_source_production_time("vending_machine"), previous_bike_cycle / 7.0), "Bike delivery did not speed up vending production sevenfold")
				pending.erase(data)
				progressed = true
		if not progressed:
			_check(false, "Could not unlock all world elements")
			break
	# Include the end of the purchase animation in the visibility check.
	await get_tree().create_timer(0.25).timeout

	var views: Dictionary = {}
	var creation_order: Array[String] = []
	for child in main.get_node("World/IncomeSourceViews").get_children():
		if child is WorldPurchaseButton:
			views[child.button_data.id] = child
			creation_order.append(child.button_data.id)
	_check(views.size() == button_manager.buttons.size(), "Missing world purchase components")
	var antenna_view: WorldPurchaseButton = views["wireless_antenna"]
	_check(not antenna_view.hover_areas.is_empty(), "Wireless antenna has no hover interaction")
	for area in antenna_view.hover_areas:
		_check(area.input_pickable, "Purchased wireless antenna hover area is disabled")
	_check(antenna_view.button_data.get_purchased_tooltip_text() == "자판기 수입 x 7", "Wireless antenna tooltip does not describe its effect")
	_check(creation_order.find("restaurant") < creation_order.find("serving_desk"), "Scene order was replaced by registry order")
	_check(creation_order.find("serving_desk") < creation_order.find("dining_seats"), "Furniture order differs from the layout")

	var expected_layers := {
		"wallpaper": RENDER_ORDER.WorldLayer.BACKGROUND,
		"window1": RENDER_ORDER.WorldLayer.FOREGROUND,
		"window2": RENDER_ORDER.WorldLayer.FOREGROUND,
		"restaurant": RENDER_ORDER.WorldLayer.OBJECT,
		"serving_desk": RENDER_ORDER.WorldLayer.OBJECT,
		"seat1": RENDER_ORDER.WorldLayer.OBJECT,
		"seat2": RENDER_ORDER.WorldLayer.OBJECT,
		"cook_soldier": RENDER_ORDER.WorldLayer.OBJECT,
		"vending_machine": RENDER_ORDER.WorldLayer.OBJECT,
		"trashbin": RENDER_ORDER.WorldLayer.OBJECT,
		"vending_machine_soldier": RENDER_ORDER.WorldLayer.OBJECT,
		"promo_sign": RENDER_ORDER.WorldLayer.OBJECT,
		"bike_delivery": RENDER_ORDER.WorldLayer.OBJECT,
		"wireless_antenna": RENDER_ORDER.WorldLayer.OBJECT,
		"wall_left": RENDER_ORDER.WorldLayer.FRONT_FRAME,
		"wall_right": RENDER_ORDER.WorldLayer.FRONT_FRAME,
		"hall_foundation": RENDER_ORDER.WorldLayer.FRONT_FRAME,
		"first_floor_ceiling": RENDER_ORDER.WorldLayer.FRONT_FRAME
	}
	for view: WorldPurchaseButton in views.values():
		for visual in view.purchased_visuals:
			_check(expected_layers.has(String(visual.name)), "Unexpected visual: " + String(visual.name))
			_check(visual.z_index == expected_layers.get(String(visual.name)), "Wrong depth: " + String(visual.name))
			_check(not visual.z_as_relative, "Clone still inherits an unrelated runtime parent depth")
			_check(visual.is_visible_in_tree(), "Purchased visual is hidden: " + String(visual.name))
			_check(visual.z_index < view.texture_button.z_index, "Visual covers a purchase button")
		_check(view.texture_button.z_index < view.info_label.z_index, "Button covers its description")

	var wall: WorldPurchaseButton = views["first_floor_wall"]
	_check(wall.purchased_visuals.size() == 3, "Wall set lost its wallpaper or pillars")
	_check(wall.purchased_visuals[0].z_index < wall.purchased_visuals[1].z_index, "Wall set was flattened into one layer")
	for child in main.get_node("World/IncomeSourceViews").get_children():
		if child is IncomeSourceView:
			_check(child.timer_label.z_index == RENDER_ORDER.WorldLayer.DESCRIPTION, "Timer is outside the description layer")
		elif child is WorldClickDialogue:
			_check(child.speech_bubble.z_index == RENDER_ORDER.WorldLayer.DESCRIPTION, "Dialogue is outside the description layer")
	_check(scene_root.get_node("TooltipManager").layer < main.get_node("HUD").layer, "World tooltip covers the HUD")
	_check(main.get_node("HUD").layer == RENDER_ORDER.ScreenLayer.HUD, "HUD canvas is misplaced")
	_check(main.get_node("World/WallPaper").z_index < RENDER_ORDER.WorldLayer.BACKGROUND, "Sky covers interior scenery")

	main.queue_free()
	await get_tree().process_frame
	if _failures == 0:
		print("PASS: scene depth, grouped visuals, reversed registry, gameplay type independence, purchases, descriptions and HUD")
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
