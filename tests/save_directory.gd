extends Node

const BIG = preload("res://scripts/BigNumber.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	if OS.get_cmdline_user_args().has("--expect-mobile"):
		_check(OS.has_feature("mobile"), "This exported regression test must exercise the mobile feature tag.")
	var default_directory := SaveManager.get_default_save_directory()
	if OS.has_feature("mobile"):
		_check(default_directory == ProjectSettings.globalize_path("user://saves"), "Mobile debug and release builds must use writable app storage.")
	elif OS.is_debug_build():
		_check(default_directory == ProjectSettings.globalize_path("res://saves"), "Desktop debug saves must stay in the project folder.")
	else:
		_check(default_directory == OS.get_executable_path().get_base_dir().path_join("saves"), "Desktop release saves must stay next to the executable.")
	# Never use the player's saves: exercise the same user:// storage with a unique folder.
	var directory := ProjectSettings.globalize_path("user://save_directory_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if not SaveManager.initialize(directory):
		_check(false, "Initialize the writable user data directory.")
	else:
		_check(FileAccess.file_exists(SaveManager.get_slot_path(0)), "Initialization must create the autosave slot.")
		_check(FileAccess.file_exists(SaveManager.get_slot_path(10)), "Initialization must create all ten manual slots.")
		EconomyManager.money = 12345.0
		_check(SaveManager.save_slot(1), "Save a manual slot in user data storage.")
		EconomyManager.money = 67890.0
		_check(SaveManager.save_slot(0, true), "Save the autosave slot in user data storage.")
		EconomyManager.money = 0.0
		_check(SaveManager.load_slot(1), "Read the manual slot back from disk.")
		_check(BIG.compare(EconomyManager.money, 12345.0) == 0, "Restore the manual slot balance.")
		SaveManager.initialized = false
		EconomyManager.money = 0.0
		_check(SaveManager.initialize(directory), "Reopen existing user data storage.")
		_check(BIG.compare(EconomyManager.money, 67890.0) == 0, "Reinitialization must restore the saved autosave balance.")
	SaveManager.initialized = false
	# The flat, uniquely named directory contains only files created by this test.
	for file in DirAccess.get_files_at(directory):
		_check(DirAccess.remove_absolute(directory.path_join(file)) == OK, "Remove the isolated test save.")
	_check(DirAccess.remove_absolute(directory) == OK, "Remove the isolated test directory.")
	_check(ErrorManager.get_errors().is_empty(), "Saving in user data storage must not report errors.")
	if _failures.is_empty():
		print("PASS: default save location, user data manual slots, autosave and reopen persistence")
	get_tree().quit(0 if _failures.is_empty() else 1)
