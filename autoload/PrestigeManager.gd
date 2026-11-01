extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const INITIAL_JJAM: int = 400
const MAX_JJAM: int = 9223372036854775807
const SHOP_PRICE_DISTANCE_FACTOR: int = 10000
const DEFAULT_UPGRADE_ICON: Texture2D = preload("res://assets/sprites/Interfaces/plus_1.png")

signal prestige_changed()
signal jjam_changed()
signal jjam_unlocked_changed()
signal prestige_animation_requested()
signal shop_changed()
signal upgrade_mode_changed()

@export var shop_items: Array[JjamShopItemData] = [
	preload("res://data/jjam_shop/batch_upgrade_panel.tres"),
	preload("res://data/jjam_shop/bulk_upgrade_5.tres"),
	preload("res://data/jjam_shop/bulk_upgrade_25.tres"),
]

@export_range(1.0, 1000000000000.0, 1.0, "or_greater") var money_per_jjam: float = 12000000000.0
## 이번 회차의 실시간 짬 400 → 800 → 1,600마다 적용할 획득 난이도 계수.
@export var jjam_growth: Resource = preload("res://data/balance/jjam_growth.tres")
## Banked jjam only: each point adds this percentage to all income.
@export_range(0.0, 100.0, 0.01, "or_greater") var boost_per_jjam: float = 1.0

var jjam_unlocked: bool = false
var banked_jjam: Variant = 0
var live_jjam: Variant = 0
var total_jjam: Variant = 0
var initial_jjam_pending: bool = false
var prestige_count: int = 0
var transition_in_progress: bool = false
var _shop_purchases: Dictionary = {}
var _upgrade_mode: int = 1
# Compatibility for callers using the former name of the unbanked amount.
var current_jjam: Variant:
	get:
		return get_current_jjam()
	set(value):
		live_jjam = value
		total_jjam = _add_counts(banked_jjam, live_jjam)


func _ready() -> void:
	IncomeManager.cumulative_income_changed.connect(refresh_jjam)


func on_button_purchased(button: ButtonData) -> void:
	if button.id == "jjamtong":
		unlock_jjam()


func unlock_jjam() -> void:
	if jjam_unlocked:
		return
	jjam_unlocked = true
	initial_jjam_pending = true
	IncomeManager.reset_jjam_income()
	refresh_jjam()
	jjam_unlocked_changed.emit()


func refresh_jjam() -> void:
	var earned: Variant = 0
	if jjam_unlocked:
		earned = BIG.whole_count(_calculate_live_jjam())
	live_jjam = earned
	total_jjam = _add_counts(banked_jjam, live_jjam)
	jjam_changed.emit()


func _calculate_live_jjam() -> Variant:
	var income: Variant = IncomeManager.get_jjam_earned_income()
	var starting_live: int = INITIAL_JJAM if initial_jjam_pending else 0
	# Banked jjam boosts production, while only this run's live jjam sets its
	# earning difficulty. Prestige restarts the curve from zero every time.
	return BIG.add(starting_live, jjam_growth.get_earned_jjam(income, starting_live, INITIAL_JJAM, money_per_jjam))


func get_prestige_multiplier() -> Variant:
	if not has_prestiged():
		return 1.0
	return BIG.add(1.0, BIG.multiply(banked_jjam, boost_per_jjam * 0.01))


func get_total_jjam() -> Variant:
	return total_jjam


func get_current_jjam() -> Variant:
	return live_jjam


func has_prestiged() -> bool:
	return prestige_count > 0


func can_prestige() -> bool:
	return jjam_unlocked and BIG.compare(live_jjam, 0) > 0 and not transition_in_progress


func get_shop_item(item_id: String) -> JjamShopItemData:
	for item in shop_items:
		if item != null and item.id == item_id:
			return item
	return null


func owns_shop_item(item_id: String) -> bool:
	return _shop_purchases.get(item_id, false)


func get_shop_display_item(root_item_id: String) -> JjamShopItemData:
	var item := get_shop_item(root_item_id)
	var visited: Dictionary = {}
	while item != null and owns_shop_item(item.id) and not item.next_item_id.is_empty():
		if visited.has(item.id):
			break
		visited[item.id] = true
		var next_item := get_shop_item(item.next_item_id)
		if next_item == null:
			break
		item = next_item
	return item


## Shared by every shop price, including future items and chained successors.
func is_shop_price_distant(item_id: String) -> bool:
	var item := get_shop_item(item_id)
	if item == null or owns_shop_item(item_id):
		return false
	var available: Variant = BIG.add(banked_jjam, live_jjam)
	return BIG.compare(BIG.multiply(available, SHOP_PRICE_DISTANCE_FACTOR), item.get_price()) < 0


func is_feature_unlocked(feature_id: StringName) -> bool:
	for item in shop_items:
		if item != null and item.feature_id == feature_id and owns_shop_item(item.id):
			return true
	return false


func can_purchase_shop_item(item_id: String) -> bool:
	var item := get_shop_item(item_id)
	if item == null:
		return false
	var price: Variant = item.get_price()
	return BIG.valid(price, false) and BIG.compare(price, BIG.floored(price)) == 0 and jjam_unlocked and not transition_in_progress \
		and (item.prerequisite_item_id.is_empty() or owns_shop_item(item.prerequisite_item_id)) \
		and not owns_shop_item(item_id) and BIG.compare(banked_jjam, price) >= 0


func get_available_upgrade_modes() -> Array[int]:
	var modes: Array[int] = [1]
	for item in shop_items:
		if item != null and item.upgrade_levels > 1 and owns_shop_item(item.id) and not modes.has(item.upgrade_levels):
			modes.append(item.upgrade_levels)
	modes.sort()
	return modes


func get_upgrade_mode() -> int:
	return _upgrade_mode if get_available_upgrade_modes().has(_upgrade_mode) else 1


func get_next_upgrade_mode() -> int:
	var modes := get_available_upgrade_modes()
	return modes[(modes.find(get_upgrade_mode()) + 1) % modes.size()]


func get_upgrade_mode_icon() -> Texture2D:
	var mode := get_upgrade_mode()
	if mode == 1:
		return DEFAULT_UPGRADE_ICON
	for item in shop_items:
		if item != null and item.upgrade_levels == mode and owns_shop_item(item.id):
			return item.icon
	return DEFAULT_UPGRADE_ICON


func toggle_upgrade_mode() -> void:
	if EventManager.presentation_locked or transition_in_progress:
		return
	_upgrade_mode = get_next_upgrade_mode()
	upgrade_mode_changed.emit()


func purchase_shop_item(item_id: String) -> bool:
	if EventManager.presentation_locked or not can_purchase_shop_item(item_id):
		return false
	var item := get_shop_item(item_id)
	# Commit payment and ownership before any synchronous UI/save callbacks run.
	banked_jjam = BIG.whole_count(BIG.subtract(banked_jjam, item.get_price()))
	_shop_purchases[item_id] = true
	if item.upgrade_levels > 1:
		_upgrade_mode = item.upgrade_levels
	total_jjam = _add_counts(banked_jjam, live_jjam)
	shop_changed.emit()
	if item.upgrade_levels > 1:
		upgrade_mode_changed.emit()
	jjam_changed.emit()
	EconomyManager.multiplier_changed.emit()
	return true


func request_prestige() -> bool:
	if not can_prestige():
		return false
	transition_in_progress = true
	prestige_animation_requested.emit()
	return true


## The presentation calls this only when the screen has faded to black.
func jjam_prestige() -> bool:
	if not jjam_unlocked or BIG.compare(live_jjam, 0) <= 0:
		return false
	EventManager.prepare_for_prestige()
	banked_jjam = _add_counts(banked_jjam, live_jjam)
	initial_jjam_pending = false
	prestige_count += 1
	IncomeManager.reset_jjam_income()
	refresh_jjam()
	EconomyManager.reset_money()
	EconomyManager.set_global_multiplier(1.0)
	ButtonManager.reset_for_prestige()
	prestige_changed.emit()
	return true


func prestige() -> bool:
	return jjam_prestige()


func _add_counts(first: Variant, second: Variant) -> Variant:
	if first is int and second is int and first <= MAX_JJAM - second:
		return first + second
	return BIG.whole_count(BIG.add(first, second))


func get_save_state() -> Dictionary:
	return {
		"jjam_system_version": 2,
		"jjam_unlocked": jjam_unlocked,
		"banked_jjam": BIG.serialize_count(banked_jjam),
		"live_jjam": BIG.serialize_count(live_jjam),
		"total_jjam": BIG.serialize_count(total_jjam),
		"initial_jjam_pending": initial_jjam_pending,
		"prestige_count": prestige_count,
		# Kept for version-2 save compatibility; banked spending no longer affects growth.
		"growth_spending": [],
		"shop_purchases": _shop_purchases.duplicate(),
		"upgrade_mode": get_upgrade_mode(),
	}


func restore_save_state(state: Dictionary) -> void:
	transition_in_progress = false
	_shop_purchases = state.get("shop_purchases", {}).duplicate()
	var modes := get_available_upgrade_modes()
	_upgrade_mode = state.get("upgrade_mode", modes.back())
	if not modes.has(_upgrade_mode):
		_upgrade_mode = 1
	# Keep ownership when loading saves made before this shop item was renamed.
	if _shop_purchases.has("income_upgrade_panel"):
		_shop_purchases["batch_upgrade_panel"] = _shop_purchases.get("batch_upgrade_panel", false) or _shop_purchases["income_upgrade_panel"]
		_shop_purchases.erase("income_upgrade_panel")
	if state.has("jjam_system_version"):
		jjam_unlocked = state.jjam_unlocked
		banked_jjam = BIG.deserialize(state.banked_jjam)
		initial_jjam_pending = state.initial_jjam_pending
		prestige_count = state.prestige_count
		if prestige_count == 0:
			banked_jjam = 0
	else:
		# Discard both kinds of old jjam and remove the old embedded 1% income bonus.
		var old_banked: Variant = BIG.deserialize(state.total_jjam)
		var old_boost: Variant = BIG.add(1.0, BIG.multiply(old_banked, 0.01))
		EconomyManager.global_multiplier = BIG.divide(EconomyManager.global_multiplier, old_boost)
		banked_jjam = 0
		prestige_count = 0
		var bin := ButtonManager.get_button("jjamtong")
		jjam_unlocked = bin != null and bin.bought
		initial_jjam_pending = jjam_unlocked
	refresh_jjam()
	jjam_unlocked_changed.emit()
	shop_changed.emit()
	upgrade_mode_changed.emit()
