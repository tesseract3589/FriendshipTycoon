extends Node

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
var _failures: Array[String] = []
var _test_directory: String


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	IncomeManager.set_process(false)
	_test_legacy_migration()
	_test_directory = ProjectSettings.globalize_path("res://.godot/save_system_test_%d" % Time.get_ticks_usec())
	_check(SaveManager.get_default_save_directory() == ProjectSettings.globalize_path("res://").path_join("saves"), "Debug builds must save inside res://saves.")
	_check(SaveManager.initialize(_test_directory), "Save folder initialization failed.")
	for slot in range(0, 11):
		_check(FileAccess.file_exists(SaveManager.get_slot_path(slot)), "Missing slot %d." % slot)
		_check(not SaveManager.get_slot_info(slot).has_save, "A new slot must be empty.")
	_check(not SaveManager.load_slot(2), "An empty slot cannot be loaded.")
	_check(SaveManager.get_slot_path(0).get_file() == "autosave.cfg", "The automatic save must use autosave.cfg.")
	_check(SaveManager.get_slot_path(1).get_file() == "slot_01.cfg" and SaveManager.get_slot_path(10).get_file() == "slot_10.cfg", "Manual filenames must match slots 1 through 10.")
	_check(not SaveManager.save_slot(0), "Manual saves must not overwrite autosave.")
	_check(not SaveManager.save_slot(2, true), "Autosaves must not write a manual slot.")
	_check(not SaveManager.save_slot(-1) and not SaveManager.save_slot(11), "Out-of-range slots must be rejected.")
	_check(not SaveManager.reset_slot(-1) and not SaveManager.reset_slot(11), "Out-of-range reset requests must be rejected.")
	EconomyManager.money = 1.0e12
	for id in ["vending_machine", "trashbin", "vending_machine_soldier", "promo_sign", "bike_delivery", "wireless_antenna"]:
		_check(ButtonManager.purchase_by_id(id), "Could not set up purchase: " + id)
	_check(IncomeManager.upgrade_source("vending_machine"), "Could not upgrade source.")
	_check(IncomeManager.upgrade_source("vending_machine"), "Could not upgrade source twice.")
	ButtonManager.get_button("trashbin").permanent_bought = true
	PrestigeManager.total_jjam = 9007199254740993
	PrestigeManager.current_jjam = 42
	EconomyManager.set_global_multiplier(3.0)
	EconomyManager.set_global_time_multiplier(2.0)
	EconomyManager.set_developer_multipliers(0.5, 1.25)
	IncomeManager._process(0.25)
	IncomeManager.source_pending_payouts["vending_machine"] = 0.75
	var expected := SaveManager._capture_progress()
	for slot in range(1, 11):
		_check(SaveManager.save_slot(slot), "Manual save failed for slot %d." % slot)
		_check(SaveManager.get_slot_info(slot).has_save, "Saved slot appears empty.")
		EconomyManager.money = 0.0
		IncomeManager.source_levels["vending_machine"] = 1
		ButtonManager.get_button("trashbin").bought = false
		_check(SaveManager.load_slot(slot), "Manual load failed for slot %d." % slot)
		_check(SaveManager._capture_progress() == expected, "Progress changed after disk round trip in slot %d." % slot)
	_check(PrestigeManager.total_jjam == 9007199254740993, "Prestige int64 precision was lost.")
	_check(SaveManager.save_slot(2), "Replacing an existing file failed.")
	_check(not FileAccess.file_exists(SaveManager.get_slot_path(2) + ".tmp"), "Temporary file was not removed.")
	# A semantically invalid file must not partially mutate money or purchases.
	var corrupted := ConfigFile.new()
	corrupted.load(SaveManager.get_slot_path(10))
	var invalid: Dictionary = corrupted.get_value("progress", "state")
	invalid.economy.money = 123.0
	invalid.sources.vending_machine.level = "invalid"
	corrupted.set_value("progress", "state", invalid)
	corrupted.save(SaveManager.get_slot_path(10))
	_check(not SaveManager.load_slot(10), "Invalid progress was accepted.")
	_check(SaveManager._capture_progress() == expected, "Invalid load changed live progress.")
	_check(not SaveManager.get_slot_info(10).valid, "Invalid file was shown as loadable.")
	invalid.sources.vending_machine.level = 9223372036854775807
	corrupted.set_value("progress", "state", invalid)
	corrupted.save(SaveManager.get_slot_path(10))
	_check(not SaveManager.load_slot(10), "An impossible level was accepted.")
	ErrorManager.clear_errors()
	# Force a disk write failure; an existing save must remain intact.
	var blocked_temp := SaveManager.get_slot_path(2) + ".tmp"
	DirAccess.make_dir_absolute(blocked_temp)
	_check(not SaveManager.save_slot(2), "A failed write was reported as successful.")
	_check(not SaveManager.reset_slot(2), "A failed reset was reported as successful.")
	_check(SaveManager.get_slot_info(2).valid and SaveManager.get_slot_info(2).has_save, "Failed write damaged the previous save.")
	DirAccess.remove_absolute(blocked_temp)
	ErrorManager.clear_errors()
	# Build the real HUD and exercise buttons, orange labels, selection and live restoration.
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().process_frame
	var ui := main.get_node("HUD/SaveSlotsPanel")
	_check(ui._slot_buttons.size() == 11, "The UI must expose autosave plus ten manual slots.")
	await _screenshot("hud.png")
	ui.open_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await _screenshot("slots.png")
	_check(ui.panel.position.x >= 0.0 and ui.panel.position.y >= 0.0 and ui.panel.get_global_rect().end.y <= ui.size.y, "The slot panel extends past the desktop viewport.")
	_check(ui.get_node("Overlay/Panel/Margin/VBox/Scroll").scroll_vertical == 0, "The automatic slot should be visible when the panel opens.")
	_check(ui.overlay.visible, "Save button did not open the slot UI.")
	ui._slot_buttons[0].pressed.emit()
	_check(ui.save_button.disabled, "The auto slot has a manual save button.")
	var auto_title := ui._slot_buttons[0].get_node("Margin/Text/Title") as Label
	_check(auto_title.text == "자동 저장 슬롯" and auto_title.get_theme_color("font_color") == ui.AUTO_COLOR, "The automatic slot must have an unnumbered orange label.")
	for slot in range(1, 11):
		_check(ui._slot_buttons[slot].get_node("Margin/Text/Title").text == "슬롯 %d" % slot, "Manual slot numbering is incorrect.")
	ui._slot_buttons[1].pressed.emit()
	_check(not ui.save_button.disabled and not ui.load_button.disabled, "Manual slot actions were not enabled.")
	EconomyManager.money = 1.0
	ui.load_button.pressed.emit()
	_check(ui.confirmation.visible, "Loading must show the progress replacement confirmation.")
	ui.confirmation.hide()
	ui.confirmation.confirmed.emit()
	_check(SaveManager._capture_progress() == expected, "Loading through the real UI did not restore progress.")
	_check(main.get_node("HUD/Panel/VBoxContainer/MoneyLabel").text.contains(preload("res://scripts/NumberFormatter.gd").format_number(expected.economy.money)), "Money HUD failed after restoration.")
	_check((main.get_node("World/IncomeSourceViews").get_child(0) as IncomeSourceView).source_is_active, "Income-source visuals failed after restoration.")
	ui.save_button.pressed.emit()
	_check(ui.confirmation.visible, "Overwrite must show a confirmation.")
	ui.confirmation.hide()
	ui.confirmation.confirmed.emit()
	await _test_slot_reset(ui)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(360, 640)
		await get_tree().process_frame
		ui._slot_buttons[10].grab_focus()
		await _screenshot("slots_small.png")
		_check(ui.panel.get_global_rect().end.x <= ui.size.x and ui.panel.get_global_rect().end.y <= ui.size.y, "The slot panel extends past a small viewport.")
	# Automatic saving writes autosave.cfg and preserves all ten manual files.
	var manual_text := FileAccess.get_file_as_string(SaveManager.get_slot_path(2))
	EconomyManager.money = 54321.0
	SaveManager.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(SaveManager.get_slot_info(0).money == 54321.0, "Background autosave did not write autosave.cfg.")
	_check(FileAccess.get_file_as_string(SaveManager.get_slot_path(2)) == manual_text, "Autosave overwrote a manual slot.")
	# Reinitialize the service as a subsequent launch and check automatic restoration.
	SaveManager.initialized = false
	EconomyManager.money = 0.0
	_check(SaveManager.initialize(_test_directory), "Reinitialization failed.")
	_check(EconomyManager.money == 54321.0, "Autosave was not automatically restored on launch.")
	# A damaged auto slot is preserved before a fresh session replaces it.
	var invalid_auto := ConfigFile.new()
	invalid_auto.set_value("slot", "version", 999)
	invalid_auto.save(SaveManager.get_slot_path(0))
	SaveManager.initialized = false
	SaveManager.initialize(_test_directory)
	_check(SaveManager.save_slot(0, true), "Could not replace a damaged auto slot.")
	_check(FileAccess.file_exists(SaveManager.get_slot_path(0) + ".invalid"), "The damaged auto slot was not preserved for recovery.")
	ErrorManager.clear_errors()
	_check(ErrorManager.get_errors().is_empty(), "Unexpected game errors during save/UI tests.")
	if _failures.is_empty():
		print("PASS: separate autosave plus ten manual slots, legacy migration and retry, typed progress round trips, int64 prestige, write-failure protection, invalid-file rejection, HUD actions, reset warning/cancellation/slot isolation, background autosave, startup restoration.")
	else:
		push_error("FAIL: %d save-system checks." % _failures.size())
	# Keep the test folder until exit so the actual close handler and fallback can run.
	print("TEST_SAVE_DIRECTORY: " + _test_directory)
	EconomyManager.money = 67890.0
	if OS.get_cmdline_user_args().has("--close-request") and _failures.is_empty():
		SaveManager.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		get_tree().quit(0 if _failures.is_empty() else 1)


func _screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_test_directory.path_join(filename))


func _test_slot_reset(ui: Control) -> void:
	var progress_before := SaveManager._capture_progress()
	var files_before: Dictionary = {}
	for slot in range(0, 11):
		files_before[slot] = FileAccess.get_file_as_string(SaveManager.get_slot_path(slot))
	ui._slot_buttons[1].pressed.emit()
	ui.reset_button.pressed.emit()
	_check(ui.confirmation.visible and ui.confirmation.dialog_text.contains("되돌릴 수 없습니다"), "Reset must show the irreversible-action warning.")
	_check(FileAccess.get_file_as_string(SaveManager.get_slot_path(1)) == files_before[1], "Opening the reset warning erased progress before confirmation.")
	await _screenshot("reset_warning.png")
	ui.confirmation.hide()
	ui.confirmation.canceled.emit()
	ui.confirmation.confirmed.emit()
	_check(FileAccess.get_file_as_string(SaveManager.get_slot_path(1)) == files_before[1], "Canceling reset changed the saved slot.")
	ui.reset_button.pressed.emit()
	# The confirmation targets the original selection even if selection later changes.
	ui._slot_buttons[2].pressed.emit()
	ui.confirmation.hide()
	ui.confirmation.confirmed.emit()
	_check(not SaveManager.get_slot_info(1).has_save and SaveManager.get_slot_info(1).valid, "Confirmed reset did not empty the selected slot.")
	_check(SaveManager._capture_progress() == progress_before, "Reset changed the current game progress.")
	for slot in range(0, 11):
		if slot != 1:
			_check(FileAccess.get_file_as_string(SaveManager.get_slot_path(slot)) == files_before[slot], "Reset erased an unrelated save slot.")
	ui._slot_buttons[1].pressed.emit()
	_check(ui.reset_button.disabled and ui.load_button.disabled and not ui.save_button.disabled, "An empty slot must be saveable with reset/load disabled.")
	# Corrupt saves remain resettable, and become valid empty slots.
	ui._slot_buttons[10].pressed.emit()
	_check(not ui.reset_button.disabled, "A corrupt save cannot be reset.")
	ui.reset_button.pressed.emit()
	ui.confirmation.hide()
	ui.confirmation.confirmed.emit()
	_check(SaveManager.get_slot_info(10).valid and not SaveManager.get_slot_info(10).has_save, "Corrupt-slot reset failed.")
	# Autosave can be cleared, while warning that normal automatic saving will resume.
	SaveManager.save_slot(0, true)
	ui._slot_buttons[0].pressed.emit()
	ui.reset_button.pressed.emit()
	_check(ui.confirmation.dialog_text.contains("게임 종료 시 현재 진행으로 다시 저장"), "Autosave reset must explain that it will be saved again on exit.")
	SaveManager._preserve_invalid_autosave = true
	ui.confirmation.hide()
	ui.confirmation.confirmed.emit()
	_check(not SaveManager.get_slot_info(0).has_save, "Autosave reset failed.")
	_check(not FileAccess.file_exists(SaveManager.get_slot_path(0) + ".invalid"), "Reset created an unwanted recovery copy.")
	_check(SaveManager._capture_progress() == progress_before, "Resetting autosave changed the current game.")
	SaveManager.initialized = false
	SaveManager.initialize(_test_directory)
	_check(not SaveManager.get_slot_info(1).has_save and not SaveManager.get_slot_info(0).has_save, "Reset saves reappeared on initialization.")
	ui._slot_buttons[1].pressed.emit()
	await _screenshot("slots_after_reset.png")


func _test_legacy_migration() -> void:
	var original := SaveManager._capture_progress()
	var legacy_directory := ProjectSettings.globalize_path("res://.godot/save_migration_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(legacy_directory)
	var expected_texts: Dictionary = {}
	for old_slot in range(1, 11):
		var config := ConfigFile.new()
		var state := original.duplicate(true)
		state.economy.money = 10000.0 + old_slot
		config.set_value("slot", "version", 1)
		config.set_value("slot", "number", old_slot)
		config.set_value("slot", "saved_at", "2026-10-11 12:00:00")
		config.set_value("progress", "state", state)
		var path := legacy_directory.path_join("slot_%02d.cfg" % old_slot)
		config.save(path)
		expected_texts[old_slot] = FileAccess.get_file_as_string(path)
	_check(SaveManager.initialize(legacy_directory), "Could not migrate old saves.")
	_check(EconomyManager.money == 10001.0, "The old automatic save was not restored from autosave.cfg.")
	for slot in range(1, 10):
		_check(SaveManager.get_slot_info(slot).money == 10001.0 + slot, "Old manual save moved to the wrong slot.")
	_check(not SaveManager.get_slot_info(10).has_save, "The new tenth manual slot must start empty.")
	var backup := ConfigFile.new()
	var backup_path := legacy_directory.path_join(SaveManager.LEGACY_BACKUP_FILENAME)
	_check(backup.load(backup_path) == OK, "Migration did not retain original save files.")
	_check(backup.get_value("migration", "files", {}) == expected_texts, "Original saves changed in the migration backup.")
	# Simulate interruption after staging: replacements must come from the backup.
	backup.set_value("migration", "complete", false)
	backup.save(backup_path)
	SaveManager.initialized = false
	_check(SaveManager.initialize(legacy_directory), "Interrupted migration could not resume.")
	_check(SaveManager.get_slot_info(1).money == 10002.0, "Retry shifted a manual save twice.")
	EconomyManager.money = 20000.0
	_check(SaveManager.save_slot(1), "The first manual slot cannot be saved.")
	SaveManager.initialized = false
	_check(SaveManager.initialize(legacy_directory), "Migrated saves could not reopen.")
	_check(SaveManager.get_slot_info(1).money == 20000.0, "Completed migration overwrote new manual progress on restart.")
	SaveManager._restore_progress(original)
	SaveManager.initialized = false
