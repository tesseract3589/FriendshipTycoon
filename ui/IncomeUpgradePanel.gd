class_name IncomeUpgradePanel
extends Control

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const UPGRADE_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_Upgrade.png")
const UPGRADE_BUTTON_TEXTURE: Texture2D = preload("res://assets/sprites/Interfaces/Button_UI_Upgrade.png")
const UPGRADE_REPEAT_INITIAL_DELAY: float = 0.55
const UPGRADE_REPEAT_ACCELERATION: float = 0.82
const UPGRADE_REPEAT_MIN_INTERVAL: float = 0.06

@onready var list: VBoxContainer = $Panel/Margin/VBox/List

var _held_source_id: String = ""
var _repeat_timer: float = 0.0
var _repeat_interval: float = UPGRADE_REPEAT_INITIAL_DELAY


func _ready() -> void:
	$OpenButton.texture_normal = UPGRADE_BUTTON_TEXTURE
	$OpenButton.pressed.connect(_toggle_panel)
	$Panel/Margin/VBox/CloseButton.pressed.connect(_toggle_panel)
	IncomeManager.source_activation_changed.connect(_on_sources_changed)
	IncomeManager.source_level_changed.connect(_on_level_changed)
	IncomeManager.source_multiplier_changed.connect(_refresh_rows)
	EconomyManager.money_changed.connect(_refresh_rows)
	EconomyManager.multiplier_changed.connect(_refresh_rows)
	_rebuild_rows()


func _process(delta: float) -> void:
	if _held_source_id.is_empty() or not $Panel.visible:
		return
	_repeat_timer -= delta
	if _repeat_timer > 0.0:
		return
	if not _upgrade_source(_held_source_id):
		_stop_upgrade_hold()
		return
	_repeat_interval = maxf(UPGRADE_REPEAT_MIN_INTERVAL, _repeat_interval * UPGRADE_REPEAT_ACCELERATION)
	_repeat_timer = _repeat_interval


func _toggle_panel() -> void:
	$Panel.visible = not $Panel.visible
	if $Panel.visible:
		_rebuild_rows()
	else:
		_stop_upgrade_hold()


func _on_sources_changed(_source_id: String, _active: bool) -> void:
	_rebuild_rows()


func _on_level_changed(_source_id: String, _level: int) -> void:
	_refresh_rows()


func _rebuild_rows() -> void:
	for child in list.get_children():
		child.queue_free()
	for source in IncomeManager.sources:
		if source == null or not IncomeManager.source_active.get(source.id, false):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.name = "Info"
		row.add_child(info)
		var upgrade := TextureButton.new()
		upgrade.name = "Upgrade"
		upgrade.texture_normal = UPGRADE_TEXTURE
		upgrade.custom_minimum_size = Vector2(67.2, 67.2)
		upgrade.ignore_texture_size = true
		upgrade.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		upgrade.button_down.connect(_on_upgrade_button_down.bind(source.id))
		upgrade.button_up.connect(_on_upgrade_button_up)
		row.add_child(upgrade)
		list.add_child(row)
		_refresh_row(row, source)


func _refresh_rows(_value = null) -> void:
	for row in list.get_children():
		var source_id: String = row.get_meta("source_id", "")
		var source := IncomeManager.get_source(source_id)
		if source != null:
			_refresh_row(row, source)


func _refresh_row(row: HBoxContainer, source: IncomeSourceData) -> void:
	row.set_meta("source_id", source.id)
	var level := IncomeManager.get_source_level(source.id)
	var payout := IncomeManager.get_source_cycle_payout(source.id)
	var cost := IncomeManager.get_upgrade_cost(source.id)
	row.get_node("Info").text = "%s  Lv.%d\n%s원 / 회 · 다음 업그레이드 %s원" % [source.source_name, level, NUMBER_FORMATTER.format_number(payout), NUMBER_FORMATTER.format_number(cost)]
	var upgrade_button := row.get_node("Upgrade") as TextureButton
	upgrade_button.disabled = not EconomyManager.can_afford(cost)
	upgrade_button.modulate = Color(0.65, 0.65, 0.65) if upgrade_button.disabled else Color.WHITE


func _on_upgrade_button_down(source_id: String) -> void:
	_held_source_id = source_id
	_repeat_interval = UPGRADE_REPEAT_INITIAL_DELAY
	if not _upgrade_source(source_id):
		_stop_upgrade_hold()
		return
	_repeat_timer = _repeat_interval


func _on_upgrade_button_up() -> void:
	_stop_upgrade_hold()


func _stop_upgrade_hold() -> void:
	_held_source_id = ""
	_repeat_timer = 0.0


func _upgrade_source(source_id: String) -> bool:
	if not IncomeManager.upgrade_source(source_id):
		return false
	SoundManager.play_purchase_sound()
	_refresh_rows()
	return true
