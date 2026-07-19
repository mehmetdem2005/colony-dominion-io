extends Node

signal mode_changed(mode: int)
signal region_changed(region_id: String, display_name: String)
signal metrics_changed(ping_ms: int, jitter_ms: int, packet_loss: float)
signal connection_state_changed(state: int, message: String)
signal assignment_changed(assignment: Dictionary)

enum SessionMode {
	OFFLINE,
	ONLINE,
}

enum ConnectionState {
	IDLE,
	PROBING,
	AUTHENTICATING,
	MATCHMAKING,
	CONNECTING,
	CONNECTED,
	RECONNECTING,
	FAILED,
}

const SETTINGS_PATH: String = "user://network_settings.cfg"

var mode: SessionMode = SessionMode.OFFLINE
var connection_state: ConnectionState = ConnectionState.IDLE
var connection_message: String = ""
var preferred_region_id: String = "auto"
var selected_region_id: String = "auto"
var selected_region_name: String = "Otomatik"
var active_region_short_name: String = "AUTO"
var ping_ms: int = -1
var jitter_ms: int = -1
var packet_loss: float = 0.0
var region_metrics: Dictionary = {}
var match_assignment: Dictionary = {}


func _ready() -> void:
	_load_settings()


func set_offline() -> void:
	mode = SessionMode.OFFLINE
	selected_region_id = "offline"
	selected_region_name = "Çevrimdışı"
	active_region_short_name = "OFFLINE"
	ping_ms = 0
	jitter_ms = 0
	packet_loss = 0.0
	match_assignment.clear()
	set_connection_state(ConnectionState.IDLE, "Çevrimdışı oyun")
	mode_changed.emit(mode)
	region_changed.emit(selected_region_id, selected_region_name)
	metrics_changed.emit(ping_ms, jitter_ms, packet_loss)


func set_online() -> void:
	if mode == SessionMode.ONLINE:
		return
	mode = SessionMode.ONLINE
	mode_changed.emit(mode)


func set_preferred_region(region_id: String) -> void:
	var cleaned: String = region_id.strip_edges().to_lower()
	preferred_region_id = cleaned if not cleaned.is_empty() else "auto"
	_save_settings()


func select_region(
	region_id: String, display_name: String, short_name: String, metrics: Dictionary = {}
) -> void:
	selected_region_id = region_id
	selected_region_name = display_name
	active_region_short_name = short_name
	set_preferred_region(region_id)
	_apply_metrics(metrics)
	region_changed.emit(selected_region_id, selected_region_name)


func update_region_metrics(region_id: String, metrics: Dictionary) -> void:
	region_metrics[region_id] = metrics.duplicate(true)
	if region_id == selected_region_id:
		_apply_metrics(metrics)


func get_region_metrics(region_id: String) -> Dictionary:
	return (region_metrics.get(region_id, {}) as Dictionary).duplicate(true)


func set_connection_state(state: ConnectionState, message: String = "") -> void:
	connection_state = state
	connection_message = message
	connection_state_changed.emit(connection_state, connection_message)


func set_match_assignment(value: Dictionary) -> void:
	match_assignment = value.duplicate(true)
	assignment_changed.emit(match_assignment.duplicate(true))


func clear_match_assignment() -> void:
	match_assignment.clear()
	assignment_changed.emit({})


func get_status_text() -> String:
	if mode == SessionMode.OFFLINE:
		return "ÇEVRİM DIŞI"
	var ping_text: String = "-- ms" if ping_ms < 0 else "%d ms" % ping_ms
	var suffix: String = ""
	if packet_loss >= 0.01:
		suffix = " • %%%d kayıp" % roundi(packet_loss * 100.0)
	return "%s • %s%s" % [active_region_short_name, ping_text, suffix]


func apply_live_metrics(live_ping_ms: int, live_jitter_ms: int, live_packet_loss: float) -> void:
	ping_ms = live_ping_ms
	jitter_ms = live_jitter_ms
	packet_loss = clampf(live_packet_loss, 0.0, 1.0)
	metrics_changed.emit(ping_ms, jitter_ms, packet_loss)


func _apply_metrics(metrics: Dictionary) -> void:
	ping_ms = int(metrics.get("ping_ms", -1))
	jitter_ms = int(metrics.get("jitter_ms", -1))
	packet_loss = clampf(float(metrics.get("packet_loss", 0.0)), 0.0, 1.0)
	metrics_changed.emit(ping_ms, jitter_ms, packet_loss)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	preferred_region_id = String(config.get_value("network", "preferred_region", "auto"))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("network", "preferred_region", preferred_region_id)
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Network settings could not be saved: %s" % error_string(error))
