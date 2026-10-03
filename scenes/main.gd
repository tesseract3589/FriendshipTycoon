extends Node2D

const INCOME_SOURCE_VIEW_SCENE: PackedScene = preload("res://ui/income_source_view.tscn")
const PURCHASE_BUTTON_SCENE: PackedScene = preload("res://ui/purchase_button.tscn")

@onready var money_label: Label = $HUD/Panel/VBoxContainer/MoneyLabel
@onready var income_label: Label = $HUD/Panel/VBoxContainer/IncomeLabel
@onready var income_source_views: Node2D = $World/IncomeSourceViews
@onready var purchase_button_list: VBoxContainer = $HUD/Panel/VBoxContainer/ScrollContainer/PurchaseButtonList


func _ready() -> void:
	EconomyManager.money_changed.connect(_refresh_finances)
	IncomeManager.income_changed.connect(_refresh_finances)
	_create_income_source_views()
	_create_purchase_buttons()
	_refresh_finances()


func _create_income_source_views() -> void:
	for source_data in IncomeManager.sources:
		if source_data == null:
			continue
		var source_view := INCOME_SOURCE_VIEW_SCENE.instantiate() as IncomeSourceView
		source_view.source_data = source_data
		income_source_views.add_child(source_view)


func _create_purchase_buttons() -> void:
	for button_data in ButtonManager.buttons:
		if button_data == null:
			continue
		var purchase_button := PURCHASE_BUTTON_SCENE.instantiate() as PurchaseButton
		purchase_button.setup(button_data)
		purchase_button_list.add_child(purchase_button)


func _refresh_finances(_value = null) -> void:
	money_label.text = "자금: %s원" % _format_number(EconomyManager.money)
	income_label.text = "수입: %s원 / 초" % _format_number(IncomeManager.get_total_income_per_second())


func _format_number(value: float) -> String:
	if absf(value) >= 1000000000.0:
		return "%.3e" % value
	return "%.2f" % value
