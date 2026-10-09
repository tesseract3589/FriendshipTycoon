@tool
class_name SceneRenderLayer
extends Node2D

const RENDER_ORDER = preload("res://scripts/RenderOrder.gd")

@export_category("Rendering")
@export var render_layer: RENDER_ORDER.WorldLayer = RENDER_ORDER.WorldLayer.OBJECT:
	set(value):
		render_layer = value
		RENDER_ORDER.apply_world_layer(self, render_layer)


func _ready() -> void:
	RENDER_ORDER.apply_world_layer(self, render_layer)
