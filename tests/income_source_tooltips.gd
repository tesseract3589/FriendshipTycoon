extends Node

const WORLD = preload("res://scenes/world_layout.tscn")
const BUTTONS = preload("res://scenes/button_layout.tscn")
const FORMAT = preload("res://scripts/NumberFormatter.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	preload("res://tests/TestFixtures.gd").prepare_viewport(self)
	var world := WORLD.instantiate()
	var buttons := BUTTONS.instantiate()
	add_child(world)
	add_child(buttons)
	buttons.hide()
	var hover_root := Node2D.new()
	add_child(hover_root)
	for source in IncomeManager.sources:
		var data := ButtonManager.get_button(source.id)
		var layout := ErrorManager.find_world_element(world, source.id) as Node2D
		var ui_layout := buttons.get_node("Buttons").find_child(source.id, true, false) as Node2D
		var areas: Array[Area2D] = []
		for area_node in layout.find_children("HoverArea", "Area2D", true, false):
			var area := area_node as Area2D
			area.reparent(hover_root, true)
			areas.append(area)
		_check(not areas.is_empty(), source.id + ": source must have hover geometry.")
		var view := WorldPurchaseButton.new()
		view.setup(data, layout, areas, ui_layout)
		add_child(view)
		TooltipManager.hide_tooltip()
		for area in areas:
			area.mouse_entered.emit()
		_check(not TooltipManager._panel.visible, source.id + ": unpurchased sources must not show a tooltip.")
		data.bought = true
		IncomeManager.activate_source(source.id)
		view._refresh()
		for area in areas:
			_check(area.input_pickable, source.id + ": purchased sources must enable hover.")
			area.mouse_entered.emit()
			_check(TooltipManager._panel.visible and TooltipManager._owner_id == data.id, source.id + ": hovering must show the source tooltip, even without a custom template.")
			var expected := "%s원/%s\n초당 %s원" % [FORMAT.format_number(IncomeManager.get_source_cycle_payout(source.id)), FORMAT.format_time(IncomeManager.get_source_production_time(source.id)), FORMAT.format_income_per_second(IncomeManager.get_source_income_unrounded(source.id))]
			_check(TooltipManager._label.text == expected, source.id + ": tooltip must show the current payout, production time and income per second.")
			area.mouse_exited.emit()
			_check(not TooltipManager._panel.visible, source.id + ": leaving must hide the tooltip.")
		var area := areas[0]
		area.mouse_entered.emit()
		var previous_text := TooltipManager._label.text
		IncomeManager.multiply_source_multiplier(source.id, 2.0)
		_check(TooltipManager._panel.visible and TooltipManager._label.text != previous_text, source.id + ": source income changes must refresh the hovered tooltip.")
		data.tooltip_text = "{source_name}: {payout}원/{time}"
		view._refresh_purchased_tooltip()
		_check(TooltipManager._label.text.begins_with(source.source_name + ": ") and not TooltipManager._label.text.contains("{"), source.id + ": custom templates must still resolve their placeholders.")
		data.show_purchased_tooltip = false
		view._refresh_purchased_tooltip()
		_check(not TooltipManager._panel.visible, source.id + ": explicit tooltip opt-out must still be respected.")
		data.show_purchased_tooltip = true
		view._refresh_purchased_tooltip()
		data.bought = false
		view._refresh()
		_check(not TooltipManager._panel.visible and not area.input_pickable, source.id + ": resetting purchase state must hide and disable the tooltip.")
		view.queue_free()
		await get_tree().process_frame
	world.queue_free()
	buttons.queue_free()
	hover_root.queue_free()
	await get_tree().process_frame
	_check(ErrorManager.get_errors().is_empty(), "Source tooltip interactions must not report game errors.")
	if _failures.is_empty():
		print("PASS: all five source tooltips, empty/custom templates, current income text, live refresh, hover exit, purchase reset and explicit opt-out")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
