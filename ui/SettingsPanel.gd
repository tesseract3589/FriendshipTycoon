extends Control

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")

@onready var open_button: TextureButton = $OpenButton
@onready var overlay: Control = $Overlay
@onready var panel: PanelContainer = $Overlay/Panel
@onready var dm_row: HBoxContainer = $Overlay/Panel/Margin/VBox/DM
@onready var dm_switch: AnimatedSwitch = $Overlay/Panel/Margin/VBox/DM/Switch
@onready var close_button: TextureButton = $Overlay/Panel/Margin/VBox/Header/Close

var _sliders: Dictionary = {}
var _values: Dictionary = {}


func _ready() -> void:
	open_button.add_to_group("panel_top_obstacle")
	var settings_layer := CanvasLayer.new()
	settings_layer.name = "SettingsLayer"
	settings_layer.layer = RENDER_ORDER.ScreenLayer.SAVE
	add_child(settings_layer)
	overlay.reparent(settings_layer, false)
	RightPanelManager.register_panel(overlay)
	open_button.pressed.connect(_open)
	close_button.pressed.connect(overlay.hide)
	$SettingsLayer/Overlay/Backdrop.pressed.connect(overlay.hide)
	for channel: String in ["master_volume", "bgm_volume", "se_volume"]:
		var row := panel.get_node("Margin/VBox/" + channel)
		var slider := row.get_node("Slider") as HSlider
		_sliders[channel] = slider
		_values[channel] = row.get_node("Heading/Value")
		slider.value_changed.connect(_on_volume_changed.bind(channel))
	dm_switch.toggled.connect(SettingsManager.set_receive_busik_dm)
	SettingsManager.settings_changed.connect(_refresh)
	ButtonManager.button_purchased.connect(_refresh)
	EventManager.event_state_restored.connect(_refresh)
	PrestigeManager.prestige_changed.connect(_refresh)
	SaveManager.progress_loaded.connect(_refresh)
	resized.connect(_fit)
	panel.minimum_size_changed.connect(_fit.call_deferred)
	_refresh()


func _open() -> void:
	if EventManager.presentation_locked or PrestigeManager.transition_in_progress:
		return
	_refresh()
	RightPanelManager.toggle_panel(overlay)
	if overlay.visible:
		_fit()
		close_button.grab_focus()


func _refresh(_unused: Variant = null) -> void:
	for channel: String in _sliders:
		var value: float = SettingsManager.get(channel) * 100.0
		_sliders[channel].set_value_no_signal(value)
		_values[channel].text = "%d%%" % roundi(value)
	dm_row.visible = EventManager.is_event_unlocked(EventManager.PHONE_DM_ID)
	if dm_switch.button_pressed != SettingsManager.receive_busik_dm:
		dm_switch.set_value_no_signal(SettingsManager.receive_busik_dm)
	dm_switch.tooltip_text = "켜짐 · 새 연락을 받습니다" if SettingsManager.receive_busik_dm else "꺼짐 · 새 연락을 받지 않습니다"
	_fit.call_deferred()


func _on_volume_changed(value: float, channel: String) -> void:
	SettingsManager.set_volume(channel, value / 100.0)


func _fit() -> void:
	if not is_instance_valid(panel):
		return
	panel.size = Vector2(540.0, 0.0)
	var available := (size - Vector2(32, 32)).max(Vector2.ONE)
	var fit := minf(1.0, minf(available.x / panel.size.x, available.y / panel.size.y))
	panel.scale = Vector2.ONE * fit
	panel.position = (size - panel.size * fit) * 0.5


func _unhandled_key_input(event: InputEvent) -> void:
	if overlay.visible and event.is_action_pressed("ui_cancel"):
		overlay.hide()
		get_viewport().set_input_as_handled()
