extends CenterContainer

@export_multiline var desktop_text: String = "마우스 드래그/휠로 카메라 조정"
@export_multiline var mobile_text: String = "터치 및 드래그로 카메라 조정"
@export_range(0.0, 5.0, 0.1) var fade_duration: float = 1.5

@onready var tutorial_label: Label = $Label

var _fade_tween: Tween


func _ready() -> void:
	hide()
	EventManager.event_started.connect(_on_event_started)
	EventManager.event_finished.connect(_on_event_finished)
	EventManager.event_state_restored.connect(_on_event_state_restored)
	EventManager.set_camera_tutorial_ui_available(true)


func _exit_tree() -> void:
	EventManager.event_started.disconnect(_on_event_started)
	EventManager.event_finished.disconnect(_on_event_finished)
	EventManager.event_state_restored.disconnect(_on_event_state_restored)
	EventManager.set_camera_tutorial_ui_available(false)


func _on_event_started(event_data: GameEventData) -> void:
	if event_data.id != EventManager.CAMERA_TUTORIAL_ID:
		return
	_stop_fade()
	tutorial_label.text = mobile_text if OS.has_feature("mobile") else desktop_text
	modulate = Color.WHITE
	show()
	TooltipManager.hide_tooltip()


func _on_event_finished(event_id: String, result: String) -> void:
	if event_id != EventManager.CAMERA_TUTORIAL_ID:
		return
	_stop_fade()
	if result != "dismissed":
		hide()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	_fade_tween.tween_callback(hide)


func _stop_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()


func _on_event_state_restored() -> void:
	# A slot change can also occur after the event ended, while its text is fading.
	_stop_fade()
	hide()
