extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const FORMAT = preload("res://scripts/NumberFormatter.gd")
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	IncomeManager.set_process(false)
	_test_formatting()
	_test_arithmetic()
	_test_runtime()
	await _test_save_and_ui()
	if failures == 0:
		print("PASS: Korean units/rounding, extended arithmetic, production, purchases, upgrades, prestige, save compatibility and HUD")
	get_tree().quit(0 if failures == 0 else 1)

func _test_formatting() -> void:
	var cases := {
		"10000": "1만", "12345.6": "1.2346만", "12344.5": "1.2345만", "100000000": "1억",
		"999999999999": "1조", "1e68": "1무량대수",
		"9.999999999e71": "1만 x 10^68", "1e72": "1만 x 10^68",
		"1.234567e401": "1.2346만 x 10^397", "1e10000": "1만 x 10^9996",
		"12340": "1.234만", "2200000000": "22억", "1.234e400": "1.234만 x 10^396",
	}
	for input: String in cases:
		_check(FORMAT.format_number(BIG.parse(input)) == cases[input], "Formatting " + input + ": " + FORMAT.format_number(BIG.parse(input)))
	var units := ["만", "억", "조", "경", "해", "자", "양", "구", "간", "정", "재", "극", "항하사", "아승기", "나유타", "불가사의", "무량대수"]
	for index in units.size():
		_check(FORMAT.format_number(BIG.power_of_ten((index + 1) * 4)) == "1" + units[index], "Unit boundary " + units[index])
	_check(FORMAT.format_income_per_second(1234.5) == "1,234.5", "Small income trims trailing zeros")
	_check(FORMAT.format_income_per_second(1234.567) == "1,234.57", "Small income rounds to two decimals")
	_check(FORMAT.format_income_per_second(9999.999) == "1만", "Small-income rounding promotes unit")
	_check(FORMAT.format_income_per_second(10000.0) == "1만", "Large income trims zero fraction")
	_check(FORMAT.format_number(0.0) == "0", "Zero money")
	_check(FORMAT.format_time(0.005) == "5.00ms" and FORMAT.format_time(1e-35) == "1.000e-5qs", "Time formatting retained")

func _test_arithmetic() -> void:
	var enormous: Variant = BIG.parse("1e10000")
	_check(BIG.compare(BIG.multiply(enormous, 1000.0), BIG.parse("1e10003")) == 0, "Extended multiplication")
	_check(BIG.compare(BIG.divide(enormous, BIG.parse("1e9996")), 10000.0) == 0, "Extended division")
	_check(BIG.compare(BIG.add(enormous, 1.0), enormous) == 0, "Insignificant tails dropped")
	_check(BIG.compare(BIG.subtract(enormous, enormous), 0.0) == 0, "Equal subtraction")
	_check(absf(float(BIG.divide(BIG.multiply(1e300, 1e100), BIG.parse("1e400"))) - 1.0) < 1e-12, "Overflow promotes native floats")
	_check(BIG.compare(BIG.square_root(BIG.parse("1e10000")), BIG.parse("1e5000")) == 0, "Extended square root")
	_check(not BIG.valid(BIG.parse("1e1000000001")), "Unsupported exponent rejected")
	_check(not BIG.is_serialized({"decimal_mantissa": 1.0, "decimal_exponent": -9223372036854775807 - 1}), "Corrupt minimum-int exponent rejected")

func _test_runtime() -> void:
	EconomyManager.reset_money()
	_check(EconomyManager.add_money(BIG.parse("1e500")), "Add huge money")
	_check(EconomyManager.add_money(1.0), "Small payout does not block huge balance")
	_check(EconomyManager.spend_money(BIG.parse("1e499")), "Spend huge money")
	_check(BIG.compare(EconomyManager.money, BIG.parse("9e499")) == 0, "Huge subtraction balance")
	_check(not EconomyManager.can_afford(BIG.parse("1e500")), "Huge affordability")
	var button := ButtonData.new()
	button.id = "test_huge_price"
	button.large_price = "1e400"
	button.effect_type = ButtonData.EffectType.GLOBAL_MULTIPLIER
	button.effect_value = 2.0
	ButtonManager.buttons.append(button)
	_check(ButtonManager.purchase(button), "Button with a huge price")
	ButtonManager.buttons.erase(button)
	EconomyManager.set_global_multiplier(1.0)
	_check(EconomyManager.set_developer_multipliers(1.0, BIG.parse("1e500")), "Developer huge income multiplier")
	IncomeManager.activate_source("vending_machine")
	var source := IncomeManager.get_source("vending_machine")
	var reference := source.base_income
	for level in range(1, 5000):
		reference += reference * source.upgrade_first_income_ratio / (1.0 + source.upgrade_income_decay * (level - 1))
	var approximated: Variant = IncomeManager._get_source_payout_at_level(source, 5000)
	_check(absf(float(BIG.divide(approximated, reference)) - 1.0) < 1e-8, "Fast high-level tail agrees with direct recurrence")
	IncomeManager._process(IncomeManager.get_source_production_time(source.id))
	_check(BIG.valid(IncomeManager.get_total_income_per_second(), false), "Huge income remains valid")
	_check(BIG.compare(EconomyManager.money, BIG.parse("1e500")) > 0, "Huge cycles pay out")
	IncomeManager.source_levels[source.id] = 100000
	var started := Time.get_ticks_usec()
	_check(BIG.valid(IncomeManager.get_upgrade_cost(source.id), false), "Exponential cost extends past double range")
	_check(BIG.valid(IncomeManager.get_source_cycle_payout(source.id), false), "High-level payout extends past double range")
	_check(Time.get_ticks_usec() - started < 1000000, "High levels calculate in bounded time")
	var cost: Variant = IncomeManager.get_upgrade_cost(source.id)
	EconomyManager.add_money(BIG.multiply(cost, 2.0))
	_check(IncomeManager.upgrade_source(source.id), "Huge upgrade purchase")
	_check(PrestigeManager.prestige(), "Prestige past int64 reward range")
	_check(BIG.valid(PrestigeManager.get_prestige_multiplier(), false), "Huge prestige bonus")
	_check(BIG.compare(EconomyManager.get_developer_income_multiplier(), BIG.parse("1e500")) == 0, "Prestige retains developer factor")

func _test_save_and_ui() -> void:
	var directory := ProjectSettings.globalize_path("res://.godot/big_number_saves_%d" % Time.get_ticks_usec())
	_check(SaveManager.initialize(directory), "Initialize isolated save directory")
	EconomyManager.add_money(BIG.parse("1.234567e10000"))
	EconomyManager.set_developer_multipliers(1.0, BIG.parse("1e500"))
	PrestigeManager.total_jjam = BIG.parse("1e5000")
	IncomeManager.activate_source("vending_machine")
	var snapshot := SaveManager._capture_progress()
	_check(SaveManager._validate_progress(snapshot), "Validate extended save")
	_check(SaveManager.save_slot(1), "Write extended save")
	EconomyManager.reset_money()
	_check(SaveManager.load_slot(1), "Load extended save")
	_check(BIG.compare(EconomyManager.money, BIG.parse("1.234567e10000")) == 0, "Huge balance round trip")
	_check(BIG.compare(PrestigeManager.total_jjam, BIG.parse("1e5000")) == 0, "Huge prestige round trip")
	var legacy := SaveManager._create_initial_progress()
	legacy.economy.money = 12345.0
	legacy.prestige.total_jjam = 9007199254740993
	_check(SaveManager._validate_progress(legacy), "Old numeric saves accepted")
	SaveManager._restore_progress(legacy)
	_check(PrestigeManager.total_jjam == 9007199254740993, "Old int64 prestige stays exact")
	SaveManager._restore_progress(snapshot)
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	_check(main.get_node("HUD/Panel/VBoxContainer/MoneyLabel").text.contains("1.2346만 x 10^9996원"), "HUD shows huge balance")
	var panel: DeveloperToolsPanel = main.get_node("HUD/DeveloperTools")
	panel.amount_input.text = "1e10001"
	panel.add_button.pressed.emit()
	_check(BIG.compare(EconomyManager.money, BIG.parse("1e10001")) > 0, "Developer money input accepts extended exponents")
	_test_money_hud_digits(main)
	main.free()

func _test_money_hud_digits(main: Node) -> void:
	var label: Label = main.get_node("HUD/Panel/VBoxContainer/MoneyLabel")
	var state := SaveManager._create_initial_progress()
	state.economy.money = 84466637.0
	state.economy.global_multiplier = 2.0
	state.economy.global_time_multiplier = 2.0
	state.sources.vending_machine.active = true
	state.sources.vending_machine.level = 69
	state.sources.vending_machine.multiplier = 80.0
	state.sources.vending_machine.speed_multiplier = 60.0
	state.sources.vending_machine.time_remaining = 7.0 / 120.0
	SaveManager._restore_progress(state)
	_check(label.text == "자금: 8446.6637만원", "Screenshot balance keeps all four HUD decimals")
	EconomyManager.add_money(1.0)
	_check(label.text == "자금: 8446.6638만원", "One-won credit immediately updates the fourth HUD decimal")
	EconomyManager.add_money(9.0)
	_check(label.text == "자금: 8446.6647만원", "Ten-won carry immediately updates the third HUD decimal")
	state.economy.money = 1e10
	SaveManager._restore_progress(state)
	_check(IncomeManager.upgrade_source("vending_machine") and IncomeManager.upgrade_source("vending_machine"), "Upgrade screenshot vending machine twice")
	_check(IncomeManager.get_source_cycle_payout("vending_machine") == 444000.0, "Level 71 pays exact multiples of 100 won")
	state = SaveManager._capture_progress()
	state.economy.money = 84466637.0
	state.economy.money_correction = 0.0
	SaveManager._restore_progress(state)
	var expected_labels := ["8491.0637", "8535.4637", "8579.8637", "8624.2637", "8668.6637"]
	for expected: String in expected_labels:
		IncomeManager._process(IncomeManager.get_source_production_time("vending_machine"))
		_check(label.text == "자금: %s만원" % expected, "Upgraded payouts update HUD while preserving unchanged ones/tens: " + expected)
	EconomyManager.add_money(1.0)
	_check(label.text == "자금: 8668.6638만원", "Fourth decimal still responds after upgrades and rapid production")
	# The average per-second rate has a fractional part even when the fastest
	# source pays multiples of ten won. The slower source must still change ones.
	state = SaveManager._create_initial_progress()
	state.economy.money = 76892021.0
	state.economy.global_time_multiplier = 2.0
	state.sources.vending_machine.active = true
	state.sources.vending_machine.level = 48
	state.sources.vending_machine.multiplier = 80.0
	state.sources.vending_machine.speed_multiplier = 60.0
	state.sources.vending_machine.time_remaining = 7.0 / 120.0
	state.sources.restaurant.active = true
	state.sources.restaurant.level = 14
	state.sources.restaurant.multiplier = 6.0
	state.sources.restaurant.speed_multiplier = 4.0
	state.sources.restaurant.time_remaining = 1.5
	SaveManager._restore_progress(state)
	_check(FORMAT.format_income_per_second(IncomeManager.get_total_income_per_second()) == "332.8416만", "Second screenshot average income reproduced")
	IncomeManager._process(0.75)
	_check(label.text == "자금: 7816.4981만원", "Fast vending payouts correctly leave the ones digit unchanged")
	IncomeManager._process(0.75)
	_check(label.text == "자금: 8180.8873만원", "First restaurant payment changes the fourth decimal from one to three")
	IncomeManager._process(1.5)
	_check(label.text == "자금: 8683.1805만원", "Second restaurant payment changes the fourth decimal from three to five")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
