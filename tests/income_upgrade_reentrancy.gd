extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const SOURCE := "vending_machine"

var _failures: Array[String] = []
var _initial_state: Dictionary
var _payment_action: Callable


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	IncomeManager.get_source(SOURCE).upgrade_base_cost = 30.0
	var directory := ProjectSettings.globalize_path("res://.godot/upgrade_reentrancy_%d" % Time.get_ticks_usec())
	if not SaveManager.initialize(directory):
		get_tree().quit(1)
		return
	_initial_state = SaveManager._create_initial_progress()
	_test_payment_reentry_and_save()
	_test_notification_reentry()
	_test_other_source()
	_test_failed_payment()
	_test_reset_during_payment()
	_test_load_during_payment()
	_test_prestige_during_payment()
	_test_scientific_price()
	_check(ErrorManager.get_errors().is_empty(), "Valid purchase flows must not report errors.")
	if _failures.is_empty():
		print("PASS: upgrade reentrancy, atomic save snapshots, independent sources, failed payments, reset/load/prestige callbacks and BigNumber prices")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _prepare(level: int = 1, money: Variant = 100000.0) -> void:
	SaveManager._restore_progress(_initial_state)
	IncomeManager.activate_source(SOURCE)
	IncomeManager.source_levels[SOURCE] = level
	EconomyManager.money = money


func _upgrade_with_payment_action(action: Callable) -> bool:
	_payment_action = action
	EconomyManager.money_changed.connect(_on_payment)
	var result := IncomeManager.upgrade_source(SOURCE)
	if EconomyManager.money_changed.is_connected(_on_payment):
		EconomyManager.money_changed.disconnect(_on_payment)
	_payment_action = Callable()
	return result


func _on_payment(_money: Variant) -> void:
	# Disconnect first so a nested purchase/reset can also emit money_changed.
	EconomyManager.money_changed.disconnect(_on_payment)
	_payment_action.call()


func _test_payment_reentry_and_save() -> void:
	_prepare()
	var observed := {}
	var action := func() -> void:
		observed.level = IncomeManager.get_source_level(SOURCE)
		observed.nested = IncomeManager.upgrade_source(SOURCE)
		observed.saved = SaveManager.save_slot(1)
	_check(_upgrade_with_payment_action(action), "The outer purchase must succeed.")
	_check(observed.level == 2 and not observed.nested, "Payment observers must see level 2 and cannot reenter the same source.")
	_check(IncomeManager.get_source_level(SOURCE) == 2 and EconomyManager.money == 99970.0, "Only one upgrade may be charged and applied.")
	_check(observed.saved, "Saving inside the payment notification must succeed.")
	_check(IncomeManager.upgrade_source(SOURCE), "A later sequential upgrade must remain available.")
	_check(IncomeManager.get_source_level(SOURCE) == 3 and EconomyManager.money == 99885.0, "Sequential upgrades must cost 30 + 85 won.")
	_check(SaveManager.load_slot(1), "Load the snapshot written during payment.")
	_check(IncomeManager.get_source_level(SOURCE) == 2 and EconomyManager.money == 99970.0, "The saved wallet and upgraded level must agree.")


func _test_notification_reentry() -> void:
	for during_level_signal in [true, false]:
		_prepare()
		var observed := {}
		var on_level := func(_id: String, _level: int) -> void:
			observed.nested = IncomeManager.upgrade_source(SOURCE)
		var on_income := func() -> void:
			observed.nested = IncomeManager.upgrade_source(SOURCE)
		if during_level_signal:
			IncomeManager.source_level_changed.connect(on_level, CONNECT_ONE_SHOT)
		else:
			IncomeManager.income_changed.connect(on_income, CONNECT_ONE_SHOT)
		_check(IncomeManager.upgrade_source(SOURCE), "Notification callbacks must not cancel the outer purchase.")
		_check(not observed.nested and IncomeManager.get_source_level(SOURCE) == 2, "The lock must last through level and income notifications.")
		_check(EconomyManager.money == 99970.0, "Notification reentry must not deduct more money.")


func _test_other_source() -> void:
	_prepare()
	IncomeManager.activate_source("restaurant")
	var observed := {}
	var action := func() -> void: observed.nested = IncomeManager.upgrade_source("restaurant")
	_check(_upgrade_with_payment_action(action) and observed.nested, "Independent sources may upgrade during payment callbacks.")
	_check(IncomeManager.get_source_level(SOURCE) == 2 and IncomeManager.get_source_level("restaurant") == 2, "Each independent purchase must apply once.")
	_check(EconomyManager.money == 49970.0, "Both independent purchases must be charged.")


func _test_failed_payment() -> void:
	_prepare(1, 29.0)
	_check(not IncomeManager.upgrade_source(SOURCE), "Insufficient funds must reject an upgrade.")
	_check(IncomeManager.get_source_level(SOURCE) == 1 and EconomyManager.money == 29.0, "Failed payment must leave the level and wallet unchanged.")
	EconomyManager.money = 30.0
	_check(IncomeManager.upgrade_source(SOURCE), "Failed payment must release the lock for a later retry.")
	_check(IncomeManager.get_source_level(SOURCE) == 2 and EconomyManager.money == 0.0, "An exact-funds retry must commit once.")


func _test_reset_during_payment() -> void:
	_prepare()
	var levels: Array[int] = []
	var observe := func(id: String, level: int) -> void:
		if id == SOURCE:
			levels.append(level)
	IncomeManager.source_level_changed.connect(observe)
	var action := func() -> void:
		IncomeManager.reset_runtime_state()
		EconomyManager.money = 42.0
	_check(not _upgrade_with_payment_action(action), "A reset during payment must invalidate the old upgrade.")
	IncomeManager.source_level_changed.disconnect(observe)
	_check(not IncomeManager.source_active[SOURCE] and IncomeManager.get_source_level(SOURCE) == 1, "A reset must not resurrect an inactive source's level.")
	_check(EconomyManager.money == 42.0 and not levels.has(2), "Old upgrade notifications must not leak into reset progress.")
	IncomeManager.activate_source(SOURCE)
	_check(IncomeManager.upgrade_source(SOURCE), "A reset must not leave a stale purchase lock.")


func _test_load_during_payment() -> void:
	_prepare(7, 54321.0)
	_check(SaveManager.save_slot(2), "Create the isolated load target.")
	_prepare()
	var observed := {}
	var action := func() -> void:
		observed.loaded = SaveManager.load_slot(2)
		observed.nested = IncomeManager.upgrade_source(SOURCE)
	_check(not _upgrade_with_payment_action(action), "A load during payment must invalidate the old upgrade.")
	_check(observed.loaded and not observed.nested, "The old call's lock must survive loading until it returns.")
	_check(IncomeManager.get_source_level(SOURCE) == 7 and EconomyManager.money == 54321.0, "Loaded progress must not gain a free level or lose its money.")
	_check(IncomeManager.upgrade_source(SOURCE) and IncomeManager.get_source_level(SOURCE) == 8, "A new purchase after loading must still work.")


func _test_prestige_during_payment() -> void:
	_prepare()
	PrestigeManager.unlock_jjam()
	var observed := {}
	var action := func() -> void: observed.prestiged = PrestigeManager.jjam_prestige()
	_check(not _upgrade_with_payment_action(action) and observed.prestiged, "Prestige must supersede an in-flight upgrade.")
	_check(IncomeManager.get_source_level(SOURCE) == 1 and not IncomeManager.source_active[SOURCE], "Prestige must keep its fresh source state.")
	_check(EconomyManager.money == 0.0 and PrestigeManager.banked_jjam == 400, "Prestige must keep its fresh wallet and banked reward.")
	IncomeManager.activate_source(SOURCE)
	EconomyManager.money = 100.0
	_check(IncomeManager.upgrade_source(SOURCE), "Prestige must not leave a stale upgrade lock.")


func _test_scientific_price() -> void:
	_prepare(5000)
	var cost: Variant = IncomeManager.get_upgrade_cost(SOURCE)
	_check(cost is BIG, "The large-price case must exceed native float range.")
	EconomyManager.money = cost
	var observed := {}
	var action := func() -> void:
		observed.level = IncomeManager.get_source_level(SOURCE)
		observed.nested = IncomeManager.upgrade_source(SOURCE)
	_check(_upgrade_with_payment_action(action), "A BigNumber purchase must succeed.")
	_check(observed.level == 5001 and not observed.nested, "A BigNumber purchase must commit its level before notification and reject reentry.")
	_check(IncomeManager.get_source_level(SOURCE) == 5001 and BIG.compare(EconomyManager.money, 0.0) == 0, "An exact-funds BigNumber purchase must be applied once.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
