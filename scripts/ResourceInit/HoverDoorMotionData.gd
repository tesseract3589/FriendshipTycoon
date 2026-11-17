class_name HoverDoorMotionData
extends Resource

@export var animation: StringName = &"default"
@export_range(0, 1000, 1) var closed_frame: int = 0
@export_range(1, 1000, 1) var open_frame: int = 24
## Uniform pose rate, independent of holds/loops in the source preview animation.
@export_range(1.0, 120.0, 1.0) var frames_per_second: float = 20.0
