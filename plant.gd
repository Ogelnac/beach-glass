extends Node3D

@export var lerp_speed := 6.0
var grazed := false

func _process(delta: float) -> void:
	var target := Vector3.ONE * (0.75 if grazed else 1.0)
	scale = scale.lerp(target, min(1.0, delta * lerp_speed))
