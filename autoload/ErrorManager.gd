extends CanvasLayer

## Central validation and presentation of recoverable game/data errors.
## Engine parse errors and missing preloads occur before these guards can run.
signal error_reported(error: Dictionary)

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")
const MAX_ERRORS: int = 100
const INT64_LIMIT: float = 9223372036854775808.0
const LIMIT_KEY: String = "ERROR_LIMIT|ErrorManager"

var _errors: Dictionary = {}
var _history: Array[String] = []
var _pending: Array[String] = []
var _current: String = ""
var _panel: PanelContainer
var _message: Label
var _details: Label
var _confirm: Button


func _ready() -> void:
	layer = RENDER_ORDER.ScreenLayer.ERROR
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_error_panel()
	get_viewport().size_changed.connect(_resize_panel)
	_show_next_error()


func report_error(code: String, message: String, context: String = "") -> void:
	var key := code + "|" + context
	if _errors.has(key):
		_errors[key]["occurrences"] += 1
		return
	if _errors.size() >= MAX_ERRORS - 1 and key != LIMIT_KEY:
		report_error("ERROR_LIMIT", "오류 이력 한도에 도달했습니다. 표시된 문제를 해결한 뒤 이력을 초기화하고 다시 검사해 주세요.", "ErrorManager")
		return
	var error := {
		"code": code, "message": message, "context": context,
		"occurrences": 1, "time": Time.get_datetime_string_from_system()
	}
	_errors[key] = error
	_history.append(key)
	_pending.append(key)
	printerr("[GameError:%s] %s (%s)" % [code, message, context])
	error_reported.emit(error.duplicate(true))
	if _current.is_empty():
		_show_next_error()
	else:
		_update_confirm_text()


func get_errors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in _history:
		result.append(_errors[key].duplicate(true))
	return result


func clear_errors() -> void:
	_errors.clear()
	_history.clear()
	_pending.clear()
	_current = ""
	if is_instance_valid(_panel):
		_panel.hide()


func dismiss_current() -> void:
	_current = ""
	_show_next_error()


func validate_id(id: String, context: String) -> bool:
	if id.is_empty() or id != id.strip_edges():
		report_error("INVALID_ID", "ID가 비어 있거나 앞뒤에 공백이 있습니다.", context)
		return false
	return true


func validate_number(value: float, context: String, allow_zero: bool = true) -> bool:
	if not is_finite(value) or value < 0.0 or (not allow_zero and value == 0.0):
		report_error("INVALID_NUMBER", "유효하지 않은 수치입니다: %s" % str(value), context)
		return false
	return true


func validate_registry(entries: Array, kind: String) -> bool:
	var valid := true
	var seen: Dictionary = {}
	for index in entries.size():
		var entry: Variant = entries[index]
		var context := "%s[%d]" % [kind, index]
		if not entry is ButtonData and not entry is IncomeSourceData:
			report_error("INVALID_RESOURCE", "등록 목록에 비어 있거나 잘못된 리소스가 있습니다.", context)
			valid = false
			continue
		if not validate_id(entry.id, context):
			valid = false
			continue
		if seen.has(entry.id):
			report_error("DUPLICATE_ID", "같은 ID가 두 번 이상 등록되어 해당 항목을 사용할 수 없습니다.", kind + ":" + entry.id)
			valid = false
		seen[entry.id] = true
	return valid


func find_resource(entries: Array, id: String, kind: String) -> Resource:
	if not validate_id(id, kind):
		return null
	var found: Resource = null
	for entry in entries:
		if (entry is ButtonData or entry is IncomeSourceData) and entry.id == id:
			if found != null:
				report_error("DUPLICATE_ID", "같은 ID가 두 번 이상 등록되어 해당 항목을 사용할 수 없습니다.", kind + ":" + id)
				return null
			found = entry
	if found == null:
		report_error("MISSING_ID", "참조한 ID를 등록 목록에서 찾을 수 없습니다.", kind + ":" + id)
	return found


func validate_income_source(source: IncomeSourceData) -> bool:
	if source == null:
		report_error("INVALID_RESOURCE", "수입원 리소스가 비어 있습니다.", "IncomeSourceData")
		return false
	var context := "IncomeSourceData:" + source.id
	var valid := validate_id(source.id, context)
	var values := {
		"base_income": source.base_income,
		"multiplier": source.multiplier,
		"upgrade_base_cost": source.upgrade_base_cost,
		"upgrade_cost_linear_growth": source.upgrade_cost_linear_growth,
		"upgrade_cost_doubling_levels": source.upgrade_cost_doubling_levels,
		"base_time": source.base_time, "time_multiplier": source.time_multiplier
	}
	for property_name: String in values:
		var allow_zero := property_name in ["base_income", "upgrade_cost_linear_growth"]
		if not validate_number(values[property_name], context + "." + property_name, allow_zero):
			valid = false
	if not validate_number(source.base_time * source.time_multiplier, context + ".production_time", false):
		valid = false
	return valid


func validate_condition(condition: UnlockCondition, buttons: Array, context: String) -> bool:
	if condition == null:
		return true
	match condition.type:
		UnlockCondition.Type.MONEY:
			return validate_number(condition.amount, context + ".amount")
		UnlockCondition.Type.TOTAL_JJAM:
			if not validate_number(condition.amount, context + ".amount"):
				return false
			if condition.amount != floorf(condition.amount) or condition.amount >= INT64_LIMIT:
				report_error("INVALID_JJAM_THRESHOLD", "누적 짬 조건은 정수 범위 내의 0 이상 정수여야 합니다.", context)
				return false
			return true
		UnlockCondition.Type.BUTTON:
			return find_resource(buttons, condition.value, "ButtonData") != null
		_:
			report_error("INVALID_UNLOCK_TYPE", "지원하지 않는 해금 조건입니다.", context)
			return false


func validate_button(button: ButtonData, buttons: Array, sources: Array) -> bool:
	if button == null:
		report_error("INVALID_RESOURCE", "버튼 리소스가 비어 있습니다.", "ButtonData")
		return false
	var context := "ButtonData:" + button.id
	if find_resource(buttons, button.id, "ButtonData") != button:
		return false
	var valid := validate_number(button.price, context + ".price")
	if button.price > 0.0 and roundf(button.price) == 0.0:
		report_error("INVALID_PRICE", "가격을 원 단위로 반올림하면 0원이 됩니다.", context)
		valid = false
	if not ButtonData.Type.values().has(button.type):
		report_error("INVALID_BUTTON_TYPE", "지원하지 않는 구매 종류입니다.", context)
		valid = false
	if not validate_condition(button.unlock_condition, buttons, context + ".unlock_condition"):
		valid = false
	if button.effect_type == ButtonData.EffectType.NONE:
		return valid
	if not validate_number(button.effect_value, context + ".effect_value", false):
		valid = false
	match button.effect_type:
		ButtonData.EffectType.ACTIVATE_SOURCE, ButtonData.EffectType.SOURCE_MULTIPLIER, ButtonData.EffectType.SOURCE_SPEED_MULTIPLIER:
			var source := find_resource(sources, button.effect_target, "IncomeSourceData") as IncomeSourceData
			if source == null or not validate_income_source(source):
				valid = false
		ButtonData.EffectType.GLOBAL_MULTIPLIER, ButtonData.EffectType.GLOBAL_TIME_MULTIPLIER:
			pass
		_:
			report_error("INVALID_EFFECT_TYPE", "지원하지 않는 구매 효과입니다.", context)
			valid = false
	return valid


func validate_button_graph(buttons: Array) -> bool:
	var valid := true
	var checked: Dictionary = {}
	for button in buttons:
		if button == null or checked.has(button.id):
			continue
		var chain: Array[String] = []
		var positions: Dictionary = {}
		var current := button as ButtonData
		while current != null and not checked.has(current.id):
			if positions.has(current.id):
				var cycle := chain.slice(positions[current.id])
				cycle.append(current.id)
				_report_unlock_cycle(cycle)
				valid = false
				break
			positions[current.id] = chain.size()
			chain.append(current.id)
			if current.unlock_condition == null or current.unlock_condition.type != UnlockCondition.Type.BUTTON:
				break
			current = find_resource(buttons, current.unlock_condition.value, "ButtonData") as ButtonData
		for id in chain:
			checked[id] = true
	return valid


func validate_button_dependency(button: ButtonData, buttons: Array) -> bool:
	var chain: Array[String] = []
	var positions: Dictionary = {}
	var current := button
	while current != null:
		if positions.has(current.id):
			var cycle := chain.slice(positions[current.id])
			cycle.append(current.id)
			_report_unlock_cycle(cycle)
			return false
		positions[current.id] = chain.size()
		chain.append(current.id)
		if not validate_condition(current.unlock_condition, buttons, "ButtonData:" + current.id + ".unlock_condition"):
			return false
		if current.unlock_condition == null or current.unlock_condition.type != UnlockCondition.Type.BUTTON:
			return true
		current = find_resource(buttons, current.unlock_condition.value, "ButtonData") as ButtonData
	return false


func _report_unlock_cycle(cycle: Array) -> void:
	var sorted := cycle.duplicate()
	sorted.sort()
	report_error("UNLOCK_CYCLE", "해금 조건이 순환합니다: " + " → ".join(cycle), "ButtonData:" + sorted[0])


func validate_buttons(buttons: Array, sources: Array) -> bool:
	var valid := validate_registry(buttons, "ButtonData")
	for button in buttons:
		if not validate_button(button, buttons, sources):
			valid = false
	if not validate_button_graph(buttons):
		valid = false
	return valid


func require_node(parent: Node, path: NodePath, expected_type: String) -> Node:
	var node := parent.get_node_or_null(path) if is_instance_valid(parent) else null
	var parent_path := str(parent.get_path()) if is_instance_valid(parent) and parent.is_inside_tree() else str(parent)
	var context := str(path) if path.is_absolute() else parent_path + "/" + str(path)
	if node == null:
		report_error("MISSING_NODE", "장면에 필요한 노드가 없습니다.", context)
		return null
	if not node.is_class(expected_type):
		report_error("INVALID_NODE_TYPE", "노드 형식이 %s이어야 합니다." % expected_type, context)
		return null
	return node


func initialize_component(component: Node, required: Array) -> bool:
	for value in required:
		if not is_instance_valid(value):
			report_error("SCENE_INITIALIZATION", "필수 구성 요소가 없어 해당 화면의 동작을 중단했습니다.", String(component.name))
			component.process_mode = Node.PROCESS_MODE_DISABLED
			if component is CanvasItem:
				component.hide()
			return false
	return true


func validate_instance(value: Variant, context: String) -> bool:
	if not is_instance_valid(value):
		report_error("INVALID_INSTANCE", "사용하려는 객체가 없거나 이미 삭제되었습니다.", context)
		return false
	return true


func find_world_element(root: Node, id: String, expected_type: String = "Node2D") -> Node2D:
	if not is_instance_valid(root):
		report_error("MISSING_NODE", "월드 배치 노드가 없습니다.", "WorldLayout")
		return null
	if not validate_id(id, "WorldLayout"):
		return null
	var found: Node2D = null
	for node in root.find_children("*", "Node2D", true, false):
		if String(node.name) != id:
			continue
		if found != null:
			report_error("DUPLICATE_WORLD_ID", "월드에 같은 ID의 노드가 여러 개 있습니다.", "WorldLayout:" + id)
			return null
		found = node as Node2D
	if found == null:
		report_error("MISSING_WORLD_ID", "ID에 해당하는 월드 배치 노드를 찾을 수 없습니다.", "WorldLayout:" + id)
	elif not found.is_class(expected_type):
		report_error("INVALID_NODE_TYPE", "월드 노드 형식이 %s이어야 합니다." % expected_type, "WorldLayout:" + id)
		return null
	elif found.global_transform.determinant() == 0.0 or not is_finite(found.global_transform.determinant()) or not found.global_position.is_finite():
		report_error("INVALID_TRANSFORM", "월드 노드의 위치나 크기로는 좌표를 계산할 수 없습니다.", "WorldLayout:" + id)
		return null
	return found


func validate_visuals(node: Node2D, context: String) -> bool:
	var visuals: Array[Node] = node.find_children("*", "Sprite2D", true, false)
	visuals.append_array(node.find_children("*", "AnimatedSprite2D", true, false))
	if node is Sprite2D or node is AnimatedSprite2D:
		visuals.append(node)
	if visuals.is_empty():
		report_error("MISSING_VISUAL", "구매 후 표시할 이미지 노드가 없습니다.", context)
		return false
	var valid := true
	for visual in visuals:
		if visual is Sprite2D and visual.texture == null:
			report_error("MISSING_TEXTURE", "이미지 노드에 텍스처가 없습니다.", context + ":" + String(visual.name))
			valid = false
		elif visual is AnimatedSprite2D:
			var frames: SpriteFrames = visual.sprite_frames
			if frames == null or not frames.has_animation(visual.animation) or frames.get_frame_count(visual.animation) == 0:
				report_error("INVALID_ANIMATION", "표시할 애니메이션 프레임이 없습니다.", context + ":" + String(visual.name))
				valid = false
	return valid


func validate_hover_areas(node: Node2D, context: String) -> bool:
	var areas := node.find_children("HoverArea", "Area2D", true, false)
	if areas.is_empty():
		report_error("MISSING_HOVER_AREA", "설명이나 대사를 표시할 HoverArea가 없습니다.", context)
		return false
	var valid := true
	for area in areas:
		var has_shape := false
		for child in area.get_children():
			if child is CollisionShape2D and child.shape != null and not child.disabled:
				has_shape = true
			elif child is CollisionPolygon2D and child.polygon.size() >= 3 and not child.disabled:
				has_shape = true
		if not has_shape:
			report_error("MISSING_COLLISION_SHAPE", "HoverArea에 유효한 충돌 모양이 없습니다.", context + ":" + str(area.get_path()))
			valid = false
	return valid


func _create_error_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "ErrorPanel"
	_panel.hide()
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "게임 오류"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 140.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_message)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	column.add_child(_details)
	_confirm = Button.new()
	_confirm.pressed.connect(dismiss_current)
	column.add_child(_confirm)
	_resize_panel()


func _resize_panel() -> void:
	var width := minf(620.0, maxf(80.0, get_viewport().get_visible_rect().size.x - 32.0))
	_panel.custom_minimum_size.x = width
	_panel.custom_maximum_size.x = width


func _show_next_error() -> void:
	if not is_instance_valid(_panel):
		return
	if _pending.is_empty():
		_panel.hide()
		return
	_current = _pending.pop_front()
	var error: Dictionary = _errors[_current]
	_message.text = error.message + "\n\n문제가 있는 동작은 중단했습니다. 설정을 확인해 주세요."
	_details.text = "[%s]\n%s" % [error.code, error.context]
	_update_confirm_text()
	_panel.show()


func _update_confirm_text() -> void:
	if is_instance_valid(_confirm):
		_confirm.text = "확인" if _pending.is_empty() else "다음 오류 (%d개 대기)" % _pending.size()
