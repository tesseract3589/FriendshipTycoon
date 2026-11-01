extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const FIXTURES = preload("res://tests/TestFixtures.gd")
const SOURCE := "vending_machine"
const PLUS_ONE = preload("res://assets/sprites/Interfaces/plus_1.png")
const PLUS_FIVE = preload("res://assets/sprites/Interfaces/plus_5.png")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	FIXTURES.prepare_viewport(self)
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	_check(SaveManager.initialize(ProjectSettings.globalize_path("res://.godot/bulk_upgrade_%d" % Time.get_ticks_usec())), "Initialize isolated saves.")
	var initial := SaveManager._create_initial_progress()
	_check(FIXTURES.unlock_batch_upgrade(), "Unlock the real batch panel.")
	IncomeManager.activate_source(SOURCE)
	var view := preload("res://ui/income_source_view.tscn").instantiate() as IncomeSourceView
	view.setup(IncomeManager.get_source(SOURCE), Vector2.ZERO, Vector2.ONE, Rect2(100, 100, 40, 40))
	add_child(view)
	var batch := preload("res://ui/batch_upgrade_panel.tscn").instantiate() as BatchUpgradePanel
	add_child(batch)
	var shop := preload("res://ui/jjam_prestige_panel.tscn").instantiate() as JjamPrestigePanel
	add_child(shop)
	var buy: TextureButton = shop._shop_buttons["bulk_upgrade_5"]
	var mode_button := shop._shop_rows["bulk_upgrade_5"].mode_button as TextureButton
	var mode_column := shop._shop_rows["bulk_upgrade_5"].mode as VBoxContainer
	var batch_button := batch.list.get_child(0).get_node("Purchase/Upgrade") as TextureButton
	var badges := [view.upgrade_button.get_node("UpgradeModeBadge"), batch_button.get_node("UpgradeModeBadge")]
	for badge in badges:
		_check(not badge.visible, "Badges must stay hidden before ownership.")
	_check(buy.visible and not mode_column.visible, "Only the purchase button appears before ownership.")
	_check(PrestigeManager.get_upgrade_mode() == 1, "Default mode must be +1.")
	PrestigeManager.toggle_upgrade_mode()
	_check(PrestigeManager.get_upgrade_mode() == 1, "Unowned mode cannot be toggled.")
	PrestigeManager.banked_jjam = 399
	_check(not PrestigeManager.purchase_shop_item("bulk_upgrade_5"), "Reject purchase below 400 jjam.")
	PrestigeManager.banked_jjam = 400
	_check(PrestigeManager.purchase_shop_item("bulk_upgrade_5"), "Buy at exactly 400 jjam.")
	_check(PrestigeManager.banked_jjam == 0 and not PrestigeManager.purchase_shop_item("bulk_upgrade_5"), "Charge once and reject repeat purchase.")
	_check(PrestigeManager.get_upgrade_mode() == 5, "Purchase must immediately select +5.")
	_check(buy.visible and mode_column.visible and mode_button.texture_normal == PLUS_FIVE, "Keep the successor purchase button beside the +5 switch.")
	for badge in badges:
		_check(badge.visible and badge.texture == PLUS_FIVE and badge.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Both panels must show a non-interactive +5 badge.")
	var source := IncomeManager.get_source(SOURCE)
	var cost: Variant = 0.0
	for level in range(1, 6):
		cost = BIG.add(cost, BIG.rounded(IncomeManager._get_upgrade_cost_at_level(source, level)))
	_check(BIG.compare(IncomeManager.get_upgrade_cost(SOURCE), cost) == 0, "Bulk price must equal five rounded individual prices.")
	EconomyManager.money = BIG.subtract(cost, 1.0)
	_check(not IncomeManager.upgrade_source(SOURCE) and IncomeManager.get_source_level(SOURCE) == 1, "Insufficient bulk funds must not buy partial levels.")
	EconomyManager.money = cost
	var preview: Variant = IncomeManager.get_next_upgrade_cycle_payout(SOURCE)
	var observed := {}
	var on_payment := func(_money: Variant) -> void:
		observed.level = IncomeManager.get_source_level(SOURCE)
		observed.nested = IncomeManager.upgrade_source(SOURCE)
		observed.saved = SaveManager.save_slot(1)
	EconomyManager.money_changed.connect(on_payment, CONNECT_ONE_SHOT)
	_check(IncomeManager.upgrade_source(SOURCE), "Bulk upgrade with exact funds must succeed.")
	_check(observed.level == 6 and not observed.nested and observed.saved, "Bulk commit must be atomic through payment, reentry and saving.")
	_check(BIG.compare(EconomyManager.money, 0.0) == 0 and BIG.compare(IncomeManager.get_source_cycle_payout(SOURCE), preview) == 0, "Bulk charge and five-level preview must match the purchase.")
	mode_button.pressed.emit()
	_check(PrestigeManager.get_upgrade_mode() == 1 and mode_button.texture_normal == PLUS_ONE, "Click must switch to +1.")
	for badge in badges:
		_check(badge.texture == PLUS_ONE and badge.visible, "Both badges must immediately switch to +1.")
	_check(SaveManager.save_slot(2), "Save selected +1 mode.")
	mode_button.pressed.emit()
	_check(SaveManager.load_slot(2) and PrestigeManager.get_upgrade_mode() == 1, "Restore owned +1 mode from disk.")
	_check(SaveManager.load_slot(1) and PrestigeManager.get_upgrade_mode() == 5 and IncomeManager.get_source_level(SOURCE) == 6, "Restore owned +5 mode and the atomic upgrade snapshot.")
	# Drive each actual panel's purchase path; inspect the real sound stream.
	EconomyManager.money = 1e20
	view.toggle_upgrade_panel()
	_check(view._upgrade_source(), "Individual panel must buy five levels.")
	_check(IncomeManager.get_source_level(SOURCE) == 11, "Individual panel must advance by five.")
	_check(SoundManager._active_se_players.back().stream == SoundManager.INCOME_UPGRADE_SOUNDS[9], "At level 11 the sound must skip to index 9.")
	view.close_upgrade_panel()
	batch.panel.show()
	_check(batch._upgrade_source(SOURCE), "Batch panel must buy five levels.")
	_check(IncomeManager.get_source_level(SOURCE) == 16, "Batch panel must advance by five.")
	_check(SoundManager._active_se_players.back().stream == SoundManager.INCOME_UPGRADE_SOUNDS[14], "The next +5 purchase must skip five sound entries.")
	IncomeManager.source_levels[SOURCE] = 5000
	cost = IncomeManager.get_upgrade_cost(SOURCE)
	_check(cost is BIG, "Exercise scientific bulk prices.")
	EconomyManager.money = cost
	preview = IncomeManager.get_next_upgrade_cycle_payout(SOURCE)
	_check(IncomeManager.upgrade_source(SOURCE) and IncomeManager.get_source_level(SOURCE) == 5005, "BigNumber bulk purchase must apply five levels.")
	_check(BIG.compare(EconomyManager.money, 0.0) == 0 and BIG.compare(IncomeManager.get_source_cycle_payout(SOURCE), preview) == 0, "BigNumber price and preview must match purchase.")
	SaveManager._restore_progress(initial)
	_check(PrestigeManager.get_upgrade_mode() == 1 and buy.visible and not mode_column.visible, "Fresh slot must restore the unowned shop state.")
	for badge in badges:
		_check(not badge.visible, "Fresh slot must hide badges.")
	_check(ErrorManager.get_errors().is_empty(), "Valid bulk flows must not report game errors.")
	view.queue_free()
	batch.queue_free()
	shop.queue_free()
	await get_tree().create_timer(2.0).timeout
	if _failures.is_empty():
		print("PASS: bulk +5 ownership, switching, badges, atomic summed prices, previews, sound steps, BigNumber purchases and save slots")
	get_tree().quit(0 if _failures.is_empty() else 1)
