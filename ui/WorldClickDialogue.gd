class_name WorldClickDialogue
extends Node2D

const SPEECH_BUBBLE_WIDTH: float = 240.0
const SPEECH_BUBBLE_MIN_HEIGHT: float = 48.0

@onready var click_area: Area2D = $ClickArea
@onready var collision_shape: CollisionShape2D = $ClickArea/CollisionShape2D
@onready var bubble_anchor: Node2D = $SpeechBubbleAnchor
@onready var speech_bubble: PanelContainer = $SpeechBubbleAnchor/SpeechBubble
@onready var speech_label: Label = $SpeechBubbleAnchor/SpeechBubble/SpeechMargin/SpeechLabel
@onready var speech_tail: Polygon2D = $SpeechBubbleAnchor/SpeechTail
@onready var speech_tail_outline: Line2D = $SpeechBubbleAnchor/SpeechTailOutline
@onready var speech_timer: Timer = $SpeechTimer

var button_data: ButtonData
var world_position: Vector2 = Vector2.ZERO
var world_scale: Vector2 = Vector2.ONE
var world_texture: Texture2D
var _next_dialogue_index: int = 0


func setup(data: ButtonData, layout_sprite: Sprite2D) -> void:
	button_data = data
	world_position = layout_sprite.position
	world_scale = layout_sprite.scale
	world_texture = layout_sprite.texture


func _ready() -> void:
	if button_data == null or world_texture == null:
		set_process_mode(Node.PROCESS_MODE_DISABLED)
		return
	click_area.position = world_position
	click_area.scale = world_scale
	var hit_shape := RectangleShape2D.new()
	hit_shape.size = world_texture.get_size()
	collision_shape.shape = hit_shape
	bubble_anchor.position = world_position
	click_area.input_event.connect(_on_click_area_input_event)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	speech_timer.timeout.connect(_on_speech_timer_timeout)
	_update_click_area()


func _update_click_area() -> void:
	var is_purchased := button_data != null and button_data.bought
	click_area.monitoring = is_purchased
	click_area.input_pickable = is_purchased


func _on_button_purchased(purchased_data: ButtonData) -> void:
	if button_data != null and purchased_data.id == button_data.id:
		_update_click_area()


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if not button_data.bought or not (event is InputEventMouseButton):
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return
	_show_next_dialogue()
	get_viewport().set_input_as_handled()


func _show_next_dialogue() -> void:
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
