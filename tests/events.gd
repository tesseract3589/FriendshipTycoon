extends Node

const PHONE_SCENE: PackedScene = preload("res://ui/phone_dm_panel.tscn")
const TOOLS_SCENE: PackedScene = preload("res://ui/developer_tools.tscn")
const DM_ID: String = "phone_dm"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	# Run entirely in memory. Never initialize SaveManager or write the player's saves.
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	var data := EventManager._definitions.get(DM_ID) as PhoneDMEventData
	_check(data != null, "The DM resource must register successfully.")
	if data == null:
		get_tree().quit(1)
		return
	_check(data.cooldown_seconds == 60.0, "DM cooldown must be 60 seconds.")
	_check(not EventManager.can_start_event(DM_ID), "An uninitialized game cannot start events.")
	SaveManager.initialized = true
	var hud := CanvasLayer.new()
	add_child(hud)
	var phone := PHONE_SCENE.instantiate() as PhoneDMPanel
	hud.add_child(phone)
	var tools := TOOLS_SCENE.instantiate() as DeveloperToolsPanel
	tools.visible = false
	hud.add_child(tools)
	await get_tree().process_frame
	_check(not tools.is_processing(), "Hidden developer tools must stop refreshing.")
	_check(not EventManager.can_start_event(DM_ID), "SPA must be purchased before a DM.")
	_check(EventManager.get_event_start_block_reason(DM_ID).contains("spa"), "Show which purchase blocks an event.")
	ButtonManager.get_button("spa").bought = true
	IncomeManager.activate_source("spa")
	_check(EventManager.can_start_event(DM_ID), "A purchased SPA with income and HUD must be eligible.")
	EconomyManager.developer_income_multiplier = 0.0
	_check(not EventManager.can_start_event(DM_ID), "Zero income must be diagnosed before rolling.")
	EconomyManager.developer_income_multiplier = 1.0
	data.chance_per_roll = 0.0
	EventManager._process(10.0)
	_check(not EventManager.is_event_active(DM_ID), "Zero probability must never auto-start.")
	_check(EventManager.get_event_debug_states()[0].roll_attempts == 10, "Low frame rates must count every elapsed second.")
	tools.toggle()
	tools.set_process(false)
	var controls: Dictionary = tools._event_row_controls[DM_ID]
	_check(not controls.start_button.disabled, "Eligible events need an enabled immediate-start button.")
	controls.start_button.pressed.emit()
	_check(EventManager.is_event_active(DM_ID), "The real developer button must bypass a zero random probability.")
	_check(phone.phone.visible, "Immediate activation must open the real phone HUD.")
	_check(controls.start_button.disabled, "Active events must disable immediate activation.")
	_check(not EventManager.start_event(DM_ID), "Active events cannot start twice.")
	EventManager.finish_event(DM_ID, "test")
	_check(EventManager.get_cooldown_remaining(DM_ID) == 60.0, "Finishing starts the full one-minute cooldown.")
	_check(not EventManager.start_event(DM_ID), "Regular activation must respect the cooldown.")
	EventManager._process(10.0)
	tools._process(0.11)
	_check(is_equal_approx(EventManager.get_cooldown_remaining(DM_ID), 50.0), "The cooldown must tick normally.")
	_check(controls.title.text.contains("00:50.0"), "The developer readout must update live.")
	_check(not controls.start_button.disabled, "The developer test button must remain enabled during cooldown.")
	EconomyManager.set_developer_multipliers(100.0, 1.0)
	EventManager._process(1.0)
	_check(is_equal_approx(EventManager.get_cooldown_remaining(DM_ID), 49.0), "Production speed must not accelerate event cooldowns.")
	EconomyManager.set_developer_multipliers(1.0, 1.0)
	EventManager.restore_save_state({DM_ID: 299.0})
	_check(EventManager.get_cooldown_remaining(DM_ID) == 60.0, "Legacy five-minute saves must clamp to the new duration.")
	EventManager.restore_save_state({DM_ID: 12.5})
	_check(EventManager.get_cooldown_remaining(DM_ID) == 12.5, "Shorter saved cooldowns must be preserved.")
	EventManager._process(12.5)
	_check(EventManager.get_cooldown_remaining(DM_ID) == 0.0, "Expired cooldowns must reach zero.")
	tools._process(0.11)
	_check(not controls.start_button.disabled, "The developer button must enable once cooldown expires.")
	tools.size = Vector2(360.0, 480.0)
	tools._fit_panel()
	await get_tree().process_frame
	_check(tools.panel.size.x <= 328.0 and tools.panel.size.y <= 448.0, "The expanded tool panel must fit smaller windows.")
	tools._close()
	phone.queue_free()
	await get_tree().process_frame
	EventManager.set_phone_dm_ui_available(true)
	EventManager.restore_save_state({})
	data.chance_per_roll = 1.0
	EventManager._process(0.5)
	_check(not EventManager.is_event_active(DM_ID), "A random roll must wait one whole second.")
	EventManager._process(0.5)
	_check(EventManager.is_event_active(DM_ID), "Guaranteed rolls must start after cooldown expiration.")
	_check(EventManager.get_event_debug_states()[0].last_roll_result == "자동 발동", "Distinguish random from manual activation.")
	EventManager.finish_event(DM_ID, "test")
	EventManager.restore_save_state({})
	EventManager._process(5.0)
	_check(EventManager.is_event_active(DM_ID), "Low frame rates must still start eligible events.")
	_check(EventManager.get_event_debug_states()[0].roll_attempts == 5, "Combined rolls must expose the elapsed trial count.")
	EventManager.finish_event(DM_ID, "test")
	data.chance_per_roll = 0.03
	EventManager._rng.seed = 42
	var total_wait := 0
	var waits_over_60 := 0
	var no_start := 0
	for sample in range(500):
		EventManager.restore_save_state({})
		var wait_seconds := 0
		while not EventManager.is_event_active(DM_ID) and wait_seconds < 600:
			EventManager._process(1.0)
			wait_seconds += 1
		total_wait += wait_seconds
		if wait_seconds > 60:
			waits_over_60 += 1
		if not EventManager.is_event_active(DM_ID):
			no_start += 1
		EventManager.finish_event(DM_ID, "test")
	var mean_wait := total_wait / 500.0
	print("DM random trials: 500; mean wait %.3fs; waits >60s %d; failed starts %d" % [mean_wait, waits_over_60, no_start])
	_check(no_start == 0, "All 500 seeded waiting periods must eventually start.")
	_check(mean_wait > 25.0 and mean_wait < 45.0, "Observed waits must agree with the expected 33.3-second geometric mean.")
	_check(ErrorManager.get_errors().is_empty(), "No game errors should be produced.")
	# Keep SaveManager._exit_tree from saving this artificial in-memory test session.
	SaveManager.initialized = false
	if _failures.is_empty():
		print("PASS: DM cooldown, readiness diagnostics, real developer controls, save migration and random scheduling")
	get_tree().quit(0 if _failures.is_empty() else 1)
