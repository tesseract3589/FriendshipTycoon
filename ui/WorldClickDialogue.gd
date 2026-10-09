class_name WorldClickDialogue
extends Node2D

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const SPEECH_BUBBLE_WIDTH: float = 240.0
const SPEECH_BUBBLE_MIN_HEIGHT: float = 48.0

@onready var bubble_anchor := ErrorManager.require_node(self, ^"SpeechBubbleAnchor", "Node2D") as Node2D
@onready var speech_bubble := ErrorManager.require_node(self, ^"SpeechBubbleAnchor/SpeechBubble", "PanelContainer") as PanelContainer
@onready var speech_label := ErrorManager.require_node(self, ^"SpeechBubbleAnchor/SpeechBubble/SpeechMargin/SpeechLabel", "Label") as Label
@onready var speech_tail := ErrorManager.require_node(self, ^"SpeechBubbleAnchor/SpeechTail", "Polygon2D") as Polygon2D
@onready var speech_tail_outline := ErrorManager.require_node(self, ^"SpeechBubbleAnchor/SpeechTailOutline", "Line2D") as Line2D
@onready var speech_timer := ErrorManager.require_node(self, ^"SpeechTimer", "Timer") as Timer

var button_data: ButtonData
var hover_areas: Array[Area2D] = []
var world_position: Vector2 = Vector2.ZERO
var world_scale: Vector2 = Vector2.ONE
var world_texture: Texture2D
var _next_dialogue_index: int = 0


func setup(data: ButtonData, layout_element: Node2D, object_hover_areas: Array[Area2D]) -> void:
	button_data = data
	hover_areas = object_hover_areas
	if not ErrorManager.validate_instance(layout_element, "WorldClickDialogue.setup"):
		return
	world_position = layout_element.global_position
	var layout_sprite := layout_element as Sprite2D
	if layout_sprite == null:
		var visuals := layout_element.find_children("*", "Sprite2D", true, false)
		if not visuals.is_empty():
			layout_sprite = visuals[0] as Sprite2D
	if layout_sprite != null:
		world_position = layout_sprite.global_position
		world_scale = layout_sprite.global_scale
		world_texture = layout_sprite.texture


func _ready() -> void:
	if not ErrorManager.initialize_component(self, [bubble_anchor, speech_bubble, speech_label, speech_tail, speech_tail_outline, speech_timer, button_data]):
		return
	if button_data == null or world_texture == null or hover_areas.is_empty():
		ErrorManager.report_error("INVALID_DIALOGUE_SETUP", "대사에 필요한 이미지나 클릭 영역이 없습니다.", "ButtonData:" + button_data.id)
		set_process_mode(Node.PROCESS_MODE_DISABLED)
		return
	bubble_anchor.global_position = world_position
	RENDER_ORDER.apply_world_layer(speech_bubble, RENDER_ORDER.WorldLayer.DESCRIPTION)
	RENDER_ORDER.apply_world_layer(speech_tail, RENDER_ORDER.WorldLayer.DESCRIPTION - 1)
	RENDER_ORDER.apply_world_layer(speech_tail_outline, RENDER_ORDER.WorldLayer.DESCRIPTION - 1)
	for area in hover_areas:
		if ErrorManager.validate_instance(area, "WorldClickDialogue:" + button_data.id + ".HoverArea"):
			area.input_event.connect(_on_hover_area_input_event)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	ButtonManager.button_state_changed.connect(_on_button_state_changed)
	speech_timer.timeout.connect(_on_speech_timer_timeout)
	_update_hover_area()


func _update_hover_area() -> void:
	var is_purchased := button_data != null and button_data.bought
	if not is_purchased:
		speech_timer.stop()
		_on_speech_timer_timeout()
		_next_dialogue_index = 0
	for area in hover_areas:
		if ErrorManager.validate_instance(area, "WorldClickDialogue:" + button_data.id + ".HoverArea"):
			area.input_pickable = is_purchased


func _on_button_purchased(purchased_data: ButtonData) -> void:
	if button_data != null and purchased_data.id == button_data.id:
		_update_hover_area()


func _on_button_state_changed(changed_data: ButtonData) -> void:
	if button_data != null and changed_data.id == button_data.id:
		_update_hover_area()


func _on_hover_area_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if not button_data.bought or not (event is InputEventMouseButton):
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return
	_show_next_dialogue()
	get_viewport().set_input_as_handled()


func _show_next_dialogue() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	var valid_dialogues := PackedStringArray()
	for dialogue in button_data.click_dialogues:
		if not dialogue.strip_edges().is_empty():
			valid_dialogues.append(dialogue)
	if valid_dialogues.is_empty():
		return
	speech_label.text = valid_dialogues[_next_dialogue_index % valid_dialogues.size()]
	_next_dialogue_index += 1
	speech_bubble.reset_size()
	speech_bubble.size = Vector2(SPEECH_BUBBLE_WIDTH, SPEECH_BUBBLE_MIN_HEIGHT)
	speech_bubble.position.x = -SPEECH_BUBBLE_WIDTH * 0.5
	speech_bubble.visible = true
	await get_tree().process_frame
	if not button_data.bought:
		return
	speech_bubble.size.y = maxf(
		speech_bubble.get_combined_minimum_size().y,
		SPEECH_BUBBLE_MIN_HEIGHT
	)
	var sprite_height := world_texture.get_size().y * absf(world_scale.y)
	speech_bubble.position = Vector2(
		-SPEECH_BUBBLE_WIDTH * 0.5,
		-sprite_height * 0.5 - speech_bubble.size.y - 14.0
	)
	var bubble_bottom := speech_bubble.position.y + speech_bubble.size.y
	var sprite_top := -sprite_height * 0.5
	var tail_points := PackedVector2Array([
		Vector2(-10.0, bubble_bottom - 3.0),
		Vector2(0.0, sprite_top - 4.0),
		Vector2(10.0, bubble_bottom - 3.0)
	])
	speech_tail.polygon = tail_points
	speech_tail_outline.points = tail_points
	speech_tail.visible = true
	speech_tail_outline.visible = true
	speech_timer.start()
	TooltipManager.hide_tooltip(button_data.id)


func _on_speech_timer_timeout() -> void:
	speech_bubble.visible = false
	speech_tail.visible = false
	speech_tail_outline.visible = false
