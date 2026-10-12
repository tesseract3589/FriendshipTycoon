extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const AUTO_COLOR := Color(1.0, 0.58, 0.18)

enum PendingAction { NONE, SAVE, LOAD, RESET }

@onready var open_button: Button = $OpenButton
@onready var overlay: Control = $Overlay
@onready var panel: PanelContainer = $Overlay/Panel
@onready var list: VBoxContainer = $Overlay/Panel/Margin/VBox/Scroll/Slots
@onready var status_label: Label = $Overlay/Panel/Margin/VBox/Status
@onready var save_button: Button = $Overlay/Panel/Margin/VBox/Actions/Save
@onready var load_button: Button = $Overlay/Panel/Margin/VBox/Actions/Load
@onready var reset_button: Button = $Overlay/Panel/Margin/VBox/Actions/Reset
@onready var close_button: Button = $Overlay/Panel/Margin/VBox/Actions/Close
@onready var confirmation: ConfirmationDialog = $Confirmation

var _selected_slot: int = 1
var _slot_buttons: Array[Button] = []
var _slot_details: Array[Label] = []
var _slot_info: Array[Dictionary] = []
var _pending_slot: int = -1
var _pending_action: PendingAction = PendingAction.NONE


func _ready() -> void:
	open_button.pressed.connect(_open)
	close_button.pressed.connect(overlay.hide)
	save_button.pressed.connect(_request_save)
	load_button.pressed.connect(_request_load)
	reset_button.pressed.connect(_request_reset)
	confirmation.confirmed.connect(_confirm_action)
	confirmation.canceled.connect(_cancel_action)
	SaveManager.slots_changed.connect(_refresh_slots)
	resized.connect(_fit_panel)
	panel.minimum_size_changed.connect(_fit_panel.call_deferred)
	var group := ButtonGroup.new()
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(0.12, 0.16, 0.22, 1.0)
	selected_style.border_color = Color.WHITE
	selected_style.set_border_width_all(3)
	selected_style.set_corner_radius_all(6)
	for slot in range(SaveManager.AUTO_SLOT, SaveManager.SLOT_COUNT + 1):
		var button := Button.new()
		button.name = "Autosave" if slot == SaveManager.AUTO_SLOT else "Slot%d" % slot
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 76.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("hover_pressed", selected_style)
		button.pressed.connect(_select_slot.bind(slot))
		list.add_child(button)
		var margin := MarginContainer.new()
		margin.name = "Margin"
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right"]:
			margin.add_theme_constant_override("margin_" + side, 14)
		button.add_child(margin)
		var text := VBoxContainer.new()
		text.name = "Text"
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.add_theme_constant_override("separation", 4)
		margin.add_child(text)
		var title := Label.new()
		title.name = "Title"
		title.text = SaveManager.get_slot_name(slot)
		title.add_theme_font_size_override("font_size", 20)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if slot == SaveManager.AUTO_SLOT:
			title.add_theme_color_override("font_color", AUTO_COLOR)
		text.add_child(title)
		var detail := Label.new()
		detail.name = "Detail"
		detail.add_theme_font_size_override("font_size", 16)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(detail)
		_slot_buttons.append(button)
		_slot_details.append(detail)
	_refresh_slots()
	_fit_panel()


func _fit_panel() -> void:
	if not is_instance_valid(panel):
		return
	panel.size = Vector2(minf(520.0, size.x - 24.0), minf(680.0, size.y - 24.0))
	panel.position = (size - panel.size) * 0.5


func _open() -> void:
	if not SaveManager.initialized and not SaveManager.initialize():
		return
	TooltipManager.hide_tooltip()
	status_label.text = "슬롯을 선택한 뒤 저장하거나 불러오세요."
	_refresh_slots()
	overlay.show()
	_fit_panel()
	_slot_buttons[_selected_slot].grab_focus()
	_fit_panel.call_deferred()
	# Keep the automatic slot visible while the initially selected manual slot gains focus.
	get_node("Overlay/Panel/Margin/VBox/Scroll").set_deferred("scroll_vertical", 0)


func _refresh_slots() -> void:
	_slot_info.clear()
	for slot in range(SaveManager.AUTO_SLOT, SaveManager.SLOT_COUNT + 1):
		var info := SaveManager.get_slot_info(slot)
		_slot_info.append(info)
		var detail := "비어 있음"
		if not info.valid:
			detail = "손상되었거나 지원하지 않는 저장 파일"
		elif info.has_save:
			detail = "%s · 자금 %s원" % [info.saved_at, NUMBER_FORMATTER.format_number(info.money)]
		_slot_details[slot].text = detail
	_select_slot(_selected_slot)


func _select_slot(slot: int) -> void:
	_selected_slot = slot
	_slot_buttons[slot].button_pressed = true
	save_button.disabled = slot == SaveManager.AUTO_SLOT
	save_button.tooltip_text = "자동 저장 슬롯은 게임 종료 시 자동 저장됩니다." if save_button.disabled else "선택한 슬롯에 현재 진행 저장"
	var info := _slot_info[slot]
	load_button.disabled = not info.valid
	load_button.tooltip_text = "선택한 슬롯의 진행 불러오기" if info.has_save else "빈 슬롯에서 새 게임 시작"
	reset_button.disabled = not info.has_save and info.valid


func _request_save() -> void:
	if _selected_slot == SaveManager.AUTO_SLOT:
		return
	_pending_slot = _selected_slot
	_pending_action = PendingAction.SAVE
	var info := _slot_info[_selected_slot]
	if info.has_save or not info.valid:
		confirmation.title = "저장 덮어쓰기"
		confirmation.dialog_text = "슬롯 %d의 저장을 현재 진행으로 덮어쓸까요?" % _pending_slot
		confirmation.ok_button_text = "덮어쓰기"
		confirmation.popup_centered()
	else:
		_confirm_action()


func _request_load() -> void:
	if load_button.disabled:
		return
	_pending_slot = _selected_slot
	_pending_action = PendingAction.LOAD
	if _slot_info[_pending_slot].has_save:
		confirmation.title = "진행 불러오기"
		confirmation.dialog_text = "%s을 불러올까요?\n저장하지 않은 현재 진행은 사라집니다." % SaveManager.get_slot_name(_pending_slot)
		confirmation.ok_button_text = "불러오기"
	else:
		confirmation.title = "새 게임 시작"
		confirmation.dialog_text = "%s은 비어 있습니다.\n초기 상태로 시작할까요?\n저장하지 않은 현재 진행은 사라집니다." % SaveManager.get_slot_name(_pending_slot)
		confirmation.ok_button_text = "새 게임 시작"
	confirmation.popup_centered()


func _request_reset() -> void:
	if reset_button.disabled:
		return
	_pending_slot = _selected_slot
	_pending_action = PendingAction.RESET
	confirmation.title = "저장 슬롯 초기화 경고"
	confirmation.dialog_text = "%s의 저장 데이터를 삭제할까요?\n초기화하면 되돌릴 수 없습니다.\n현재 플레이 중인 진행은 유지됩니다." % SaveManager.get_slot_name(_pending_slot)
	if _pending_slot == SaveManager.AUTO_SLOT:
		confirmation.dialog_text += "\n자동 저장 슬롯은 게임 종료 시 현재 진행으로 다시 저장됩니다."
	confirmation.ok_button_text = "초기화"
	confirmation.popup_centered()
	confirmation.get_cancel_button().grab_focus()


func _cancel_action() -> void:
	_pending_action = PendingAction.NONE
	_pending_slot = -1


func _confirm_action() -> void:
	var slot := _pending_slot
	var action := _pending_action
	_cancel_action()
	match action:
		PendingAction.LOAD:
			var was_empty: bool = not SaveManager.get_slot_info(slot).has_save
			if SaveManager.load_slot(slot):
				status_label.text = "%s에서 새 게임을 시작했습니다." % SaveManager.get_slot_name(slot) if was_empty else "%s의 진행을 불러왔습니다." % SaveManager.get_slot_name(slot)
				TooltipManager.hide_tooltip()
			else:
				status_label.text = "불러오지 못했습니다. 오류 메시지를 확인하세요."
		PendingAction.SAVE:
			status_label.text = "슬롯 %d에 저장했습니다." % slot if SaveManager.save_slot(slot) else "저장하지 못했습니다. 오류 메시지를 확인하세요."
		PendingAction.RESET:
			status_label.text = "%s을 초기화했습니다." % SaveManager.get_slot_name(slot) if SaveManager.reset_slot(slot) else "초기화하지 못했습니다. 오류 메시지를 확인하세요."
		_:
			return
	_refresh_slots()


func _unhandled_key_input(event: InputEvent) -> void:
	if overlay.visible and event.is_action_pressed("ui_cancel"):
		overlay.hide()
		get_viewport().set_input_as_handled()
