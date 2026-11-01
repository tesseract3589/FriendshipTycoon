extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const PHONE_SCENE: PackedScene = preload("res://ui/phone_dm_panel.tscn")
const TOOLS_SCENE: PackedScene = preload("res://ui/developer_tools.tscn")
const DM_ID: String = "phone_dm"

var _failures: Array[String] = []
var _initial_state: Dictionary
var _data: PhoneDMEventData


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	_data = EventManager._definitions.get(DM_ID) as PhoneDMEventData
	if _data == null:
		push_error("The DM resource must register successfully.")
		get_tree().quit(1)
		return
	_check(_data.unlock_condition.type == UnlockCondition.Type.BUTTON and _data.unlock_condition.value == "bumin", "DM must unlock through bumin.")
	_check(_data.permanent_unlock, "DM eligibility must survive prestige.")
	_check(not EventManager.can_start_event(DM_ID), "An uninitialized game cannot start events.")
	var directory := ProjectSettings.globalize_path("res://.godot/events_test_%d" % Time.get_ticks_usec())
	if not SaveManager.initialize(directory):
		get_tree().quit(1)
		return
	_initial_state = SaveManager._create_initial_progress()
	# Schedule the DM independently of unrelated tutorials and their presentation locks.
	for definition in EventManager.events:
		definition.enabled = definition.id == DM_ID
	_data.chance_per_roll = 0.0
	var hud := CanvasLayer.new()
	add_child(hud)
	var phone := PHONE_SCENE.instantiate() as PhoneDMPanel
	hud.add_child(phone)
	var tools := TOOLS_SCENE.instantiate() as DeveloperToolsPanel
	tools.visible = false
	hud.add_child(tools)
	await get_tree().process_frame
	_check(not tools.is_processing(), "Hidden developer tools must stop refreshing.")
	_check(not EventManager.can_start_event(DM_ID), "The DM must wait for its purchase condition.")
	_check(EventManager.get_event_start_block_reason(DM_ID).contains("bumin"), "The diagnostic must name the missing purchase.")
	_unlock_dm()
	IncomeManager.activate_source("bumin")
	_check(EventManager.can_start_event(DM_ID), "A purchased bumin with the phone UI must be eligible.")
	EventManager._process(_data.roll_interval_seconds * 10.0)
	_check(not EventManager.is_event_active(DM_ID) and _debug_state().roll_attempts == 10, "Zero probability must count trials without starting.")
	tools.toggle()
	tools.set_process(false)
	var controls: Dictionary = tools._event_row_controls[DM_ID]
	_check(not controls.start_button.disabled, "An eligible DM needs an immediate-start button.")
	controls.start_button.pressed.emit()
	_check(EventManager.is_event_active(DM_ID) and phone.phone.visible, "The developer button must bypass probability and open the actual phone.")
	_check(controls.start_button.disabled and not EventManager.start_event(DM_ID), "An active DM cannot start twice.")
	EventManager.finish_event(DM_ID, "test")
	var cooldown := _data.cooldown_seconds
	_check(EventManager.get_cooldown_remaining(DM_ID) == cooldown, "Finishing must start the configured cooldown.")
	_check(not EventManager.start_event(DM_ID), "Regular activation must respect cooldown.")
	EventManager._process(10.0)
	tools._process(0.11)
	_check(is_equal_approx(EventManager.get_cooldown_remaining(DM_ID), cooldown - 10.0), "The cooldown must tick normally.")
	var remaining := cooldown - 10.0
	var countdown := "%02d:%04.1f" % [floori(remaining / 60.0), fmod(remaining, 60.0)]
	_check(controls.title.text.contains(countdown), "The tool countdown must reflect the configured cooldown.")
	_check(not controls.start_button.disabled, "Testing may bypass cooldown.")
	EconomyManager.set_developer_multipliers(100.0, 1.0)
	EventManager._process(1.0)
	_check(is_equal_approx(EventManager.get_cooldown_remaining(DM_ID), cooldown - 11.0), "Production speed must not change event time.")
	EconomyManager.set_developer_multipliers(1.0, 1.0)
	EventManager.restore_save_state({DM_ID: cooldown + 300.0})
	_check(EventManager.get_cooldown_remaining(DM_ID) == cooldown, "Long saved cooldowns must clamp to the current setting.")
	EventManager.restore_save_state({DM_ID: 12.5})
	_check(EventManager.get_cooldown_remaining(DM_ID) == 12.5, "A shorter saved cooldown must remain intact.")
	EventManager._process(12.5)
	_check(EventManager.get_cooldown_remaining(DM_ID) == 0.0, "An expired cooldown must reach zero.")
	tools.size = Vector2(360.0, 480.0)
	tools._fit_panel()
	await get_tree().process_frame
	_check(tools.panel.size.x <= 328.0 and tools.panel.size.y <= 448.0, "The tools must fit a small viewport.")
	tools._close()
	_test_scheduling()
	_test_reward_and_prestige()
	_test_tutorial_conditions()
	_check(ErrorManager.get_errors().is_empty(), "Valid event flows must not produce game errors.")
	hud.queue_free()
	await get_tree().process_frame
	SaveManager.initialized = false
	if _failures.is_empty():
		print("PASS: configured DM scheduling/cooldown, real developer controls, minimum offers, reward settlement/cancellation, permanent unlock, prestige and tutorial eligibility")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _unlock_dm() -> void:
	var button := ButtonManager.get_button("bumin")
	button.bought = true
	ButtonManager.button_purchased.emit(button)


func _debug_state() -> Dictionary:
	for state in EventManager.get_event_debug_states():
		if state.id == DM_ID:
			return state
	return {}


func _test_scheduling() -> void:
	EventManager.restore_save_state({})
	_data.chance_per_roll = 1.0
	var interval := _data.roll_interval_seconds
	EventManager._process(interval * 0.5)
	_check(not EventManager.is_event_active(DM_ID), "A roll must wait for its full interval.")
	EventManager._process(interval * 0.5)
	_check(EventManager.is_event_active(DM_ID) and _debug_state().last_roll_result == "자동 발동", "A guaranteed roll must start automatically.")
	EventManager.finish_event(DM_ID, "test")
	EventManager.restore_save_state({})
	EventManager._process(interval * 5.0)
	_check(EventManager.is_event_active(DM_ID) and _debug_state().roll_attempts == 5, "A long frame must combine all missed trials.")
	EventManager.finish_event(DM_ID, "test")
	# Fix probability only for the statistical fixture; gameplay tuning is independent.
	_data.chance_per_roll = 0.03
	EventManager._rng.seed = 42
	var total_wait := 0
	var no_start := 0
	for sample in range(500):
		EventManager.restore_save_state({})
		var wait_steps := 0
		while not EventManager.is_event_active(DM_ID) and wait_steps < 600:
			EventManager._process(interval)
			wait_steps += 1
		total_wait += wait_steps
		if not EventManager.is_event_active(DM_ID):
			no_start += 1
		EventManager.finish_event(DM_ID, "test")
	var mean_steps := total_wait / 500.0
	_check(no_start == 0 and mean_steps > 25.0 and mean_steps < 45.0, "Seeded 3% trials must follow the expected geometric wait.")
	_data.chance_per_roll = 0.0


func _reserve_reward() -> Variant:
	if not EventManager.start_event_for_testing(DM_ID):
		_check(false, "The reward fixture must start a DM.")
		return 0.0
	for step in range(32):
		if EventManager._waiting_for_choice:
			break
		EventManager._advance_phone_dm(100.0)
	_check(EventManager.choose_phone_dm(EventManager.Choice.ACCEPT), "The current offer must be accepted once.")
	_check(not EventManager.choose_phone_dm(EventManager.Choice.ACCEPT), "A repeated acceptance must be rejected.")
	for step in range(32):
		if EventManager._phone_reward_id >= 0:
			return EventManager._offer
		EventManager._advance_phone_dm(100.0)
	_check(false, "Acceptance must reserve a reward within a bounded number of steps.")
	return 0.0


func _test_reward_and_prestige() -> void:
	SaveManager._restore_progress(_initial_state)
	_unlock_dm()
	# Permanent unlock + the minimum offer permits zero-income transactions.
	ButtonManager.get_button("bumin").bought = false
	var unlocked := EventManager.get_save_state()
	EventManager.restore_save_state(unlocked)
	_check(EventManager.is_event_unlocked(DM_ID) and EventManager.can_start_event(DM_ID), "Saved permanent unlock must permit a zero-income DM.")
	var reward: Variant = _reserve_reward()
	_check(BIG.compare(reward, _data.minimum_offer_amount) == 0, "Zero income must use the configured minimum offer.")
	_check(BIG.compare(IncomeManager.total_earned_income, reward) == 0 and BIG.compare(EconomyManager.money, 0.0) == 0, "Reserve income once before the visual deposit.")
	_check(BIG.compare(EventManager.get_wallet_for_save()[0], reward) == 0, "Saving must include outstanding accepted rewards.")
	EventManager.set_reward_deposit_ui_available(false)
	EventManager.finish_event(DM_ID, "accepted")
	EventManager._process(0.0)
	_check(BIG.compare(EconomyManager.money, reward) == 0 and BIG.compare(IncomeManager.total_earned_income, reward) == 0, "Settlement must pay once without recording income twice.")
	EventManager._process(0.0)
	_check(BIG.compare(EconomyManager.money, reward) == 0, "Repeated settlement must not duplicate the reward.")
	SaveManager._restore_progress(_initial_state)
	_unlock_dm()
	PrestigeManager.unlock_jjam()
	reward = _reserve_reward()
	_check(BIG.compare(IncomeManager.jjam_earned_income, reward) == 0, "Reservations after jjam unlock must enter the run ledger.")
	_check(PrestigeManager.jjam_prestige(), "The initial jjam must allow a real prestige.")
	_check(EventManager.get_event_result(DM_ID) == "rejected" and EventManager._pending_rewards.is_empty(), "Prestige must reject the active deal and clear delayed rewards.")
	_check(BIG.compare(IncomeManager.total_earned_income, 0.0) == 0 and BIG.compare(EconomyManager.money, 0.0) == 0, "Rejected reserved rewards must not survive in money or lifetime earnings.")
	_check(EventManager.is_event_unlocked(DM_ID), "DM permanent unlock must survive prestige.")


func _test_tutorial_conditions() -> void:
	SaveManager._restore_progress(_initial_state)
	var income_guide := EventManager._definitions[EventManager.INCOME_UPGRADE_TUTORIAL_ID] as GameEventData
	income_guide.enabled = true
	EventManager.set_income_upgrade_tutorial_ui_available(true)
	_check(ButtonManager.purchase_by_id("vending_machine"), "The free vending machine must be purchasable.")
	_check(EventManager.is_event_active(income_guide.id), "Buying the first vending machine must start its tutorial.")
	EventManager.notify_income_upgrade_panel_opened("vending_machine")
	_check(not EventManager.is_event_active(income_guide.id), "Opening the source panel must dismiss the tutorial.")
	PrestigeManager.unlock_jjam()
	_check(PrestigeManager.jjam_prestige(), "Prepare the first prestige run.")
	var shop_guide := EventManager._definitions[EventManager.JJAM_SHOP_TUTORIAL_ID] as GameEventData
	shop_guide.enabled = true
	EventManager.set_jjam_shop_tutorial_ui_available(true)
	_check(ButtonManager.purchase_by_id("vending_machine"), "Rebuy vending after the first prestige.")
	_check(not EventManager.is_event_active(income_guide.id) and EventManager.is_event_active(shop_guide.id), "The first prestige must switch from the income tutorial to the shop tutorial.")
	EventManager.finish_event(shop_guide.id, "completed")
	IncomeManager.record_income(PrestigeManager.money_per_jjam)
	_check(PrestigeManager.jjam_prestige(), "Prepare a second prestige run.")
	EventManager.restore_save_state({})
	_check(ButtonManager.purchase_by_id("vending_machine"), "Rebuy vending after the second prestige.")
	_check(not EventManager.is_event_active(shop_guide.id), "Even with no consumed record, the shop guide must not run after the second prestige.")
