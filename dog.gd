extends RigidBody3D

@onready var cam: Camera3D = $Camera3D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var texture_button: TextureButton = $"../../../TextureButton"

@export var run_multiplier := 1.7

var move_speed = 6.0
var accel = 12.0
var decel = 16.0
var turn_speed = 10.0
var cam_sens = 0.01
var cam_distance = 6.0
var cam_target_height = 1.5
var cam_collision = true
var cam_collision_margin = 0.25
var yaw = 0.0
var pitch = -0.6
var pitch_min = deg_to_rad(-80)
var pitch_max = deg_to_rad(25)

var left_id = -1
var right_id = -1
var left_origin = Vector2.ZERO
var left_vec = Vector2.ZERO
var right_last = Vector2.ZERO
var stick_radius = 100.0

var run_held := false
var run_touch_id := -1

func _ready():
	gravity_scale = 0.0
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	angular_damp = 8.0
	if texture_button:
		texture_button.button_down.connect(_on_run_down)
		texture_button.button_up.connect(_on_run_up)
	if cam != null:
		var to_cam = cam.global_transform.origin - (global_transform.origin + Vector3(0, cam_target_height, 0))
		if to_cam.length() > 0.01:
			yaw = atan2(to_cam.x, -to_cam.z)
	_update_camera(0.0)

func _on_run_down():
	run_held = true

func _on_run_up():
	run_held = false
	run_touch_id = -1

func _is_on_run_button(pos: Vector2) -> bool:
	return texture_button != null and texture_button.get_global_rect().has_point(pos)

func _unhandled_input(event):
	var half = get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if _is_on_run_button(event.position) and run_touch_id == -1:
				run_touch_id = event.index
				run_held = true
			elif event.position.x < half and left_id == -1:
				left_id = event.index
				left_origin = event.position
				left_vec = Vector2.ZERO
			elif event.position.x >= half and right_id == -1 and not _is_on_run_button(event.position):
				right_id = event.index
				right_last = event.position
		else:
			if event.index == run_touch_id:
				run_touch_id = -1
				run_held = false
			if event.index == left_id:
				left_id = -1
				left_vec = Vector2.ZERO
			if event.index == right_id:
				right_id = -1
	if event is InputEventScreenDrag:
		if event.index == run_touch_id:
			if not _is_on_run_button(event.position):
				run_touch_id = -1
				run_held = false
		elif event.index == left_id:
			var v = event.position - left_origin
			if v.length() > stick_radius:
				v = v.normalized() * stick_radius
			left_vec = v / stick_radius
		elif event.index == right_id:
			var d = event.position - right_last
			right_last = event.position
			yaw -= d.x * cam_sens
			pitch = clamp(pitch - d.y * cam_sens, pitch_min, pitch_max)

func _physics_process(delta):
	var world_dir = Vector3.ZERO
	if left_vec.length() > 0.01:
		var f = -global_transform.basis.z
		var r = global_transform.basis.x
		if cam != null:
			f = -cam.global_transform.basis.z
			r = cam.global_transform.basis.x
		f.y = 0.0
		r.y = 0.0
		f = f.normalized()
		r = r.normalized()
		var stick = Vector2(left_vec.x, -left_vec.y)
		world_dir = (r * stick.x + f * stick.y).normalized()
	var speed = move_speed * (run_multiplier if run_held else 1.0)
	var target_vel = world_dir * speed
	var horiz = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if world_dir != Vector3.ZERO:
		horiz = horiz.lerp(target_vel, accel * delta)
		var desired = atan2(world_dir.x, world_dir.z)
		var ang = lerp_angle(rotation.y, desired, clamp(turn_speed * delta, 0.0, 1.0))
		rotation.y = ang
		angular_velocity.y = 0.0
	else:
		horiz = horiz.lerp(Vector3.ZERO, decel * delta)
		angular_velocity.y = 0.0
	linear_velocity = Vector3(horiz.x, 0.0, horiz.z)
	_update_camera(delta)
	_update_anim()

func _update_camera(_delta):
	if cam == null:
		return
	var target = global_transform.origin + Vector3(0, cam_target_height, 0)
	var dir = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()
	var desired_pos = target - dir * cam_distance
	if cam_collision:
		var space = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(target, desired_pos)
		query.exclude = [self]
		query.collide_with_areas = false
		var hit = space.intersect_ray(query)
		if hit.has("position"):
			var hp = hit.position + hit.normal * cam_collision_margin
			desired_pos = hp
	cam.global_transform = Transform3D(Basis(), desired_pos)
	cam.look_at(target, Vector3.UP)

func _update_anim():
	if anim == null:
		return
	var spd = Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()
	if spd > 0.1:
		if run_held:
			if anim.current_animation != "Run":
				anim.play("Run")
		else:
			if anim.current_animation != "Walk":
				anim.play("Walk")
	else:
		if anim.current_animation != "Idle":
			anim.play("Idle")
