class_name ColdMistData
extends Resource

@export var emission_rect: Rect2 = Rect2(-150, 245, 300, 45)
@export_range(1, 64, 1) var wisp_count: int = 18
@export var random_seed: int = 17
@export_range(0.1, 10.0, 0.1) var lifetime: float = 1.8
@export var horizontal_speed: Vector2 = Vector2(-42, 42)
@export var downward_speed: Vector2 = Vector2(12, 30)
@export var radius_range: Vector2 = Vector2(12, 34)
@export var color: Color = Color(0.82, 0.96, 1.0, 0.32)
