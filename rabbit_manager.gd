extends Node

@export var rabbit_scene: PackedScene
@onready var holes: Node = $"../Holes"

var timer: Timer

func _ready() -> void:
	_schedule_timer()
	_spawn_rabbit()

func _schedule_timer():
	if timer:
		timer.queue_free()
	timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = randf_range(10.0, 20.0)
	add_child(timer)
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

func _on_timer_timeout():
	print("time out")
	_spawn_rabbit()
	_schedule_timer()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_0 or event.keycode == KEY_KP_0:
			_spawn_rabbit()

func _spawn_rabbit():
	if holes.get_child_count() == 0:
		return
	var rand_ind = randi_range(0, holes.get_child_count() - 1)
	var instance = rabbit_scene.instantiate()
	var hole: MeshInstance3D = holes.get_child(rand_ind)
	instance.position = hole.position
	add_child(instance)
