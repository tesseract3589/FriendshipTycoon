extends Node

## Device preferences live beside saves, independently of individual progress slots.
signal settings_changed()

const DEFAULTS := {"master_volume": 1.0, "bgm_volume": 1.0, "se_volume": 0.3, "receive_busik_dm": true}

var master_volume: float = 1.0
var bgm_volume: float = 1.0
var se_volume: float = 0.3
var receive_busik_dm: bool = true
var _path: String = ""


func initialize(path: String) -> void:
	_path = path
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("설정 파일을 읽지 못해 기본값을 사용합니다: " + error_string(error))
	for key: String in DEFAULTS:
		var value: Variant = config.get_value("settings", key, DEFAULTS[key]) if error == OK else DEFAULTS[key]
		if DEFAULTS[key] is bool:
			set(key, value if value is bool else DEFAULTS[key])
		else:
			set(key, clampf(float(value), 0.0, 1.0) if (value is float or value is int) and is_finite(float(value)) else DEFAULTS[key])
	settings_changed.emit()


func set_volume(channel: String, value: float) -> void:
	if channel not in ["master_volume", "bgm_volume", "se_volume"] or not is_finite(value):
		return
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(get(channel), value):
		return
	set(channel, value)
	_commit()


func set_receive_busik_dm(enabled: bool) -> void:
	if receive_busik_dm == enabled:
		return
	receive_busik_dm = enabled
	_commit()
	# Persist the paused timer immediately with its matching progress snapshot.
	if not enabled and SaveManager.initialized:
		SaveManager.save_slot(SaveManager.AUTO_SLOT, true)


func _commit() -> void:
	settings_changed.emit()
	if _path.is_empty():
		return
	var config := ConfigFile.new()
	for key: String in DEFAULTS:
		config.set_value("settings", key, get(key))
	var error := config.save(_path)
	if error != OK:
		ErrorManager.report_error("SETTINGS_SAVE", "설정을 저장하지 못했습니다.\n" + error_string(error), _path)
