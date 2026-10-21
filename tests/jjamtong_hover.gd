extends Node

const WORLD_LAYOUT: PackedScene = preload("res://scenes/world_layout.tscn")
const BUTTON_LAYOUT: PackedScene = preload("res://scenes/button_layout.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _step(sprite: HoverPeekSprite) -> void:
	sprite._process(1.0 / 12.0 + 0.00001)


func _run() -> void:
	# Exercise the real layout/clone/input wiring without initializing player saves.
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	var world := WORLD_LAYOUT.instantiate() as Node2D
	var buttons := BUTTON_LAYOUT.instantiate()
	add_child(world)
	add_child(buttons)
	var layout := world.get_node("Restaurant/jjamtong") as Node2D
	var source_sprite := layout.get_node("bin") as HoverPeekSprite
	var area := source_sprite.get_node("HoverArea") as Area2D
	var original_area_transform := area.global_transform
	area.reparent(self, true)
	world.hide()
	var second_area := Area2D.new()
	add_child(second_area)
	var data := ButtonManager.get_button("jjamtong")
	data.bought = false
	data.show_purchased_tooltip = false
	var view := WorldPurchaseButton.new()
	view.setup(data, layout, [area, second_area], buttons.get_node("Buttons/Restaurant/jjamtong"))
	add_child(view)
	var sprite := view.purchased_visuals[0] as HoverPeekSprite
	_check(sprite != null, "The purchased bin must retain its hover animation script.")
	_check(sprite.peek_frames.get_frame_count(&"open") == 3, "Opening needs two intermediate images and one final image.")
	_check(not sprite.is_processing() and sprite.peek_frame == 0, "The unpurchased bin must start closed and idle.")
	_check(not area.input_pickable, "The unpurchased bin must not receive hover input.")
	area.mouse_entered.emit()
	_check(not sprite.is_processing(), "Stale hover events must not animate an unpurchased bin.")
	data.bought = true
	ButtonManager.button_state_changed.emit(data)
	_check(area.input_pickable, "Animation must enable hover input even with tooltips disabled.")
	_check(area.global_transform.is_equal_approx(original_area_transform), "Animation must preserve the original hover area position and scale.")
	area.mouse_entered.emit()
	_check(sprite.is_processing(), "Entering the real hover area must start opening.")
	_step(sprite)
	_check(sprite.peek_frame == 1, "The first opening step must show the ears.")
	view._refresh()
	_step(sprite)
	_check(sprite.peek_frame == 2, "Finance/UI refreshes must preserve opening progress.")
	area.mouse_exited.emit()
	_step(sprite)
	_check(sprite.peek_frame == 1, "Leaving during opening must reverse from the current frame.")
	area.mouse_entered.emit()
	_step(sprite)
	_check(sprite.peek_frame == 2, "Reentering during closing must reverse without jumping closed.")
	_step(sprite)
	_check(sprite.peek_frame == 3 and not sprite.is_processing(), "The fully open cat must hold without looping.")
	second_area.mouse_entered.emit()
	area.mouse_exited.emit()
	_check(not sprite.is_processing(), "Moving between hover shapes must keep the lid open.")
	second_area.mouse_exited.emit()
	for expected in [2, 1, 0]:
		_step(sprite)
		_check(sprite.peek_frame == expected, "Closing must replay the same three steps in reverse.")
	_check(not sprite.is_processing(), "A fully closed bin must stop updating.")
	area.mouse_entered.emit()
	area.mouse_exited.emit()
	_check(sprite.peek_frame == 0 and not sprite.is_processing(), "Exiting before the first frame must leave the lid closed.")
	area.mouse_entered.emit()
	_step(sprite)
	data.bought = false
	ButtonManager.button_state_changed.emit(data)
	_check(sprite.peek_frame == 0 and not sprite.is_processing(), "Resetting purchase progress must immediately close and stop the animation.")
	_check(not area.input_pickable, "Resetting purchases must disable the old hover area.")
	if OS.get_cmdline_user_args().has("--render-preview"):
		await _render_preview(source_sprite)
	view.queue_free()
	world.queue_free()
	buttons.queue_free()
	area.queue_free()
	second_area.queue_free()
	await get_tree().process_frame
	_check(ErrorManager.get_errors().is_empty(), "The hover animation must not report game errors.")
	if _failures.is_empty():
		print("PASS: jjamtong hover wiring, three opening steps, reverse closing, rapid reversal, tooltip independence and purchase reset")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _render_preview(source: HoverPeekSprite) -> void:
	var preview := SubViewport.new()
	preview.size = Vector2i(1440, 720)
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(preview)
	var background := ColorRect.new()
	background.color = Color("b6d9ed")
	background.size = Vector2(preview.size)
	preview.add_child(background)
	var captions := ["닫힘", "중간 1 · 귀", "중간 2 · 눈", "열림 · 빼꼼"]
	for phase in range(4):
		var sprite := source.duplicate() as HoverPeekSprite
		sprite.show()
		sprite.position = Vector2(180.0 + 360.0 * phase, 445.0)
		sprite.scale = Vector2.ONE * 0.6
		preview.add_child(sprite)
		sprite.peek_frame = phase
		sprite.set_process(false)
		sprite.queue_redraw()
		var label := Label.new()
		label.text = captions[phase]
		label.position = Vector2(360.0 * phase, 660.0)
		label.size.x = 360.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color("17212b"))
		label.add_theme_font_size_override("font_size", 24)
		preview.add_child(label)
	await RenderingServer.frame_post_draw
	var result := preview.get_texture().get_image().save_png("res://.godot/jjamtong_hover_preview.png")
	_check(result == OK, "The engine must render the four-state animation preview.")
	preview.queue_free()
