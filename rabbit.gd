extends CharacterBody3D

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var interact_area: Area3D = $InteractArea
@onready var alert_area: Area3D = $AlertArea
@onready var panic_area: Area3D = $PanicArea

@export var plant_manager_path: NodePath = ^"../../PlantManager"
@export var holes_path: NodePath = ^"../../Holes"
@export var move_speed := 4.5
@export var accel := 12.0
@export var decel := 16.0
@export var turn_speed := 10.0
@export var interact_radius := 1.2
@export var idle_stand_time_min := 1.0
@export var idle_stand_time_max := 2.5
@export var idle_walk_time_min := 1.5
@export var idle_walk_time_max := 3.5
@export var idle_wander_radius := 6.0
@export var flee_run_distance := 12.0
@export var side_eye_tolerance_deg := 50.0
@export var post_flee_cooldown := 3.0
@export var go_home_stress_threshold := 15.0
@export var arrive_slowdown_distance := 1.5
@export var idle_search_chance := 0.2
@export var hop_flee_speed := 1.8

enum State {SPAWNING, IDLE_GRAZING, SEARCHING, GRAZING, IDLE_ALERT, FLEEING, HEADING_HOME, HOME}
var state := State.SPAWNING

var target_plant: Node = null
var target_hole: Node = null
var watch_target: Node = null
var watch_eye := 1
var alert_bodies := {}
var panic_bodies := {}
var cooldown_t := 0.0
var stress_time := 0.0
var wander_t := 0.0
var wander_move := false
var wander_target := Vector3.ZERO
var forcing_oneshot := false
var last_pos := Vector3.ZERO
var stuck_t := 0.0

func _ready():
	randomize()
	alert_area.body_entered.connect(_on_alert_entered)
	alert_area.body_exited.connect(_on_alert_exited)
	panic_area.body_entered.connect(_on_panic_entered)
	panic_area.body_exited.connect(_on_panic_exited)
	agent.avoidance_enabled = false
	agent.path_desired_distance = 0.8
	agent.target_desired_distance = max(0.6, interact_radius * 0.8)
	_set_state(State.SPAWNING)
	_play_hop_oneshot_then(_after_spawn)
	last_pos = global_transform.origin

func _physics_process(delta):
	if state == State.FLEEING:
		stress_time += 2.0 * delta
	elif state == State.IDLE_ALERT:
		stress_time += delta
	else:
		stress_time = 0.0
	if stress_time >= go_home_stress_threshold and state in [State.FLEEING, State.IDLE_ALERT]:
		_start_heading_home()
	match state:
		State.SPAWNING:
			velocity = velocity.lerp(Vector3.ZERO, decel * delta)
		State.IDLE_GRAZING:
			_process_idle_grazing(delta)
		State.SEARCHING:
			_process_seek_target(delta, _ensure_target_plant, _on_reached_plant)
		State.GRAZING:
			velocity = velocity.lerp(Vector3.ZERO, decel * delta)
		State.IDLE_ALERT:
			_process_idle_alert(delta)
		State.FLEEING:
			_process_flee(delta)
		State.HEADING_HOME:
			_process_seek_target(delta, _ensure_target_hole, _on_reached_hole)
		State.HOME:
			velocity = velocity.lerp(Vector3.ZERO, decel * delta)
	move_and_slide()
	_update_anim()
	_update_stuck(delta)

func _process_seek_target(delta, ensure_target_fn, on_reached_fn):
	ensure_target_fn.call()
	var dest := agent.get_next_path_position()
	var to_next := dest - global_transform.origin
	to_next.y = 0.0
	var dist_to_next := to_next.length()
	if dist_to_next < 0.02:
		velocity = velocity.lerp(Vector3.ZERO, decel * delta)
	else:
		var dir := to_next / dist_to_next
		var dist_to_target := agent.distance_to_target()
		var speed := move_speed
		if dist_to_target < arrive_slowdown_distance:
			speed *= clamp(dist_to_target / arrive_slowdown_distance, 0.1, 1.0)
		var desired_vel := dir * speed
		velocity = velocity.lerp(desired_vel, accel * delta)
		var desired_yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))
	var target_pos = _current_target_position()
	if target_pos != null:
		if global_transform.origin.distance_to(target_pos) <= interact_radius or agent.is_navigation_finished():
			on_reached_fn.call()

func _process_idle_grazing(delta):
	if wander_t <= 0.0:
		if not wander_move and randf() < idle_search_chance:
			var p := _nearest_available_plant()
			if p:
				target_plant = p
				_reserve(target_plant)
				agent.target_position = _nav_snap(p.global_transform.origin)
				_set_state(State.SEARCHING)
				return
		wander_move = not wander_move
		if wander_move:
			var p2 := _nav_snap(_random_point_near(global_transform.origin, idle_wander_radius))
			wander_target = p2
			agent.target_position = p2
			wander_t = randf_range(idle_walk_time_min, idle_walk_time_max)
		else:
			agent.target_position = global_transform.origin
			wander_t = randf_range(idle_stand_time_min, idle_stand_time_max)
	else:
		wander_t -= delta
	if wander_move:
		var dest := agent.get_next_path_position()
		var to_next := dest - global_transform.origin
		to_next.y = 0.0
		var dlen := to_next.length()
		if dlen > 0.02:
			var dir := to_next / dlen
			var desired_vel := dir * move_speed
			velocity = velocity.lerp(desired_vel, accel * delta)
			var desired_yaw := atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))
		else:
			velocity = velocity.lerp(Vector3.ZERO, decel * delta)
	else:
		velocity = velocity.lerp(Vector3.ZERO, decel * delta)

func _process_idle_alert(delta):
	velocity = velocity.lerp(Vector3.ZERO, decel * delta)
	if panic_bodies.size() > 0:
		_enter_fleeing()
		return
	if alert_bodies.size() >= 2:
		_enter_fleeing()
		return
	if alert_bodies.size() == 0:
		if cooldown_t > 0.0:
			cooldown_t -= delta
		else:
			_pick_next_after_alert()
		return
	_update_watch_target()
	if watch_target == null:
		return
	var d = watch_target.global_transform.origin - global_transform.origin
	d.y = 0.0
	if d.length() < 0.001:
		return
	var d_dir = d.normalized()
	var side_dir := global_transform.basis.x if watch_eye == 1 else -global_transform.basis.x
	side_dir.y = 0.0
	side_dir = side_dir.normalized()
	var angle := acos(clamp(side_dir.dot(d_dir), -1.0, 1.0))
	if abs(rad_to_deg(angle)) > side_eye_tolerance_deg:
		var fwd_to_target := atan2(d_dir.x, d_dir.z)
		var desired_yaw := fwd_to_target - PI / 2.0 if watch_eye == 1 else fwd_to_target + PI / 2.0
		rotation.y = desired_yaw
		_play_hop_oneshot()

func _process_flee(delta):
	if panic_bodies.size() == 0:
		_set_state(State.IDLE_ALERT)
		cooldown_t = post_flee_cooldown
		return
	var threat := _closest_body(panic_bodies.keys())
	if threat == null:
		return
	var away = global_transform.origin - threat.global_transform.origin
	away.y = 0.0
	if away.length() < 0.001:
		away = -global_transform.basis.z
	var flee_target = _nav_snap(global_transform.origin + away.normalized() * flee_run_distance)
	agent.target_position = flee_target
	var dest := agent.get_next_path_position()
	var to_next := dest - global_transform.origin
	to_next.y = 0.0
	var dlen := to_next.length()
	if dlen > 0.02:
		var dir := to_next / dlen
		var desired_vel := dir * move_speed
		velocity = velocity.lerp(desired_vel, accel * delta)
		var desired_yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))

func _after_spawn():
	if randi() % 2 == 0:
		_set_state(State.IDLE_GRAZING)
	else:
		_set_state(State.SEARCHING)

func _on_reached_plant():
	if state != State.SEARCHING:
		return
	if target_plant and is_instance_valid(target_plant):
		target_plant.set("grazed", true)
	_set_state(State.GRAZING)

func _on_reached_hole():
	_set_state(State.HOME)
	_play_hop_oneshot_then(queue_free)

func _ensure_target_plant():
	if target_plant and is_instance_valid(target_plant):
		if _reserved_by_self(target_plant) or not target_plant.has_meta("reserved_by"):
			agent.target_position = _nav_snap(target_plant.global_transform.origin)
			return
	target_plant = _nearest_available_plant()
	if target_plant:
		_reserve(target_plant)
		agent.target_position = _nav_snap(target_plant.global_transform.origin)
	else:
		if state == State.SEARCHING:
			_set_state(State.IDLE_GRAZING)

func _ensure_target_hole():
	if target_hole and is_instance_valid(target_hole):
		agent.target_position = _nav_snap(target_hole.global_transform.origin)
		return
	target_hole = _nearest_hole()
	if target_hole:
		agent.target_position = _nav_snap(target_hole.global_transform.origin)

func _current_target_position():
	if state == State.SEARCHING and target_plant and is_instance_valid(target_plant):
		return target_plant.global_transform.origin
	if state == State.HEADING_HOME and target_hole and is_instance_valid(target_hole):
		return target_hole.global_transform.origin
	return null

func _nearest_available_plant() -> Node:
	var pm := get_node_or_null(plant_manager_path)
	if pm == null:
		return null
	var best = null
	var best_d := INF
	for p in pm.get_children():
		if not is_instance_valid(p):
			continue
		if p.get("grazed") == true:
			continue
		if p.has_meta("reserved_by") and p.get_meta("reserved_by") != null and p.get_meta("reserved_by") != self:
			continue
		var d := global_transform.origin.distance_to(p.global_transform.origin)
		if d < best_d:
			best_d = d
			best = p
	return best

func _nearest_hole() -> Node:
	var hn := get_node_or_null(holes_path)
	if hn == null:
		return null
	var best = null
	var best_d := INF
	for h in hn.get_children():
		if not is_instance_valid(h):
			continue
		var d := global_transform.origin.distance_to(h.global_transform.origin)
		if d < best_d:
			best_d = d
			best = h
	return best

func _random_point_near(center: Vector3, radius: float) -> Vector3:
	var ang := randf() * TAU
	var r := sqrt(randf()) * radius
	var offset := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	return center + offset

func _nav_snap(p: Vector3) -> Vector3:
	var map := agent.get_navigation_map()
	if map.is_valid():
		return NavigationServer3D.map_get_closest_point(map, p)
	return p

func _has_target() -> bool:
	if state == State.SEARCHING:
		return target_plant != null and is_instance_valid(target_plant)
	if state == State.HEADING_HOME:
		return target_hole != null and is_instance_valid(target_hole)
	return false

func _reserved_by_self(p) -> bool:
	return p != null and is_instance_valid(p) and p.has_meta("reserved_by") and p.get_meta("reserved_by") == self

func _reserve(p):
	if p != null and is_instance_valid(p):
		p.set_meta("reserved_by", self)

func _unreserve(p):
	if p != null and is_instance_valid(p) and p.has_meta("reserved_by") and p.get_meta("reserved_by") == self:
		p.remove_meta("reserved_by")

func _set_state(s):
	if state == State.GRAZING and s != State.GRAZING:
		if target_plant and is_instance_valid(target_plant):
			target_plant.set("grazed", false)
			_unreserve(target_plant)
	if s != State.SEARCHING:
		_unreserve(target_plant)
	if s != State.HEADING_HOME:
		target_hole = null
	state = s
	match state:
		State.SPAWNING: print("spawning")
		State.IDLE_GRAZING: print("idle_grazing")
		State.SEARCHING: print("searching")
		State.GRAZING: print("grazing")
		State.IDLE_ALERT: print("idle_alert")
		State.FLEEING: print("fleeing")
		State.HEADING_HOME: print("heading_home")
		State.HOME: print("home")

func _enter_fleeing():
	if state == State.GRAZING and target_plant and is_instance_valid(target_plant):
		target_plant.set("grazed", false)
		_unreserve(target_plant)
	forcing_oneshot = false
	_set_state(State.FLEEING)

func _start_heading_home():
	_set_state(State.HEADING_HOME)
	_ensure_target_hole()

func _update_watch_target():
	if alert_bodies.size() == 0:
		watch_target = null
		return
	if watch_target and alert_bodies.has(watch_target):
		return
	watch_target = _closest_body(alert_bodies.keys())
	if watch_target:
		watch_eye = alert_bodies[watch_target]

func _closest_body(bodies: Array) -> Node:
	var best = null
	var best_d := INF
	for b in bodies:
		if not is_instance_valid(b):
			continue
		var d := global_transform.origin.distance_to(b.global_transform.origin)
		if d < best_d:
			best_d = d
			best = b
	return best

func _on_alert_entered(b):
	if not b.is_in_group("scary"):
		return
	var rel = (b.global_transform.origin - global_transform.origin)
	rel.y = 0.0
	var side := 1 if rel.dot(global_transform.basis.x) >= 0.0 else -1
	alert_bodies[b] = side
	if state != State.GRAZING and panic_bodies.size() == 0:
		if alert_bodies.size() >= 2:
			_enter_fleeing()
		elif state not in [State.FLEEING, State.IDLE_ALERT]:
			_set_state(State.IDLE_ALERT)
			cooldown_t = post_flee_cooldown
	_update_watch_target()

func _on_alert_exited(b):
	if alert_bodies.has(b):
		alert_bodies.erase(b)
	if watch_target == b:
		watch_target = null
	if state == State.IDLE_ALERT and panic_bodies.size() == 0 and alert_bodies.size() == 0:
		cooldown_t = post_flee_cooldown

func _on_panic_entered(b):
	if not b.is_in_group("scary"):
		return
	panic_bodies[b] = true
	_enter_fleeing()

func _on_panic_exited(b):
	if panic_bodies.has(b):
		panic_bodies.erase(b)

func _pick_next_after_alert():
	if randi() % 2 == 0:
		_set_state(State.SEARCHING)
	else:
		_set_state(State.IDLE_GRAZING)

func _play_hop_oneshot():
	if anim:
		forcing_oneshot = true
		anim.play("Hop")

func _play_hop_oneshot_then(cb):
	if anim:
		forcing_oneshot = true
		anim.play("Hop")
		await anim.animation_finished
		forcing_oneshot = false
		cb.call()

func _update_anim():
	if anim == null:
		return
	if state == State.FLEEING:
		if anim.speed_scale != hop_flee_speed or anim.current_animation != "Hop" or not anim.is_playing():
			anim.speed_scale = hop_flee_speed
			anim.play("Hop")
		return
	if forcing_oneshot or (anim.current_animation == "Hop" and anim.is_playing() and anim.speed_scale == 1.0):
		return
	anim.speed_scale = 1.0
	if velocity.length() > 0.05:
		if anim.current_animation != "Hop":
			anim.play("Hop")
	else:
		if anim.current_animation != "Idle":
			anim.play("Idle")

func _update_stuck(delta):
	var moved := (global_transform.origin - last_pos).length()
	last_pos = global_transform.origin
	var moving := state in [State.SEARCHING, State.FLEEING, State.HEADING_HOME] or (state == State.IDLE_GRAZING and wander_move)
	if moving and moved < 0.01:
		stuck_t += delta
	else:
		stuck_t = 0.0
	if stuck_t > 1.0:
		agent.target_position = _nav_snap(agent.target_position)
		stuck_t = 0.0
