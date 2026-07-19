class_name OnlineSoakClient
extends Node

const BUILD_ID: String = "PHASE-05.3-ONLINE-PRODUCTION-COMPLETION"

var _duration_seconds: float = 120.0
var _elapsed: float = 0.0
var _movement_left: float = 0.0
var _command_left: float = 0.0
var _snapshot_count: int = 0
var _snapshot_gap_max_msec: int = 0
var _last_snapshot_msec: int = 0
var _report_path: String = "user://soak-report.json"
var _rng := RandomNumberGenerator.new()
var _started_unix_msec: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	_duration_seconds = clampf(float(args.get("duration", 120.0)), 5.0, 3600.0)
	_report_path = String(args.get("report", _report_path))
	_rng.seed = int(args.get("seed", Time.get_ticks_usec()))
	GameTransport.snapshot_received.connect(_on_snapshot)
	_started_unix_msec = roundi(Time.get_unix_time_from_system() * 1000.0)
	var now_msec: int = _started_unix_msec
	var assignment := {
		"match_id": String(args.get("match-id", "")),
		"server_id": String(args.get("server-id", "")),
		"host": String(args.get("host", "127.0.0.1")),
		"port": int(args.get("port", NetworkProtocol.DEFAULT_GAME_PORT)),
		"join_ticket": String(args.get("ticket", "dev-ticket-000000000000000000000000")),
		"region_id": "local-soak",
		"region_name": "Local Soak",
		"region_short_name": "SOAK",
		"expires_at": now_msec + 300_000,
		"protocol_version": NetworkProtocol.VERSION,
	}
	var player_id: String = String(args.get("player-id", ""))
	var display_name: String = String(args.get("name", "SoakBot"))
	var result: Dictionary = GameTransport.connect_to_assignment(
		assignment, player_id, display_name, BUILD_ID
	)
	if not bool(result.get("ok", false)):
		_finish(false, String(result.get("error", "connect_failed")))
		return
	var auth: Dictionary = await GameTransport.wait_for_authentication(15.0)
	if not bool(auth.get("ok", false)):
		_finish(false, String(auth.get("error", "auth_failed")))


func _process(delta: float) -> void:
	if not GameTransport.is_authenticated():
		return
	_elapsed += delta
	_movement_left -= delta
	_command_left -= delta
	if _movement_left <= 0.0:
		_movement_left = 0.10
		var direction := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		GameTransport.send_command(&"move", {"vector": direction})
	if _command_left <= 0.0:
		_command_left = _rng.randf_range(2.0, 5.0)
		var commands: Array[StringName] = [&"gather", &"rally", &"spread", &"merge"]
		GameTransport.send_command(commands[_rng.randi_range(0, commands.size() - 1)])
	if _elapsed >= _duration_seconds:
		GameTransport.send_command(&"move", {"vector": Vector2.ZERO})
		GameTransport.disconnect_from_game("soak_complete")
		_finish(true, "complete")


func _on_snapshot(_snapshot: Dictionary) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if _last_snapshot_msec > 0:
		_snapshot_gap_max_msec = maxi(_snapshot_gap_max_msec, now_msec - _last_snapshot_msec)
	_last_snapshot_msec = now_msec
	_snapshot_count += 1


func _finish(ok: bool, reason: String) -> void:
	var stats: Dictionary = GameTransport.get_transport_stats()
	var report := {
		"ok": ok,
		"reason": reason,
		"duration_seconds": _elapsed,
		"snapshot_count": _snapshot_count,
		"max_snapshot_gap_msec": _snapshot_gap_max_msec,
		"ping_ms": NetworkSession.ping_ms,
		"jitter_ms": NetworkSession.jitter_ms,
		"packet_loss_percent": NetworkSession.packet_loss_percent,
		"transport": stats,
		"started_at_unix_msec": _started_unix_msec,
		"ended_at_unix_msec": roundi(Time.get_unix_time_from_system() * 1000.0),
	}
	var path: String = _report_path
	if path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.flush()
	get_tree().quit(0 if ok else 1)


func _parse_args(values: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		if not value.begins_with("--") or not value.contains("="):
			continue
		var parts: PackedStringArray = value.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			result[parts[0]] = parts[1]
	return result
