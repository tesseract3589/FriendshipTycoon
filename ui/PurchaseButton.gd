class_name PurchaseButton
extends Button

var button_data: ButtonData


func _ready() -> void:
	pressed.connect(_purchase)
	ButtonManager.button_state_changed.connect(_on_button_state_changed)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	EconomyManager.money_changed.connect(_on_money_changed)
	_refresh()


func setup(data: ButtonData) -> void:
	button_data = data
	_refresh()


func _refresh() -> void:
	if button_data == null:
		disabled = true
		return

	text = button_data.button_name
	var description := button_data.description
	if description.is_empty() and button_data.effect_type == ButtonData.EffectType.ACTIVATE_SOURCE:
		var source_data := IncomeManager.get_source(button_data.effect_target)
		if source_data != null:
			var production_time := source_data.base_time * source_data.time_multiplier
			description = "%s초당 %s원" % [
				_format_number(production_time),
				_format_number(source_data.base_income)
			]
	if not description.is_empty():
		text += " · " + description
	if button_data.price > 0.0:
		text += " · %s원" % _format_number(button_data.price)
	if button_data.bought:
		text += " · 구매 완료"
	disabled = not ButtonManager.can_purchase(button_data)


func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.2f" % value


func _purchase() -> void:
	if button_data != null:
		ButtonManager.purchase(button_data)


func _on_button_state_changed(changed_data: ButtonData) -> void:
	if button_data != null and changed_data.id == button_data.id:
		_refresh()


func _on_button_purchased(purchased_data: ButtonData) -> void:
	if button_data != null and purchased_data.id == button_data.id:
		_refresh()


func _on_money_changed(_new_money: float) -> void:
	_refresh()
