extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const FIXTURES = preload("res://tests/TestFixtures.gd")
const SOURCE := "vending_machine"
const PLUS_25 = preload("res://assets/sprites/Interfaces/plus_25.png")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _set_jjam(banked: Variant, live: Variant = 0) -> void:
	PrestigeManager.banked_jjam = banked
	PrestigeManager.live_jjam = live
	PrestigeManager.jjam_changed.emit()


func _run() -> void:
	FIXTURES.prepare_viewport(self)
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	_check(SaveManager.initialize(ProjectSettings.globalize_path("res://.godot/shop_progression_%d" % Time.get_ticks_usec())), "Use isolated save files.")
	var initial := SaveManager._create_initial_progress()
	PrestigeManager.unlock_jjam()
	_check(PrestigeManager.jjam_prestige(), "Bank the initial jjam.")
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var shop := preload("res://ui/jjam_prestige_panel.tscn").instantiate() as JjamPrestigePanel
	layer.add_child(shop)
	shop.show()
	shop._select_tab(true)
	var first_buy: TextureButton = shop._shop_buttons["batch_upgrade_panel"]
	var first_price := first_buy.get_parent().get_node("Price") as Label
	var buy: TextureButton = shop._shop_buttons["bulk_upgrade_5"]
	var price := buy.get_parent().get_node("Price") as Label
	var row: Dictionary = shop._shop_rows["bulk_upgrade_5"]
	var bulk_price: Variant = PrestigeManager.get_shop_item("bulk_upgrade_25").get_price()
	_check(BIG.compare(bulk_price, BIG.parse("2.5e17")) == 0, "The +25 resource must override its price to 25 gyeong jjam.")
	_check(shop.shop_list.get_child_count() == 2, "The successor must reuse the bulk card, not create a third card.")
	_check(first_price.text == "100짬", "A nearby first item must display its price.")
	_set_jjam(0)
	_check(first_price.text == "???짬", "A positive price must be hidden with no current or live jjam.")
	_set_jjam(0, 1)
	_check(first_price.text == "100짬", "Include live jjam when revealing an ordinary price.")
	_set_jjam(100)
	_check(PrestigeManager.purchase_shop_item("batch_upgrade_panel"), "Buy the first item.")
	_check(first_price.text == "구매 완료" and first_buy.get_parent().get_node_or_null("Purchased") == null, "Replace the price with ownership and remove the separate purchased label.")
	_set_jjam(bulk_price)
	_check(not PrestigeManager.purchase_shop_item("bulk_upgrade_25"), "The successor cannot be bought before +5, even with enough jjam.")
	_set_jjam(400)
	buy.pressed.emit()
	_check(shop._pending_shop_item == "bulk_upgrade_5", "The initial button must request +5.")
	shop._confirm_action()
	_check(PrestigeManager.owns_shop_item("bulk_upgrade_5") and PrestigeManager.get_upgrade_mode() == 5, "The real confirmation must buy +5.")
	_check(row.title.text == "25레벨씩 업그레이드" and row.icon.texture == PLUS_25, "Replace the card name and icon with +25.")
	_check(row.mode.visible and buy.visible and price.visible, "Mode switch and successor BUY/price must coexist.")
	_check(price.text == "???짬", "Distant successor price must be masked.")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(row.mode_button.get_global_rect().end.x <= buy.get_global_rect().position.x, "The mode switch must push BUY to its right.")
	price.mouse_entered.emit()
	_check(TooltipManager._panel.visible and TooltipManager._label.text == "감히 넘볼 수 없는 짬입니다...", "Hover must show the exact text through TooltipManager.")
	_check(TooltipManager.layer > layer.layer and price.tooltip_text.is_empty(), "The managed tooltip must render above the shop without a native tooltip.")
	price.mouse_exited.emit()
	_check(not TooltipManager._panel.visible, "Leaving the price must hide its tooltip.")
	price.mouse_entered.emit()
	shop._select_tab(false)
	_check(not TooltipManager._panel.visible, "Changing tabs must clear the shop tooltip.")
	shop._select_tab(true)
	price.mouse_entered.emit()
	var half_reveal_threshold: Variant = BIG.divide(bulk_price, 20000)
	_set_jjam(half_reveal_threshold)
	_check(price.text == "???짬", "Mask the overridden +25 price below the reveal threshold.")
	_set_jjam(half_reveal_threshold, half_reveal_threshold)
	_check(price.text == "25경짬" and not TooltipManager._panel.visible, "Reveal the overridden price at the exact boundary, including live jjam.")
	_set_jjam(BIG.subtract(BIG.divide(bulk_price, 10000), 1))
	_check(price.text == "???짬", "Hide immediately below one ten-thousandth of the price.")
	for balance: String in ["4.975e16", "4.9057e16"]:
		_set_jjam(BIG.parse(balance))
		_check(price.text == "25경짬" and buy.disabled, "A roughly five-gyeong balance must reveal 25 gyeong without enabling purchase.")
	_set_jjam(BIG.multiply(bulk_price, 0.5))
	_check(not PrestigeManager.purchase_shop_item("bulk_upgrade_25"), "The native fallback price must not bypass the overridden price.")
	_set_jjam(bulk_price)
	buy.pressed.emit()
	_check(shop._pending_shop_item == "bulk_upgrade_25", "The same BUY button must now request +25.")
	_check(shop.confirmation_question.text.begins_with("25경짬") and shop.confirmation_hint.visible, "Confirmation and high-spend warning must use the overridden price.")
	shop._confirm_action()
	_check(PrestigeManager.banked_jjam == 0 and PrestigeManager.get_upgrade_mode() == 25, "Charge 25 gyeong jjam and immediately select +25.")
	_check(price.text == "구매 완료" and buy.disabled and row.mode_button.texture_normal == PLUS_25, "Final ownership must replace the price while retaining the mode switch.")
	row.mode_button.pressed.emit()
	_check(PrestigeManager.get_upgrade_mode() == 1, "Cycle +25 to +1.")
	row.mode_button.pressed.emit()
	_check(PrestigeManager.get_upgrade_mode() == 5, "Cycle +1 to +5.")
	row.mode_button.pressed.emit()
	_check(PrestigeManager.get_upgrade_mode() == 25, "Cycle +5 to +25.")
	IncomeManager.activate_source(SOURCE)
	var view := preload("res://ui/income_source_view.tscn").instantiate() as IncomeSourceView
	view.setup(IncomeManager.get_source(SOURCE), Vector2.ZERO, Vector2.ONE, Rect2(100, 100, 40, 40))
	add_child(view)
	_check(view.upgrade_button.get_node("UpgradeModeBadge").texture == PLUS_25, "Upgrade buttons must show the +25 badge.")
	var source := IncomeManager.get_source(SOURCE)
	var expected_cost: Variant = 0.0
	for level in range(1, 26):
		expected_cost = BIG.add(expected_cost, BIG.rounded(IncomeManager._get_upgrade_cost_at_level(source, level)))
	_check(BIG.compare(IncomeManager.get_upgrade_cost(SOURCE), expected_cost) == 0, "The +25 cost must sum 25 single-level prices.")
	EconomyManager.money = expected_cost
	var preview: Variant = IncomeManager.get_next_upgrade_cycle_payout(SOURCE)
	view.toggle_upgrade_panel()
	_check(view._upgrade_source() and IncomeManager.get_source_level(SOURCE) == 26, "The panel must purchase 25 levels in one action.")
	_check(BIG.compare(EconomyManager.money, 0) == 0 and BIG.compare(IncomeManager.get_source_cycle_payout(SOURCE), preview) == 0, "The +25 charge and preview must match the purchase.")
	_check(SoundManager._active_se_players.back().stream == SoundManager.INCOME_UPGRADE_SOUNDS[24], "The +25 sound must use the destination level.")
	_check(SaveManager.save_slot(1), "Save +25 ownership and mode.")
	SaveManager._restore_progress(initial)
	_check(row.title.text == "5레벨씩 업그레이드" and not row.mode.visible, "A fresh slot must restore the original card.")
	_check(SaveManager.load_slot(1) and PrestigeManager.get_upgrade_mode() == 25, "Restore +25 mode from disk.")
	_check(row.title.text == "25레벨씩 업그레이드" and price.text == "구매 완료", "Restore the evolved card and purchased display.")
	# A future unrelated resource uses the same price rule without UI branches.
	var future := JjamShopItemData.new()
	future.id = "future_price_fixture"
	future.price = 7
	PrestigeManager.shop_items.append(future)
	_set_jjam(BIG.power_of_ten(400))
	_check(not PrestigeManager.is_shop_price_distant(future.id), "Scientific jjam totals must use BigNumber-safe comparisons.")
	_set_jjam(0)
	_check(PrestigeManager.is_shop_price_distant(future.id), "Apply the rule to an unrelated future item.")
	_set_jjam(0, 1)
	_check(not PrestigeManager.is_shop_price_distant(future.id), "Live jjam must also reveal a nearby future item.")
	for empty: String in ["", " \t "]:
		future.large_price = empty
		_check(future.get_price() == 7, "An empty override must preserve the native price.")
	future.large_price = " 1.25e400 "
	_check(future.get_price() is BIG, "Prices beyond float range must remain BigNumber values.")
	_set_jjam(BIG.parse("1e400"))
	_check(not PrestigeManager.purchase_shop_item(future.id), "Insufficient scientific jjam must reject the overridden price.")
	_set_jjam(BIG.parse("6.25e395"))
	_check(PrestigeManager.is_shop_price_distant(future.id), "Scientific price overrides remain masked below one ten-thousandth.")
	_set_jjam(BIG.parse("6.25e395"), BIG.parse("6.25e395"))
	_check(not PrestigeManager.is_shop_price_distant(future.id), "Scientific price overrides must drive the reveal threshold.")
	_set_jjam(BIG.parse("2e400"))
	_check(not PrestigeManager.is_shop_price_distant(future.id) and PrestigeManager.purchase_shop_item(future.id), "An affordable scientific price must be visible and purchasable.")
	_check(BIG.compare(PrestigeManager.banked_jjam, BIG.parse("7.5e399")) == 0, "Deduct the actual scientific price without native conversion.")
	_check(SaveManager.save_slot(2), "Save the scientific balance left by the shop purchase.")
	_set_jjam(0)
	_check(SaveManager.load_slot(2) and BIG.compare(PrestigeManager.banked_jjam, BIG.parse("7.5e399")) == 0, "Restore the scientific shop balance from disk.")
	for invalid: String in ["invalid", "0", "-1e400", "1.5", "1e1000000001"]:
		future.id = "invalid_price_fixture"
		future.large_price = invalid
		_check(not PrestigeManager.can_purchase_shop_item(future.id), "Reject invalid or fractional jjam prices: " + invalid)
	PrestigeManager.shop_items.erase(future)
	_check(ErrorManager.get_errors().is_empty(), "Valid shop progression must not report game errors.")
	view.queue_free()
	shop.queue_free()
	await get_tree().create_timer(2.0).timeout
	if _failures.is_empty():
		print("PASS: chained +25 shop, inline ownership, generic hidden prices, TooltipManager hover, modes, payments, previews, audio and save slots")
	get_tree().quit(0 if _failures.is_empty() else 1)
