extends "res://tests/balance_playthrough_v2.gd"

var _test_failures: Array[String] = []
var _fresh_state: Dictionary = {}


func _run() -> void:
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	var directory := ProjectSettings.globalize_path("res://.godot/balance_v2_rules_%d" % Time.get_ticks_usec())
	if not SaveManager.initialize(directory):
		get_tree().quit(1)
		return
	_fresh_state = SaveManager._create_initial_progress()
	_connect_events()
	_check(estimate_wait(1000.0, 400.0, 1.0) == 600.0, "Wait estimate must use the shortage after existing money.")
	_check(estimate_wait(1000.0, 401.0, 1.0) < 600.0, "A wait below ten minutes must remain eligible.")
	_check(estimate_wait(100.0, 100.0, 0.0) == 0.0, "An affordable purchase needs no income.")
	_check(is_inf(estimate_wait(100.0, 0.0, 0.0)), "No income and insufficient funds must have infinite wait.")
	_check(absf(float(estimate_wait(BIG.parse("1e500"), BIG.parse("9e499"), BIG.parse("1e498"))) - 10.0) < 1.0e-9, "Scientific values must retain correct waiting times.")
	await _test_wait_limit()
	_test_successful_dm()
	_test_failed_bargain()
	await _test_prestige_after_dm()
	_check(ErrorManager.get_errors().is_empty(), "Rule fixtures must not produce game errors.")
	SaveManager.initialized = false
	if _test_failures.is_empty():
		print("PASS: inclusive 600-second stop, shortage/zero/scientific income, two bargains then acceptance, natural breakdown, reward-before-prestige and exactly one prestige with post-reset purchases")
	get_tree().quit(0 if _test_failures.is_empty() else 1)


func _fresh() -> void:
	SaveManager._restore_progress(_fresh_state)
	_frame = 0
	_run_index = 1
	_run_start_frame = 0
	_prestiges_done = 0
	_prestige_records.clear()
	_actions.clear()
	_button_log.clear()
	_timeline.clear()
	_unlock_frames.clear()
	_failure = ""
	_status = "진행 중"
	_end_reason = ""
	_stop_snapshot.clear()
	_dm_started = 0
	_dm_accepted = 0
	_dm_rejected = 0
	_dm_bargains = 0
	_dm_deposited = 0.0
	_dm_ready = false
	_candidate_dirty = true
	_rate_dirty = true
	_last_button_in_run = 0
	_last_purchase_in_run = 0
	EventManager._rng.seed = event_seed


func _test_wait_limit() -> void:
	_fresh()
	# Only this synthetic button remains, with an exact ten-minute shortage.
	for button in ButtonManager.buttons:
		button.bought = true
	var target := ButtonManager.get_button("trashbin")
	var source := IncomeManager.get_source("vending_machine")
	var old_price := target.price
	var old_large_price := target.large_price
	var old_base := source.base_income
	var old_time := source.base_time
	var old_cost := source.upgrade_base_cost
	target.bought = false
	target.price = 1000.0
	target.large_price = ""
	source.base_income = 60.0
	source.base_time = 60.0
	source.upgrade_base_cost = 1.0e9
	IncomeManager.activate_source(source.id)
	EconomyManager.money = 400.0
	await _play()
	_check(_status == "대기 한도 종료" and _frame == 0 and _actions.is_empty(), "Exactly 600 seconds must stop immediately before any purchase or time advance.")
	_check(_stop_snapshot.get("wait", 0.0) == 600.0, "The stop report must capture the real estimated wait.")
	target.price = old_price
	target.large_price = old_large_price
	source.base_income = old_base
	source.base_time = old_time
	source.upgrade_base_cost = old_cost


func _prepare_dm(chances: PackedFloat32Array) -> PackedFloat32Array:
	_fresh()
	IncomeManager.activate_source("vending_machine")
	ButtonManager.get_button("bumin").bought = true
	var data := EventManager._definitions[EventManager.PHONE_DM_ID] as PhoneDMEventData
	var original := data.breakdown_chances.duplicate()
	data.breakdown_chances = chances
	_check(EventManager.start_event_for_testing(data.id), "The isolated dialogue fixture must start.")
	return original


func _finish_dm() -> void:
	for step in range(60 * SIMULATION_FPS):
		_step_simulation()
		if not EventManager.is_event_active(EventManager.PHONE_DM_ID):
			return
	_check(false, "A dialogue fixture must finish within sixty simulated seconds.")


func _test_successful_dm() -> void:
	var original := _prepare_dm(PackedFloat32Array([0.0, 0.0, 0.0]))
	_finish_dm()
	_check(_dm_bargains == 2 and _dm_accepted == 1 and _dm_rejected == 0, "A successful DM must bargain twice and then accept, never a third time.")
	_check(BIG.compare(_dm_deposited, 0.0) > 0, "Accepted rewards must actually reach the wallet.")
	_check(_failure.is_empty(), "Successful DM handling must not fail.")
	(EventManager._definitions[EventManager.PHONE_DM_ID] as PhoneDMEventData).breakdown_chances = original


func _test_failed_bargain() -> void:
	var original := _prepare_dm(PackedFloat32Array([1.0, 1.0, 1.0]))
	_finish_dm()
	_check(_dm_bargains == 1 and _dm_rejected == 1 and _dm_accepted == 0, "A natural breakdown must end the DM without forced acceptance.")
	_check(BIG.compare(_dm_deposited, 0.0) == 0, "A broken deal must not pay a reward.")
	(EventManager._definitions[EventManager.PHONE_DM_ID] as PhoneDMEventData).breakdown_chances = original


func _test_prestige_after_dm() -> void:
	var original := _prepare_dm(PackedFloat32Array([0.0, 0.0, 0.0]))
	ButtonManager.get_button("bumin").bought = true
	var bin := ButtonManager.get_button("jjamtong")
	EconomyManager.money = bin.get_price()
	_check(ButtonManager.purchase(bin) and PrestigeManager.jjam_unlocked, "Buying the real bin must unlock prestige.")
	# End the synthetic world after the reset so only one prestige is exercised.
	var finish_world := func() -> void:
		for button in ButtonManager.buttons:
			button.bought = true
	PrestigeManager.prestige_changed.connect(finish_world, CONNECT_ONE_SHOT)
	await _play()
	_check(_failure.is_empty() and _status == "완료", "The world must finish after the first prestige.")
	_check(_prestiges_done == 1 and PrestigeManager.prestige_count == 1 and _run_index == 2, "Only one prestige must be performed.")
	_check(_dm_accepted == 1 and BIG.compare(_dm_deposited, 0.0) > 0, "An active DM must finish instead of being cancelled by prestige.")
	if not _prestige_records.is_empty():
		_check(BIG.compare(_prestige_records[0].money, _dm_deposited) >= 0, "The accepted deposit must precede the wallet reset.")
	ButtonManager.get_button("vending_machine").bought = false
	_candidate_dirty = true
	await _play()
	_check(_actions.size() == 1 and _actions[0].run == 2 and _actions[0].id == "vending_machine", "Cheapest purchases must resume in the second run.")
	_check(PrestigeManager.prestige_count == 1, "Purchasing after prestige must not trigger another reset.")
	(EventManager._definitions[EventManager.PHONE_DM_ID] as PhoneDMEventData).breakdown_chances = original


func _check(condition: bool, message: String) -> void:
	if not condition:
		_test_failures.append(message)
		push_error(message)
