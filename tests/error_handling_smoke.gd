extends Node

var _failures: int = 0
var _unlock_events: int = 0
var _error_events: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	IncomeManager.set_process(false)
	_check(ErrorManager.get_errors().is_empty(), "Current game configuration produced startup errors")
	_test_jjam_unlock()
	_test_invalid_ids()
	_test_invalid_sources()
	_test_invalid_conditions()
	_test_scene_validation()
	_test_numeric_limits()
	_test_normal_rejections()
	await _test_bad_world()
	await _test_bad_ui()
	await _test_error_display()
	if _failures == 0:
		print("PASS: lifetime jjam unlocks, invalid/duplicate IDs, source data, dependency cycles, scene/UI guards, numeric limits and error display deduplication")
	get_tree().quit(0 if _failures == 0 else 1)


func _make_button(id: String) -> ButtonData:
	var button := ButtonData.new()
	button.id = id
	button.effect_type = ButtonData.EffectType.NONE
	return button


func _test_jjam_unlock() -> void:
	var button := _make_button("test_jjam_unlock")
	var condition := UnlockCondition.new()
	condition.type = UnlockCondition.Type.TOTAL_JJAM
	condition.amount = 5.0
	button.unlock_condition = condition
	ButtonManager.buttons.append(button)
	PrestigeManager.total_jjam = 4
	PrestigeManager.current_jjam = 999
	EconomyManager.reset_money()
	EconomyManager.add_money(1000000.0)
	_check(not ButtonManager.is_unlocked(button), "Pending jjam or money unlocked a lifetime-jjam condition")
	ButtonManager.button_unlock_changed.connect(_on_unlock_changed)
	_check(PrestigeManager.prestige(), "A valid prestige failed")
	_check(PrestigeManager.get_total_jjam() == 5, "Prestige did not accumulate lifetime jjam")
	_check(ButtonManager.is_unlocked(button) and _unlock_events == 1, "Prestige did not refresh the lifetime-jjam unlock")
	_check(ButtonManager.purchase(button), "A free jjam-gated button could not be purchased")
	_check(ErrorManager.get_errors().is_empty(), "A valid jjam unlock reported an error")
	ButtonManager.button_unlock_changed.disconnect(_on_unlock_changed)
	ButtonManager.buttons.erase(button)
	PrestigeManager.total_jjam = 0
	PrestigeManager.current_jjam = 0
	EconomyManager.set_global_multiplier(1.0)
	ButtonManager.reset_for_prestige()


func _on_unlock_changed(button: ButtonData) -> void:
	if button.id == "test_jjam_unlock":
		_unlock_events += 1


func _test_invalid_ids() -> void:
	ErrorManager.clear_errors()
	_check(ButtonManager.get_button("missing_button") == null, "Unknown button resolved to another button")
	_expect_error("MISSING_ID")
	ErrorManager.clear_errors()
	var original := ButtonManager.get_button("vending_machine")
	var duplicate := original.duplicate() as ButtonData
	ButtonManager.buttons.append(duplicate)
	EconomyManager.add_money(100.0)
	var balance := EconomyManager.money
	_check(ButtonManager.get_button(original.id) == null, "A duplicate ID selected an arbitrary resource")
	_check(not ButtonManager.purchase(original) and not ButtonManager.purchase(duplicate), "Duplicate IDs could be purchased")
	_check(EconomyManager.money == balance and not original.bought, "A duplicate purchase modified game state")
	_expect_error("DUPLICATE_ID")
	ButtonManager.buttons.erase(duplicate)
	ErrorManager.clear_errors()
	var empty := _make_button(" ")
	ButtonManager.buttons.append(empty)
	_check(not ButtonManager.purchase(empty), "An empty/whitespace ID was purchasable")
	_expect_error("INVALID_ID")
	ButtonManager.buttons.erase(empty)
	_check(not ErrorManager.validate_registry([null], "TestRegistry"), "A null registry entry was accepted")
	_expect_error("INVALID_RESOURCE")


func _test_invalid_sources() -> void:
	ErrorManager.clear_errors()
	var source := IncomeManager.sources[0]
	var duplicate := source.duplicate() as IncomeSourceData
	IncomeManager.sources.append(duplicate)
	IncomeManager.reset_runtime_state()
	IncomeManager.activate_source(source.id)
	_check(not IncomeManager.source_active.has(source.id), "A duplicate source ID initialized ambiguous runtime state")
	_expect_error("DUPLICATE_ID")
	IncomeManager.sources.erase(duplicate)
	ErrorManager.clear_errors()
	var broken := IncomeSourceData.new()
	broken.id = "test_invalid_source"
	broken.base_time = 0.0
	IncomeManager.sources.append(broken)
	IncomeManager.reset_runtime_state()
	_check(not IncomeManager.source_active.has(broken.id), "A zero production interval initialized runtime state")
	_expect_error("INVALID_NUMBER")
	IncomeManager.sources.erase(broken)
	IncomeManager.reset_runtime_state()


func _test_invalid_conditions() -> void:
	ErrorManager.clear_errors()
	var first := _make_button("test_cycle_a")
	var second := _make_button("test_cycle_b")
	for button in [first, second]:
		button.unlock_condition = UnlockCondition.new()
		button.unlock_condition.type = UnlockCondition.Type.BUTTON
		ButtonManager.buttons.append(button)
	first.unlock_condition.value = second.id
	second.unlock_condition.value = first.id
	_check(not ErrorManager.validate_button_graph(ButtonManager.buttons), "A dependency cycle was accepted")
	_check(not ButtonManager.is_unlocked(first) and not ButtonManager.purchase(first), "A cyclic condition could be purchased")
	_expect_error("UNLOCK_CYCLE")
	ButtonManager.buttons.erase(first)
	ButtonManager.buttons.erase(second)
	ErrorManager.clear_errors()
	var invalid := _make_button("test_invalid_condition")
	invalid.unlock_condition = UnlockCondition.new()
	invalid.unlock_condition.type = UnlockCondition.Type.TOTAL_JJAM
	invalid.unlock_condition.amount = 1.5
	ButtonManager.buttons.append(invalid)
	_check(not ButtonManager.is_unlocked(invalid), "A fractional jjam threshold was accepted")
	_expect_error("INVALID_JJAM_THRESHOLD")
	invalid.unlock_condition.set("type", 99)
	_check(not ButtonManager.is_unlocked(invalid), "An unknown unlock type was accepted")
	_expect_error("INVALID_UNLOCK_TYPE")
	invalid.unlock_condition = null
	invalid.set("effect_type", 99)
	_check(not ButtonManager.purchase(invalid), "An unknown effect type was accepted")
	_expect_error("INVALID_EFFECT_TYPE")
	ButtonManager.buttons.erase(invalid)


func _test_scene_validation() -> void:
	ErrorManager.clear_errors()
	var root := Node2D.new()
	add_child(root)
	for index in 2:
		var group := Node2D.new()
		root.add_child(group)
		var sprite := Sprite2D.new()
		sprite.name = "duplicate_world_id"
		group.add_child(sprite)
	_check(ErrorManager.find_world_element(root, "duplicate_world_id") == null, "Duplicate world names selected an arbitrary node")
	_expect_error("DUPLICATE_WORLD_ID")
	_check(ErrorManager.find_world_element(root, "missing_world_id") == null, "Missing world names were accepted")
	_expect_error("MISSING_WORLD_ID")
	_check(ErrorManager.require_node(root, ^"MissingLabel", "Label") == null, "A missing required node was accepted")
	_expect_error("MISSING_NODE")
	_check(ErrorManager.require_node(self, root.get_path(), "Label") == null, "A required node with the wrong class was accepted")
	_expect_error("INVALID_NODE_TYPE")
	var sprite := Sprite2D.new()
	sprite.name = "test_empty_texture"
	root.add_child(sprite)
	_check(not ErrorManager.validate_visuals(sprite, "TestSprite"), "A missing texture was accepted")
	_expect_error("MISSING_TEXTURE")
	sprite.transform = Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	_check(ErrorManager.find_world_element(root, String(sprite.name)) == null, "A singular world transform was accepted")
	_expect_error("INVALID_TRANSFORM")
	_check(not ErrorManager.validate_hover_areas(root, "TestHover"), "A missing hover area was accepted")
	_expect_error("MISSING_HOVER_AREA")
	var area := Area2D.new()
	area.name = "HoverArea"
	root.add_child(area)
	_check(not ErrorManager.validate_hover_areas(root, "TestHover"), "An empty collision area was accepted")
	_expect_error("MISSING_COLLISION_SHAPE")
	root.free()
	_check(not ErrorManager.validate_instance(root, "TestFreedObject"), "A freed instance was accepted")
	_expect_error("INVALID_INSTANCE")


func _test_numeric_limits() -> void:
	ErrorManager.clear_errors()
	EconomyManager.reset_money()
	EconomyManager.add_money(1.0e20)
	var balance := EconomyManager.money
	_check(not EconomyManager.spend_money(1.0) and EconomyManager.money == balance, "A purchase succeeded without actually spending money")
	_check(not EconomyManager.add_money(1.0), "An unrepresentable addition claimed success")
	_expect_error("PRECISION_LOSS")
	EconomyManager.reset_money()
	EconomyManager.add_money(1.0e45)
	balance = EconomyManager.money
	_check(not PrestigeManager.prestige() and EconomyManager.money == balance, "An overflowing prestige reset game state")
	_expect_error("JJAM_OVERFLOW")
	EconomyManager.reset_money()
	EconomyManager.add_money(1000000.0)
	PrestigeManager.total_jjam = PrestigeManager.MAX_JJAM
	_check(not PrestigeManager.prestige() and PrestigeManager.total_jjam == PrestigeManager.MAX_JJAM, "Lifetime jjam addition overflowed")
	PrestigeManager.total_jjam = 0
	SoundManager.play_se(null)
	_expect_error("INVALID_AUDIO")


func _test_normal_rejections() -> void:
	ButtonManager.reset_for_prestige()
	EconomyManager.reset_money()
	ErrorManager.clear_errors()
	_check(ButtonManager.purchase_by_id("vending_machine"), "The free starting purchase failed")
	_check(not ButtonManager.purchase_by_id("vending_machine"), "An already-purchased button was purchased twice")
	_check(not ButtonManager.purchase_by_id("trashbin"), "An unaffordable purchase succeeded")
	_check(not IncomeManager.upgrade_source("restaurant"), "An inactive source was upgraded")
	_check(not PrestigeManager.prestige(), "A prestige with no reward succeeded")
	_check(ErrorManager.get_errors().is_empty(), "Normal gameplay rejection displayed an error")
	ButtonManager.reset_for_prestige()


func _test_bad_world() -> void:
	ErrorManager.clear_errors()
	var main := load("res://scenes/main.tscn").instantiate() as Node2D
	main.get_node("World/WorldLayout/VendingMachine/vending_machine").name = "typo_vending_machine"
	get_tree().root.add_child(main)
	await get_tree().process_frame
	_check(not ButtonManager.purchase_by_id("vending_machine"), "A source with a missing world node could still be purchased")
	_expect_error("MISSING_WORLD_ID")
	main.queue_free()
	await get_tree().process_frame
	ButtonManager.set_world_invalid_buttons([])


func _test_bad_ui() -> void:
	ErrorManager.clear_errors()
	var panel := load("res://ui/income_upgrade_panel.tscn").instantiate() as IncomeUpgradePanel
	panel.get_node("Panel/Margin/VBox/List").free()
	add_child(panel)
	_check(panel.process_mode == Node.PROCESS_MODE_DISABLED and not panel.visible, "A broken UI component stayed active")
	_expect_error("MISSING_NODE")
	_expect_error("SCENE_INITIALIZATION")
	panel.queue_free()
	await get_tree().process_frame
	ErrorManager.clear_errors()
	var main := load("res://scenes/main.tscn").instantiate() as Node2D
	main.get_node("Camera2D").free()
	get_tree().root.add_child(main)
	_check(main.process_mode == Node.PROCESS_MODE_DISABLED, "A main scene without a camera stayed active")
	_expect_error("MISSING_NODE")
	main.queue_free()
	await get_tree().process_frame


func _test_error_display() -> void:
	ErrorManager.clear_errors()
	ErrorManager.error_reported.connect(_on_error_reported)
	for index in 100:
		ErrorManager.report_error("TEST_REPEAT", "반복 오류 표시 검증", "test_context")
	await get_tree().process_frame
	_check(ErrorManager.get_errors().size() == 1 and _error_events == 1, "Repeated errors flooded notifications/history")
	_check(ErrorManager.get_errors()[0].occurrences == 100, "Repeated errors lost their occurrence count")
	_check(ErrorManager._panel.visible and ErrorManager._details.text.contains("TEST_REPEAT"), "An error was not displayed with its code")
	_check(ErrorManager.layer > get_tree().root.get_node("TooltipManager").layer, "The error message appeared below other overlays")
	var copy := ErrorManager.get_errors()
	copy[0].message = "mutated"
	_check(ErrorManager.get_errors()[0].message != "mutated", "Error history could be modified by a caller")
	ErrorManager.dismiss_current()
	ErrorManager.report_error("TEST_REPEAT", "반복 오류 표시 검증", "test_context")
	_check(not ErrorManager._panel.visible, "An acknowledged repeating error reopened its popup")
	ErrorManager.report_error("TEST_NEXT", "새 오류 표시 검증", "next_context")
	_check(ErrorManager._panel.visible and ErrorManager._details.text.contains("TEST_NEXT"), "A distinct later error did not display")
	ErrorManager.error_reported.disconnect(_on_error_reported)
	for index in ErrorManager.MAX_ERRORS + 3:
		ErrorManager.report_error("TEST_CAP", "이력 한도 검증", "limit:%d" % index)
	_check(ErrorManager.get_errors().size() == ErrorManager.MAX_ERRORS, "Error history grew beyond its limit")
	_expect_error("ERROR_LIMIT")
	for index in ErrorManager.MAX_ERRORS:
		ErrorManager.dismiss_current()
	_check(not ErrorManager._panel.visible, "The queued error messages could not all be acknowledged")
	ErrorManager.clear_errors()


func _on_error_reported(_error: Dictionary) -> void:
	_error_events += 1


func _expect_error(code: String) -> void:
	for error in ErrorManager.get_errors():
		if error.code == code:
			return
	_check(false, "Expected error was not reported: " + code)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
