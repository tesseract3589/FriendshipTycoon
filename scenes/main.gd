extends Node2D

var money_label: Label
var income_label: Label
var jjam_label: Label
var source_button: Button
var promotion_button: Button
var prestige_button: Button


func _ready() -> void:
	_build_interface()
	EconomyManager.money_changed.connect(_refresh_interface)
	EconomyManager.multiplier_changed.connect(_refresh_interface)
	IncomeManager.income_changed.connect(_refresh_interface)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	PrestigeManager.prestige_changed.connect(_refresh_interface)
	_refresh_interface()


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24.0, 24.0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(420.0, 0.0)
	panel.add_child(column)

	var title := Label.new()
	title.text = "우정회관 키우기"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	money_label = Label.new()
	column.add_child(money_label)
	income_label = Label.new()
	column.add_child(income_label)
	jjam_label = Label.new()
	column.add_child(jjam_label)

	source_button = Button.new()
	source_button.pressed.connect(_buy_source)
	column.add_child(source_button)
	promotion_button = Button.new()
	promotion_button.pressed.connect(_buy_promotion)
	column.add_child(promotion_button)
	prestige_button = Button.new()
	prestige_button.text = "짬 환생"
	prestige_button.pressed.connect(_prestige)
	column.add_child(prestige_button)


func _format_number(value: float) -> String:
	if absf(value) >= 1000000000.0:
		return "%.3e" % value
	return "%.2f" % value


func _refresh_interface(_value = null) -> void:
	if not is_instance_valid(money_label):
		return
	money_label.text = "자금: $%s" % _format_number(EconomyManager.money)
	income_label.text = "수입: $%s / 초" % _format_number(IncomeManager.get_total_income_per_second())
	var jjam := PrestigeManager.get_current_jjam()
	jjam_label.text = "환생 시 획득 짬: %d | 누적 짬: %d | 배율: x%.2f" % [jjam, PrestigeManager.total_jjam, PrestigeManager.get_prestige_multiplier()]
	var source := ButtonManager.get_button("open_hall")
	var promotion := ButtonManager.get_button("promotion_campaign")
	source_button.text = "회관 문 열기 (무료)" if source == null or not source.bought else "회관 운영 중"
	source_button.disabled = source != null and source.bought
	promotion_button.text = "홍보 캠페인 ($10)" if promotion == null else "%s ($%s)" % [promotion.button_name, _format_number(promotion.price)]
	promotion_button.disabled = promotion == null or not ButtonManager.can_purchase(promotion)
	prestige_button.disabled = jjam <= 0


func _buy_source() -> void:
	ButtonManager.purchase_by_id("open_hall")


func _buy_promotion() -> void:
	ButtonManager.purchase_by_id("promotion_campaign")


func _prestige() -> void:
	PrestigeManager.prestige()


func _on_button_purchased(_button_data: ButtonData) -> void:
	_refresh_interface()
