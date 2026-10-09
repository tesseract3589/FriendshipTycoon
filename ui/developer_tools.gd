class_name DeveloperToolsPanel
extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")

@onready var amount_input := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/AmountInput", "LineEdit") as LineEdit
@onready var status_label := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/StatusLabel", "Label") as Label
@onready var add_button := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/Buttons/AddButton", "Button") as Button
@onready var close_button := ErrorManager.require_node(self, ^"Panel/MarginContainer/VBoxContainer/Buttons/CloseButton", "Button") as Button


func _ready() -> void:
	if not ErrorManager.initialize_component(self, [amount_input, status_label, add_button, close_button]):
		return
	add_button.pressed.connect(_add_money)
	close_button.pressed.connect(_close)
	amount_input.text_submitted.connect(_on_amount_submitted)


func toggle() -> void:
	if process_mode == Node.PROCESS_MODE_DISABLED:
		return
	visible = not visible
	if visible:
		status_label.text = ""
		amount_input.grab_focus()
		amount_input.select_all()


func _add_money() -> void:
	var amount_text := amount_input.text.strip_edges()
	if not amount_text.is_valid_float():
		status_label.text = "유효한 금액을 입력하세요."
		return

	var amount := amount_text.to_float()
	if amount <= 0.0 or not is_finite(amount):
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


