class_name ColonyGatherService
extends RefCounted

const COMMAND_RADIUS: float = 310.0
const CANCEL_RADIUS: float = 360.0
const COMMAND_DURATION: float = 7.0

var _host: Node = null
var _workers_enabled: bool = false
var _active_target: WorldResourceNode = null
var _active_generation: int = 0
var _command_left: float = 0.0
var _last_second: int = -1


func configure(host: Node) -> void:
	_host = host
	reset()


func advance(delta: float) -> void:
	if _command_left <= 0.0:
		return
	_command_left = maxf(0.0, _command_left - maxf(delta, 0.0))
	var commander: ColonyUnit = _get_commander()
	var should_stop: bool = (
		not is_instance_valid(commander)
		or not is_instance_valid(_active_target)
		or not _active_target.matches_activation(_active_generation)
		or not _active_target.is_available()
		or commander.global_position.distance_to(_active_target.global_position) > CANCEL_RADIUS
		or _command_left <= 0.0
	)
	if should_stop:
		stop(true)
		return
	var current_second: int = ceili(_command_left)
	if current_second != _last_second:
		_last_second = current_second
		_emit_state()


func command_gather() -> bool:
	var commander: ColonyUnit = _get_commander()
	if not is_instance_valid(commander) or not is_instance_valid(_get_match_controller()):
		return false
	var match_controller: Node = _get_match_controller()
	var resource: WorldResourceNode = (
		match_controller.call("find_nearest_resource", commander.global_position, COMMAND_RADIUS)
		as WorldResourceNode
	)
	if not is_instance_valid(resource):
		_request_toast("HASAT için kaynağın yanına yaklaş")
		return false
	_host.call("clear_forced_target")
	_active_target = resource
	_active_generation = resource.activation_generation
	_workers_enabled = true
	_command_left = COMMAND_DURATION
	_last_second = -1
	resource.show_harvest_focus(_get_team_color(), COMMAND_DURATION)
	var assigned_workers: int = 0
	for unit in _get_units():
		if (
			is_instance_valid(unit)
			and unit.definition != null
			and unit.definition.role == &"worker"
			and unit.is_alive()
		):
			unit.clear_combat_target()
			unit.resource_target = resource
			assigned_workers += 1
	if assigned_workers <= 0:
		stop(false)
		_request_toast("Hasat yapacak işçi yok")
		return false
	_emit_state()
	_request_toast("%d işçi yakındaki kaynağı hasat ediyor" % assigned_workers)
	return true


func stop(show_message: bool) -> void:
	var had_active_gather: bool = _command_left > 0.0 or _workers_enabled
	_workers_enabled = false
	_command_left = 0.0
	_active_target = null
	_active_generation = 0
	_last_second = -1
	if is_instance_valid(_host):
		for unit in _get_units():
			if (
				is_instance_valid(unit)
				and unit.definition != null
				and unit.definition.role == &"worker"
			):
				unit.resource_target = null
	if had_active_gather:
		_emit_state()
	if show_message and is_instance_valid(_host):
		_request_toast("Hasat bitti; işçiler formasyona döndü")


func should_gather() -> bool:
	return (
		_workers_enabled
		and _command_left > 0.0
		and is_instance_valid(_active_target)
		and _active_target.matches_activation(_active_generation)
		and _active_target.is_available()
	)


func get_active_target() -> WorldResourceNode:
	return _active_target if should_gather() else null


func can_worker_reach(worker: ColonyUnit, resource: WorldResourceNode) -> bool:
	var commander: ColonyUnit = _get_commander()
	if (
		not is_instance_valid(worker)
		or not is_instance_valid(resource)
		or resource != _active_target
		or not should_gather()
		or not is_instance_valid(commander)
	):
		return false
	return (
		commander.global_position.distance_to(resource.global_position) <= CANCEL_RADIUS
		and (
			worker.global_position.distance_to(commander.global_position)
			<= float(_host.call("get_hard_recall_radius"))
		)
	)


func emit_current_state() -> void:
	_emit_state()


func reset() -> void:
	_workers_enabled = false
	_active_target = null
	_active_generation = 0
	_command_left = 0.0
	_last_second = -1


func _get_commander() -> ColonyUnit:
	if not is_instance_valid(_host):
		return null
	return _host.get("commander") as ColonyUnit


func _emit_state() -> void:
	if not is_instance_valid(_host):
		return
	var resource_id: StringName = &""
	if is_instance_valid(_active_target):
		resource_id = _active_target.resource_type
	_host.call("emit_gather_state", should_gather(), ceili(_command_left), resource_id)


func _get_match_controller() -> Node:
	return _host.get("match_controller") as Node if is_instance_valid(_host) else null


func _get_units() -> Array[ColonyUnit]:
	var result: Array[ColonyUnit] = []
	if not is_instance_valid(_host):
		return result
	var units_variant: Variant = _host.get("units")
	if not units_variant is Array:
		return result
	for unit_variant in units_variant:
		var unit := unit_variant as ColonyUnit
		if is_instance_valid(unit):
			result.append(unit)
	return result


func _get_team_color() -> Color:
	var color_variant: Variant = (
		_host.get("team_color") if is_instance_valid(_host) else Color.WHITE
	)
	return color_variant if color_variant is Color else Color.WHITE


func _request_toast(message: String) -> void:
	if is_instance_valid(_host) and _host.has_method("request_player_toast"):
		_host.call("request_player_toast", message)
