extends Node

const WORLD_ENV_PATH := "/root/Main/SubViewportContainer/SubViewport/WorldEnvironment"

var world_environment: WorldEnvironment

func _ready() -> void:
	# Wait until the world_environment exists
	await get_tree().process_frame
	while world_environment == null:
		world_environment = get_node_or_null(WORLD_ENV_PATH)
		if world_environment == null:
			await get_tree().process_frame
	
	# Start updating once it's ready
	_update_sky_time()
	var timer := Timer.new()
	timer.wait_time = 30.0
	timer.autostart = true
	timer.timeout.connect(_update_sky_time)
	add_child(timer)

func _update_sky_time() -> void:
	if world_environment == null:
		return
	var env := world_environment.environment
	if env == null or env.sky == null:
		return
	var mat := env.sky.sky_material
	if mat == null:
		return

	var minutes := _minutes_since_midnight()
	var v := _compute_sky_time(minutes)
	if mat.has_parameter("sky_time"):
		mat.set_shader_parameter("sky_time", v)

func _minutes_since_midnight() -> int:
	var t := Time.get_time_dict_from_system()
	return t.hour * 60 + t.minute

func _compute_sky_time(m: int) -> float:
	const SR_START := 4 * 60
	const SR_END := 8 * 60
	const SS_START := 18 * 60 + 30
	const SS_END := 22 * 60 + 30

	if m >= SR_START and m <= SR_END:
		return float(m - SR_START) / float(SR_END - SR_START)
	if m > SR_END and m < SS_START:
		return 1.0
	if m >= SS_START and m <= SS_END:
		return 1.0 - float(m - SS_START) / float(SS_END - SS_START)
	return 0.0
