class_name PhoneDMDialogueData
extends Resource

## One resource contains the entire conversation. Offer lines use {amount}, without 원.
@export var contact_name: String = "부식 구매자"
@export_multiline var greeting: String = ""
@export_multiline var introduction: String = ""
@export_multiline var offer_1: String = ""
@export_multiline var refusal_1: String = ""
@export_multiline var offer_2: String = ""
@export_multiline var refusal_2: String = ""
@export_multiline var offer_3: String = ""
@export_multiline var refusal_3: String = ""
@export_multiline var final_offer: String = ""
@export_multiline var acceptance: String = ""
@export_multiline var breakdown: String = ""

@export_group("Player Replies")
@export_multiline var player_accept: String = "좋습니다. {amount}원에 보내드릴게요."
@export_multiline var player_bargain: String = "조금 더 쳐주실 수 있을까요?"
@export_multiline var player_reject: String = "죄송하지만 이번 거래는 어렵겠습니다."


func get_offer(stage: int) -> String:
	return [offer_1, offer_2, offer_3, final_offer][clampi(stage, 0, 3)]


func get_refusal(stage: int) -> String:
	return [refusal_1, refusal_2, refusal_3][clampi(stage, 0, 2)]


func is_complete() -> bool:
	for line in [contact_name, greeting, introduction, refusal_1, refusal_2, refusal_3, acceptance, breakdown, player_accept, player_bargain, player_reject]:
		if line.strip_edges().is_empty():
			return false
	for stage in range(4):
		if not get_offer(stage).contains("{amount}"):
			return false
	return true
