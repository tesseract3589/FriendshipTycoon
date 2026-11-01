class_name JjamShopItemData
extends Resource

const BIG = preload("res://scripts/BigNumber.gd")

## Each item permanently unlocks one feature in the current save slot.
@export var id: String = ""
@export var item_name: String = ""
@export var icon: Texture2D
@export_multiline var description: String = ""
@export_range(1, 1000000000, 1, "or_greater") var price: int = 100
## 큰 수 가격 덮어쓰기. 예: "25e16", "1.25e500". 비워 두면 price를 사용합니다.
@export var large_price: String = ""
@export var feature_id: StringName = &""
## Chained upgrades share one shop card; the successor appears after ownership.
@export var prerequisite_item_id: String = ""
@export var next_item_id: String = ""
## Values above one unlock a selectable income upgrade mode.
@export_range(1, 1000, 1, "or_greater") var upgrade_levels: int = 1


func get_price() -> Variant:
	return price if large_price.strip_edges().is_empty() else BIG.parse(large_price)
