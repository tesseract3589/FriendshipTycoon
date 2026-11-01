@tool
class_name GameEventData
extends Resource

## Register event resources in EventManager.events. Presentation listens to its signals.
enum Trigger { INSTANT = 0, RANDOM = 1 }

@export var id: String = ""
@export var enabled: bool = true
@export var unlock_condition: UnlockCondition
## Once the condition is met, keep this event unlocked for the entire save slot.
@export var permanent_unlock: bool = false
## Instant starts as soon as unlock_condition is met. Random rolls at each interval.
@export var trigger: Trigger = Trigger.RANDOM:
	set(value):
		trigger = value
		notify_property_list_changed()
## Mark as consumed at first start; prestige does not reset this saved record.
@export var one_off: bool = false
## Disallow starting after the first prestige, even if the event has never occurred.
@export var no_prestige_only: bool = false
## Require this many jjam prestiges before the unlock condition can trigger.
@export_range(0, 1000000, 1) var minimum_prestige_count: int = 0
## -1 leaves the upper limit open; 1 restricts an event to the first prestige run.
@export_range(-1, 1000000, 1) var maximum_prestige_count: int = -1
## Random only: seconds between independent rolls, unrelated to production speed.
@export_range(0.01, 86400.0, 0.01) var roll_interval_seconds: float = 1.0
## Random only: probability per roll. 0.03 means 3%, regardless of interval length.
@export_range(0.0, 1.0, 0.001) var chance_per_roll: float = 0.03
@export_range(0.0, 86400.0, 1.0) var cooldown_seconds: float = 300.0


func _validate_property(property: Dictionary) -> void:
	if property.name in ["roll_interval_seconds", "chance_per_roll"] and trigger == Trigger.INSTANT:
		property.usage |= PROPERTY_USAGE_READ_ONLY
