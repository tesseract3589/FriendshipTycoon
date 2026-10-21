class_name JjamCatEffectData
extends Resource

## Reusable cat effect scene and timing for jjam prestige rewards.
@export var effect_scene: PackedScene
@export_range(1, 200, 1) var count: int = 30
@export_range(0.0, 5.0, 0.01) var spawn_duration: float = 0.3
@export_range(0.01, 5.0, 0.01) var pop_duration: float = 0.12
@export_range(0.01, 5.0, 0.01) var absorption_duration: float = 1.0
@export var size_range := Vector2(48.0, 88.0)
