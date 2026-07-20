class_name DedicatedMatchStartGate
extends RefCounted

var _match: Node = null
var _expected_players: int = 1
var _started: bool = false
var _join_deadline_msec: int = 0
var _start_deadline_msec: int = 0


func set_expected_players(value: int) -> void:
	_expected_players = clampi(value, 1, NetworkProtocol.DEFAULT_MAX_PLAYERS)


func bind_match(match_node: Node, now_msec: int) -> void:
	_match = match_node
	_started = false
	_start_deadline_msec = 0
	_join_deadline_msec = now_msec + roundi(NetworkProtocol.SERVER_JOIN_TIMEOUT_SECONDS * 1000.0)
	if is_instance_valid(_match):
		_match.process_mode = Node.PROCESS_MODE_DISABLED


func consider_start(connected_players: int, now_msec: int) -> bool:
	if _started or connected_players <= 0 or not is_instance_valid(_match):
		return false
	if connected_players >= _expected_players:
		return _start()
	if _start_deadline_msec <= 0:
		_start_deadline_msec = now_msec + roundi(NetworkProtocol.SERVER_START_WAIT_SECONDS * 1000.0)
	return false


func advance(connected_players: int, now_msec: int) -> Dictionary:
	if _started:
		return {"started": false, "shutdown": false}
	if connected_players > 0 and _start_deadline_msec > 0 and now_msec >= _start_deadline_msec:
		return {"started": _start(), "shutdown": false}
	return {
		"started": false,
		"shutdown":
		connected_players <= 0 and _join_deadline_msec > 0 and now_msec >= _join_deadline_msec,
	}


func is_started() -> bool:
	return _started


func get_expected_players() -> int:
	return _expected_players


func _start() -> bool:
	if _started or not is_instance_valid(_match):
		return false
	_started = true
	_match.process_mode = Node.PROCESS_MODE_INHERIT
	return true


static func is_server_mode() -> bool:
	if "--soak-client" in OS.get_cmdline_user_args():
		return false
	return (
		OS.has_feature("dedicated_server")
		or DisplayServer.get_name() == "headless"
		or "--server" in OS.get_cmdline_user_args()
	)


static func read_int_environment(name: String, fallback: int, minimum: int, maximum: int) -> int:
	var effective_maximum: int = maximum
	if name == "MAX_PLAYERS" or name == "EXPECTED_PLAYERS":
		effective_maximum = mini(maximum, NetworkProtocol.DEFAULT_MAX_PLAYERS)
	var value: String = OS.get_environment(name)
	return clampi(int(value), minimum, effective_maximum) if value.is_valid_int() else fallback
