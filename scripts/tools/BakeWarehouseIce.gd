extends SceneTree
## Run headlessly with --script res://scripts/tools/BakeWarehouseIce.gd.
## Bake only the moving doorway; the original building stays a static sprite.

const DIRECTORY := "res://assets/sprites/Bumin/Warehouse/"
const OPENING := Rect2i(328, 324, 323, 281)
const SPLIT_X := 490
const STEPS := 24
const COLUMNS := 5


func _initialize() -> void:
	var original := Image.load_from_file(DIRECTORY + "warehouse_ice.png")
	var box := Image.load_from_file(DIRECTORY + "box_frozen.png")
	var interior_path := DIRECTORY + "warehouse_ice_interior.png"
	var interior: Image
	if FileAccess.file_exists(interior_path):
		interior = Image.load_from_file(interior_path)
	else:
		var generated := Image.load_from_file("res://.godot/warehouse_open_generated.png")
		interior = generated.get_region(Rect2i(530, 525, 524, 453))
		interior.resize(OPENING.size.x, OPENING.size.y, Image.INTERPOLATE_LANCZOS)
		interior.save_png(interior_path)
	for image in [original, box, interior]:
		image.convert(Image.FORMAT_RGBA8)
	# Reuse the supplied box without changing its lettering or drawing style.
	box.resize(116, 92, Image.INTERPOLATE_LANCZOS)
	var contents := interior.duplicate() as Image
	for origin in [Vector2i(102, 78), Vector2i(38, 166), Vector2i(166, 166)]:
		contents.blend_rect(box, Rect2i(Vector2i.ZERO, box.get_size()), origin)
	var sheet := Image.create(OPENING.size.x * COLUMNS, OPENING.size.y * 5, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for index in range(STEPS + 1):
		var phase := float(index) / STEPS
		# Smooth acceleration and braking give the flat sliding doors weight.
		var eased := phase * phase * (3.0 - 2.0 * phase)
		var travel := roundi(eased * 162.0)
		var doorway := contents.duplicate() as Image
		var left_width := SPLIT_X - OPENING.position.x - travel
		if left_width > 0:
			doorway.blit_rect(original, Rect2i(OPENING.position.x + travel, OPENING.position.y, left_width, OPENING.size.y), Vector2i.ZERO)
		var right_width := OPENING.end.x - SPLIT_X - travel
		if right_width > 0:
			doorway.blit_rect(original, Rect2i(SPLIT_X, OPENING.position.y, right_width, OPENING.size.y), Vector2i(SPLIT_X - OPENING.position.x + travel, 0))
		sheet.blit_rect(doorway, Rect2i(Vector2i.ZERO, OPENING.size), Vector2i(index % COLUMNS, index / COLUMNS) * OPENING.size)
	assert(sheet.save_png(DIRECTORY + "warehouse_ice_doors.png") == OK)
	_write_frames()
	# Full-canvas contact sheet for inspecting closed, half-open and open states.
	var preview := Image.create(original.get_width() * 3, original.get_height(), false, Image.FORMAT_RGBA8)
	preview.fill(Color.TRANSPARENT)
	for column in range(3):
		var index := column * 12
		var origin := Vector2i(column * original.get_width(), 0)
		preview.blit_rect(original, Rect2i(Vector2i.ZERO, original.get_size()), origin)
		preview.blit_rect(sheet, Rect2i(Vector2i(index % COLUMNS, index / COLUMNS) * OPENING.size, OPENING.size), origin + OPENING.position)
	preview.save_png("res://.godot/warehouse_ice_preview.png")
	print("Baked 25 sliding-door poses; original facade and ice pixels preserved.")
	quit()


func _write_frames() -> void:
	var text := "[gd_resource type=\"SpriteFrames\" load_steps=27 format=3]\n\n"
	text += "[ext_resource type=\"Texture2D\" path=\"" + DIRECTORY + "warehouse_ice_doors.png\" id=\"1_doors\"]\n\n"
	for index in range(STEPS + 1):
		text += "[sub_resource type=\"AtlasTexture\" id=\"Door_%02d\"]\n" % index
		text += "atlas = ExtResource(\"1_doors\")\n"
		text += "region = Rect2(%d, %d, 323, 281)\n" % [(index % COLUMNS) * 323, (index / COLUMNS) * 281]
		# Virtual full-size canvas retains the source sprite's origin and bounds.
		text += "margin = Rect2(328, 324, 656, 330)\nfilter_clip = true\n\n"
	text += "[resource]\nanimations = [{\n\"frames\": ["
	var sequence: Array[int] = []
	for index in range(STEPS + 1):
		sequence.append(index)
	for index in range(STEPS - 1, 0, -1):
		sequence.append(index)
	for slot in range(sequence.size()):
		var index := sequence[slot]
		if slot > 0:
			text += ", "
		text += "{\n\"duration\": %.1f,\n\"texture\": SubResource(\"Door_%02d\")\n}" % [32.0 if index == 0 or index == STEPS else 1.0, index]
	text += "],\n\"loop\": true,\n\"name\": &\"default\",\n\"speed\": 20.0\n}]\n"
	var file := FileAccess.open("res://data/animations/warehouse_ice_frames.tres", FileAccess.WRITE)
	file.store_string(text)
