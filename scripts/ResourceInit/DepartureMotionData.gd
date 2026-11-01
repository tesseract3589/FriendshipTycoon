class_name DepartureMotionData
extends Resource

@export_range(1.0, 2000.0, 1.0, "or_greater") var acceleration: float = 180.0
@export_range(1.0, 2000.0, 1.0, "or_greater") var maximum_speed: float = 420.0
## Optional income source whose speed bonuses also scale driving motion.
@export var speed_source_id: String = ""
## Source speed already present when this vehicle first becomes available.
@export_range(0.01, 100.0, 0.01, "or_greater") var source_speed_baseline: float = 1.0
## Normalize existing global speed bonuses to preserve the reference driving speed.
## At global speed 1, driving speed/acceleration are the reference values divided by this.
@export_range(0.01, 100.0, 0.01, "or_greater") var global_speed_baseline: float = 1.0
## Visual speed cap only; income production is never capped by this resource.
@export_range(1.0, 10.0, 0.1, "or_greater") var maximum_speed_multiplier: float = 1.0
@export_range(0.0, 10.0, 0.1, "or_greater") var respawn_delay: float = 1.0
@export_range(0.01, 5.0, 0.01, "or_greater") var fade_duration: float = 0.6
## Extra distance the rear must travel beyond the maximum scroll edge, in world pixels.
@export_range(0.0, 100.0, 1.0, "or_greater") var world_exit_margin: float = 0.0
