extends Node

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const SIZE_POP_MOTION = preload("res://scripts/SizePopMotion.gd")

var _failures: int = 0
var _income_changes: int = 0
var _reentrant_button: ButtonData
var _reentrant_purchase_succeeded: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	IncomeManager.set_process(false)
	_test_number_formatting()
	_test_economy_limits()
	_test_purchase_validation()
	_test_purchase_reentrancy()
	_test_production()
	await _test_repeated_animation()
	await _test_world_reset()
	if _failures == 0:
		print("PASS: rounding, finite balances, purchase validation/reentrancy, production, repeated animation, layout transforms and prestige UI reset")
	get_tree().quit(0 if _failures == 0 else 1)


func _test_number_formatting() -> void:
	_check(NUMBER_FORMATTER.format_number(999.999) == "1,000", "Rounding lost the carry into the whole part")
	_check(NUMBER_FORMATTER.format_number(-999.999) == "-1,000", "Negative rounding lost the carry")
	_check(NUMBER_FORMATTER.format_number(1234567.5) == "1,234,567.50", "A large value lost its fractional part")
	_check(NUMBER_FORMATTER.format_number(0.005) == "5.000e-3", "A short production interval is displayed as zero")
	_check(NUMBER_FORMATTER.format_number(1.0e12) == "1.000e+12", "Scientific formatting changed")


func _test_economy_limits() -> void:
	EconomyManager.reset_money()
	EconomyManager.add_money(1.0e308)
	EconomyManager.add_money(1.0e308)
	_check(is_finite(EconomyManager.money), "Adding finite amounts overflowed the balance")
	_check(not EconomyManager.can_afford(INF), "An infinite price was affordable")
	EconomyManager.set_global_multiplier(1.0e308)
	EconomyManager.multiply_global_multiplier(2.0)
	_check(is_finite(EconomyManager.get_global_multiplier()), "A finite factor overflowed the global multiplier")
	EconomyManager.reset_money()
	EconomyManager.set_global_multiplier(1.0)


func _test_purchase_validation() -> void:
	var invalid_button := ButtonData.new()
	invalid_button.id = "test_invalid_target"
	invalid_button.price = 10.0
	invalid_button.effect_type = ButtonData.EffectType.ACTIVATE_SOURCE
	invalid_button.effect_target = "missing_source"
	ButtonManager.buttons.append(invalid_button)
	EconomyManager.add_money(100.0)
	_check(not ButtonManager.can_purchase(invalid_button), "An invalid source target was purchasable")
	_check(not ButtonManager.purchase(invalid_button), "A broken effect charged money and marked the button bought")
	_check(EconomyManager.money == 100.0, "An invalid purchase changed the balance")
	invalid_button.effect_type = ButtonData.EffectType.GLOBAL_MULTIPLIER
	invalid_button.effect_value = 2.0
	EconomyManager.set_global_multiplier(1.0e308)
	_check(not ButtonManager.purchase(invalid_button), "An overflowing effect was charged without applying a multiplier")
	_check(EconomyManager.money == 100.0, "An overflowing effect changed the balance")
	EconomyManager.set_global_multiplier(1.0)
	ButtonManager.buttons.erase(invalid_button)


func _test_purchase_reentrancy() -> void:
	_reentrant_button = ButtonData.new()
	_reentrant_button.id = "test_reentrant_purchase"
	_reentrant_button.price = 10.0
	_reentrant_button.effect_type = ButtonData.EffectType.GLOBAL_MULTIPLIER
	_reentrant_button.effect_value = 2.0
	ButtonManager.buttons.append(_reentrant_button)
	EconomyManager.reset_money()
	EconomyManager.add_money(100.0)
	EconomyManager.money_changed.connect(_on_purchase_spend)
	_check(ButtonManager.purchase(_reentrant_button), "A valid purchase failed")
	_check(not _reentrant_purchase_succeeded, "money_changed allowed the same purchase recursively")
	_check(EconomyManager.money == 90.0, "A reentrant purchase charged twice")
	_check(EconomyManager.get_global_multiplier() == 2.0, "A reentrant purchase applied its effect twice")
	ButtonManager.buttons.erase(_reentrant_button)
	_reentrant_button = null
	EconomyManager.set_global_multiplier(1.0)


func _on_purchase_spend(_money: float) -> void:
	EconomyManager.money_changed.disconnect(_on_purchase_spend)
	_reentrant_purchase_succeeded = ButtonManager.purchase(_reentrant_button)


func _test_production() -> void:
	ButtonManager.reset_for_prestige()
	EconomyManager.reset_money()
	IncomeManager.activate_source("vending_machine")
	IncomeManager._process(2.0)
	IncomeManager.multiply_source_speed_multiplier("vending_machine", 2.0)
	_check(is_equal_approx(IncomeManager.get_source_time_remaining("vending_machine"), 1.5), "Changing speed lost cycle progress")
	IncomeManager._process(1.5)
	_check(EconomyManager.money == 10.0, "The completed cycle paid the wrong amount")
	IncomeManager._process(5.25)
	_check(EconomyManager.money == 30.0, "A long frame lost completed cycles")
	_check(is_equal_approx(IncomeManager.get_source_time_remaining("vending_machine"), 2.25), "A long frame lost partial cycle progress")
	IncomeManager.multiply_source_speed_multiplier("vending_machine", 1.0e22)
	IncomeManager._process(1.0)
	_check(EconomyManager.money > 1.0e22, "Sub-attosecond production overflowed an integer cycle count")
	var remaining := IncomeManager.get_source_time_remaining("vending_machine")
	_check(remaining > 0.0 and remaining <= IncomeManager.get_source_production_time("vending_machine"), "Fast production produced an invalid timer")
	IncomeManager.income_changed.connect(_on_income_changed)
	EconomyManager.multiply_global_multiplier(2.0)
	_check(_income_changes > 0, "Changing the global multiplier did not notify the income display")
	IncomeManager.income_changed.disconnect(_on_income_changed)
	EconomyManager.set_global_multiplier(1.0)
	ButtonManager.reset_for_prestige()


func _on_income_changed() -> void:
	_income_changes += 1


func _test_repeated_animation() -> void:
	var visual := Node2D.new()
	visual.scale = Vector2(2.0, 3.0)
	add_child(visual)
	var visuals: Array[Node2D] = [visual]
	SIZE_POP_MOTION.play(visuals)
	SIZE_POP_MOTION.play(visuals)
	await get_tree().create_timer(0.25).timeout
	_check(visual.scale.is_equal_approx(Vector2(2.0, 3.0)), "Restarting a purchase animation lost the original visual scale")
	visual.queue_free()


func _test_world_reset() -> void:
	var main := load("res://scenes/main.tscn").instantiate() as Node2D
	var group := main.get_node("World/WorldLayout/VendingMachine") as Node2D
	group.position = Vector2(180.0, -70.0)
	group.scale = Vector2(1.2, 1.2)
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var views: Dictionary = {}
	var source_views: Array[IncomeSourceView] = []
	var dialogue: WorldClickDialogue
	for child in main.get_node("World/IncomeSourceViews").get_children():
		if child is WorldPurchaseButton:
			views[child.button_data.id] = child
		elif child is IncomeSourceView:
			source_views.append(child)
		elif child is WorldClickDialogue and child.button_data.id == "vending_machine_soldier":
			dialogue = child
	EconomyManager.reset_money()
	EconomyManager.add_money(1.0e9)
	var pending: Array[ButtonData] = ButtonManager.buttons.duplicate()
	while not pending.is_empty():
		var progressed := false
		for data in pending.duplicate():
			if data.bought or ButtonManager.purchase(data):
				pending.erase(data)
				progressed = true
		if not progressed:
			_check(false, "The configured purchase graph is unreachable")
			break
	var panel := main.get_node("HUD/IncomeUpgradePanel") as IncomeUpgradePanel
	panel._rebuild_rows()
	panel._rebuild_rows()
	_check(panel.list.get_child_count() == IncomeManager.sources.size(), "Repeated rebuilds left duplicate upgrade rows in the tree")
	for view in source_views:
		var layout := main.get_node("World/WorldLayout").find_child(view.source_data.id, true, false) as Sprite2D
		_check(view.timer_label.global_position.is_equal_approx(layout.global_position + view.source_data.timer_offset), "A transformed layout group detached its timer from the source")
	dialogue._show_next_dialogue()
	_check(PrestigeManager.prestige(), "Prestige failed with sufficient funds")
	await get_tree().process_frame
	for view: WorldPurchaseButton in views.values():
		for visual in view.purchased_visuals:
			_check(not visual.is_visible_in_tree(), "Prestige left a purchased visual visible: " + view.button_data.id)
		for area in view.hover_areas:
			_check(not area.input_pickable, "Prestige left a purchased hover area active: " + view.button_data.id)
	for view in source_views:
		_check(not view.source_is_active and not view.timer_label.visible, "Prestige left a production timer active: " + view.source_data.id)
	_check(panel.list.get_child_count() == 0, "Prestige left stale upgrade rows")
	_check(not dialogue.speech_bubble.visible and not dialogue.speech_tail.visible, "A pending dialogue survived prestige")
	var balance_after_reset := EconomyManager.money
	IncomeManager._process(10.0)
	_check(EconomyManager.money == balance_after_reset, "A reset source still produced income")
	_check(ButtonManager.purchase_by_id("vending_machine"), "The free starting source could not be purchased after prestige")
	for view in source_views:
		if view.source_data.id == "vending_machine":
			_check(view.source_is_active, "Repurchasing after prestige did not reactivate the view")
	main.queue_free()
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
