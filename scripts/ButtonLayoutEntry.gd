@tool
extends Node2D

@export var button_data: ButtonData:
	set(value):
		if button_data != null and button_data.changed.is_connected(_refresh_label):
			button_data.changed.disconnect(_refresh_label)
		button_data = value
		if button_data != null:
			button_data.changed.connect(_refresh_label)
		_refresh_label()

# Resolve source names in the editor without requiring running Autoloads.
@export var income_source: IncomeSourceData:
	set(value):
		income_source = value
		_refresh_label()


func _ready() -> void:
	_refresh_label()


func _refresh_label() -> void:
	if not is_inside_tree() or button_data == null:
		return
	var label := get_node_or_null("InfoLabel") as Label
	if label == null:
		return
	var source_name := ""
	if income_source != null and income_source.id == button_data.effect_target:
		source_name = income_source.source_name
	label.text = button_data.get_purchase_label_text(source_name)
	# Hidden runtime references still need the same text dimensions as their clones.
	label.size = label.size.max(label.get_combined_minimum_size())
