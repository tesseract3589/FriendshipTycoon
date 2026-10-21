extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const PANEL_SCENE: PackedScene = preload("res://ui/income_upgrade_panel.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	# Exercise the real panel and finance signals without touching player saves.
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	# Pin the fixture's first price; gameplay resources can be tuned independently.
	IncomeManager.get_source("vending_machine").upgrade_base_cost = 30.0
	IncomeManager.activate_source("vending_machine")
	EconomyManager.money = 0.0
	var panel := PANEL_SCENE.instantiate() as IncomeUpgradePanel
	add_child(panel)
	await get_tree().process_frame
	var row := panel.list.get_child(0) as HBoxContainer
	var button := row.get_node("Purchase/Upgrade") as TextureButton
	_check(button.disabled, "Insufficient funds must disable an ordinary upgrade.")
	_check(row.get_node("Purchase/Price").text == "30원", "Ordinary prices must retain their display format.")
	EconomyManager.money = IncomeManager.get_upgrade_cost("vending_machine")
	EconomyManager.money_changed.emit(EconomyManager.money)
	_check(not button.disabled, "Exact funds must enable an ordinary upgrade.")
	var ordinary_preview: Variant = IncomeManager.get_next_upgrade_cycle_payout("vending_machine")
	_check(IncomeManager.upgrade_source("vending_machine"), "The ordinary upgrade purchase must succeed.")
	_check(BIG.compare(IncomeManager.get_source_cycle_payout("vending_machine"), ordinary_preview) == 0, "The next-level forecast must equal the purchased exponential payout.")
	_check(IncomeManager.get_source_level("vending_machine") == 2, "The ordinary purchase must upgrade the source.")
	_check(BIG.compare(EconomyManager.money, 0.0) == 0, "The ordinary upgrade must deduct its price.")
	_check(button.disabled, "The next ordinary upgrade must be disabled after spending all funds.")
	# This price exceeds native float range and must remain a BigNumber in the UI.
	IncomeManager.source_levels["vending_machine"] = 5000
	var price: Variant = IncomeManager.get_upgrade_cost("vending_machine")
	_check(price is BIG, "The regression case must exercise a BigNumber price.")
	EconomyManager.money = BIG.divide(price, 2.0)
	EconomyManager.money_changed.emit(EconomyManager.money)
	_check(button.disabled, "Insufficient funds must disable a BigNumber upgrade.")
	_check(row.get_node("Purchase/Price").text == "2.3836 × 10^761원", "The large price must follow the documented notation.")
	_check(button.modulate == Color(0.65, 0.65, 0.65), "The unaffordable BigNumber button must be shaded.")
	EconomyManager.money = price
	EconomyManager.money_changed.emit(EconomyManager.money)
	_check(not button.disabled, "Exact BigNumber funds must enable the upgrade.")
	_check(button.modulate == Color.WHITE, "The affordable BigNumber button must restore its color.")
	var large_preview: Variant = IncomeManager.get_next_upgrade_cycle_payout("vending_machine")
	_check(IncomeManager.upgrade_source("vending_machine"), "The BigNumber upgrade purchase must succeed.")
	_check(BIG.compare(IncomeManager.get_source_cycle_payout("vending_machine"), large_preview) == 0, "The BigNumber forecast must equal the purchased exponential payout.")
	_check(IncomeManager.get_source_level("vending_machine") == 5001, "The BigNumber purchase must upgrade the source.")
	_check(BIG.compare(EconomyManager.money, 0.0) == 0, "The BigNumber upgrade must deduct its price.")
	_check(button.disabled, "The next BigNumber upgrade must be disabled after spending all funds.")
	_check(ErrorManager.get_errors().is_empty(), "Valid upgrades must not report game errors.")
	panel.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("PASS: ordinary/BigNumber upgrade panel prices, affordability, shading and post-purchase refresh")
	get_tree().quit(0 if _failures.is_empty() else 1)
