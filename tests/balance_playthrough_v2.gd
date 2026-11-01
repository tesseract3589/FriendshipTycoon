extends Node

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const BIG = preload("res://scripts/BigNumber.gd")
const SIMULATION_FPS: int = 60
const MAX_SIMULATION_SECONDS: int = 86400
const MAX_PURCHASES: int = 10000

@export var curve_checks_only: bool = false

@export var report_path: String = "res://logs/balance_playthrough_v2.txt"
@export var event_seed: int = 20261022
@export var max_expected_wait_seconds: float = 600.0

var _frame: int = 0
var _unlock_frames: Dictionary = {}
var _failure: String = ""

var _status: String = "진행 중"
var _end_reason: String = ""
var _run_index: int = 1
var _run_start_frame: int = 0
var _prestiges_done: int = 0
var _prestige_records: Array[Dictionary] = []
var _actions: Array[Dictionary] = []
var _button_log: Array[Dictionary] = []
var _timeline: Array[String] = []
var _stop_snapshot: Dictionary = {}
var _dm_bargains: int = 0
var _dm_ready: bool = false
var _dm_can_bargain: bool = false
var _dm_offer: Variant = 0.0
var _dm_started: int = 0
var _dm_accepted: int = 0
var _dm_rejected: int = 0
var _dm_deposited: Variant = 0.0
var _last_button_in_run: int = 0
var _last_purchase_in_run: int = 0
var _candidate_dirty: bool = true
var _candidate_cache: Dictionary = {}
var _rate_dirty: bool = true
var _rate_cache: Variant = 0.0
var _money_unlocks: bool = false
var _jjam_unlocks: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	IncomeManager.set_process(false)
	EventManager.set_process(false)
	if not ErrorManager.get_errors().is_empty():
		_failure = "시작 시 게임 데이터 오류가 있습니다."
	elif curve_checks_only:
		_check_income_curves()
	else:
		# Event scheduling requires initialized saves, but never use the player's slots.
		var directory := ProjectSettings.globalize_path("res://.godot/balance_v2_%d" % Time.get_ticks_usec())
		if not SaveManager.initialize(directory):
			_failure = "테스트 전용 저장소를 초기화하지 못했습니다."
		else:
			SaveManager._restore_progress(SaveManager._create_initial_progress())
			_connect_events()
			_check_income_curves()
			if _failure.is_empty():
				await _play()
	if not ErrorManager.get_errors().is_empty() and _failure.is_empty():
		_failure = "플레이 중 게임 오류가 발생했습니다."
	if curve_checks_only:
		if _failure.is_empty():
			print("PASS: exponential income growth, next-level forecasts, large levels and resource cache invalidation")
		else:
			push_error(_failure)
		get_tree().quit(0 if _failure.is_empty() else 1)
		return
	if not _failure.is_empty():
		_status = "실패"
		_end_reason = _failure
	if not _write_report():
		_failure = "결과 파일을 저장하지 못했습니다: " + report_path
	# Prevent exit autosaves of the artificial session, including on failed tests.
	SaveManager.initialized = false
	if _failure.is_empty():
		print("PASS: balance v2; %s; prestige %d; DM %d accepted/%d rejected; %d purchases; %.2fs; %s" % [
			_status, _prestiges_done, _dm_accepted, _dm_rejected, _actions.size(), _seconds(_frame), report_path])
	else:
		push_error(_failure)
	get_tree().quit(0 if _failure.is_empty() else 1)


func _connect_events() -> void:
	for button in ButtonManager.buttons:
		if button != null and button.unlock_condition != null:
			_money_unlocks = _money_unlocks or button.unlock_condition.type == UnlockCondition.Type.MONEY
			_jjam_unlocks = _jjam_unlocks or button.unlock_condition.type == UnlockCondition.Type.TOTAL_JJAM
	EconomyManager.money_changed.connect(_on_money_for_unlocks)
	PrestigeManager.jjam_changed.connect(_on_jjam_for_unlocks)
	IncomeManager.income_changed.connect(_invalidate_income)
	EventManager.event_started.connect(_on_event_started)
	EventManager.event_finished.connect(_on_event_finished)
	EventManager.phone_dm_choices_changed.connect(_on_dm_choices)
	EventManager.phone_dm_resolved.connect(_on_dm_resolved)
	EventManager.reward_deposit_requested.connect(_on_reward_deposit)
	EventManager._rng.seed = event_seed
	EventManager.presentation_locked = false
	EventManager.set_phone_dm_ui_available(true)
	EventManager.set_reward_deposit_ui_available(true)
	EventManager.set_camera_tutorial_ui_available(true)
	EventManager.set_cat_watching_ui_available(true)
	EventManager.set_jjamtong_intro_ui_available(true)


func _play() -> void:
	while _failure.is_empty():
		if _prestiges_done == 1 and not _has_unpurchased_buttons():
			_status = "완료"
			_end_reason = "짬 환생 1회 후 현재 등록된 모든 버튼을 구매했습니다."
			return
		if _frame >= MAX_SIMULATION_SECONDS * SIMULATION_FPS or _actions.size() >= MAX_PURCHASES:
			_status = "안전 한도 종료"
			_end_reason = "가상 시간 24시간 또는 구매 10,000회 한도에 도달했습니다."
			return
		_handle_dm_choice()
		if not _failure.is_empty():
			return
		if _prestiges_done == 0 and PrestigeManager.jjam_unlocked:
			# Finish the in-progress deal before prestige can revoke its reward.
			if EventManager.is_event_active(EventManager.PHONE_DM_ID):
				_step_simulation()
			else:
				_perform_prestige()
			continue
		var candidate := _current_candidate()
		if candidate.is_empty():
			_status = "진행 불가"
			_end_reason = "현재 해금된 구매 항목이 없습니다."
			return
		var rate: Variant = _current_rate()
		var wait: Variant = estimate_wait(candidate.cost, EconomyManager.money, rate)
		if BIG.compare(wait, max_expected_wait_seconds) >= 0:
			_status = "대기 한도 종료"
			_end_reason = "다음 최저가 구매까지 현재 생산 수입 기준 예상 대기가 %.0f초 이상입니다." % max_expected_wait_seconds
			_stop_snapshot = {"candidate": candidate.duplicate(), "money": EconomyManager.money,
				"rate": rate, "wait": wait}
			_record("종료", "%s · 가격 %s · 자금 %s · 수입 %s원/초 · 예상 %s" % [
				candidate.name, _won(candidate.cost), _won(EconomyManager.money),
				NUMBER_FORMATTER.format_income_per_second(rate), _wait_text(wait)])
			return
		if EconomyManager.can_afford(candidate.cost):
			if not _purchase(candidate):
				return
			continue
		_step_simulation()
		if _frame % 3600 == 0:
			if _frame % 36000 == 0:
				print("BALANCE V2: %.0fs, run %d, %d purchases, %d DM, next %s" % [_seconds(_frame), _run_index, _actions.size(), _dm_started, candidate.name])
			await get_tree().process_frame


func _on_money_for_unlocks(_value: Variant) -> void:
	if _money_unlocks:
		_candidate_dirty = true


func _on_jjam_for_unlocks() -> void:
	if _jjam_unlocks:
		_candidate_dirty = true


func _invalidate_income() -> void:
	_candidate_dirty = true
	_rate_dirty = true


func _current_candidate() -> Dictionary:
	# Unlock conditions can change with money, live jjam or a purchase. Signals
	# invalidate the ranking at those exact changes, rather than revalidating all
	# button dependency trees in every unchanged simulation frame.
	if _candidate_dirty:
		_candidate_cache = _get_cheapest_candidate()
		_candidate_dirty = false
	return _candidate_cache


func _current_rate() -> Variant:
	if _rate_dirty:
		_rate_cache = IncomeManager.get_total_income_per_second()
		_rate_dirty = false
	return _rate_cache


static func estimate_wait(cost: Variant, money: Variant, rate: Variant) -> Variant:
	if BIG.compare(money, cost) >= 0:
		return 0.0
	if BIG.compare(rate, 0.0) <= 0:
		return INF
	return BIG.divide(BIG.subtract(cost, money), rate)


func _step_simulation() -> void:
	_frame += 1
	var delta := 1.0 / float(SIMULATION_FPS)
	IncomeManager._process(delta)
	EventManager._process(delta)
	_handle_dm_choice()
	if not ErrorManager.get_errors().is_empty():
		_failure = "플레이 중 게임 오류가 발생했습니다."


func _purchase(candidate: Dictionary) -> bool:
	var money_before: Variant = EconomyManager.money
	var preview: Variant = IncomeManager.get_next_upgrade_cycle_payout(candidate.id) if candidate.kind == "upgrade" else 0.0
	var purchased := ButtonManager.purchase_by_id(candidate.id) if candidate.kind == "button" else IncomeManager.upgrade_source(candidate.id)
	if not purchased:
		_failure = "최저가 항목 구매에 실패했습니다: " + str(candidate.name)
		return false
	if candidate.kind == "upgrade" and (IncomeManager.get_source_level(candidate.id) != int(candidate.level) + 1 \
		or BIG.compare(IncomeManager.get_source_cycle_payout(candidate.id), preview) != 0):
		_failure = "레벨 또는 다음 레벨 수입 미리보기가 실제 구매와 다릅니다: " + str(candidate.name)
		return false
	var action := {"run": _run_index, "frame": _frame, "run_frame": _frame - _run_start_frame,
		"kind": candidate.kind, "id": candidate.id, "name": candidate.name, "cost": candidate.cost,
		"wait_frames": _frame - _last_purchase_in_run, "money_before": money_before,
		"money_after": EconomyManager.money, "rate": IncomeManager.get_total_income_per_second()}
	_actions.append(action)
	_candidate_dirty = true
	_last_purchase_in_run = _frame
	if candidate.kind == "button":
		action["unlock_frame"] = int(_unlock_frames[candidate.id])
		action["button_wait_frames"] = _frame - _last_button_in_run
		_button_log.append(action)
		_last_button_in_run = _frame
	_record("버튼" if candidate.kind == "button" else "레벨업", "%s [%s] · %s · 잔액 %s · 수입 %s원/초" % [
		candidate.name, candidate.id, _won(candidate.cost), _won(EconomyManager.money),
		NUMBER_FORMATTER.format_income_per_second(action.rate)])
	return true


func _perform_prestige() -> void:
	if not PrestigeManager.can_prestige():
		_failure = "짬통 구매 후 짬 환생을 실행할 수 없습니다."
		return
	var jjam_before: Variant = PrestigeManager.get_current_jjam()
	var money_before: Variant = EconomyManager.money
	if not PrestigeManager.jjam_prestige():
		_failure = "짬 환생에 실패했습니다."
		return
	_prestiges_done += 1
	_prestige_records.append({"frame": _frame, "jjam": jjam_before, "money": money_before,
		"banked": PrestigeManager.banked_jjam, "multiplier": PrestigeManager.get_prestige_multiplier()})
	_record("짬 환생", "획득 짬 %s · 누적 환생 짬 %s · 환생 배율 %s배 · 초기화 전 자금 %s" % [
		NUMBER_FORMATTER.format_number(jjam_before), NUMBER_FORMATTER.format_number(PrestigeManager.banked_jjam),
		NUMBER_FORMATTER.format_number(PrestigeManager.get_prestige_multiplier()), _won(money_before)])
	_run_index = 2
	_run_start_frame = _frame
	_last_purchase_in_run = _frame
	_last_button_in_run = _frame
	_unlock_frames.clear()
	_candidate_dirty = true
	_rate_dirty = true
	_dm_ready = false


func _on_event_started(data: GameEventData) -> void:
	if data is PhoneDMEventData:
		_dm_started += 1
		_dm_bargains = 0
		_dm_ready = false
		_record("DM 시작", EventManager.get_phone_dm_contact())
	else:
		# Acknowledge presentations with no economic choice; omit their animation time.
		_record("안내 이벤트", data.id)
		EventManager.finish_event(data.id, "acknowledged" if data.id == EventManager.CAT_WATCHING_ID else "completed")


func _on_dm_choices(available: bool, can_bargain: bool, offer: Variant) -> void:
	_dm_ready = available
	_dm_can_bargain = can_bargain
	_dm_offer = offer


func _handle_dm_choice() -> void:
	if not _dm_ready:
		return
	var bargain := _dm_can_bargain and _dm_bargains < 2
	var offer: Variant = _dm_offer
	_dm_ready = false
	if not EventManager.choose_phone_dm(EventManager.Choice.BARGAIN if bargain else EventManager.Choice.ACCEPT):
		_failure = "DM 응답에 실패했습니다."
		return
	if bargain:
		_dm_bargains += 1
	_record("DM 흥정" if bargain else "DM 수락", "%d회 흥정 · 제안 %s" % [_dm_bargains, _won(offer)])


func _on_dm_resolved(accepted: bool, reward: Variant) -> void:
	if accepted:
		_dm_accepted += 1
	else:
		_dm_rejected += 1
	_record("DM 거래 성립" if accepted else "DM 결렬", "%d회 흥정 · 보상 %s" % [_dm_bargains, _won(reward)])


func _on_event_finished(event_id: String, result: String) -> void:
	if event_id == EventManager.PHONE_DM_ID:
		_dm_ready = false
		_record("DM 종료", result)


func _on_reward_deposit(reward_id: int) -> void:
	var amount: Variant = EventManager.get_reward_remaining(reward_id)
	var remaining: Variant = EventManager.advance_reward_deposit(reward_id, 1.0)
	if BIG.compare(remaining, 0.0) != 0:
		_failure = "DM 보상 입금이 완료되지 않았습니다."
		return
	_dm_deposited = BIG.add(_dm_deposited, amount)
	_record("DM 입금", "%s · 잔액 %s" % [_won(amount), _won(EconomyManager.money)])


func _record(kind: String, detail: String) -> void:
	_timeline.append("%s\t%d\t%s\t%s" % [_duration(_frame), _run_index, kind, detail.replace("\n", " ")])


func _wait_text(wait: Variant) -> String:
	if wait is float and is_inf(wait):
		return "무한대 (생산 수입 0)"
	return NUMBER_FORMATTER.format_income_per_second(wait) + "초"


func _write_report() -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir())) != OK:
		return false
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line("최저가 구매 밸런스 테스트 V2 — 짬 환생 1회 / DM 최대 2회 흥정 후 수락")
	file.store_line("결과: %s — %s" % [_status, _end_reason])
	file.store_line("총 가상 플레이 시간: " + _duration(_frame))
	file.store_line("버튼 구매 %d회 / 레벨업 %d회 / 짬 환생 %d회 / 현재 %d회차" % [
		_button_log.size(), _actions.size() - _button_log.size(), _prestiges_done, _run_index])
	file.store_line("DM 시작 %d회 / 수락 %d회 / 결렬 %d회 / 실제 입금 합계 %s / 난수 시드 %d" % [
		_dm_started, _dm_accepted, _dm_rejected, _won(_dm_deposited), event_seed])
	file.store_line("현재 자금 %s / 현재 초당 수입 %s원" % [_won(EconomyManager.money), NUMBER_FORMATTER.format_income_per_second(IncomeManager.get_total_income_per_second())])
	file.store_line("구매 규칙: 해금된 미구매 버튼과 활성 수입원의 다음 레벨업 중 최저가. 동률은 버튼 우선, 이후 등록 순서.")
	file.store_line("환생 규칙: 짬통을 구매해 짬 환생이 열리면 진행 중 DM 종료·입금 후 1회 실행. 이후에는 환생하지 않음.")
	file.store_line("대기 규칙: max(가격 - 현재 자금, 0) / 반올림 전 총 초당 생산 수입이 %.0f초 이상이면 즉시 종료. 미래 DM 수익은 예상에 포함하지 않음." % max_expected_wait_seconds)
	file.store_line("가상 시간 60FPS. 생산·추첨·대화 지연·쿨타임은 실제 로직. 클릭·안내·환생·입금 애니메이션 시간은 생략.")
	file.store_line("DM 확률과 보상 설정은 게임 리소스 그대로 사용. 흥정 중 결렬되면 해당 DM은 종료되며 다음 DM에서 다시 최대 2회 시도.")
	file.store_line("완료 조건: 환생 1회 후 모든 등록 버튼을 구매한 상태. 테스트 전용 저장소만 사용하며 플레이어 저장을 읽거나 덮어쓰지 않음.")
	if not _stop_snapshot.is_empty():
		var candidate: Dictionary = _stop_snapshot.candidate
		file.store_line("종료 대상: %s [%s] / 가격 %s / 보유 자금 %s / 부족액 %s / 수입 %s원/초 / 예상 대기 %s" % [
			candidate.name, candidate.id, _won(candidate.cost), _won(_stop_snapshot.money),
			_won(BIG.subtract(candidate.cost, _stop_snapshot.money)),
			NUMBER_FORMATTER.format_income_per_second(_stop_snapshot.rate), _wait_text(_stop_snapshot.wait)])
	file.store_line("")
	file.store_line("[짬 환생]")
	for record in _prestige_records:
		file.store_line("%s / 획득 짬 %s / 누적 환생 짬 %s / 배율 %s배 / 초기화 전 자금 %s" % [
			_duration(record.frame), NUMBER_FORMATTER.format_number(record.jjam), NUMBER_FORMATTER.format_number(record.banked),
			NUMBER_FORMATTER.format_number(record.multiplier), _won(record.money)])
	file.store_line("")
	file.store_line("[버튼 구매 요약]")
	file.store_line("순서\t회차\t이름 [ID]\t가격\t누적 시간\t회차 시간\t이전 버튼 이후\t해금 후 대기")
	for index in _button_log.size():
		var action: Dictionary = _button_log[index]
		file.store_line("%d\t%d\t%s [%s]\t%s\t%s\t%s\t%s\t%s" % [index + 1, action.run, action.name, action.id,
			_won(action.cost), _duration(action.frame), _duration(action.run_frame), _duration(action.button_wait_frames),
			_duration(int(action.frame) - int(action.unlock_frame))])
	file.store_line("")
	file.store_line("[전체 구매 기록]")
	file.store_line("순서\t회차\t종류\t이름 [ID]\t가격\t누적 시간\t회차 시간\t이전 구매 이후\t구매 전 자금\t구매 후 자금\t구매 후 초당 수입")
	for index in _actions.size():
		var action: Dictionary = _actions[index]
		file.store_line("%d\t%d\t%s\t%s [%s]\t%s\t%s\t%s\t%s\t%s\t%s\t%s원/초" % [index + 1, action.run,
			"버튼" if action.kind == "button" else "레벨업", action.name, action.id, _won(action.cost),
			_duration(action.frame), _duration(action.run_frame), _duration(action.wait_frames),
			_won(action.money_before), _won(action.money_after), NUMBER_FORMATTER.format_income_per_second(action.rate)])
	file.store_line("")
	file.store_line("[이벤트·환생·구매 통합 타임라인]")
	file.store_line("누적 시간\t회차\t종류\t상세")
	for line in _timeline:
		file.store_line(line)
	file.store_line("")
	file.store_line("[종료 시 미구매 버튼]")
	for button in ButtonManager.buttons:
		if button != null and not button.bought:
			file.store_line("%s [%s]\t%s\t%s" % [button.button_name, button.id, _won(button.get_price()), "해금" if ButtonManager.is_unlocked(button) else "잠김"])
	for error in ErrorManager.get_errors():
		file.store_line(str(error))
	file.flush()
	var success := file.get_error() == OK
	file.close()
	return success


func _check_income_curves() -> void:
	for source in IncomeManager.sources:
		if source == null:
			continue
		var expected_ratio := pow(source.upgrade_income_growth_multiplier, 1.0 / float(source.upgrade_income_growth_levels))
		for level in [1, 2, 3, 17, 50, 51, 101, 5001, 100001]:
			var payout: Variant = IncomeManager._get_source_payout_at_level(source, level)
			var next_payout: Variant = IncomeManager._get_source_payout_at_level(source, level + 1)
			var window_payout: Variant = IncomeManager._get_source_payout_at_level(source, level + source.upgrade_income_growth_levels)
			if not BIG.valid(payout, false) or BIG.compare(next_payout, payout) <= 0:
				_failure = "레벨업 곡선에 유효한 수입 증가가 없습니다: " + source.source_name
				return
			if level == 1 and BIG.compare(payout, source.get_base_income()) != 0:
				_failure = "Lv.1 수입이 기본 수입과 다릅니다: " + source.source_name
				return
			var ratio := float(BIG.divide(next_payout, payout))
			var window_ratio := float(BIG.divide(window_payout, payout))
			if absf(ratio / expected_ratio - 1.0) > 1.0e-9 or absf(window_ratio / source.upgrade_income_growth_multiplier - 1.0) > 1.0e-9:
				_failure = "수입이 설정된 지수 성장 배율을 따르지 않습니다: " + source.source_name
				return
		# Editing a .tres setting during play must also invalidate cached income.
		var original_multiplier := source.upgrade_income_growth_multiplier
		var original_levels := source.upgrade_income_growth_levels
		var original_base := source.base_income
		var original_override := source.large_base_income
		var sample_level := original_levels + 1
		var before: Variant = IncomeManager._get_source_payout_at_level(source, sample_level)
		source.upgrade_income_growth_multiplier = original_multiplier * 2.0
		var raised_growth: Variant = IncomeManager._get_source_payout_at_level(source, sample_level)
		source.upgrade_income_growth_multiplier = original_multiplier
		source.upgrade_income_growth_levels = original_levels * 2
		var slower_growth: Variant = IncomeManager._get_source_payout_at_level(source, sample_level)
		source.upgrade_income_growth_levels = original_levels
		source.large_base_income = "2e500"
		var large_base: Variant = IncomeManager._get_source_payout_at_level(source, sample_level)
		source.large_base_income = original_override
		source.base_income = original_base * 2.0
		var raised_base: Variant = IncomeManager._get_source_payout_at_level(source, sample_level)
		source.base_income = original_base
		var restored: Variant = IncomeManager._get_source_payout_at_level(source, sample_level)
		var expected_base_factor := 2.0 if original_override.strip_edges().is_empty() else 1.0
		if absf(float(BIG.divide(raised_growth, before)) - 2.0) > 1.0e-10 \
			or BIG.compare(slower_growth, before) >= 0 \
			or absf(float(BIG.divide(raised_base, before)) - expected_base_factor) > 1.0e-10 \
			or absf(float(BIG.divide(large_base, BIG.multiply(BIG.parse("2e500"), original_multiplier))) - 1.0) > 1.0e-10 \
			or BIG.compare(restored, before) != 0:
			_failure = "수입원 설정을 변경해도 이전 캐시가 유지됩니다: " + source.source_name
			return


func _get_cheapest_candidate() -> Dictionary:
	var cheapest: Dictionary = {}
	# Equal prices prefer buttons; within each category retain registration order.
	for button in ButtonManager.buttons:
		if button == null or button.bought or not ButtonManager.is_unlocked(button):
			continue
		if not _unlock_frames.has(button.id):
			_unlock_frames[button.id] = _frame
		var cost: Variant = BIG.rounded(button.get_price())
		if cheapest.is_empty() or BIG.compare(cost, cheapest.cost) < 0:
			cheapest = {"kind": "button", "id": button.id, "name": button.button_name, "cost": cost}
	for source in IncomeManager.sources:
		if source == null or not IncomeManager.source_active.get(source.id, false):
			continue
		var cost: Variant = IncomeManager.get_upgrade_cost(source.id)
		if BIG.compare(cost, 0.0) > 0 and (cheapest.is_empty() or BIG.compare(cost, cheapest.cost) < 0):
			var level := IncomeManager.get_source_level(source.id)
			cheapest = {
				"kind": "upgrade", "id": source.id, "cost": cost, "level": level,
				"name": "%s Lv.%d → Lv.%d" % [source.source_name, level, level + 1]
			}
	return cheapest


func _has_unpurchased_buttons() -> bool:
	for button in ButtonManager.buttons:
		if button != null and not button.bought:
			return true
	return false


func _seconds(frames: int) -> float:
	return float(frames) / float(SIMULATION_FPS)


func _duration(frames: int) -> String:
	var seconds := _seconds(frames)
	var minutes := floori(seconds / 60.0)
	return "%.2f초 (%d분 %05.2f초)" % [seconds, minutes, seconds - minutes * 60.0]


func _won(amount: Variant) -> String:
	return NUMBER_FORMATTER.format_number(amount) + "원"
