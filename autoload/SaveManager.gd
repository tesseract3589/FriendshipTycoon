extends Node

signal slots_changed()
signal progress_loaded(slot: int)

const SLOT_COUNT: int = 10
const AUTO_SLOT: int = 0
const SAVE_VERSION: int = 2
const LEGACY_BACKUP_FILENAME := "legacy_slots_v1.cfg"

var save_directory: String = ""
var initialized: bool = false
var _saved_on_quit: bool = false
var _defaults: Dictionary = {}
var _preserve_invalid_autosave: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_default_save_directory() -> String:
	var base := ProjectSettings.globalize_path("res://") if OS.is_debug_build() else OS.get_executable_path().get_base_dir()
	return base.path_join("saves")


func initialize(directory: String = "") -> bool:
	if initialized:
		return true
	save_directory = get_default_save_directory() if directory.is_empty() else directory
	_preserve_invalid_autosave = false
	_defaults = _create_initial_progress()
	var error := DirAccess.make_dir_recursive_absolute(save_directory)
	if error != OK:
		return _file_error("SAVE_DIRECTORY", "저장 폴더를 만들 수 없습니다.", error)
	if not _migrate_legacy_slots():
		return false
	for slot in range(AUTO_SLOT, SLOT_COUNT + 1):
		if FileAccess.file_exists(get_slot_path(slot)):
			continue
		var empty_slot := _new_config(slot)
		empty_slot.set_value("slot", "saved_at", "")
		if not _write_config(slot, empty_slot):
			return false
	initialized = true
	get_tree().auto_accept_quit = false
	# Main calls this before creating world views. Test scenes do not initialize saves.
	var info := get_slot_info(AUTO_SLOT)
	_preserve_invalid_autosave = not info.valid
	load_slot(AUTO_SLOT)
	slots_changed.emit()
	return true


func get_slot_path(slot: int) -> String:
	if slot < AUTO_SLOT or slot > SLOT_COUNT or save_directory.is_empty():
		return ""
	if slot == AUTO_SLOT:
		return save_directory.path_join("autosave.cfg")
	return save_directory.path_join("slot_%02d.cfg" % slot)


func get_slot_name(slot: int) -> String:
	return "자동 저장 슬롯" if slot == AUTO_SLOT else "슬롯 %d" % slot


func _migrate_legacy_slots() -> bool:
	var backup_path := save_directory.path_join(LEGACY_BACKUP_FILENAME)
	var backup := ConfigFile.new()
	var legacy_files: Dictionary = {}
	if FileAccess.file_exists(backup_path):
		var error := backup.load(backup_path)
		if error != OK or not backup.has_section_key("migration", "files") \
			or not backup.has_section_key("migration", "complete") \
			or not backup.get_value("migration", "files", {}) is Dictionary \
			or not backup.get_value("migration", "complete", false) is bool:
			return _file_error("SAVE_MIGRATION", "이전 저장 파일의 백업을 읽을 수 없습니다.", error if error != OK else ERR_INVALID_DATA)
		legacy_files = backup.get_value("migration", "files", {})
		if not legacy_files.has(1):
			return _file_error("SAVE_MIGRATION", "이전 자동 저장의 백업이 없습니다.", ERR_INVALID_DATA)
		if backup.get_value("migration", "complete", false) == true:
			return true
	else:
		if FileAccess.file_exists(get_slot_path(AUTO_SLOT)):
			return true
		var first_legacy := ConfigFile.new()
		var first_path := save_directory.path_join("slot_01.cfg")
		if not FileAccess.file_exists(first_path):
			return true
		# Without autosave.cfg, numbered saves belong to the old ten-slot layout.
		if first_legacy.load(first_path) == OK and first_legacy.get_value("slot", "version", -1) == SAVE_VERSION:
			return true
		for old_slot in range(1, SLOT_COUNT + 1):
			var old_path := save_directory.path_join("slot_%02d.cfg" % old_slot)
			if not FileAccess.file_exists(old_path):
				continue
			var file := FileAccess.open(old_path, FileAccess.READ)
			if file == null:
				return _file_error("SAVE_MIGRATION", "이전 저장 파일을 읽을 수 없습니다.", FileAccess.get_open_error())
			legacy_files[old_slot] = file.get_as_text()
			var read_error := file.get_error()
			file.close()
			if read_error != OK:
				return _file_error("SAVE_MIGRATION", "이전 저장 파일을 읽을 수 없습니다.", read_error)
		backup.set_value("migration", "files", legacy_files)
		backup.set_value("migration", "complete", false)
		# Save every original file before replacing overlapping numbered filenames.
		if not _store_legacy_backup(backup_path, backup):
			return false
	for old_slot in legacy_files:
		if not old_slot is int or old_slot < 1 or old_slot > SLOT_COUNT or not legacy_files[old_slot] is String:
			return _file_error("SAVE_MIGRATION", "이전 저장 파일의 백업 내용이 올바르지 않습니다.", ERR_INVALID_DATA)
	# Retrying after an interrupted migration always reads the untouched backup.
	for slot in range(1, SLOT_COUNT + 1):
		if not _migrate_legacy_slot(slot, legacy_files.get(slot + 1, "")):
			return false
	if not _migrate_legacy_slot(AUTO_SLOT, legacy_files.get(1, "")):
		return false
	backup.set_value("migration", "complete", true)
	return _store_legacy_backup(backup_path, backup)


func _store_legacy_backup(path: String, backup: ConfigFile) -> bool:
	var temporary_path := path + ".tmp"
	var error := backup.save(temporary_path)
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, path)
	if error != OK:
		return _file_error("SAVE_MIGRATION", "이전 저장 파일의 백업을 보존하지 못했습니다.", error)
	return true


func _migrate_legacy_slot(slot: int, original_text: String) -> bool:
	if original_text.is_empty():
		return _write_config(slot, _new_config(slot))
	var config := ConfigFile.new()
	var old_slot := 1 if slot == AUTO_SLOT else slot + 1
	if config.parse(original_text) == OK and _valid_header(config, old_slot, 1):
		config.set_value("slot", "version", SAVE_VERSION)
		config.set_value("slot", "number", slot)
		return _write_config(slot, config)
	# Keep damaged saves available at their new slot and in the original backup.
	var path := get_slot_path(slot)
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _file_error("SAVE_MIGRATION", "이전 저장 파일을 옮기지 못했습니다.", FileAccess.get_open_error())
	file.store_string(original_text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, path)
	if error != OK:
		return _file_error("SAVE_MIGRATION", "이전 저장 파일을 옮기지 못했습니다.", error)
	return true


func get_slot_info(slot: int) -> Dictionary:
	var info := {"has_save": false, "valid": true, "saved_at": "", "money": 0.0}
	var path := get_slot_path(slot)
	if path.is_empty() or not FileAccess.file_exists(path):
		return info
	var config := ConfigFile.new()
	if config.load(path) != OK or not _valid_header(config, slot):
		info.valid = false
		return info
	if not config.has_section_key("progress", "state"):
		return info
	info.has_save = true
	var state: Variant = config.get_value("progress", "state")
	info.valid = _validate_progress(state)
	if info.valid:
		info.saved_at = config.get_value("slot", "saved_at", "")
		info.money = state.economy.money
	return info


func save_slot(slot: int, automatic: bool = false) -> bool:
	if not initialized or slot < AUTO_SLOT or slot > SLOT_COUNT:
		return false
	# Autosave is separate from the ten manual slots.
	if (slot == AUTO_SLOT) != automatic:
		return false
	var state := _capture_progress()
	if not _validate_progress(state):
		ErrorManager.report_error("SAVE_STATE", "현재 진행 데이터가 올바르지 않아 저장하지 못했습니다.", "SaveManager")
		return false
	var config := _new_config(slot)
	config.set_value("slot", "saved_at", Time.get_datetime_string_from_system(false, true))
	config.set_value("progress", "state", state)
	if not _write_config(slot, config):
		return false
	slots_changed.emit()
	return true


func reset_slot(slot: int) -> bool:
	if not initialized or slot < AUTO_SLOT or slot > SLOT_COUNT:
		return false
	# Empty only the chosen save; resetting must not create a recovery copy.
	if not _write_config(slot, _new_config(slot), false):
		return false
	slots_changed.emit()
	return true


func load_slot(slot: int) -> bool:
	if not initialized or slot < AUTO_SLOT or slot > SLOT_COUNT:
		return false
	# Empty slots start a new game without writing over any saved progress.
	var state: Variant = _defaults
	var path := get_slot_path(slot)
	if FileAccess.file_exists(path):
		var config := ConfigFile.new()
		var error := config.load(path)
		if error != OK:
			return _file_error("SAVE_READ", "%s을 불러올 수 없습니다." % get_slot_name(slot), error)
		if not _valid_header(config, slot):
			return _invalid_save(slot)
		state = config.get_value("progress", "state", _defaults)
	# Validate the complete snapshot before changing any live progress.
	if not _validate_progress(state):
		return _invalid_save(slot)
	_restore_progress(state)
	progress_loaded.emit(slot)
	return true


func _new_config(slot: int) -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("slot", "version", SAVE_VERSION)
	config.set_value("slot", "number", slot)
	config.set_value("slot", "saved_at", "")
	return config


func _valid_header(config: ConfigFile, slot: int, version: int = SAVE_VERSION) -> bool:
	return config.get_value("slot", "version", -1) == version \
		and config.get_value("slot", "number", -1) == slot \
		and config.get_value("slot", "saved_at", "") is String


func _write_config(slot: int, config: ConfigFile, preserve_invalid: bool = true) -> bool:
	var path := get_slot_path(slot)
	var temporary_path := path + ".tmp"
	var error := config.save(temporary_path)
	if error == OK and slot == AUTO_SLOT and _preserve_invalid_autosave and preserve_invalid:
		# Retain a damaged startup save for recovery before the new session replaces it.
		error = DirAccess.copy_absolute(path, path + ".invalid")
	if error == OK:
		# Replace only after the complete new file has been written and closed.
		error = DirAccess.rename_absolute(temporary_path, path)
	if error != OK:
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(temporary_path)
		return _file_error("SAVE_WRITE", "%s을 저장하지 못했습니다. 이전 저장은 유지됩니다." % get_slot_name(slot), error)
	if slot == AUTO_SLOT:
		_preserve_invalid_autosave = false
	return true


func _create_initial_progress() -> Dictionary:
	# Define a fresh game independently of the currently running session.
	var button_states: Dictionary = {}
	for button in ButtonManager.buttons:
		if button != null:
			button_states[button.id] = {"bought": false, "permanent_bought": false}
	var source_states: Dictionary = {}
	for source in IncomeManager.sources:
		if source != null:
			source_states[source.id] = {
				"active": false,
				"level": 1,
				"multiplier": source.multiplier,
				"speed_multiplier": 1.0,
				"time_remaining": 0.0,
				"pending_payout": 0.0,
			}
	return {
		"economy": {
			"money": 0.0,
			"global_multiplier": 1.0,
			"global_time_multiplier": 1.0,
			"developer_income_multiplier": 1.0,
			"developer_time_multiplier": 1.0,
		},
		"prestige": {"total_jjam": 0, "current_jjam": 0},
		"buttons": button_states,
		"sources": source_states,
	}


func _capture_progress() -> Dictionary:
	var button_states: Dictionary = {}
	for button in ButtonManager.buttons:
		if button != null:
			button_states[button.id] = {"bought": button.bought, "permanent_bought": button.permanent_bought}
	var source_states: Dictionary = {}
	for source in IncomeManager.sources:
		if source != null:
			source_states[source.id] = {
				"active": IncomeManager.source_active.get(source.id, false),
				"level": IncomeManager.source_levels.get(source.id, 1),
				"multiplier": IncomeManager.source_multipliers.get(source.id, source.multiplier),
				"speed_multiplier": IncomeManager.source_speed_multipliers.get(source.id, 1.0),
				"time_remaining": IncomeManager.source_time_remaining.get(source.id, 0.0),
				"pending_payout": IncomeManager.source_pending_payouts.get(source.id, 0.0),
			}
	return {
		"economy": {
			"money": EconomyManager.money,
			"global_multiplier": EconomyManager.global_multiplier,
			"global_time_multiplier": EconomyManager.global_time_multiplier,
			"developer_income_multiplier": EconomyManager.developer_income_multiplier,
			"developer_time_multiplier": EconomyManager.developer_time_multiplier,
		},
		"prestige": {"total_jjam": PrestigeManager.total_jjam, "current_jjam": PrestigeManager.current_jjam},
		"buttons": button_states,
		"sources": source_states,
	}


func _validate_progress(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var state: Dictionary = value
	for key in ["economy", "prestige", "buttons", "sources"]:
		if not state.get(key) is Dictionary:
			return false
	var economy: Dictionary = state.economy
	for key in ["money", "global_multiplier", "developer_income_multiplier"]:
		if not _valid_number(economy.get(key)):
			return false
	for key in ["global_time_multiplier", "developer_time_multiplier"]:
		if not _valid_number(economy.get(key), true):
			return false
	if not _valid_number(economy.global_multiplier * economy.developer_income_multiplier) \
		or not _valid_number(economy.global_time_multiplier * economy.developer_time_multiplier, true):
		return false
	for key in ["total_jjam", "current_jjam"]:
		if not state.prestige.get(key) is int or state.prestige[key] < 0:
			return false
	for id in state.buttons:
		var button: Variant = state.buttons[id]
		if not id is String or not button is Dictionary:
			return false
		if not button.get("bought") is bool or not button.get("permanent_bought") is bool:
			return false
	for id in state.sources:
		var source: Variant = state.sources[id]
		if not id is String or not source is Dictionary:
			return false
		if not source.get("active") is bool or not source.get("level") is int or source.level < 1:
			return false
		for key in ["multiplier", "speed_multiplier"]:
			if not _valid_number(source.get(key), true):
				return false
		for key in ["time_remaining", "pending_payout"]:
			if not _valid_number(source.get(key)):
				return false
		# Reject impossible levels before the cumulative-income calculation can loop.
		if not IncomeManager.source_active.has(id):
			continue # Removed content can remain in older saves.
		var definition := IncomeManager.get_source(id)
		if source.level > 1 and not is_finite(IncomeManager._get_upgrade_cost_at_level(definition, source.level - 1)):
			return false
		var production_time: float = definition.base_time * definition.time_multiplier / source.speed_multiplier / economy.global_time_multiplier / economy.developer_time_multiplier
		if not _valid_number(production_time, true):
			return false
		if not _valid_number(source.multiplier * economy.global_multiplier * economy.developer_income_multiplier):
			return false
	return true


func _valid_number(value: Variant, positive: bool = false) -> bool:
	return (value is float or value is int) and is_finite(float(value)) \
		and (float(value) > 0.0 if positive else float(value) >= 0.0)


func _restore_progress(state: Dictionary) -> void:
	var economy: Dictionary = state.economy
	EconomyManager.money = economy.money
	EconomyManager.global_multiplier = economy.global_multiplier
	EconomyManager.global_time_multiplier = economy.global_time_multiplier
	EconomyManager.developer_income_multiplier = economy.developer_income_multiplier
	EconomyManager.developer_time_multiplier = economy.developer_time_multiplier
	PrestigeManager.total_jjam = state.prestige.total_jjam
	PrestigeManager.current_jjam = state.prestige.current_jjam
	for button in ButtonManager.buttons:
		if button != null:
			var saved: Dictionary = state.buttons.get(button.id, _defaults.buttons[button.id])
			button.bought = saved.bought
			button.permanent_bought = saved.permanent_bought
	IncomeManager.source_upgrade_income_cache.clear()
	for source in IncomeManager.sources:
		if source == null:
			continue
		var saved: Dictionary = state.sources.get(source.id, _defaults.sources[source.id])
		IncomeManager.source_active[source.id] = saved.active
		IncomeManager.source_levels[source.id] = saved.level
		IncomeManager.source_multipliers[source.id] = saved.multiplier
		IncomeManager.source_speed_multipliers[source.id] = saved.speed_multiplier
		IncomeManager.source_time_remaining[source.id] = saved.time_remaining
		IncomeManager.source_pending_payouts[source.id] = saved.pending_payout
		IncomeManager.source_timer_display_keys[source.id] = IncomeManager._get_timer_display_key(saved.time_remaining)
	# Notify only after all managers agree. Effects are already saved, so do not replay purchases.
	ButtonManager.update_button_states(true)
	EconomyManager.money_changed.emit(EconomyManager.money)
	EconomyManager.multiplier_changed.emit()
	PrestigeManager.prestige_changed.emit()
	for source in IncomeManager.sources:
		if source != null:
			IncomeManager.source_activation_changed.emit(source.id, IncomeManager.source_active[source.id])
			IncomeManager.source_level_changed.emit(source.id, IncomeManager.source_levels[source.id])
			IncomeManager.source_speed_multiplier_changed.emit(source.id)
			IncomeManager.source_multiplier_changed.emit(source.id)
			IncomeManager.source_timer_changed.emit(source.id, IncomeManager.source_time_remaining[source.id])
	IncomeManager.income_changed.emit()


func _invalid_save(slot: int) -> bool:
	ErrorManager.report_error("SAVE_INVALID", "%s의 저장 파일이 손상되었거나 지원하지 않는 버전입니다. 현재 진행은 유지됩니다." % get_slot_name(slot), get_slot_path(slot))
	return false


func _file_error(code: String, message: String, error: Error) -> bool:
	ErrorManager.report_error(code, message + "\n저장 위치: " + save_directory + "\n오류: " + error_string(error), "SaveManager")
	return false


func _notification(what: int) -> void:
	if not initialized:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if save_slot(AUTO_SLOT, true):
			_saved_on_quit = true
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		save_slot(AUTO_SLOT, true)


func _exit_tree() -> void:
	# Also cover in-game SceneTree.quit(), which does not send a close notification.
	if initialized and not _saved_on_quit:
		save_slot(AUTO_SLOT, true)
