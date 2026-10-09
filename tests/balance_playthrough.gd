extends Node

const NUMBER_FORMATTER = preload("res://scripts/NumberFormatter.gd")
const LOG_PATH := "res://logs/balance_playthrough.txt"
const SIMULATION_FPS: int = 60
const MAX_SIMULATION_SECONDS: int = 86400
const MAX_PURCHASES: int = 10000
const MIN_RESTAURANT_SECONDS: float = 120.0
const MAX_RESTAURANT_SECONDS: float = 180.0
const MIN_FRONT_DOOR_UNLOCK_SECONDS: float = 600.0

var _frame: int = 0
var _last_purchase_frame: int = 0
var _last_button_frame: int = 0
var _unlock_frames: Dictionary = {}
var _button_purchase_frames: Dictionary = {}
var _button_records: Array[String] = []
var _purchase_records: Array[String] = []
var _failure: String = ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Advance the actual production logic ourselves at 60 FPS, without real-time waits.
	IncomeManager.set_process(false)
	if not ErrorManager.get_errors().is_empty():
		_failure = "시작 시 게임 데이터 오류가 있습니다."
	else:
		PrestigeManager.total_jjam = 0
		PrestigeManager.current_jjam = 0
		EconomyManager.reset_money()
		EconomyManager.set_global_multiplier(1.0)
		ButtonManager.reset_for_prestige()
		await _play()
		if _failure.is_empty():
			_check_pacing()
	if not ErrorManager.get_errors().is_empty() and _failure.is_empty():
		_failure = "플레이 중 게임 오류가 발생했습니다."
	if not _write_report():
		_failure = "결과 파일을 저장하지 못했습니다: " + LOG_PATH
	if _failure.is_empty():
		print("PASS: cheapest-first playthrough; %d buttons, %d total purchases, %.2f simulated seconds; %s" % [
			_button_records.size(), _purchase_records.size(), _seconds(_frame), LOG_PATH
		])
	else:
		push_error(_failure)
	get_tree().quit(0 if _failure.is_empty() else 1)


func _play() -> void:
	while _has_unpurchased_buttons():
		if _frame >= MAX_SIMULATION_SECONDS * SIMULATION_FPS or _purchase_records.size() >= MAX_PURCHASES:
			_failure = "안전 한도에 도달했습니다. 해금 조건과 진행 속도를 확인하세요."
			return
		var candidate := _get_cheapest_candidate()
		if not candidate.is_empty() and EconomyManager.can_afford(float(candidate.cost)):
			if not _purchase(candidate):
				return
			# Re-evaluate immediately: a purchase may unlock a cheaper button.
			continue
		if not _has_production_income():
			_failure = "구매할 자금과 생산 수입이 없어 진행이 멈췄습니다."
			return
		IncomeManager._process(1.0 / float(SIMULATION_FPS))
		_frame += 1
		if not ErrorManager.get_errors().is_empty():
			_failure = "플레이 중 게임 오류가 발생했습니다."
			return
		if _frame % 3600 == 0:
			await get_tree().process_frame


func _get_cheapest_candidate() -> Dictionary:
	var cheapest: Dictionary = {}
	# Equal prices prefer buttons; within each category retain registration order.
	for button in ButtonManager.buttons:
		if button == null or button.bought or not ButtonManager.is_unlocked(button):
			continue
		if not _unlock_frames.has(button.id):
			_unlock_frames[button.id] = _frame
		var cost := roundf(button.price)
		if cheapest.is_empty() or cost < float(cheapest.cost):
			cheapest = {"kind": "button", "id": button.id, "name": button.button_name, "cost": cost}
	for source in IncomeManager.sources:
		if source == null or not IncomeManager.source_active.get(source.id, false):
			continue
		var cost := IncomeManager.get_upgrade_cost(source.id)
		if cost > 0.0 and (cheapest.is_empty() or cost < float(cheapest.cost)):
			var level := IncomeManager.get_source_level(source.id)
			cheapest = {
				"kind": "upgrade", "id": source.id, "cost": cost, "level": level,
				"name": "%s Lv.%d → Lv.%d" % [source.source_name, level, level + 1]
			}
	return cheapest


func _purchase(candidate: Dictionary) -> bool:
	var money_before := EconomyManager.money
	var preview_payout := IncomeManager.get_next_upgrade_cycle_payout(candidate.id) if candidate.kind == "upgrade" else 0.0
	var success: bool
	if candidate.kind == "button":
		success = ButtonManager.purchase_by_id(candidate.id)
	else:
		success = IncomeManager.upgrade_source(candidate.id)
	if not success:
		_failure = "최저가 항목 구매에 실패했습니다: " + str(candidate.name)
		return false
	if EconomyManager.money != money_before - float(candidate.cost):
		_failure = "구매 가격과 실제 차감액이 다릅니다: " + str(candidate.name)
		return false
	if candidate.kind == "upgrade" and IncomeManager.get_source_level(candidate.id) != int(candidate.level) + 1:
		_failure = "수입원 레벨이 정상적으로 증가하지 않았습니다: " + str(candidate.name)
		return false
	if candidate.kind == "upgrade" and IncomeManager.get_source_cycle_payout(candidate.id) != preview_payout:
		_failure = "다음 레벨 미리보기와 실제 회당 수입이 다릅니다: " + str(candidate.name)
		return false
	var order := _purchase_records.size() + 1
	_purchase_records.append("%d\t%s\t%s\t%s\t%s\t%s\t%s" % [
		order, "버튼" if candidate.kind == "button" else "레벨업", candidate.name,
		_won(candidate.cost), _duration(_frame), _duration(_frame - _last_purchase_frame),
		_won(IncomeManager.get_total_income_per_second()) + "/초"
	])
	_last_purchase_frame = _frame
	if candidate.kind == "button":
		_button_purchase_frames[candidate.id] = _frame
		_button_records.append("%d\t%s [%s]\t%s\t%s\t%s\t%s\t%s" % [
			_button_records.size() + 1, candidate.name, candidate.id, _won(candidate.cost),
			_duration(_frame), _duration(_frame - _last_button_frame),
			_duration(int(_unlock_frames[candidate.id])),
			_duration(_frame - int(_unlock_frames[candidate.id]))
		])
		_last_button_frame = _frame
	return true


func _check_pacing() -> void:
	if not _button_purchase_frames.has("restaurant") or not _unlock_frames.has("front_door"):
		_failure = "간부식당 구매 또는 평범한 유리문 해금 기록이 없습니다."
		return
	var restaurant_seconds := _seconds(int(_button_purchase_frames["restaurant"]))
	if restaurant_seconds < MIN_RESTAURANT_SECONDS or restaurant_seconds > MAX_RESTAURANT_SECONDS:
		_failure = "간부식당 구매가 2~3분 목표를 벗어났습니다: %.2f초" % restaurant_seconds
		return
	var door_unlock_seconds := _seconds(int(_unlock_frames["front_door"]))
	if door_unlock_seconds < MIN_FRONT_DOOR_UNLOCK_SECONDS:
		_failure = "평범한 유리문이 10분 전에 해금되었습니다: %.2f초" % door_unlock_seconds


func _has_unpurchased_buttons() -> bool:
	for button in ButtonManager.buttons:
		if button != null and not button.bought:
			return true
	return false


func _has_production_income() -> bool:
	for source in IncomeManager.sources:
		if source != null and IncomeManager.source_active.get(source.id, false) and IncomeManager.get_source_cycle_payout(source.id) > 0.0:
			return true
	return false


func _write_report() -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs")) != OK:
		return false
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line("최저가 구매 밸런스 테스트")
	file.store_line("결과: " + ("완료" if _failure.is_empty() else "실패 — " + _failure))
	file.store_line("총 플레이 시간: " + _duration(_frame))
	file.store_line("버튼 구매: %d개 / 전체 구매(레벨업 포함): %d회" % [_button_records.size(), _purchase_records.size()])
	file.store_line("규칙: 첫 플레이(자금 0원, 짬 0, 환생 없음). 현재 해금된 미구매 버튼과 활성 수입원의 다음 레벨업 중 가장 싼 항목을 선택.")
	file.store_line("자금이 부족하면 실제 생산 주기가 완료될 때까지 기다리고 매 프레임 다시 비교. 같은 가격은 버튼 우선, 이후 등록 순서.")
	file.store_line("실제 게임의 구매·생산·배율·원 단위 반올림을 사용. 60FPS 가상 시간, 클릭 지연 없음. 모든 버튼 구매 시 종료.")
	file.store_line("초기 영구 구매 항목은 게임 초기화 규칙에 따르며 구매 기록에서 제외.")
	file.store_line("진행 목표: 간부식당 구매 2~3분, 평범한 유리문 해금 최소 10분. 해금은 구매 버튼이 열리는 시점.")
	file.store_line("K=%s, 초기 p=%s, 전환 가격=%s, 후반 p=%s" % [IncomeManager.upgrade_income_coefficient,
		IncomeManager.upgrade_income_exponent, _won(IncomeManager.upgrade_income_transition_cost),
		IncomeManager.upgrade_late_income_exponent])
	for source in IncomeManager.sources:
		if source == null:
			continue
		file.store_line("%s: 기본 수입 %s / 기본 주기 %.4f초 / 첫 레벨업 %s / 선형 성장 %s / 가격 2배 간격 %s레벨 / 종료 Lv.%d" % [
			source.source_name, _won(source.base_income), source.base_time * source.time_multiplier,
			_won(source.upgrade_base_cost), source.upgrade_cost_linear_growth,
			source.upgrade_cost_doubling_levels, IncomeManager.get_source_level(source.id)
		])
	file.store_line("")
	file.store_line("[버튼 구매 요약]")
	file.store_line("순서\t버튼 이름 [ID]\t가격\t시작부터 구매까지\t이전 버튼 구매 이후\t해금 시점\t해금부터 구매까지")
	for record in _button_records:
		file.store_line(record)
	file.store_line("")
	file.store_line("[전체 구매 기록 — 레벨업 포함]")
	file.store_line("순서\t종류\t이름\t가격\t누적 시간\t이전 구매 이후\t구매 후 초당 수입")
	for record in _purchase_records:
		file.store_line(record)
	if not _failure.is_empty():
		file.store_line("")
		file.store_line("[미구매 버튼]")
		for button in ButtonManager.buttons:
			if button != null and not button.bought:
				file.store_line("%s [%s]\t%s" % [button.button_name, button.id, _won(roundf(button.price))])
		for error in ErrorManager.get_errors():
			file.store_line(str(error))
	file.flush()
	var success := file.get_error() == OK
	file.close()
	return success


func _seconds(frames: int) -> float:
	return float(frames) / float(SIMULATION_FPS)


func _duration(frames: int) -> String:
	var seconds := _seconds(frames)
	var minutes := floori(seconds / 60.0)
	return "%.2f초 (%d분 %05.2f초)" % [seconds, minutes, seconds - minutes * 60.0]


func _won(amount: float) -> String:
	return NUMBER_FORMATTER.format_number(amount) + "원"
