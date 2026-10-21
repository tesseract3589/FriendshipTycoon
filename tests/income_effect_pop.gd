extends Node

const WORLD_LAYOUT: PackedScene = preload("res://scenes/world_layout.tscn")
const BUTTON_LAYOUT: PackedScene = preload("res://scenes/button_layout.tscn")
const MOTION = preload("res://scripts/SizePopMotion.gd")

var _failures: Array[String] = []
var _views: Dictionary = {}
var _base_scales: Dictionary = {}
var _source_ids: Array[String] = []
var _fixture_count: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	# Use real layouts and successful purchases, without initializing player saves.
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	EconomyManager.money = 1e12
	var world := WORLD_LAYOUT.instantiate() as Node2D
	var buttons := BUTTON_LAYOUT.instantiate()
	add_child(world)
	add_child(buttons)
	world.hide()
	for source in IncomeManager.sources:
		var data := ButtonManager.get_button(source.id)
		data.bought = false
		data.permanent_bought = false
		data.price = 0.0
		data.large_price = ""
		data.unlock_condition = null
		var layout := ErrorManager.find_world_element(world, source.id)
		var ui_layout := ErrorManager.find_world_element(buttons.get_node("Buttons"), source.id)
		var view := WorldPurchaseButton.new()
		view.setup(data, layout, [], ui_layout)
		add_child(view)
		_views[source.id] = view
		_source_ids.append(source.id)
		var scales: Array[Vector2] = []
		for visual in view.purchased_visuals:
			scales.append(visual.scale)
		_base_scales[source.id] = scales
	_check(_source_ids.size() >= 2, "The fixture needs distinct visible and unpurchased sources.")
	var active: Array[String] = []
	for index in range(_source_ids.size() - 1):
		var id := _source_ids[index]
		_check(ButtonManager.purchase(ButtonManager.get_button(id)), "Source purchase must succeed: " + id)
		active.append(id)
	_finish_all()
	var target := _source_ids[0]
	_purchase_effect(ButtonData.EffectType.SOURCE_MULTIPLIER, target)
	_expect_pulsing([target])
	var visual := (_views[target] as WorldPurchaseButton).purchased_visuals[0]
	var tween := _get_tween(visual)
	tween.custom_step(0.1)
	_check(visual.scale.x > _base_scales[target][0].x, "An applied multiplier must visibly enlarge its source.")
	tween.custom_step(0.199)
	_check(visual.has_meta(MOTION.TWEEN_METADATA), "The pulse must last for the full 0.3 seconds.")
	tween.custom_step(0.002)
	_expect_restored()
	_purchase_effect(ButtonData.EffectType.SOURCE_SPEED_MULTIPLIER, target)
	_expect_pulsing([target])
	_finish_all()
	for global_effect in [ButtonData.EffectType.GLOBAL_MULTIPLIER, ButtonData.EffectType.GLOBAL_TIME_MULTIPLIER]:
		_purchase_effect(global_effect)
		_expect_pulsing(active)
		_finish_all()
	_purchase_effect(ButtonData.EffectType.NONE)
	_expect_pulsing([])
	_purchase_effect(ButtonData.EffectType.SOURCE_MULTIPLIER, target, 1.0)
	_expect_pulsing([])
	EconomyManager.money = 0.0
	_purchase_effect(ButtonData.EffectType.GLOBAL_MULTIPLIER, "", 2.0, false)
	_expect_pulsing([])
	EconomyManager.money = 1e12
	# Mix source/global effects while each previous tween is partway through its rise.
	for index in range(40):
		var previous := _get_tween(visual)
		var visible_scale := visual.scale
		var effect: ButtonData.EffectType = ButtonData.EffectType.SOURCE_MULTIPLIER if index % 2 == 0 else ButtonData.EffectType.GLOBAL_TIME_MULTIPLIER
		_purchase_effect(effect, target)
		_check(visual.scale.is_equal_approx(visible_scale), "Retriggering must preserve the current visible size.")
		if previous != null:
			_check(not previous.is_valid(), "Retriggering must kill the previous tween.")
		_get_tween(visual).custom_step(0.06)
		for id in _source_ids:
			var view := _views[id] as WorldPurchaseButton
			for part in range(view.purchased_visuals.size()):
				var item := view.purchased_visuals[part]
				var base: Vector2 = _base_scales[id][part]
				_check(item.scale.x <= base.x * 1.12, "Rapid effects must not accumulate scale.")
	_finish_all()
	_expect_restored()
	# Global effects may interrupt the source's own initial purchase animation.
	var last_id: String = _source_ids.back()
	_check(ButtonManager.purchase(ButtonManager.get_button(last_id)), "The final source must become active.")
	var last_visual := (_views[last_id] as WorldPurchaseButton).purchased_visuals[0]
	_get_tween(last_visual).custom_step(0.03)
	_purchase_effect(ButtonData.EffectType.GLOBAL_MULTIPLIER)
	_expect_pulsing(_source_ids)
	_finish_all()
	_expect_restored()
	# Normal scene-tree processing must also finish and restore the exact size.
	_purchase_effect(ButtonData.EffectType.SOURCE_MULTIPLIER, target)
	for frame in range(3):
		await get_tree().process_frame
	_check(visual.scale.x > _base_scales[target][0].x, "The actual frame loop must run the scale tween.")
	await get_tree().create_timer(0.35).timeout
	_expect_restored()
	_purchase_effect(ButtonData.EffectType.GLOBAL_MULTIPLIER)
	_get_tween(visual).custom_step(0.06)
	ButtonManager.reset_for_prestige()
	_expect_restored()
	_expect_pulsing([])
	_check(ButtonManager.purchase(ButtonManager.get_button(target)), "A reset source must be purchasable again.")
	_finish_all()
	_expect_restored()
	for view: WorldPurchaseButton in _views.values():
		view.queue_free()
	world.queue_free()
	buttons.queue_free()
	await get_tree().process_frame
	_check(ErrorManager.get_errors().is_empty(), "Valid scale effects must not report errors.")
	_check(not SaveManager.initialized, "The test must not touch player saves.")
	if _failures.is_empty():
		print("PASS: targeted/global income and speed effects, 0.3s duration, 40 rapid interruptions, initial purchase overlap, live frames and reset/rebuy scale restoration")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _purchase_effect(kind: ButtonData.EffectType, target: String = "", factor: float = 2.0, succeeds: bool = true) -> void:
	_fixture_count += 1
	var effect := ButtonData.new()
	effect.id = "test_pop_%d" % _fixture_count
	effect.button_name = effect.id
	effect.price = 1.0
	effect.effect_type = kind
	effect.effect_target = target
	effect.effect_value = factor
	ButtonManager.buttons.append(effect)
	_check(ButtonManager.purchase(effect) == succeeds, "Effect purchase result: " + effect.id)


func _get_tween(visual: Node2D) -> Tween:
	return visual.get_meta(MOTION.TWEEN_METADATA) as Tween if visual.has_meta(MOTION.TWEEN_METADATA) else null


func _expect_pulsing(ids: Array[String]) -> void:
	for id in _source_ids:
		var view := _views[id] as WorldPurchaseButton
		for visual in view.purchased_visuals:
			_check(visual.has_meta(MOTION.TWEEN_METADATA) == ids.has(id), "Only the intended active sources must pulse: " + id)


func _finish_all() -> void:
	for view: WorldPurchaseButton in _views.values():
		for visual in view.purchased_visuals:
			var tween := _get_tween(visual)
			if tween != null:
				tween.custom_step(1.0)


func _expect_restored() -> void:
	for id in _source_ids:
		var view := _views[id] as WorldPurchaseButton
		for index in range(view.purchased_visuals.size()):
			var visual := view.purchased_visuals[index]
			_check(visual.scale.is_equal_approx(_base_scales[id][index]), "Scale must return to its original value: " + id)
			_check(not visual.has_meta(MOTION.SCALE_METADATA) and not visual.has_meta(MOTION.TWEEN_METADATA), "Finished/reset motion must release its tween and baseline: " + id)
