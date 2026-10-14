extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const FORMAT = preload("res://scripts/NumberFormatter.gd")
var failures := 0
var _restore_on_failure: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	IncomeManager.set_process(false)
	_test_mixed_arithmetic()
	_test_wallet_residuals()
	_test_frame_payments()
	_test_fractional_cycles()
	_test_extreme_cycle_counts()
	_test_callbacks_and_rollback()
	_test_save_residuals()
	if failures == 0:
		print("PASS: native/scientific consistency, tiny cumulative credits/debits, multiple sources, 1/30/60/144 FPS, sub-won cycles, overflowing cycle counts, callbacks, rollback and residual saves")
	get_tree().quit(0 if failures == 0 else 1)

func _test_mixed_arithmetic() -> void:
	for exponent: int in [-300, -10, 0, 4, 100, 300, 308]:
		for coefficient: float in [-2.5, -1.25, 0.0, 1.25, 9.8765]:
			var scientific := BIG.new(coefficient, exponent)
			var native := coefficient * pow(10.0, exponent)
			if not is_finite(native):
				continue
			_check(BIG.compare(scientific, native) == 0, "Equal mixed values: %s / %s" % [scientific, native])
			_close(BIG.add(scientific, native), BIG.multiply(native, 2.0), "Mixed addition")
			_close(BIG.add(native, scientific), BIG.multiply(native, 2.0), "Commutative addition")
			_close(BIG.subtract(scientific, native), 0.0, "Mixed cancellation")
			_close(BIG.divide(scientific, 2.0), native / 2.0, "Mixed division")
			_close(BIG.multiply(scientific, 2.0), BIG.multiply(native, 2.0), "Mixed multiplication")
			if coefficient > 0.0:
				_close(BIG.square_root(scientific), sqrt(native), "Mixed square root")
	_check(BIG.rounded(BIG.new(1.5)) == 2.0 and BIG.floored(BIG.new(1.5)) == 1.0, "Scientific small rounding/floor")
	_check(BIG.floored(BIG.new(-1.2)) == -2.0 and BIG.truncated(BIG.new(-1.2)) == -1.0, "Signed small floor/truncate")
	_check(BIG.floored(BIG.new(-1.0, -400)) == -1.0, "Signed subnormal floor")
	_close(BIG.subtract(1e308, -1e308), BIG.parse("2e308"), "Subtraction overflow promotion")
	_close(BIG.multiply(1e-300, 1e-100), BIG.parse("1e-400"), "Multiplication underflow promotion")
	_close(BIG.new(0.5, 400), BIG.parse("5e399"), "Constructor normalization")
	_close(BIG.subtract(BIG.parse("1e500"), BIG.parse("9.99999999999999e499")), BIG.parse("1e485"), "Near cancellation across scientific exponents")
	var native_price := 9.99999999999999e299
	var mixed_difference: Variant = BIG.subtract(BIG.new(1.0, 300), native_price)
	# Native inputs already contain binary rounding; bound error at the input scale.
	_close(BIG.add(mixed_difference, native_price), BIG.new(1.0, 300), "Near cancellation reconstructs the original mixed value")
	_check(BIG.compare(mixed_difference, 0.0) > 0, "Near mixed cancellation preserves sign")
	_check(BIG.valid(BIG.new()) and not BIG.valid(BIG.new(), false), "Scientific zero validation")
	_check(FORMAT.format_number(BIG.new(1.5)) == FORMAT.format_number(1.5), "Small scientific formatting matches native")
	_check(FORMAT.format_income_per_second(BIG.new(1.5)) == "1.5", "Scientific small income formatting")

func _test_wallet_residuals() -> void:
	EconomyManager.money = BIG.parse("1e500")
	_check(EconomyManager.spend_money(BIG.parse("9.99999999999999e499")), "Near-cancelling scientific purchase")
	_close(EconomyManager.money, BIG.parse("1e485"), "Near-cancelling purchase leaves the correct balance")
	EconomyManager.money = 1e16
	for index in range(128):
		_check(EconomyManager.add_money(1.0), "Repeated native tiny credit")
	_check(EconomyManager.spend_money(1e16), "Spend native base balance")
	_close(EconomyManager.money, 128.0, "Native tiny credits survive")
	EconomyManager.money = BIG.parse("1e500")
	for index in range(1000):
		EconomyManager.add_money(BIG.parse("1e484"))
	_check(EconomyManager.spend_money(BIG.parse("1e500")), "Spend scientific base balance")
	_close(EconomyManager.money, BIG.parse("1e487"), "Scientific tiny credits survive")
	EconomyManager.money = BIG.parse("1e500")
	EconomyManager.add_money(1.0)
	_check(EconomyManager.spend_money(BIG.parse("1e500")), "Spend while a tiny credit is pending")
	_close(EconomyManager.money, 1.0, "Cancellation reveals tiny credit")
	EconomyManager.money = 1e16
	_check(EconomyManager.spend_money(1.0), "Tiny debit accepted")
	_check(not EconomyManager.can_afford(1e16), "Pending debit prevents overspending")
	_check(EconomyManager.spend_money(1e16 - 2.0), "Spend affordable balance with pending debit")
	_close(EconomyManager.money, 1.0, "Tiny debit deducted")
	EconomyManager.money = 1e16
	EconomyManager.spend_money(1.0)
	EconomyManager.money = 10.0
	_check(EconomyManager.money_correction == 0.0 and EconomyManager.can_afford(10.0), "Direct balance replacement clears old correction")

func _reset_runtime() -> void:
	EconomyManager.reset_money()
	EconomyManager.set_developer_multipliers(1.0, 1.0)
	EconomyManager.set_global_multiplier(1.0)
	ButtonManager.reset_for_prestige()

func _test_frame_payments() -> void:
	for fps in [1, 30, 60, 144]:
		for scientific in [false, true]:
			_reset_runtime()
			var base: Variant = BIG.parse("1e500") if scientific else 1e20
			EconomyManager.money = base
			IncomeManager.activate_source("vending_machine")
			IncomeManager.activate_source("restaurant")
			IncomeManager.multiply_source_speed_multiplier("vending_machine", IncomeManager.get_source_production_time("vending_machine") / 0.001)
			IncomeManager.multiply_source_speed_multiplier("restaurant", IncomeManager.get_source_production_time("restaurant") / 0.0001)
			var expected: Variant = BIG.add(IncomeManager.get_source_income_unrounded("vending_machine"), IncomeManager.get_source_income_unrounded("restaurant"))
			for frame in range(fps):
				IncomeManager._process(1.0 / fps)
			_check(EconomyManager.spend_money(base), "Spend base after %d FPS" % fps)
			_close(EconomyManager.money, expected, "Multi-source earnings at %d FPS (scientific=%s)" % [fps, scientific])

func _test_fractional_cycles() -> void:
	for fps in [1, 30, 60, 144]:
		_reset_runtime()
		EconomyManager.set_developer_multipliers(1.0, 0.01)
		IncomeManager.activate_source("vending_machine")
		IncomeManager.multiply_source_speed_multiplier("vending_machine", IncomeManager.get_source_production_time("vending_machine") / 0.001)
		_close(IncomeManager.get_source_cycle_payout("vending_machine"), 0.1, "Sub-won cycle remains positive")
		for frame in range(fps):
			IncomeManager._process(1.0 / fps)
		_close(EconomyManager.money, 100.0, "Sub-won cycles pay at %d FPS" % fps)
	_reset_runtime()
	IncomeManager.activate_source("vending_machine")
	IncomeManager.source_pending_payouts["vending_machine"] = 0.75
	EconomyManager.set_developer_multipliers(1.0, BIG.parse("1e500"))
	IncomeManager._process(IncomeManager.get_source_production_time("vending_machine"))
	_close(BIG.add(IncomeManager.source_pending_payouts["vending_machine"], IncomeManager.source_pending_corrections["vending_machine"]), 0.75, "Fraction preserved through a huge batch")
	var huge_payment: Variant = EconomyManager.money
	EconomyManager.set_developer_multipliers(1.0, 0.025)
	IncomeManager._process(IncomeManager.get_source_production_time("vending_machine"))
	_check(EconomyManager.spend_money(huge_payment), "Spend huge batch after fractional payout")
	_close(EconomyManager.money, 1.0, "Fractions combine into a whole won across magnitudes")

func _test_extreme_cycle_counts() -> void:
	for fps in [1, 30, 60, 144]:
		_reset_runtime()
		IncomeManager.activate_source("vending_machine")
		IncomeManager.multiply_source_speed_multiplier("vending_machine", 100.0)
		EconomyManager.set_global_time_multiplier(1e308)
		var expected: Variant = IncomeManager.get_source_income_unrounded("vending_machine")
		for frame in range(fps):
			IncomeManager._process(1.0 / fps)
		_close(EconomyManager.money, expected, "Overflowing cycle counts at %d FPS" % fps)
		var remaining := IncomeManager.get_source_time_remaining("vending_machine")
		_check(remaining > 0.0 and remaining <= IncomeManager.get_source_production_time("vending_machine"), "Extreme timer remains valid")

func _test_callbacks_and_rollback() -> void:
	_reset_runtime()
	EconomyManager.money = 1e20
	IncomeManager.activate_source("vending_machine")
	IncomeManager.multiply_source_speed_multiplier("vending_machine", 5000.0)
	EconomyManager.money_changed.connect(_reset_on_payment)
	IncomeManager._process(0.01)
	_check(EconomyManager.money == 0.0 and EconomyManager.money_correction == 0.0, "Payout callback reset clears wallet")
	_check(not IncomeManager.source_active["vending_machine"] and IncomeManager.source_pending_payouts["vending_machine"] == 0.0 and IncomeManager.source_pending_corrections["vending_machine"] == 0.0, "Payout callback reset clears pending earnings")
	IncomeManager.activate_source("vending_machine")
	var limit := BIG.new(9.0, BIG.MAX_EXPONENT)
	EconomyManager.money = limit
	IncomeManager.source_pending_payouts["vending_machine"] = limit
	IncomeManager.source_pending_corrections["vending_machine"] = 0.75
	IncomeManager._flush_source_payout("vending_machine")
	_close(IncomeManager.source_pending_payouts["vending_machine"], limit, "Failed payout restores full pending amount")
	_close(IncomeManager.source_pending_corrections["vending_machine"], 0.75, "Failed payout restores correction")
	ErrorManager.clear_errors()
	ErrorManager.error_reported.connect(_reset_on_error)
	IncomeManager._flush_source_payout("vending_machine")
	_check(not IncomeManager.source_active["vending_machine"] and IncomeManager.source_pending_payouts["vending_machine"] == 0.0, "Error callback reset cannot resurrect earnings")
	ErrorManager.clear_errors()

func _reset_on_payment(_money: Variant) -> void:
	EconomyManager.money_changed.disconnect(_reset_on_payment)
	EconomyManager.reset_money()
	IncomeManager.reset_runtime_state()

func _reset_on_error(_error: Dictionary) -> void:
	ErrorManager.error_reported.disconnect(_reset_on_error)
	EconomyManager.reset_money()
	IncomeManager.reset_runtime_state()

func _test_save_residuals() -> void:
	_reset_runtime()
	var directory := ProjectSettings.globalize_path("res://.godot/payment_saves_%d" % Time.get_ticks_usec())
	_check(SaveManager.initialize(directory), "Initialize isolated residual saves")
	EconomyManager.money = BIG.parse("1e500")
	EconomyManager.money_correction = BIG.subtract(0.0, BIG.parse("1e484"))
	IncomeManager.source_pending_payouts["vending_machine"] = BIG.parse("1e400")
	IncomeManager.source_pending_corrections["vending_machine"] = BIG.subtract(0.0, BIG.parse("1e384"))
	var snapshot := SaveManager._capture_progress()
	_check(SaveManager._validate_progress(snapshot), "Signed residual save validates")
	_check(SaveManager.save_slot(1), "Write signed residual save")
	EconomyManager.reset_money()
	IncomeManager.reset_runtime_state()
	_check(SaveManager.load_slot(1), "Load signed residual save")
	_close(EconomyManager.money_correction, BIG.subtract(0.0, BIG.parse("1e484")), "Wallet correction round trip")
	_close(IncomeManager.source_pending_corrections["vending_machine"], BIG.subtract(0.0, BIG.parse("1e384")), "Source correction round trip")
	var legacy := SaveManager._create_initial_progress()
	legacy.economy.erase("money_correction")
	for source: Dictionary in legacy.sources.values():
		source.erase("pending_correction")
	_check(SaveManager._validate_progress(legacy), "Legacy saves without corrections accepted")
	SaveManager._restore_progress(legacy)
	_check(EconomyManager.money_correction == 0.0 and IncomeManager.source_pending_corrections["vending_machine"] == 0.0, "Legacy residual defaults")
	EconomyManager.money = 1e16
	EconomyManager.add_money(1.0)
	IncomeManager.source_pending_payouts["vending_machine"] = 0.75
	_check(SaveManager.save_slot(2) and SaveManager.load_slot(2), "Small credit save/load")
	EconomyManager.add_money(1.0)
	_check(EconomyManager.spend_money(1e16), "Spend base after residual restoration")
	_close(EconomyManager.money, 2.0, "Small credit survives save and resumes accumulation")
	_restore_on_failure = SaveManager._create_initial_progress()
	_restore_on_failure.economy.money = 42.0
	_restore_on_failure.sources.vending_machine.pending_payout = 0.75
	EconomyManager.money = BIG.new(9.0, BIG.MAX_EXPONENT)
	IncomeManager.source_pending_payouts["vending_machine"] = BIG.new(9.0, BIG.MAX_EXPONENT)
	IncomeManager.source_pending_corrections["vending_machine"] = 0.0
	ErrorManager.error_reported.connect(_load_on_error)
	IncomeManager._flush_source_payout("vending_machine")
	_check(EconomyManager.money == 42.0 and IncomeManager.source_pending_payouts["vending_machine"] == 0.75, "Loading from an error callback preserves restored earnings")
	ErrorManager.clear_errors()

func _load_on_error(_error: Dictionary) -> void:
	ErrorManager.error_reported.disconnect(_load_on_error)
	SaveManager._restore_progress(_restore_on_failure)

func _close(actual: Variant, expected: Variant, message: String) -> void:
	if BIG.compare(expected, 0.0) == 0:
		_check(BIG.compare(actual, 0.0) == 0, message + ": " + str(actual))
	else:
		_check(absf(float(BIG.divide(actual, expected)) - 1.0) < 1e-11, message + ": " + str(actual) + " vs " + str(expected))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
