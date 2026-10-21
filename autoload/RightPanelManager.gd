extends Node

## Any future right-side entry can register its content without knowing other panels.
var _panels: Array[Control] = []


func register_panel(panel: Control) -> void:
	if not _panels.has(panel):
		_panels.append(panel)
		panel.tree_exiting.connect(_unregister.bind(panel), CONNECT_ONE_SHOT)
	panel.hide()


func _unregister(panel: Control) -> void:
	_panels.erase(panel)


func open_panel(panel: Control) -> void:
	if not _panels.has(panel):
		register_panel(panel)
	close_all()
	TooltipManager.hide_tooltip()
	panel.show()


func toggle_panel(panel: Control) -> void:
	if panel.visible:
		panel.hide()
	else:
		open_panel(panel)


func close_all() -> void:
	for panel in _panels:
		if is_instance_valid(panel):
			panel.hide()
