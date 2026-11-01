extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const GROWTH = preload("res://scripts/ResourceInit/JjamGrowthData.gd")

var _failures: Array[String] = []
var _initial: Dictionary
var _price: float


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _fresh() -> void:
	SaveManager._restore_progress(_initial)
	PrestigeManager.unlock_jjam()


func _earn(jjam_at_base_rate: float) -> void:
	IncomeManager.record_income(jjam_at_base_rate * _price)


func _run() -> void:
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	_check(SaveManager.initialize(ProjectSettings.globalize_path("res://.godot/jjam_growth_%d" % Time.get_ticks_usec())), "Use isolated saves.")
	_initial = SaveManager._create_initial_progress()
	_price = PrestigeManager.money_per_jjam
	_check(_price == 12000000000.0, "Keep the initial money ratio.")
	# Use a known coefficient for exact boundary fixtures, preserving the user's .tres tuning.
	var configured_curve: Resource = PrestigeManager.jjam_growth
	PrestigeManager.jjam_growth = configured_curve.duplicate()
	PrestigeManager.jjam_growth.difficulty_multiplier = 4.0
	_test_boundaries()
	_test_prestige()
	_test_faster_start()
	_test_spending_and_saves()
	_test_revoked_income()
	_test_reference_and_large_income()
	PrestigeManager.jjam_growth = configured_curve
	_check(ErrorManager.get_errors().is_empty(), "Growth must not produce runtime errors.")
	SaveManager.initialized = false
	if _failures.is_empty():
		print("PASS: live-only difficulty, faster post-prestige production, fresh-run curve reset, shop independence, initial ratio, fractional progress, save migration, DM revocation and scientific income")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_boundaries() -> void:
	SaveManager._restore_progress(_initial)
	_earn(10000.0)
	_check(PrestigeManager.live_jjam == 0, "Income before unlock cannot create jjam.")
	PrestigeManager.unlock_jjam()
	_check(PrestigeManager.live_jjam == 400, "Unlock grants exactly 400 and resets the qualifying ledger.")
	IncomeManager.record_income(_price - 1.0)
	_check(PrestigeManager.live_jjam == 400, "No first jjam before the original money threshold.")
	IncomeManager.record_income(1.0)
	_check(PrestigeManager.live_jjam == 401, "The original initial conversion ratio remains exact.")
	_earn(399.0)
	_check(PrestigeManager.live_jjam == 800, "400 to 800 uses the original price.")
	IncomeManager.record_income(4.0 * _price - 1.0)
	_check(PrestigeManager.live_jjam == 800, "The next point costs 4x at exactly 800 live jjam.")
	IncomeManager.record_income(1.0)
	_check(PrestigeManager.live_jjam == 801, "Award at the exact 4x threshold.")
	_fresh()
	_earn(400.0 + 800.0 * 4.0 + 1600.0 * 16.0)
	_check(PrestigeManager.live_jjam == 3200, "One income payment must cross every tier at its own price.")
	_earn(64.0)
	_check(PrestigeManager.live_jjam == 3201, "At 3200 the cost has reached 64x.")


func _test_prestige() -> void:
	_fresh()
	_check(PrestigeManager.jjam_prestige(), "Bank the initial 400.")
	_check(PrestigeManager.banked_jjam == 400 and PrestigeManager.live_jjam == 0, "Only the first unlock grants free jjam.")
	_check(PrestigeManager.get_prestige_multiplier() == 5.0, "Keep the existing 1% per banked jjam bonus.")
	_earn(400.0)
	_check(PrestigeManager.live_jjam == 400 and PrestigeManager.total_jjam == 800, "Banked jjam must not raise this run's difficulty.")
	_check(PrestigeManager.jjam_prestige(), "Prestige again at 800 total.")
	_earn(1.0)
	_check(PrestigeManager.live_jjam == 1 and PrestigeManager.banked_jjam == 800, "Prestige restarts at the base price, without a duplicate initial grant.")
	_check(PrestigeManager.jjam_prestige(), "A third prestige still works.")
	_earn(1.0)
	_check(PrestigeManager.live_jjam == 1, "Every prestige restarts the live curve at the base price.")
	for banked: Variant in [800, 1000000, BIG.parse("1e400")]:
		var state := _initial.duplicate(true)
		state.prestige.jjam_unlocked = true
		state.prestige.prestige_count = 10
		state.prestige.banked_jjam = BIG.serialize_count(banked)
		state.prestige.total_jjam = BIG.serialize_count(banked)
		SaveManager._restore_progress(state)
		_earn(800.0)
		_check(PrestigeManager.live_jjam == 800, "Even huge banked balances must not raise live earning prices.")
		_earn(3.0)
		_check(PrestigeManager.live_jjam == 800, "Live jjam alone must still trigger diminishing returns at 800.")
		_earn(1.0)
		_check(PrestigeManager.live_jjam == 801, "Live-only difficulty retains exact tier thresholds.")


func _test_faster_start() -> void:
	_fresh()
	var source := IncomeManager.get_source("vending_machine")
	var original_base := source.base_income
	var original_override := source.large_base_income
	source.base_income = _price
	source.large_base_income = ""
	IncomeManager.activate_source(source.id)
	var cycle := IncomeManager.get_source_production_time(source.id)
	var before: Variant = PrestigeManager.live_jjam
	IncomeManager._process(cycle)
	var first_gain: Variant = BIG.subtract(PrestigeManager.live_jjam, before)
	_check(first_gain == 1, "One baseline production cycle earns one jjam before the first prestige.")
	_check(PrestigeManager.jjam_prestige(), "Prestige with the actual production earnings.")
	IncomeManager.activate_source(source.id)
	IncomeManager._process(IncomeManager.get_source_production_time(source.id))
	_check(PrestigeManager.live_jjam == 5, "The same source earns five live jjam per cycle after banking 401, instead of one.")
	_check(BIG.compare(PrestigeManager.live_jjam, first_gain) > 0, "The retained income bonus must make the new run visibly faster.")
	source.base_income = original_base
	source.large_base_income = original_override
	IncomeManager.reset_runtime_state()


func _test_spending_and_saves() -> void:
	_fresh()
	_check(PrestigeManager.jjam_prestige(), "Prepare banked jjam for shop spending.")
	_earn(399.5)
	_check(PrestigeManager.live_jjam == 399, "Keep half a point outside the usable integer balance.")
	_check(PrestigeManager.purchase_shop_item("batch_upgrade_panel"), "Spend 100 banked jjam through the real shop.")
	_check(PrestigeManager.banked_jjam == 300 and PrestigeManager.live_jjam == 399, "Spending must not reprice already earned jjam.")
	PrestigeManager.refresh_jjam()
	_check(PrestigeManager.live_jjam == 399, "Refreshing without new income cannot generate jjam after spending.")
	var snapshot := SaveManager._capture_progress()
	_check(SaveManager._validate_progress(snapshot) and SaveManager.save_slot(1), "Save the current curve position, including fractional progress.")
	_fresh()
	_check(SaveManager.load_slot(1), "Load the spending checkpoint.")
	_check(PrestigeManager.banked_jjam == 300 and PrestigeManager.live_jjam == 399 and PrestigeManager.owns_shop_item("batch_upgrade_panel"), "Restore balances and shop ownership.")
	_earn(0.5)
	_check(PrestigeManager.live_jjam == 400, "Spending and loading cannot discard half a point of progress.")
	_earn(400.0)
	_check(PrestigeManager.live_jjam == 800, "Spending banked jjam cannot change the live-only tier boundary.")
	_earn(3.0)
	_check(PrestigeManager.live_jjam == 800, "At 800 live jjam the 4x price applies regardless of banked spending.")
	_earn(1.0)
	_check(PrestigeManager.live_jjam == 801, "Cross the live-only threshold exactly.")
	# Old version-1 saves keep banked jjam, shop ownership and the initial grant;
	# unbanked income is recalculated with the newly configured curve.
	var old := _initial.duplicate(true)
	old.prestige.jjam_system_version = 1
	old.prestige.erase("growth_spending")
	old.prestige.jjam_unlocked = true
	old.prestige.prestige_count = 2
	old.prestige.banked_jjam = 800
	old.prestige.live_jjam = 4
	old.prestige.total_jjam = 804
	old.prestige.shop_purchases = {"batch_upgrade_panel": true}
	old.income.jjam_earned_income = 4.0 * _price
	old.income.total_earned_income = 4.0 * _price
	_check(SaveManager._validate_progress(old), "Keep version-1 saves readable.")
	SaveManager._restore_progress(old)
	_check(PrestigeManager.banked_jjam == 800 and PrestigeManager.live_jjam == 4 and PrestigeManager.owns_shop_item("batch_upgrade_panel"), "Migrate to live-only prices without wiping banked jjam or shop ownership.")
	old.prestige.jjam_system_version = 2
	old.prestige.growth_spending = [{"income": 2.0 * _price, "price": 100}]
	_check(SaveManager._validate_progress(old), "Old version-2 spending checkpoints remain readable.")
	SaveManager._restore_progress(old)
	_check(PrestigeManager.live_jjam == 4 and PrestigeManager.banked_jjam == 800, "Old spending checkpoints cannot affect the live-only curve.")
	_check(PrestigeManager.get_save_state().growth_spending.is_empty(), "New saves do not accumulate obsolete banked-spending checkpoints.")
	var invalid := old.duplicate(true)
	invalid.prestige.growth_spending[0].price = -1
	_check(not SaveManager._validate_progress(invalid), "Reject negative saved curve progress.")
	invalid = old.duplicate(true)
	invalid.prestige.growth_spending[0].income = BIG.serialize(BIG.parse("1e500"))
	_check(not SaveManager._validate_progress(invalid), "Reject a checkpoint beyond the run's recorded income.")


func _test_revoked_income() -> void:
	_fresh()
	_check(PrestigeManager.jjam_prestige(), "Prepare shop funds before a reserved DM reward.")
	_earn(500.0)
	_check(PrestigeManager.purchase_shop_item("batch_upgrade_panel"), "Spend while income is reserved.")
	IncomeManager.revoke_recorded_income(500.0 * _price, true)
	_check(PrestigeManager.live_jjam == 0 and PrestigeManager.banked_jjam == 300, "Revoking a reservation removes its live reward while retaining the shop payment.")
	_check(SaveManager._validate_progress(SaveManager._capture_progress()), "Revoked reservations leave valid curve checkpoints.")
	_earn(100.0)
	_check(PrestigeManager.live_jjam == 100, "Future earnings after revocation use current holdings.")
	_check(PrestigeManager.jjam_prestige(), "A revoked reward cannot be banked on prestige.")
	_check(PrestigeManager.banked_jjam == 400 and PrestigeManager.live_jjam == 0, "Bank only the real subsequent earnings.")


func _test_reference_and_large_income() -> void:
	var curve = GROWTH.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	for coefficient: float in [1.0, 1.5, 2.0, 4.0, 8.0]:
		curve.difficulty_multiplier = coefficient
		for sample in range(20):
			var held := rng.randi_range(0, 6400)
			var target := held + rng.randi_range(1, 1500)
			# Independent per-point reference, not the geometric-series shortcut.
			var required := 0.0
			for point in range(held, target):
				var step := maxi(0, floori(log(maxi(point, 400) / 400.0) / log(2.0)))
				required += pow(coefficient, step)
			var actual: Variant = curve.get_earned_jjam(required, held, 400, 1.0)
			_check(absf(float(actual) - float(target - held)) < 1.0e-7, "Match per-point reference for coefficient %s, holdings %s." % [coefficient, held])
	curve.difficulty_multiplier = 4.0
	var huge_income: Variant = BIG.parse("1e5000")
	var started := Time.get_ticks_usec()
	var huge: Variant = curve.get_earned_jjam(huge_income, 400, 400, _price)
	_check(BIG.valid(huge, false) and BIG.compare(huge, BIG.parse("1e1600")) > 0 and BIG.compare(huge, BIG.parse("1e1700")) < 0, "Huge income earns valid sublinear jjam past native float limits.")
	_check(Time.get_ticks_usec() - started < 1000000, "Huge rewards must calculate without iterating per point or per tier.")
	var small: Variant = curve.get_earned_jjam(_price, BIG.parse("1e400"), 400, _price)
	_check(BIG.valid(small) and BIG.compare(small, 1.0) < 0, "An ordinary payment at scientific holdings must not overflow or award a free point.")
