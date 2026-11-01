class_name DeveloperToolsPanel
extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const BIG = preload("res://scripts/BigNumber.gd")
const WINDOW_LAYOUT = preload("res://scripts/GameWindowLayout.gd")

@onready var amount_input := ErrorManager.require_node(self, ^"Panel/Scroll/MarginContainer/VBoxContainer/AmountInput", "LineEdit") as LineEdit
@onready var time_multiplier_input := ErrorManager.require_node(self, ^"Panel/Scroll/MarginContainer/VBoxContainer/TimeMultiplierRow/TimeMultiplierInput", "LineEdit") as LineEdit
@onready var income_multiplier_input := ErrorManager.require_node(self, ^"Panel/Scroll/MarginContainer/VBoxContainer/IncomeMultiplierRow/IncomeMultiplierInput", "LineEdit") as LineEdit
@onready var apply_multipliers_button := ErrorManager.require_node(self, ^"Panel/Scroll/MarginContainer/VBoxContainer/ApplyMultipliersButton", "Button") as Button
@onready var status_label := ErrorManager.require_node(self, ^"Panel/Scroll/MarginContainer/VBoxContainer/StatusLabel", "Label") as Label
@onready var add_button := ErrorManager.require_node(self, ^"Panel/Scroll/MarginContainer/VBoxContainer/Buttons/AddButton", "Button") as Button
@onready var close_button := ErrorManager.require_node(self, ^"Panel/Scroll/MarginContainer/VBoxContainer/Buttons/CloseButton", "Button") as Button
@onready var event_rows := ErrorManager.require_node(self, ^"Panel/Scroll/MarginContainer/VBoxContainer/EventRows", "VBoxContainer") as VBoxContainer
@onready var panel: PanelContainer = $Panel

var _event_row_controls: Dictionary = {}
var _event_refresh_elapsed: float = 0.0


func _ready() -> void:
	if not ErrorManager.initialize_component(self, [amount_input, time_multiplier_input, income_multiplier_input, apply_multipliers_button, status_label, add_button, close_button, event_rows, panel]):
		return
	add_button.pressed.connect(_add_money)
	close_button.pressed.connect(_close)
	apply_multipliers_button.pressed.connect(_apply_multipliers)
	amount_input.text_submitted.connect(_on_amount_submitted)
	time_multiplier_input.text_submitted.connect(_on_multiplier_submitted)
	income_multiplier_input.text_submitted.connect(_on_multiplier_submitted)
	visibility_changed.connect(_on_visibility_changed)
	resized.connect(_fit_panel)
	_refresh_multiplier_inputs()
	_fit_panel()
	_on_visibility_changed()


func _fit_panel() -> void:
	var layout_size := WINDOW_LAYOUT.get_ui_layout_size(size)
	panel.size = Vector2(minf(540.0, maxf(1.0, layout_size.x - 32.0)), minf(760.0, maxf(1.0, layout_size.y - 32.0)))
	panel.position = (size - panel.size) * 0.5


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
	_event_refresh_elapsed = 0.0
	if is_visible_in_tree():
		_refresh_event_rows()


func _process(delta: float) -> void:
	_event_refresh_elapsed += delta
	if _event_refresh_elapsed >= 0.1:
		_event_refresh_elapsed = fmod(_event_refresh_elapsed, 0.1)
		_refresh_event_rows()


func _refresh_event_rows() -> void:
	var current_ids: Array[String] = []
	for state in EventManager.get_event_debug_states():
		var event_id: String = state.id
		current_ids.append(event_id)
		if not _event_row_controls.has(event_id):
			_create_event_row(event_id, state.one_off)
		var controls: Dictionary = _event_row_controls[event_id]
		var title: Label = controls.title
		if state.one_off:
			title.text = "%s · %s" % [state.name, "진행됨" if state.consumed else "미진행"]
			title.tooltip_text = title.text
			continue
		var detail: Label = controls.detail
		var start_button: Button = controls.start_button
		var remaining: float = state.cooldown_remaining
		var displayed_remaining := ceilf(remaining * 10.0) / 10.0
		title.text = "%s · 쿨타임 %02d:%04.1f" % [state.name, floori(displayed_remaining / 60.0), fmod(displayed_remaining, 60.0)]
		if not state.can_start:
			detail.text = state.block_reason
		elif state.trigger == GameEventData.Trigger.INSTANT:
			detail.text = "조건 충족 · 즉시 발동"
		else:
			detail.text = "발동 가능 · %.2f초마다 %.1f%% · 다음 추첨 %.1f초" % [state.roll_interval_seconds, state.chance_per_roll * 100.0, state.next_roll_in]
		if state.trigger == GameEventData.Trigger.RANDOM:
			detail.text += "\n이번 대기 추첨 %d회 · 마지막 결과: %s" % [state.roll_attempts, state.last_roll_result]
		start_button.disabled = not state.can_start_for_testing
		if not state.can_start_for_testing:
			start_button.tooltip_text = state.test_block_reason
		else:
			start_button.tooltip_text = "확률과 쿨타임을 무시하고 즉시 시작합니다."
	for event_id in _event_row_controls.keys():
		if event_id not in current_ids:
			_event_row_controls[event_id].row.queue_free()
			_event_row_controls.erase(event_id)


func _create_event_row(event_id: String, one_off: bool = false) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	event_rows.add_child(row)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	row.add_child(heading)
	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(title)
	if one_off:
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_event_row_controls[event_id] = {"row": row, "title": title}
		return
	var start_button := Button.new()
	start_button.text = "즉시 발동"
	start_button.custom_minimum_size = Vector2(116.0, 40.0)
	start_button.pressed.connect(_start_event_now.bind(event_id))
	heading.add_child(start_button)
	var detail := Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 14)
	row.add_child(detail)
	_event_row_controls[event_id] = {"row": row, "title": title, "detail": detail, "start_button": start_button}


func _start_event_now(event_id: String) -> void:
	if EventManager.start_event_for_testing(event_id):
		status_label.text = "이벤트를 즉시 발동했습니다."
	else:
		status_label.text = EventManager.get_event_start_block_reason(event_id, true)
	_refresh_event_rows()


func toggle() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	if visible:
		_close()
		return
	visible = true
	status_label.text = ""
	_refresh_multiplier_inputs()
	amount_input.grab_focus()
	amount_input.select_all()


func _refresh_multiplier_inputs() -> void:
	time_multiplier_input.text = str(EconomyManager.get_developer_time_multiplier())
	income_multiplier_input.text = str(EconomyManager.get_developer_income_multiplier())


func _apply_multipliers() -> void:
	var time_multiplier: Variant = _read_multiplier(time_multiplier_input, "시간", false)
	if BIG.compare(time_multiplier, 0.0) < 0:
		return
	var income_multiplier: Variant = _read_multiplier(income_multiplier_input, "수입", true)
	if BIG.compare(income_multiplier, 0.0) < 0:
		return
	if not EconomyManager.set_developer_multipliers(time_multiplier, income_multiplier):
		status_label.text = "배율을 적용하지 못했습니다. 오류 메시지를 확인하세요."
		return
	_refresh_multiplier_inputs()
	status_label.text = "개발자 시간 배율 %s / 수입 배율 %s 적용" % [
		NUMBER_FORMATTER.format_number(EconomyManager.get_developer_time_multiplier()),
		NUMBER_FORMATTER.format_number(EconomyManager.get_developer_income_multiplier()),
	]


func _read_multiplier(input: LineEdit, label: String, allow_zero: bool) -> Variant:
	var value_text := input.text.strip_edges()
	if not value_text.is_valid_float():
		status_label.text = "유효한 %s 배율을 입력하세요." % label
		return -1.0
	var value: Variant = BIG.parse(value_text) if allow_zero else value_text.to_float()
	if not BIG.valid(value, allow_zero) or (not allow_zero and value is BIG):
		status_label.text = "%s 배율은 %s 입력하세요." % [label, "0 이상의 값으로" if allow_zero else "0보다 큰 값으로"]
		return -1.0
	return value


func _on_multiplier_submitted(_text: String) -> void:
	_apply_multipliers()


func _add_money() -> void:
	var amount_text := amount_input.text.strip_edges()
	if not amount_text.is_valid_float():
		status_label.text = "유효한 금액을 입력하세요."
		return

	var amount: Variant = BIG.parse(amount_text)
	if not BIG.valid(amount, false):
		status_label.text = "0보다 큰 금액을 입력하세요."
		return

	if not EconomyManager.add_income(amount):
		status_label.text = "자금을 추가하지 못했습니다. 오류 메시지를 확인하세요."
		return
	status_label.text = "%s원을 추가했습니다." % NUMBER_FORMATTER.format_number(amount)
	amount_input.clear()
	amount_input.grab_focus()


func _on_amount_submitted(_text: String) -> void:
	_add_money()


func _close() -> void:
	visible = false
	amount_input.release_focus()
	time_multiplier_input.release_focus()
	income_multiplier_input.release_focus()
