extends Node

const BIG = preload("res://scripts/BigNumber.gd")
const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const PHONE_DM_ID: String = "phone_dm"
const CAMERA_TUTORIAL_ID: String = "camera_tutorial"
const INCOME_UPGRADE_TUTORIAL_ID: String = "income_upgrade_tutorial"
const JJAM_SHOP_TUTORIAL_ID: String = "jjam_shop_tutorial"
const CAT_WATCHING_ID: String = "cat_watching"
const JJAMTONG_INTRO_ID: String = "jjamtong_intro"

signal event_started(event_data: GameEventData)
signal event_finished(event_id: String, result: String)
signal event_state_restored()
signal phone_dm_message(text: String, from_player: bool)
signal phone_dm_choices_changed(available: bool, can_bargain: bool, offer: Variant)
signal phone_dm_resolved(accepted: bool, reward: Variant)
signal reward_deposit_requested(reward_id: int)
signal reward_deposits_cancelled()

enum Choice { ACCEPT, BARGAIN, REJECT }
enum NextStep { NONE, CHOICES, BARGAIN_RESULT, ACCEPT, REJECT, FINISH }

@export var events: Array[GameEventData] = [
	preload("res://data/events/phone_dm_event.tres"),
	preload("res://data/events/camera_tutorial_event.tres"),
	preload("res://data/events/income_upgrade_tutorial_event.tres"),
	preload("res://data/events/jjam_shop_tutorial_event.tres"),
	preload("res://data/events/cat_watching_event.tres"),
	preload("res://data/events/jjamtong_intro_event.tres"),
]

var _definitions: Dictionary = {}
var _active_events: Dictionary = {}
var _cooldowns: Dictionary = {}
var _roll_elapsed: Dictionary = {}
var _roll_attempts: Dictionary = {}
var _last_roll_result: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _phone_ui_available: bool = false
var _phone_event: PhoneDMEventData
var _dialogue: PhoneDMDialogueData
var _offer: Variant = 0.0
var _offer_stage: int = 0
var _waiting_for_choice: bool = false
var _message_queue: Array[Dictionary] = []
var _message_wait: float = 0.0
var _next_step: NextStep = NextStep.NONE
var _result: String = ""
var _phone_reward_id: int = -1
var _next_reward_id: int = 0
var _pending_rewards: Dictionary = {}
var _reward_deposit_ui_available: bool = false
var _consumed_events: Dictionary = {}
var _event_results: Dictionary = {}
var _legacy_one_off_events: Dictionary = {}
var _permanently_unlocked_events: Dictionary = {}
var _legacy_permanent_unlock_events: Dictionary = {}
var _camera_tutorial_ui_available: bool = false
var _income_upgrade_tutorial_ui_available: bool = false
var _jjam_shop_tutorial_ui_available: bool = false
var _cat_watching_ui_available: bool = false
var _jjamtong_intro_ui_available: bool = false
var presentation_locked: bool = false


func _ready() -> void:
	_rng.randomize()
	for event_data in events:
		register_event(event_data)
	ButtonManager.button_purchased.connect(_on_button_purchased)
	PrestigeManager.prestige_changed.connect(_on_prestige_changed)


func _on_button_purchased(button_data: ButtonData) -> void:
	_refresh_permanent_unlocks()
	for event_id in _definitions:
		var data: GameEventData = _definitions[event_id]
		var condition := data.unlock_condition
		if (
			data.trigger == GameEventData.Trigger.INSTANT
			and condition != null
			and condition.type == UnlockCondition.Type.BUTTON
			and condition.value == button_data.id
		):
			start_event(event_id, true)


func _on_prestige_changed() -> void:
	if not PrestigeManager.has_prestiged():
		return
	for event_id in _definitions:
		var data: GameEventData = _definitions[event_id]
		if not data.no_prestige_only:
			continue
		finish_event(event_id, "cancelled")


## Additional event types share registration, eligibility, cooldown and lifecycle signals.
func register_event(event_data: GameEventData) -> bool:
	if not _validate_event(event_data) or _definitions.has(event_data.id):
		ErrorManager.report_error("INVALID_EVENT", "이벤트 리소스가 잘못되었거나 ID가 중복되었습니다.", "EventManager")
		return false
	_definitions[event_data.id] = event_data
	_cooldowns[event_data.id] = 0.0
	_roll_elapsed[event_data.id] = 0.0
	_roll_attempts[event_data.id] = 0
	_last_roll_result[event_data.id] = "추첨 없음"
	return true


func _validate_event(data: GameEventData) -> bool:
	if data == null or data.id.strip_edges().is_empty():
		return false
	if data.trigger not in GameEventData.Trigger.values():
		return false
	if data.trigger == GameEventData.Trigger.RANDOM:
		if not is_finite(data.roll_interval_seconds) or data.roll_interval_seconds <= 0.0:
			return false
		if not is_finite(data.chance_per_roll) or data.chance_per_roll < 0.0 or data.chance_per_roll > 1.0:
			return false
	if not is_finite(data.cooldown_seconds) or data.cooldown_seconds < 0.0:
		return false
	if data.minimum_prestige_count < 0 or (data.no_prestige_only and data.minimum_prestige_count > 0):
		return false
	if data.maximum_prestige_count < -1 or (data.maximum_prestige_count >= 0 and data.maximum_prestige_count < data.minimum_prestige_count):
		return false
	if data.unlock_condition != null:
		if not ErrorManager.validate_condition(data.unlock_condition, ButtonManager.buttons, "Event:" + data.id):
			return false
	if data is PhoneDMEventData:
		var dm := data as PhoneDMEventData
		if dm.dialogues.is_empty() or dm.breakdown_chances.size() != 3:
			return false
		if not is_finite(dm.initial_offer_income_seconds) or dm.initial_offer_income_seconds <= 0.0:
			return false
		if not is_finite(dm.minimum_offer_amount) or dm.minimum_offer_amount < 1.0:
			return false
		if not is_finite(dm.message_interval_seconds) or dm.message_interval_seconds <= 0.0 or not is_finite(dm.result_display_seconds) or dm.result_display_seconds < 0.0:
			return false
		for chance in dm.breakdown_chances:
			if not is_finite(chance) or chance < 0.0 or chance > 1.0:
				return false
		for increase in [dm.offer_increase_range, dm.final_offer_increase_range]:
			if not increase.is_finite() or increase.x < 0.0 or increase.y < increase.x:
				return false
		for dialogue in dm.dialogues:
			if dialogue == null or not dialogue.is_complete():
				return false
	return true


func is_condition_met(condition: UnlockCondition) -> bool:
	if condition == null:
		return true
	match condition.type:
		UnlockCondition.Type.MONEY:
			return BIG.compare(EconomyManager.money, condition.get_amount()) >= 0
		UnlockCondition.Type.TOTAL_JJAM:
			return BIG.compare(PrestigeManager.get_total_jjam(), condition.get_amount()) >= 0
		UnlockCondition.Type.BUTTON:
			var button := ButtonManager.get_button(condition.value)
			return button != null and button.bought
	return false


func _process(delta: float) -> void:
	if not SaveManager.initialized:
		return
	_refresh_permanent_unlocks()
	if presentation_locked:
		return
	# Update current dialogue before scheduling, so a newly started event gets its full slide-in.
	_advance_phone_dm(delta)
	if not _reward_deposit_ui_available:
		for reward_id in _pending_rewards.keys():
			if _pending_rewards[reward_id].ready:
				advance_reward_deposit(reward_id, 1.0)
	for event_id in _definitions:
		var data: GameEventData = _definitions[event_id]
		if _active_events.has(event_id):
			continue
		var cooldown: float = _cooldowns.get(event_id, 0.0)
		if cooldown > 0.0:
			_cooldowns[event_id] = maxf(0.0, cooldown - delta)
			_roll_elapsed[event_id] = 0.0
			continue
		if not can_start_event(event_id):
			_roll_elapsed[event_id] = 0.0
			continue
		if data.trigger == GameEventData.Trigger.INSTANT:
			start_event(event_id, true)
			continue
		_roll_elapsed[event_id] += delta
		# Combine missed intervals into the equivalent probability of at least one success.
		# Low frame rates still count each configured roll, without starting duplicates.
		if _roll_elapsed[event_id] >= data.roll_interval_seconds:
			var elapsed_rolls := floori(_roll_elapsed[event_id] / data.roll_interval_seconds)
			_roll_elapsed[event_id] = fmod(_roll_elapsed[event_id], data.roll_interval_seconds)
			var chance := 1.0 - pow(1.0 - data.chance_per_roll, elapsed_rolls)
			_roll_attempts[event_id] += elapsed_rolls
			_last_roll_result[event_id] = "미발동"
			if _rng.randf() < chance:
				start_event(event_id, true)


func is_event_active(event_id: String) -> bool:
	return _active_events.has(event_id)


func get_event_result(event_id: String) -> String:
	return _event_results.get(event_id, "")


func get_cooldown_remaining(event_id: String) -> float:
	return _cooldowns.get(event_id, 0.0)


func is_event_unlocked(event_id: String) -> bool:
	var data := _definitions.get(event_id) as GameEventData
	if data == null:
		return false
	if PrestigeManager.prestige_count < data.minimum_prestige_count or (data.maximum_prestige_count >= 0 and PrestigeManager.prestige_count > data.maximum_prestige_count):
		return false
	return (data.permanent_unlock and _permanently_unlocked_events.get(event_id, false)) or is_condition_met(data.unlock_condition)


func _refresh_permanent_unlocks() -> void:
	for event_id in _definitions:
		var data: GameEventData = _definitions[event_id]
		if data.permanent_unlock and not _permanently_unlocked_events.get(event_id, false) and is_event_unlocked(event_id):
			_permanently_unlocked_events[event_id] = true


func _get_initial_phone_offer(data: PhoneDMEventData) -> Variant:
	var offer: Variant = BIG.rounded(BIG.multiply(IncomeManager.get_total_income_per_second(), data.initial_offer_income_seconds))
	if not BIG.valid(offer):
		return offer
	return BIG.rounded(data.minimum_offer_amount) if BIG.compare(offer, data.minimum_offer_amount) < 0 else offer


func get_event_start_block_reason(event_id: String, ignore_cooldown: bool = false) -> String:
	var data := _definitions.get(event_id) as GameEventData
	if data == null:
		return "이벤트 등록 실패: 리소스 오류를 확인하세요."
	if not SaveManager.initialized:
		return "게임 초기화 대기"
	if not data.enabled:
		return "이벤트 비활성화"
	if PrestigeManager.prestige_count < data.minimum_prestige_count:
		return "짬 환생 %d회 필요" % data.minimum_prestige_count
	if data.maximum_prestige_count >= 0 and PrestigeManager.prestige_count > data.maximum_prestige_count:
		return "짬 환생 %d회까지의 이벤트" % data.maximum_prestige_count
	if data.no_prestige_only and PrestigeManager.has_prestiged():
		return "첫 환생 전 전용 이벤트"
	if is_event_active(event_id):
		return "이벤트 진행 중 · 응답 대기" if data is PhoneDMEventData and _waiting_for_choice else "이벤트 진행 중"
	if data.one_off and _consumed_events.get(event_id, false):
		return "이미 진행한 일회성 이벤트"
	if not ignore_cooldown and get_cooldown_remaining(event_id) > 0.0:
		return "쿨타임 대기"
	if presentation_locked:
		return "카메라 연출 진행 중"
	if not is_event_unlocked(event_id):
		if data.unlock_condition.type == UnlockCondition.Type.BUTTON:
			return "조건 미충족 · %s 구매 필요" % data.unlock_condition.value
		return "해금 조건 미충족"
	if event_id == CAMERA_TUTORIAL_ID and not _camera_tutorial_ui_available:
		return "카메라 튜토리얼 화면 대기"
	if event_id == INCOME_UPGRADE_TUTORIAL_ID and not _income_upgrade_tutorial_ui_available:
		return "수입원 업그레이드 튜토리얼 화면 대기"
	if event_id == JJAM_SHOP_TUTORIAL_ID and not _jjam_shop_tutorial_ui_available:
		return "짬 상점 튜토리얼 화면 대기"
	if event_id == CAT_WATCHING_ID and not _cat_watching_ui_available:
		return "짬타이거 예고 이벤트 화면 대기"
	if event_id == JJAMTONG_INTRO_ID and not _jjamtong_intro_ui_available:
		return "짬통 소개 화면 대기"
	if data is PhoneDMEventData:
		if not _phone_ui_available:
			return "폰 DM 화면 대기"
		if _phone_event != null:
			return "다른 폰 DM 진행 중"
		var dm := data as PhoneDMEventData
		var first_offer: Variant = _get_initial_phone_offer(dm)
		if not BIG.valid(first_offer, false):
			return "제시 금액 계산 불가 · 현재 수입과 수입 배율을 확인하세요."
	return ""


func can_start_event(event_id: String) -> bool:
	return get_event_start_block_reason(event_id).is_empty()


func get_event_debug_states() -> Array[Dictionary]:
	var definitions := _definitions.duplicate()
	# Include rejected resources so the tools can explain why an event never starts.
	for data in events:
		if data != null and not definitions.has(data.id):
			definitions[data.id] = data
	var states: Array[Dictionary] = []
	for event_id in definitions:
		var data: GameEventData = definitions[event_id]
		var reason := get_event_start_block_reason(event_id)
		var test_reason := get_event_start_block_reason(event_id, true)
		states.append({
			"id": event_id,
			"name": data.resource_name if not data.resource_name.is_empty() else event_id,
			"cooldown_remaining": get_cooldown_remaining(event_id),
			"can_start": reason.is_empty(),
			"block_reason": reason,
			"can_start_for_testing": test_reason.is_empty(),
			"test_block_reason": test_reason,
			"roll_interval_seconds": data.roll_interval_seconds,
			"chance_per_roll": data.chance_per_roll,
			"trigger": data.trigger,
			"one_off": data.one_off,
			"unlocked": is_event_unlocked(event_id),
			"consumed": _consumed_events.get(event_id, false),
			"next_roll_in": maxf(0.0, data.roll_interval_seconds - float(_roll_elapsed.get(event_id, 0.0))) if data.trigger == GameEventData.Trigger.RANDOM else 0.0,
			"roll_attempts": _roll_attempts.get(event_id, 0),
			"last_roll_result": _last_roll_result.get(event_id, "추첨 없음"),
		})
	return states


func get_phone_dm_contact() -> String:
	return _dialogue.contact_name if _dialogue != null else ""


func set_phone_dm_ui_available(available: bool) -> void:
	_phone_ui_available = available
	if not available and _phone_event != null:
		finish_event(_phone_event.id, "cancelled")


func set_camera_tutorial_ui_available(available: bool) -> void:
	_camera_tutorial_ui_available = available
	if not available:
		finish_event(CAMERA_TUTORIAL_ID, "cancelled")


func notify_camera_interaction() -> void:
	finish_event(CAMERA_TUTORIAL_ID, "dismissed")


func set_income_upgrade_tutorial_ui_available(available: bool) -> void:
	_income_upgrade_tutorial_ui_available = available
	if not available:
		finish_event(INCOME_UPGRADE_TUTORIAL_ID, "cancelled")


func notify_income_upgrade_panel_opened(source_id: String) -> void:
	if source_id == "vending_machine":
		finish_event(INCOME_UPGRADE_TUTORIAL_ID, "dismissed")


func set_jjam_shop_tutorial_ui_available(available: bool) -> void:
	_jjam_shop_tutorial_ui_available = available
	if not available:
		finish_event(JJAM_SHOP_TUTORIAL_ID, "guiding")
	elif not is_event_active(JJAM_SHOP_TUTORIAL_ID) and get_event_result(JJAM_SHOP_TUTORIAL_ID) == "guiding":
		_consumed_events[JJAM_SHOP_TUTORIAL_ID] = false


func set_cat_watching_ui_available(available: bool) -> void:
	_cat_watching_ui_available = available
	if not available:
		finish_event(CAT_WATCHING_ID, "cancelled")


func start_event_for_testing(event_id: String) -> bool:
	return start_event(event_id, false, true)


func set_jjamtong_intro_ui_available(available: bool) -> void:
	_jjamtong_intro_ui_available = available
	if not available:
		finish_event(JJAMTONG_INTRO_ID, "cancelled")


func prepare_for_prestige() -> void:
	_refresh_permanent_unlocks()
	# Agreed DM rewards have already entered the income ledger. End the old run's
	# conversation/deposits so delayed wallet animations cannot credit the new run.
	for event_id in _active_events.keys():
		if _active_events.get(event_id) is PhoneDMEventData:
			_force_reject_phone_dm()
		else:
			finish_event(event_id, "prestige")
	_pending_rewards.clear()
	_phone_reward_id = -1
	reward_deposits_cancelled.emit()


func _force_reject_phone_dm() -> void:
	if _phone_event == null:
		return
	var event_id := _phone_event.id
	var player_reply := _dialogue.player_reject
	var buyer_reply := _dialogue.breakdown
	var already_rejected := _result == "rejected"
	_waiting_for_choice = false
	_message_queue.clear()
	_next_step = NextStep.NONE
	_result = "rejected"
	# An accepted deal can still be displaying its result. Revoke its reserved
	# income too, so forcing rejection cannot leave behind money or live jjam.
	var reward_id := _phone_reward_id
	_phone_reward_id = -1
	if _pending_rewards.has(reward_id):
		var reward: Dictionary = _pending_rewards[reward_id]
		_pending_rewards.erase(reward_id)
		IncomeManager.revoke_recorded_income(reward.amount, reward.get("recorded_in_jjam", PrestigeManager.jjam_unlocked))
	if not is_event_active(event_id):
		return
	if not already_rejected:
		phone_dm_message.emit(player_reply.replace("{amount}", NUMBER_FORMATTER.format_number(_offer)), true)
		phone_dm_message.emit(buyer_reply.replace("{amount}", NUMBER_FORMATTER.format_number(_offer)), false)
	phone_dm_resolved.emit(false, 0.0)
	finish_event(event_id, "rejected")


func start_event(event_id: String, automatic: bool = false, ignore_cooldown: bool = false) -> bool:
	var data := _definitions.get(event_id) as GameEventData
	# Testing may bypass cooldown; initialization, eligibility and duplicate checks still apply.
	if not get_event_start_block_reason(event_id, ignore_cooldown).is_empty():
		return false
	if data is PhoneDMEventData:
		var dm := data as PhoneDMEventData
		var first_offer: Variant = _get_initial_phone_offer(dm)
		if not BIG.valid(first_offer, false):
			return false
		_phone_event = dm
		_dialogue = _phone_event.dialogues[_rng.randi_range(0, _phone_event.dialogues.size() - 1)]
		_offer = first_offer
		_offer_stage = 0
		_waiting_for_choice = false
		_message_queue.clear()
		_result = ""
		_phone_reward_id = -1
		_queue_message(_dialogue.greeting)
		_queue_message(_dialogue.introduction)
		_queue_message(_dialogue.get_offer(0))
		_next_step = NextStep.CHOICES
		_message_wait = 0.3
	_active_events[event_id] = data
	if event_id == JJAM_SHOP_TUTORIAL_ID:
		# A visual-only guide can be left unfinished while the player saves/quits.
		_event_results[event_id] = "guiding"
	if data.permanent_unlock:
		_permanently_unlocked_events[event_id] = true
	if data.one_off:
		# Commit before presentation callbacks, including synchronous saves or reloads.
		_consumed_events[event_id] = true
	_cooldowns[event_id] = 0.0
	_roll_elapsed[event_id] = 0.0
	_last_roll_result[event_id] = "즉시 발동" if automatic and data.trigger == GameEventData.Trigger.INSTANT else ("자동 발동" if automatic else "직접 발동")
	event_started.emit(data)
	return true


func choose_phone_dm(choice: Choice) -> bool:
	if _phone_event == null or not _waiting_for_choice:
		return false
	if choice not in [Choice.ACCEPT, Choice.BARGAIN, Choice.REJECT] or (choice == Choice.BARGAIN and _offer_stage >= 3):
		return false
	# Disable immediately, before emitting any signals, to prevent repeated payouts/clicks.
	_waiting_for_choice = false
	phone_dm_choices_changed.emit(false, _offer_stage < 3, _offer)
	match choice:
		Choice.ACCEPT:
			_queue_message(_dialogue.player_accept, true)
			_queue_message(_dialogue.acceptance)
			_next_step = NextStep.ACCEPT
		Choice.BARGAIN:
			_queue_message(_dialogue.player_bargain, true)
			_queue_message(_dialogue.get_refusal(_offer_stage))
			_next_step = NextStep.BARGAIN_RESULT
		Choice.REJECT:
			_queue_message(_dialogue.player_reject, true)
			_queue_message(_dialogue.breakdown)
			_next_step = NextStep.REJECT
	_message_wait = 0.0
	return true


func _queue_message(template: String, from_player: bool = false) -> void:
	_message_queue.append({
		"text": template.replace("{amount}", NUMBER_FORMATTER.format_number(_offer)),
		"from_player": from_player,
	})


func _advance_phone_dm(delta: float) -> void:
	if _phone_event == null or _waiting_for_choice:
		return
	_message_wait -= delta
	if _message_wait > 0.0:
		return
	if not _message_queue.is_empty():
		var message: Dictionary = _message_queue.pop_front()
		_message_wait = _phone_event.message_interval_seconds
		phone_dm_message.emit(message.text, message.from_player)
		return
	var step := _next_step
	_next_step = NextStep.NONE
	match step:
		NextStep.CHOICES:
			_waiting_for_choice = true
			phone_dm_choices_changed.emit(true, _offer_stage < 3, _offer)
		NextStep.BARGAIN_RESULT:
			_resolve_bargain()
		NextStep.ACCEPT:
			var reward: Variant = _offer
			_result = "accepted"
			_next_step = NextStep.FINISH
			_message_wait = _phone_event.result_display_seconds
			# Reserve the agreed reward now; transfer it after the phone slides away.
			_phone_reward_id = _next_reward_id
			_next_reward_id += 1
			_pending_rewards[_phone_reward_id] = {"amount": reward, "credited": 0.0, "ready": false, "recorded_in_jjam": PrestigeManager.jjam_unlocked}
			# Record the completed deal once; saving also settles its pending wallet.
			IncomeManager.record_income(reward)
			phone_dm_resolved.emit(true, reward)
		NextStep.REJECT:
			_result = "rejected"
			_next_step = NextStep.FINISH
			_message_wait = _phone_event.result_display_seconds
			phone_dm_resolved.emit(false, 0.0)
		NextStep.FINISH:
			finish_event(_phone_event.id, _result)


func _resolve_bargain() -> void:
	if _rng.randf() < _phone_event.breakdown_chances[_offer_stage]:
		_queue_message(_dialogue.breakdown)
		_next_step = NextStep.REJECT
		return
	_offer_stage += 1
	var increase := _phone_event.final_offer_increase_range if _offer_stage == 3 else _phone_event.offer_increase_range
	var next_offer: Variant = BIG.rounded(BIG.multiply(_offer, 1.0 + _rng.randf_range(increase.x, increase.y)))
	if not BIG.valid(next_offer, false):
		finish_event(_phone_event.id, "invalid_offer")
		return
	_offer = next_offer
	# Hide bargaining as soon as the final offer begins, before its bubble appears.
	phone_dm_choices_changed.emit(false, _offer_stage < 3, _offer)
	_queue_message(_dialogue.get_offer(_offer_stage))
	_next_step = NextStep.CHOICES


func finish_event(event_id: String, result: String = "completed") -> void:
	if not _active_events.has(event_id):
		return
	var data: GameEventData = _active_events[event_id]
	_active_events.erase(event_id)
	_event_results[event_id] = result
	_cooldowns[event_id] = data.cooldown_seconds
	_roll_elapsed[event_id] = 0.0
	_roll_attempts[event_id] = 0
	_last_roll_result[event_id] = "추첨 없음"
	var reward_id := -1
	if _phone_event != null and _phone_event.id == event_id:
		reward_id = _phone_reward_id
		_phone_reward_id = -1
		_phone_event = null
		_dialogue = null
		_message_queue.clear()
		_waiting_for_choice = false
		_next_step = NextStep.NONE
		phone_dm_choices_changed.emit(false, false, 0.0)
	event_finished.emit(event_id, result)
	if _pending_rewards.has(reward_id):
		_pending_rewards[reward_id].ready = true
		reward_deposit_requested.emit(reward_id)


func set_reward_deposit_ui_available(available: bool) -> void:
	_reward_deposit_ui_available = available
	if available:
		for reward_id in _pending_rewards.keys():
			if _pending_rewards[reward_id].ready:
				reward_deposit_requested.emit(reward_id)


func get_reward_remaining(reward_id: int) -> Variant:
	if not _pending_rewards.has(reward_id):
		return 0.0
	var reward: Dictionary = _pending_rewards[reward_id]
	return BIG.subtract(reward.amount, reward.credited)


func advance_reward_deposit(reward_id: int, progress: float) -> Variant:
	if not _pending_rewards.has(reward_id) or not _pending_rewards[reward_id].ready:
		return get_reward_remaining(reward_id)
	var reward: Dictionary = _pending_rewards[reward_id]
	progress = clampf(progress, 0.0, 1.0)
	var target: Variant = reward.amount if progress >= 1.0 else BIG.rounded(BIG.multiply(reward.amount, progress))
	if BIG.compare(target, reward.credited) <= 0:
		if progress >= 1.0:
			_pending_rewards.erase(reward_id)
		return get_reward_remaining(reward_id)
	var previous: Variant = reward.credited
	var delta: Variant = BIG.subtract(target, previous)
	# Commit the ledger before money_changed callbacks can save or load progress.
	reward.credited = target
	if not EconomyManager.add_money(delta):
		if _pending_rewards.has(reward_id):
			reward.credited = previous
		return get_reward_remaining(reward_id)
	if progress >= 1.0:
		_pending_rewards.erase(reward_id)
	return get_reward_remaining(reward_id)


## Save a settled wallet without interrupting the visible deposit animation.
func get_wallet_for_save() -> Array:
	var wallet: Array = [EconomyManager.money, EconomyManager.money_correction]
	for reward_id in _pending_rewards:
		var addition := BIG.add_with_residual(wallet[0], get_reward_remaining(reward_id))
		var correction: Variant = BIG.add(wallet[1], addition[1])
		wallet = BIG.add_with_residual(addition[0], correction)
	return wallet


func get_save_state() -> Dictionary:
	_refresh_permanent_unlocks()
	var state := _cooldowns.duplicate()
	for event_id in _active_events:
		# Interrupted conversations cannot be replayed for another reward after loading.
		state[event_id] = (_active_events[event_id] as GameEventData).cooldown_seconds
	for event_id in _definitions:
		var data: GameEventData = _definitions[event_id]
		if data.one_off or data.permanent_unlock:
			state[event_id] = {
				"cooldown_remaining": state.get(event_id, 0.0),
				"consumed": _consumed_events.get(event_id, false),
				"result": get_event_result(event_id),
			}
			if data.permanent_unlock:
				state[event_id]["unlocked"] = _permanently_unlocked_events.get(event_id, false)
	return state


func is_save_state_valid(state: Variant) -> bool:
	if not state is Dictionary:
		return false
	for event_id in state:
		var remaining: Variant = state[event_id]
		if remaining is Dictionary:
			if not remaining.get("consumed") is bool:
				return false
			if not remaining.get("result", "") is String:
				return false
			if remaining.has("unlocked") and not remaining.unlocked is bool:
				return false
			remaining = remaining.get("cooldown_remaining")
		if not event_id is String or not (remaining is float or remaining is int):
			return false
		if not is_finite(float(remaining)) or remaining < 0.0:
			return false
	return true


func restore_save_state(state: Dictionary) -> void:
	# Saved wallets already include outstanding rewards; never replay their deposits.
	_pending_rewards.clear()
	_phone_reward_id = -1
	reward_deposits_cancelled.emit()
	for event_id in _active_events.keys():
		finish_event(event_id, "cancelled")
	_consumed_events.clear()
	_event_results.clear()
	_legacy_one_off_events.clear()
	_permanently_unlocked_events.clear()
	_legacy_permanent_unlock_events.clear()
	for event_id in _definitions:
		var data: GameEventData = _definitions[event_id]
		var saved: Variant = state.get(event_id, 0.0)
		var remaining := float(saved.cooldown_remaining) if saved is Dictionary else float(saved)
		if saved is Dictionary:
			_event_results[event_id] = saved.get("result", "")
		if data.permanent_unlock:
			if saved is Dictionary and saved.has("unlocked"):
				_permanently_unlocked_events[event_id] = saved.unlocked
			else:
				_legacy_permanent_unlock_events[event_id] = true
				# A stored cooldown proves that this event already occurred.
				_permanently_unlocked_events[event_id] = remaining > 0.0
		if data.one_off:
			if saved is Dictionary:
				_consumed_events[event_id] = saved.consumed
				if event_id == JJAM_SHOP_TUTORIAL_ID and saved.consumed and saved.get("result", "") == "guiding":
					# Resume the guide after loading without replaying completed tutorials.
					_consumed_events[event_id] = false
				if event_id == CAT_WATCHING_ID and saved.consumed:
					if not saved.has("result"):
						# Older saves recorded the encounter without a separate confirmation result.
						_event_results[event_id] = "acknowledged"
					elif get_event_result(event_id) != "acknowledged":
						# Resume an interrupted encounter so confirmation cannot become unreachable.
						_consumed_events[event_id] = false
			else:
				_legacy_one_off_events[event_id] = true
		# Existing saves must also respect a shortened cooldown configuration.
		_cooldowns[event_id] = minf(remaining, data.cooldown_seconds)
		_roll_elapsed[event_id] = 0.0
		_roll_attempts[event_id] = 0
		_last_roll_result[event_id] = "추첨 없음"
	event_state_restored.emit()


## Call after purchase, source and prestige state have all been restored.
func reconcile_permanent_unlocks() -> void:
	if _legacy_permanent_unlock_events.has(PHONE_DM_ID) and PrestigeManager.jjam_unlocked:
		var data := _definitions.get(PHONE_DM_ID) as GameEventData
		var condition := data.unlock_condition if data != null else null
		# Older saves lost bumin's purchase on prestige. Permanent bin ownership is
		# evidence of that earlier purchase when it occurs in the bin's prerequisites.
		if condition != null and condition.type == UnlockCondition.Type.BUTTON and _purchase_requires("jjamtong", condition.value):
			_permanently_unlocked_events[PHONE_DM_ID] = true
	_legacy_permanent_unlock_events.clear()
	_refresh_permanent_unlocks()


func _purchase_requires(purchase_id: String, required_id: String) -> bool:
	var visited: Dictionary = {}
	var button := ButtonManager.get_button(purchase_id)
	while button != null and not visited.has(button.id):
		if button.id == required_id:
			return true
		visited[button.id] = true
		var condition := button.unlock_condition
		if condition == null or condition.type != UnlockCondition.Type.BUTTON:
			return false
		button = ButtonManager.get_button(condition.value)
	return false


## Called only after all saved purchase/prestige state has been restored.
func reconcile_one_off_history() -> void:
	for event_id in _legacy_one_off_events:
		var data: GameEventData = _definitions[event_id]
		if PrestigeManager.prestige_count < data.minimum_prestige_count:
			continue
		if data.maximum_prestige_count >= 0 and PrestigeManager.prestige_count > data.maximum_prestige_count:
			_consumed_events[event_id] = true
			continue
		if data.no_prestige_only and PrestigeManager.has_prestiged():
			_consumed_events[event_id] = true
		var condition := data.unlock_condition
		if data.trigger == GameEventData.Trigger.INSTANT and condition != null and condition.type == UnlockCondition.Type.BUTTON:
			var button := ButtonManager.get_button(condition.value)
			if button != null and button.bought:
				_consumed_events[event_id] = true
		if event_id == CAT_WATCHING_ID and _consumed_events.get(event_id, false):
			_event_results[event_id] = "acknowledged"
	_legacy_one_off_events.clear()
	_on_prestige_changed()
