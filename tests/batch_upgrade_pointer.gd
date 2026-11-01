extends Node

const PANEL_SCENE = preload("res://ui/batch_upgrade_panel.tscn")
const SOURCE := "vending_machine"
const FIXTURES = preload("res://tests/TestFixtures.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	FIXTURES.prepare_viewport(self)
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	_check(FIXTURES.unlock_batch_upgrade(), "The shop must unlock the panel before testing pointer input.")
	IncomeManager.activate_source(SOURCE)
	EconomyManager.money = 1e20
	var panel := PANEL_SCENE.instantiate() as BatchUpgradePanel
	add_child(panel)
	panel.set_process(false)
	panel.panel.show()
	await get_tree().process_frame
	await get_tree().process_frame
	var button := panel.list.get_child(0).get_node("Purchase/Upgrade") as TextureButton
	var rect := button.get_global_rect()
	if not get_viewport().get_visible_rect().encloses(rect):
		_check(false, "The pointer fixture must place the button inside the viewport.")
		get_tree().quit(1)
		return
	var texture_size := button.texture_normal.get_size()
	var scale_factor := minf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	var drawn_size := texture_size * scale_factor
	var drawn_rect := Rect2(rect.get_center() - drawn_size * 0.5, drawn_size)
	_check(rect.size.y > drawn_size.y + 4.0, "The fixture must include empty space below the aspect-fit button.")
	var level := IncomeManager.get_source_level(SOURCE)
	# This point used to start purchases despite lying below the visible artwork.
	var below := Vector2(rect.get_center().x, (drawn_rect.end.y + rect.end.y) * 0.5)
	_mouse_button(below, true)
	_check(IncomeManager.get_source_level(SOURCE) == level and panel._held_source_id.is_empty(), "Empty space below the button must not start an upgrade or a hold.")
	panel._process(1.0)
	_check(IncomeManager.get_source_level(SOURCE) == level, "Holding in empty space must not repeat purchases.")
	_mouse_button(below, false)
	# Transparent rounded corners must not count as the visible button either.
	var corner := drawn_rect.position + Vector2.ONE * 0.1
	_mouse_button(corner, true)
	_check(IncomeManager.get_source_level(SOURCE) == level, "A transparent texture corner must not purchase.")
	_mouse_button(corner, false)
	_mouse_button(drawn_rect.get_center(), true)
	_check(IncomeManager.get_source_level(SOURCE) == level + 1 and panel._held_source_id == SOURCE, "Pressing the visible button must purchase and start holding.")
	# Moving outside must keep the existing press, regardless of the new hit mask.
	var outside := rect.end + Vector2(40.0, 40.0)
	var motion := InputEventMouseMotion.new()
	motion.position = outside
	motion.global_position = outside
	motion.relative = outside - drawn_rect.get_center()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	_check(panel._held_source_id == SOURCE, "Leaving the button while pressed must preserve the hold.")
	panel._process(panel.UPGRADE_REPEAT_INITIAL_DELAY + 0.01)
	_check(IncomeManager.get_source_level(SOURCE) == level + 2, "Holding outside must still repeat the upgrade.")
	_mouse_button(outside, false)
	_check(panel._held_source_id.is_empty(), "Releasing outside must stop the hold.")
	panel._process(1.0)
	_check(IncomeManager.get_source_level(SOURCE) == level + 2, "No upgrade may repeat after release outside.")
	_check(ErrorManager.get_errors().is_empty(), "Valid pointer interactions must not report errors.")
	panel.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	if _failures.is_empty():
		print("PASS: visible upgrade hit area, transparent padding/corners, hold outside and release outside")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
