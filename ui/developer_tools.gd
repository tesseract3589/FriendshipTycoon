class_name DeveloperToolsPanel
extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const BIG = preload("res://scripts/BigNumber.gd")

@onready var amount_input := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/AmountInput", "LineEdit") as LineEdit
@onready var time_multiplier_input := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/TimeMultiplierRow/TimeMultiplierInput", "LineEdit") as LineEdit
@onready var income_multiplier_input := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/IncomeMultiplierRow/IncomeMultiplierInput", "LineEdit") as LineEdit
@onready var apply_multipliers_button := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/ApplyMultipliersButton", "Button") as Button
@onready var status_label := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/StatusLabel", "Label") as Label
@onready var add_button := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/Buttons/AddButton", "Button") as Button
@onready var close_button := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/Buttons/CloseButton", "Button") as Button


func _ready() -> void:
	if not ErrorManager.initialize_component(self, [amount_input, time_multiplier_input, income_multiplier_input, apply_multipliers_button, status_label, add_button, close_button]):
		return
	add_button.pressed.connect(_add_money)
	close_button.pressed.connect(_close)
	apply_multipliers_button.pressed.connect(_apply_multipliers)
	amount_input.text_submitted.connect(_on_amount_submitted)
	time_multiplier_input.text_submitted.connect(_on_multiplier_submitted)
	income_multiplier_input.text_submitted.connect(_on_multiplier_submitted)
	_refresh_multiplier_inputs()


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

	if not EconomyManager.add_money(amount):
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


