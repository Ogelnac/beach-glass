extends TouchScreenButton

@onready var control: Control = $".."
@export var offset: float = 100.0

func _ready() -> void:
	var ratio = float(get_window().size.x) / float(get_window().size.y)
	position = control.size - (texture_normal.region.size * scale) - Vector2(offset * ratio, offset / ratio)
