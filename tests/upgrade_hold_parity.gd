extends Node

const SOURCE := "vending_machine"
const VIEW_SCENE = preload("res://ui/income_source_view.tscn")
const BATCH_SCENE = preload("res://ui/batch_upgrade_panel.tscn")
const BIG = preload("res://scripts/BigNumber.gd")
const FIXTURES = preload("res://tests/TestFixtures.gd")

var _failures: Array[String] = []
var _subject: Node
var _panel: Control
var _button: TextureButton
var _kind: String


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	FIXTURES.prepare_viewport(self)
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	_check(FIXTURES.unlock_batch_upgrade(), "Both views must run after the real batch feature is unlocked.")
	IncomeManager.activate_source(SOURCE)
	for kind in ["individual", "batch"]:
		_kind = kind
		IncomeManager.source_levels[SOURCE] = 1
		_set_money(0.0)
		if kind == "individual":
			var view := VIEW_SCENE.instantiate() as IncomeSourceView
			view.setup(IncomeManager.get_source(SOURCE), Vector2.ZERO, Vector2.ONE, Rect2(100, 100, 40, 40))
			add_child(view)
			view.toggle_upgrade_panel()
			_subject = view
			_panel = view.upgrade_panel
			_button = view.upgrade_button
		else:
			var batch := BATCH_SCENE.instantiate() as BatchUpgradePanel
			add_child(batch)
			batch.panel.show()
			_subject = batch
			_panel = batch.panel
			_button = batch.list.get_child(0).get_node("Purchase/Upgrade")
		_subject.set_process(false)
		await _settle()
		_test_waiting_and_speed()
		await _settle()
		_test_large_price()
		await _settle()
		_test_release_and_close()
		_subject.queue_free()
		await _settle()
	_check(ErrorManager.get_errors().is_empty(), "Valid hold interactions must not report game errors.")
	await get_tree().create_timer(2.0).timeout
	if _failures.is_empty():
		print("PASS: identical individual/batch holds: initially unaffordable, new income, cooldown, accelerated speed after starvation, no catch-up burst, release/close, and BigNumber prices")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_waiting_and_speed() -> void:
	_check(not _button.disabled and _button.modulate == Color(0.55, 0.55, 0.55), "An unaffordable button must accept a hold and be shaded.")
	_mouse_button(_button.get_global_rect().get_center(), true)
	_step(1.0)
	_check(_level() == 1, "Holding without funds must not purchase.")
	_set_money(IncomeManager.get_upgrade_cost(SOURCE))
	_step(0.001)
	_check(_level() == 2, "New income must purchase on the next frame when ready.")
	_set_money(1e20)
	_step(0.39)
	_check(_level() == 2, "Incoming money must respect the pending cooldown.")
	_step(0.011)
	_check(_level() == 3, "The first repeat must retain the initial delay.")
	_step(0.329)
	_check(_level() == 4, "Repeats must accelerate identically.")
	for repeat in range(12):
		_step(1.0)
	var level := _level()
	_set_money(0.0)
	_step(10.0)
	_step(1.0)
	_check(_level() == level, "Waiting without funds must not purchase or cancel the hold.")
	_set_money(IncomeManager.get_upgrade_cost(SOURCE))
	_step(0.001)
	_check(_level() == level + 1 and BIG.compare(EconomyManager.money, 0.0) == 0, "A long wait must resume with exactly one paid purchase.")
	_set_money(1e20)
	_step(0.03)
	_check(_level() == level + 1, "Funding must not bypass the preserved cooldown.")
	_step(0.031)
	_check(_level() == level + 2, "The accelerated 0.06 second interval must survive a long shortage.")
	_mouse_button(_panel.get_global_rect().end + Vector2(40, 40), false)


func _test_release_and_close() -> void:
	var funds: Variant = BIG.multiply(IncomeManager.get_upgrade_cost(SOURCE), 1000.0)
	_set_money(0.0)
	_mouse_button(_button.get_global_rect().get_center(), true)
	_step(1.0)
	_mouse_button(_panel.get_global_rect().end + Vector2(40, 40), false)
	var level := _level()
	_set_money(funds)
	_step(1.0)
	_check(_level() == level, "Releasing outside while waiting must prevent purchases when income arrives.")
	_set_money(0.0)
	_mouse_button(_button.get_global_rect().get_center(), true)
	_step(1.0)
	_panel.hide()
	_step(0.001)
	_panel.show()
	if _subject is BatchUpgradePanel:
		_button = _subject.list.get_child(0).get_node("Purchase/Upgrade")
	_set_money(funds)
	_step(1.0)
	_check(_level() == level, "Closing and reopening while waiting must cancel the hold.")
	_mouse_button(_button.get_global_rect().get_center(), false)


func _test_large_price() -> void:
	_set_money(0.0)
	_mouse_button(_button.get_global_rect().get_center(), true)
	IncomeManager.source_levels[SOURCE] = 5000
	IncomeManager.source_level_changed.emit(SOURCE, 5000)
	_step(1.0)
	var price: Variant = IncomeManager.get_upgrade_cost(SOURCE)
	_check(price is BIG, "The large-price fixture must use BigNumber.")
	_set_money(price)
	_step(0.001)
	_check(_level() == 5001 and BIG.compare(EconomyManager.money, 0.0) == 0, "A waiting hold must use incoming BigNumber funds exactly once.")
	_mouse_button(_panel.get_global_rect().end + Vector2(40, 40), false)


func _step(delta: float) -> void:
	_subject.call("_process", delta)


func _level() -> int:
	return IncomeManager.get_source_level(SOURCE)


func _set_money(value: Variant) -> void:
	EconomyManager.money = value
	EconomyManager.money_changed.emit(value)


func _settle() -> void:
	for frame in range(4):
		await get_tree().process_frame


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	motion.button_mask = 0 if pressed else MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [_kind, message])
		push_error(_failures.back())
