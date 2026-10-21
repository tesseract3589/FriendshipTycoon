extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const INITIAL_JJAM: int = 400
const MAX_JJAM: int = 9223372036854775807

signal prestige_changed()
signal jjam_changed()
signal jjam_unlocked_changed()
signal prestige_animation_requested()

@export_range(1.0, 1000000000000.0, 1.0, "or_greater") var money_per_jjam: float = 3300000000000.0
## Banked jjam only: each point adds this percentage to all income.
@export_range(0.0, 100.0, 0.01, "or_greater") var boost_per_jjam: float = 1.0

var jjam_unlocked: bool = false
var banked_jjam: Variant = 0
var live_jjam: Variant = 0
var total_jjam: Variant = 0
var initial_jjam_pending: bool = false
var prestige_count: int = 0
var transition_in_progress: bool = false
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
		earned = BIG.whole_count(BIG.divide(IncomeManager.get_jjam_earned_income(), money_per_jjam))
		if initial_jjam_pending:
			earned = _add_counts(earned, INITIAL_JJAM)
	live_jjam = earned
	total_jjam = _add_counts(banked_jjam, live_jjam)
	jjam_changed.emit()


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
		"jjam_system_version": 1,
		"jjam_unlocked": jjam_unlocked,
		"banked_jjam": BIG.serialize_count(banked_jjam),
		"live_jjam": BIG.serialize_count(live_jjam),
		"total_jjam": BIG.serialize_count(total_jjam),
		"initial_jjam_pending": initial_jjam_pending,
		"prestige_count": prestige_count,
	}


func restore_save_state(state: Dictionary) -> void:
	transition_in_progress = false
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
