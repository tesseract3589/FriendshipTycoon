extends Node

const VIEW_SCENE = preload("res://ui/income_source_view.tscn")
const SOURCE := "vending_machine"
const FIXTURES = preload("res://tests/TestFixtures.gd")

var _failures: Array[String] = []
var _view: IncomeSourceView


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	FIXTURES.prepare_viewport(self)
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	IncomeManager.activate_source(SOURCE)
	EconomyManager.money = 1e20
	_view = VIEW_SCENE.instantiate() as IncomeSourceView
	_view.setup(IncomeManager.get_source(SOURCE), Vector2.ZERO, Vector2.ONE, Rect2(100, 100, 40, 40))
	add_child(_view)
	_view.set_process(false)
	_view.toggle_upgrade_panel()
	await _settle()
	var button := _view.upgrade_button
	var center := button.get_global_rect().get_center()
	var level := IncomeManager.get_source_level(SOURCE)
	_mouse_button(center, true)
	_check(IncomeManager.get_source_level(SOURCE) == level + 1, "Pressing must purchase immediately.")
	_mouse_button(center, false)
	_view._process(1.0)
	_check(IncomeManager.get_source_level(SOURCE) == level + 1, "A short click must buy exactly one level, without another purchase on release.")
	level = IncomeManager.get_source_level(SOURCE)
	var opened_position := _view.upgrade_panel.position
	_mouse_button(center, true)
	_view._process(0.39)
	_check(IncomeManager.get_source_level(SOURCE) == level + 1, "A hold must wait 0.4 seconds before repeating.")
	_view._process(0.02)
	_check(IncomeManager.get_source_level(SOURCE) == level + 2, "A hold must repeat after the initial delay.")
	_view._process(0.33)
	_check(IncomeManager.get_source_level(SOURCE) == level + 3, "The next repeat must accelerate like the batch panel.")
	var outside := _view.upgrade_panel.get_global_rect().end + Vector2(40, 40)
	var motion := InputEventMouseMotion.new()
	motion.position = outside
	motion.global_position = outside
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	_view._process(0.28)
	_check(IncomeManager.get_source_level(SOURCE) == level + 4, "Moving outside while holding must continue purchases.")
	_check(_view.upgrade_panel.position.is_equal_approx(opened_position), "Repeated upgrades must preserve the panel's open position.")
	_mouse_button(outside, false)
	_view._process(1.0)
	_check(IncomeManager.get_source_level(SOURCE) == level + 4, "Releasing outside must stop purchases.")
	await _settle()
	center = button.get_global_rect().get_center()
	# Spending the last affordable price must preserve the hold until more income arrives.
	EconomyManager.money = IncomeManager.get_upgrade_cost(SOURCE)
	EconomyManager.money_changed.emit(EconomyManager.money)
	level = IncomeManager.get_source_level(SOURCE)
	_mouse_button(center, true)
	_check(IncomeManager.get_source_level(SOURCE) == level + 1 and not button.disabled, "Exact funds must buy one upgrade and keep the button available for holding.")
	EconomyManager.money = 1e20
	EconomyManager.money_changed.emit(EconomyManager.money)
	_view._process(1.0)
	_check(IncomeManager.get_source_level(SOURCE) == level + 2, "A held button must resume purchases when money returns.")
	_mouse_button(center, false)
	_mouse_button(center, true)
	level = IncomeManager.get_source_level(SOURCE)
	_view.close_upgrade_panel()
	_view.toggle_upgrade_panel()
	_view._process(1.0)
	_check(IncomeManager.get_source_level(SOURCE) == level, "Closing and reopening must cancel a previous hold.")
	_mouse_button(center, false)
	await _settle()
	center = button.get_global_rect().get_center()
	_mouse_button(center, true)
	level = IncomeManager.get_source_level(SOURCE)
	EventManager.presentation_locked = true
	_view._process(1.0)
	EventManager.presentation_locked = false
	_view._process(1.0)
	_check(IncomeManager.get_source_level(SOURCE) == level, "An event lock must stop the hold without restarting afterward.")
	_mouse_button(center, false)
	_check(ErrorManager.get_errors().is_empty(), "Valid hold interactions must not report game errors.")
	_view.queue_free()
	# Let the real UI sounds finish before the audio server shuts down.
	await get_tree().create_timer(2.0).timeout
	await _settle()
	# Let the upgrade sounds finish before shutting down the audio server.
	await get_tree().create_timer(2.0).timeout
	if _failures.is_empty():
		print("PASS: source upgrade click, hold delay/acceleration, release outside, fixed placement, affordability, close/reopen and event lock")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _settle() -> void:
	for frame in range(4):
		await get_tree().process_frame


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
