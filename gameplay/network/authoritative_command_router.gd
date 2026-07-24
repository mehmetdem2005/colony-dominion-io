class_name AuthoritativeCommandRouter
extends RefCounted

const COMMAND_VALIDATOR_SCRIPT := preload("res://gameplay/network/network_command_validator.gd")

var _host: Node = null
var _rules: MatchRules = null
var _clock: FixedStepClock = null
var _journal: AuthoritativeCommandJournal = null
var _snapshot_builder: NetworkSnapshotBuilder = null
var _local_command_sequence: int = 0
var _last_command_sequence_by_peer: Dictionary = {}
var _command_rate_by_peer: Dictionary = {}
var _peer_to_team: Dictionary = {}


func configure(
	host: Node,
	rules: MatchRules,
	clock: FixedStepClock,
	journal: AuthoritativeCommandJournal,
	snapshot_builder: NetworkSnapshotBuilder,
	initial_peer_to_team: Dictionary = {}
) -> void:
	_host = host
	_rules = rules
	_clock = clock
	_journal = journal
	_snapshot_builder = snapshot_builder
	_local_command_sequence = 0
	_last_command_sequence_by_peer.clear()
	_command_rate_by_peer.clear()
	_peer_to_team = initial_peer_to_team.duplicate()


func advance_server_tick(delta: float) -> void:
	if _clock != null:
		_clock.advance(delta)


func get_server_tick() -> int:
	return _clock.tick if _clock != null else 0


func request_local_command(command_type: StringName, payload: Dictionary = {}) -> bool:
	if _is_match_finished():
		return false
	_local_command_sequence += 1
	var command := {
		"sequence": _local_command_sequence,
		"client_tick": get_server_tick(),
		"type": command_type,
		"payload": payload,
	}
	return receive(1, command)


func receive(peer_id: int, command: Dictionary) -> bool:
	if _is_match_finished():
		return false
	var controllers: Array = _get_controllers()
	var team_id: int = int(_peer_to_team.get(peer_id, -1))
	if team_id < 0 or team_id >= controllers.size():
		return false
	if not _allow_command_rate(peer_id):
		return false
	var controller: ColonyController = controllers[team_id] as ColonyController
	var last_sequence: int = int(_last_command_sequence_by_peer.get(peer_id, -1))
	var validation: Dictionary = COMMAND_VALIDATOR_SCRIPT.validate(
		command, controller, peer_id, last_sequence
	)
	if not bool(validation.get("valid", false)):
		return false
	_last_command_sequence_by_peer[peer_id] = int(command.get("sequence", -1))
	var command_type := StringName(command.get("type", ""))
	var payload_variant: Variant = command.get("payload", {})
	var payload: Dictionary = payload_variant if payload_variant is Dictionary else {}
	var succeeded: bool = controller.execute_authoritative_command(command_type, payload)
	if _journal != null:
		_journal.record(get_server_tick(), peer_id, team_id, command_type, payload, succeeded)
	return succeeded


func assign_peer_to_team(peer_id: int, team_id: int, display_name: String = "") -> bool:
	var controllers: Array = _get_controllers()
	if peer_id <= 0 or team_id < 0 or team_id >= controllers.size():
		return false
	var controller: ColonyController = controllers[team_id] as ColonyController
	if not is_instance_valid(controller) or controller.eliminated:
		return false
	if _peer_to_team.has(peer_id):
		return int(_peer_to_team[peer_id]) == team_id
	if _peer_to_team.values().has(team_id):
		return false
	if _snapshot_builder != null:
		_snapshot_builder.clear_team(team_id)
	_peer_to_team[peer_id] = team_id
	controller.is_human = true
	controller.owner_peer_id = peer_id
	if not display_name.strip_edges().is_empty():
		controller.set_display_name(display_name)
	controller.set_simulation_tier(ColonyController.SimulationTier.FULL)
	_notify_interest_changed()
	return true


func assign_peer_to_available_team(peer_id: int, display_name: String = "") -> int:
	if _peer_to_team.has(peer_id):
		return int(_peer_to_team[peer_id])
	var controllers: Array = _get_controllers()
	for team_id in range(controllers.size()):
		var controller: ColonyController = controllers[team_id] as ColonyController
		if (
			is_instance_valid(controller)
			and not controller.eliminated
			and not _peer_to_team.values().has(team_id)
		):
			return team_id if assign_peer_to_team(peer_id, team_id, display_name) else -1
	return -1


func get_team_for_peer(peer_id: int) -> int:
	return int(_peer_to_team.get(peer_id, -1))


func release_peer(peer_id: int) -> void:
	if not _peer_to_team.has(peer_id):
		return
	var team_id: int = int(_peer_to_team[peer_id])
	_peer_to_team.erase(peer_id)
	_last_command_sequence_by_peer.erase(peer_id)
	_command_rate_by_peer.erase(peer_id)
	if _snapshot_builder != null:
		_snapshot_builder.clear_team(team_id)
	var controllers: Array = _get_controllers()
	if team_id >= 0 and team_id < controllers.size():
		var controller: ColonyController = controllers[team_id] as ColonyController
		if is_instance_valid(controller):
			controller.set_joystick_input(Vector2.ZERO)
			controller.is_human = false
			controller.owner_peer_id = 0
	_notify_interest_changed()
	_notify_ai_refresh()
	_notify_spatial_dirty()


func detach_peer_for_reconnect(peer_id: int) -> int:
	if not _peer_to_team.has(peer_id):
		return -1
	var team_id: int = int(_peer_to_team[peer_id])
	_peer_to_team.erase(peer_id)
	_last_command_sequence_by_peer.erase(peer_id)
	_command_rate_by_peer.erase(peer_id)
	var controllers: Array = _get_controllers()
	if team_id >= 0 and team_id < controllers.size():
		var controller: ColonyController = controllers[team_id] as ColonyController
		if is_instance_valid(controller):
			controller.set_joystick_input(Vector2.ZERO)
			controller.owner_peer_id = 0
			# Hand the colony straight back to the AI for the reconnect grace.
			# Without this the colony keeps is_human = true with no peer driving
			# it, so the bot brain (gated on `not is_human`) never runs and the
			# colony freezes — a sitting duck — until the reservation finally
			# expires. The reservation still holds the slot; if the player
			# reconnects, assign_peer_to_team re-flags it human and they resume.
			controller.is_human = false
			_notify_ai_refresh()
	_notify_interest_changed()
	return team_id


func release_team_to_ai(team_id: int) -> void:
	var controllers: Array = _get_controllers()
	if team_id < 0 or team_id >= controllers.size():
		return
	var controller: ColonyController = controllers[team_id] as ColonyController
	if not is_instance_valid(controller):
		return
	controller.set_joystick_input(Vector2.ZERO)
	controller.is_human = false
	controller.owner_peer_id = 0
	_notify_ai_refresh()
	_notify_interest_changed()


func get_last_sequence(peer_id: int) -> int:
	return int(_last_command_sequence_by_peer.get(peer_id, -1))


func build_snapshot_for_team(team_id: int, radius: float = 2300.0) -> Dictionary:
	if _snapshot_builder == null:
		return {}
	return _snapshot_builder.build_for_team(team_id, radius)


func get_recent_commands() -> Array[Dictionary]:
	return _journal.snapshot() if _journal != null else []


func reset() -> void:
	_local_command_sequence = 0
	_last_command_sequence_by_peer.clear()
	_command_rate_by_peer.clear()
	_peer_to_team.clear()


func _allow_command_rate(peer_id: int) -> bool:
	if _rules == null:
		return false
	var now_msec: int = Time.get_ticks_msec()
	var state: Dictionary = _command_rate_by_peer.get(
		peer_id, {"window_start": now_msec, "count": 0}
	)
	if now_msec - int(state.get("window_start", now_msec)) >= 1000:
		state = {"window_start": now_msec, "count": 0}
	var count: int = int(state.get("count", 0))
	if count >= _rules.max_commands_per_second:
		_command_rate_by_peer[peer_id] = state
		return false
	state["count"] = count + 1
	_command_rate_by_peer[peer_id] = state
	return true


func _get_controllers() -> Array:
	if not is_instance_valid(_host):
		return []
	var controllers_variant: Variant = _host.get("controllers")
	return controllers_variant if controllers_variant is Array else []


func _is_match_finished() -> bool:
	return not is_instance_valid(_host) or bool(_host.get("match_finished"))


func _notify_interest_changed() -> void:
	if is_instance_valid(_host) and _host.has_method("refresh_world_interest_targets"):
		_host.call("refresh_world_interest_targets")


func _notify_ai_refresh() -> void:
	if is_instance_valid(_host) and _host.has_method("refresh_ai_simulation_tiers"):
		_host.call("refresh_ai_simulation_tiers")


func _notify_spatial_dirty() -> void:
	if is_instance_valid(_host) and _host.has_method("mark_spatial_index_dirty"):
		_host.call("mark_spatial_index_dirty")
