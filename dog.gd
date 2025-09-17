extends CharacterBody3D

@onready var cam: Camera3D = $Camera3D
@onready var anim: AnimationPlayer = $AnimationPlayer

var move_speed = 6.0
var accel = 12.0
var decel = 16.0
var turn_speed = 10.0
var cam_sens = 0.005
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

func _ready():
	if cam != null:
		var to_cam = cam.global_transform.origin - (global_transform.origin + Vector3(0, cam_target_height, 0))
		if to_cam.length() > 0.01:
			yaw = atan2(to_cam.x, -to_cam.z)
	_update_camera(0.0)

func _unhandled_input(event):
	var half = get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and left_id == -1:
				left_id = event.index
				left_origin = event.position
				left_vec = Vector2.ZERO
			elif event.position.x >= half and right_id == -1:
				right_id = event.index
				right_last = event.position
		else:
			if event.index == left_id:
				left_id = -1
				left_vec = Vector2.ZERO
			if event.index == right_id:
				right_id = -1
	if event is InputEventScreenDrag:
		if event.index == left_id:
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
	var target_vel = world_dir * move_speed
	if world_dir != Vector3.ZERO:
		velocity = velocity.lerp(target_vel, accel * delta)
		var desired = atan2(world_dir.x, world_dir.z)
		var ang = lerp_angle(rotation.y, desired, clamp(turn_speed * delta, 0.0, 1.0))
		rotation.y = ang
	else:
		velocity = velocity.lerp(Vector3.ZERO, decel * delta)
	move_and_slide()
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
	if velocity.length() > 0.1:
		if anim.current_animation != "Walk":
			anim.play("Walk")
	else:
		if anim.current_animation != "Idle":
			anim.play("Idle")
