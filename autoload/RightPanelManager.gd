extends Node

## Any future right-side entry can register its content without knowing other panels.
var _panels: Array[Control] = []
const SIDEBAR_GAP: float = 16.0


func register_sidebar_entry(entry: Control, order: int) -> void:
	entry.set_meta(&"_sidebar_order", order)
	entry.add_to_group("right_panel_sidebar_entry")
	entry.add_to_group("panel_right_obstacle")
	entry.visibility_changed.connect(_layout_sidebar_entries)
	entry.tree_exiting.connect(_layout_sidebar_entries.call_deferred, CONNECT_ONE_SHOT)
	_layout_sidebar_entries()


func _layout_sidebar_entries() -> void:
	var entries: Array[Control] = []
	for item in get_tree().get_nodes_in_group("right_panel_sidebar_entry"):
		var entry := item as Control
		if entry != null and entry.visible:
			entries.append(entry)
	entries.sort_custom(func(a: Control, b: Control) -> bool: return a.get_meta(&"_sidebar_order") < b.get_meta(&"_sidebar_order"))
	var height := SIDEBAR_GAP * maxi(0, entries.size() - 1)
	for entry in entries:
		height += entry.size.y
	var top := -height * 0.5
	for entry in entries:
		var entry_height := entry.size.y
		entry.offset_top = top
		entry.offset_bottom = top + entry_height
		entry.pivot_offset = entry.size * 0.5
		top += entry_height + SIDEBAR_GAP


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
