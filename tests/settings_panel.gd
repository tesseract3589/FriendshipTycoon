extends Node

const SETTINGS_SCENE = preload("res://ui/settings_panel.tscn")
const SAVE_SCENE = preload("res://ui/save_slots_panel.tscn")
const FIXTURES = preload("res://tests/TestFixtures.gd")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	FIXTURES.prepare_viewport(self)
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	var directory := ProjectSettings.globalize_path("res://.godot/settings_test_%d" % Time.get_ticks_usec())
	if not SaveManager.initialize(directory):
		get_tree().quit(1)
		return
	for definition in EventManager.events:
		definition.enabled = definition.id == EventManager.PHONE_DM_ID
	var hud := CanvasLayer.new()
	add_child(hud)
	var saves := SAVE_SCENE.instantiate()
	var settings := SETTINGS_SCENE.instantiate()
	hud.add_child(saves)
	hud.add_child(settings)
	await get_tree().process_frame
	settings.open_button.pressed.emit()
	await get_tree().process_frame
	_check(settings.overlay.visible and not settings.dm_row.visible, "Locked DM preferences must stay hidden.")
	_check(saves.open_button.get_global_rect().end.x < settings.open_button.get_global_rect().position.x, "Save and settings buttons must not overlap.")
	settings._sliders.master_volume.value = 50.0
	settings._sliders.bgm_volume.value = 40.0
	settings._sliders.se_volume.value = 60.0
	_check(is_equal_approx(SoundManager._bgm_player.volume_db, linear_to_db(0.2)), "Master and BGM volume must multiply.")
	# Silent looping fixture keeps a real effect player alive without adding game BGM.
	var stream := AudioStreamWAV.new()
	stream.data = PackedByteArray([0, 0, 0, 0])
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 4
	SoundManager.play_se(stream, 0.5)
	var player: AudioStreamPlayer = SoundManager._active_se_players.back()
	_check(is_equal_approx(player.volume_db, linear_to_db(0.15)), "New effects must combine master, SE and local volume.")
	settings._sliders.master_volume.value = 0.0
	_check(player.volume_db == SoundManager.SILENT_VOLUME_DB and SoundManager._bgm_player.volume_db == SoundManager.SILENT_VOLUME_DB, "Zero master must mute both channels immediately.")
	settings._sliders.master_volume.value = 50.0
	_check(is_equal_approx(player.volume_db, linear_to_db(0.15)), "Existing effect players must update immediately.")
	player.stop()
	SoundManager._on_se_finished(player)
	var bumin := ButtonManager.get_button("bumin")
	bumin.bought = true
	ButtonManager.button_purchased.emit(bumin)
	EventManager.set_phone_dm_ui_available(true)
	await get_tree().process_frame
	_check(settings.dm_row.visible, "DM preference must appear immediately on unlock.")
	EventManager._cooldowns[EventManager.PHONE_DM_ID] = 42.5
	settings.dm_switch.button_pressed = false
	var paused_save := ConfigFile.new()
	_check(paused_save.load(SaveManager.get_slot_path(SaveManager.AUTO_SLOT)) == OK, "Blocking DMs must save the paused timer immediately.")
	var paused_state: Dictionary = paused_save.get_value("progress", "state", {})
	_check(paused_state.get("events", {}).get(EventManager.PHONE_DM_ID, {}).get("cooldown_remaining", -1.0) == 42.5, "The automatic save must capture the exact paused cooldown.")
	EventManager._process(12.0)
	_check(EventManager.get_cooldown_remaining(EventManager.PHONE_DM_ID) == 42.5, "Disabled DM reception must freeze cooldown.")
	_check(not EventManager.start_event(EventManager.PHONE_DM_ID, false, true), "Disabled DM reception must block even forced starts.")
	await get_tree().create_timer(0.06).timeout
	_check(settings.dm_switch._position > 0.0 and settings.dm_switch._position < 1.0, "The thumb must animate through an intermediate position.")
	await get_tree().create_timer(0.25).timeout
	_check(is_zero_approx(settings.dm_switch._position), "The off thumb must finish at the left endpoint.")
	_check(SaveManager.save_slot(1), "Preferences and paused cooldown must be saveable.")
	SettingsManager.master_volume = 1.0
	SettingsManager.receive_busik_dm = true
	SettingsManager.initialize(directory.path_join("settings.cfg"))
	_check(SettingsManager.master_volume == 0.5 and SettingsManager.bgm_volume == 0.4 and SettingsManager.se_volume == 0.6 and not SettingsManager.receive_busik_dm, "All preferences must survive a config reload.")
	EventManager._cooldowns[EventManager.PHONE_DM_ID] = 0.0
	_check(SaveManager.load_slot(1), "Progress must load with global preferences intact.")
	EventManager._process(10.0)
	_check(EventManager.get_cooldown_remaining(EventManager.PHONE_DM_ID) == 42.5, "Saved paused cooldown must remain frozen after reload.")
	settings.dm_switch.button_pressed = true
	EventManager._process(2.0)
	_check(EventManager.get_cooldown_remaining(EventManager.PHONE_DM_ID) == 40.5, "Re-enabling must resume the remaining cooldown.")
	_check(EventManager.start_event(EventManager.PHONE_DM_ID, false, true), "Re-enabled unlocked DMs must start.")
	settings.dm_switch.button_pressed = false
	_check(EventManager.is_event_active(EventManager.PHONE_DM_ID), "Disabling reception must preserve an already active conversation.")
	for step in range(20):
		EventManager._process(100.0)
		if EventManager._waiting_for_choice:
			EventManager.choose_phone_dm(EventManager.Choice.REJECT)
	_check(not EventManager.is_event_active(EventManager.PHONE_DM_ID) and EventManager.get_event_result(EventManager.PHONE_DM_ID) == "rejected", "An active conversation must still run to completion while blocked.")
	var cooldown := EventManager.get_cooldown_remaining(EventManager.PHONE_DM_ID)
	EventManager._process(20.0)
	_check(cooldown > 0.0 and EventManager.get_cooldown_remaining(EventManager.PHONE_DM_ID) == cooldown, "A finished blocked DM must retain its full cooldown.")
	settings.overlay.hide()
	settings.open_button.pressed.emit()
	saves.open_button.pressed.emit()
	_check(saves.overlay.visible and not settings.overlay.visible, "Opening save must close settings.")
	settings.open_button.pressed.emit()
	_check(settings.overlay.visible and not saves.overlay.visible, "Opening settings must close save.")
	await get_tree().process_frame
	for viewport_size: Vector2 in [Vector2(360, 480), Vector2(1152, 648), Vector2(1920, 1080)]:
		settings.size = viewport_size
		settings._fit()
		_check(settings.panel.position.x >= 15.0 and settings.panel.position.y >= 15.0 and settings.panel.position + settings.panel.size * settings.panel.scale <= viewport_size - Vector2(15, 15), "Settings must fit the available viewport.")
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings.dm_switch.button_pressed = true
	await get_tree().create_timer(0.3).timeout
	if "--settings-preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/settings_preview.png")
	if _failures.is_empty():
		print("PASS: Settings, audio, animated switch and paused DM cooldown")
	get_tree().quit(0 if _failures.is_empty() else 1)
