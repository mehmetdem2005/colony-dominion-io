extends Node

signal mode_changed(mode: int)
signal region_changed(region_id: String, display_name: String)
signal metrics_changed(ping_ms: int, jitter_ms: int, packet_loss: float)
signal region_pings_changed
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
## Measured pings are compared in buckets this wide when choosing automatically,
## so two players in the same place agree on a region instead of being separated
## by a few milliseconds of measurement noise.
const REGION_PING_BUCKET_MS: int = 25

var mode: SessionMode = SessionMode.OFFLINE
var connection_state: ConnectionState = ConnectionState.IDLE
var connection_message: String = ""
var preferred_region_id: String = "auto"
var selected_region_id: String = "auto"
## True while the shown region came from automatic selection rather than the player.
var region_is_automatic: bool = true
## region id -> last measured round-trip in ms, from matches actually played.
var measured_region_pings: Dictionary = {}
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
	# set_offline() parks the region on an "offline" sentinel, and nothing used
	# to clear it. Playing one offline match therefore left every later online
	# queue asking for a region that does not exist, instead of the automatic
	# one the player still sees selected in the menu.
	if selected_region_id == "offline":
		selected_region_id = "auto"
		selected_region_name = "Otomatik — En Yakın Sunucu"
		active_region_short_name = "AUTO"
		region_changed.emit(selected_region_id, selected_region_name)
	mode_changed.emit(mode)


func set_preferred_region(region_id: String) -> void:
	var cleaned: String = region_id.strip_edges().to_lower()
	preferred_region_id = cleaned if not cleaned.is_empty() else "auto"
	_save_settings()


func select_region(
	region_id: String,
	display_name: String,
	short_name: String,
	metrics: Dictionary = {},
	automatic: bool = false
) -> void:
	selected_region_id = region_id
	selected_region_name = display_name
	active_region_short_name = short_name
	region_is_automatic = automatic
	set_preferred_region(region_id)
	_apply_metrics(metrics)
	region_changed.emit(selected_region_id, selected_region_name)


## The region the matchmaker groups this player by: always a real city.
##
## Two players are pooled together when this agrees, so it has to be stable.
## It used to be rewritten every twenty seconds by a ping probe that measured
## nothing, which is what separated players who both believed they were on
## automatic. It is now whatever region was resolved — either the player's own
## pick, or the lowest measured ping in coarse buckets — and it only changes
## when one of those changes.
func get_matchmaking_region_id() -> String:
	if selected_region_id.is_empty() or selected_region_id in ["auto", "offline"]:
		return ""
	return selected_region_id


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


## Remember what a region actually measured, from a match really played there.
##
## Edgegap publishes no per-city latency endpoint, so a region cannot be pinged
## before a server exists in it. Rather than show an invented number, the ping
## of the server the player was actually on is attributed to its region and
## kept. A region that has never been played reports nothing, and says so.
func record_region_ping(region_id: String, measured_ping_ms: int) -> void:
	var cleaned: String = region_id.strip_edges().to_lower()
	if cleaned.is_empty() or cleaned == "auto" or cleaned == "offline":
		return
	if measured_ping_ms < 0 or measured_ping_ms > 5000:
		return
	var previous: int = int(measured_region_pings.get(cleaned, -1))
	# Smooth toward the new reading so one bad match cannot rewrite a region.
	var blended: int = (
		measured_ping_ms if previous < 0 else roundi(float(previous) * 0.6 + measured_ping_ms * 0.4)
	)
	measured_region_pings[cleaned] = blended
	region_pings_changed.emit()
	_save_settings()


func get_measured_region_ping(region_id: String) -> int:
	return int(measured_region_pings.get(region_id.strip_edges().to_lower(), -1))


## The region to queue in when the player has not picked one.
##
## Lowest measured ping wins, but readings are compared in coarse buckets and
## ties break on a fixed order. Two players sitting in the same room measure
## slightly different numbers, and letting a two-millisecond difference decide
## would put them in different pools — which is the whole failure this game has
## already been through once.
func get_auto_region_id(candidate_ids: PackedStringArray, fallback_id: String) -> String:
	var best_id: String = ""
	var best_bucket: int = 1 << 30
	for region_id in candidate_ids:
		var measured: int = get_measured_region_ping(region_id)
		if measured < 0:
			continue
		var bucket: int = int(floor(float(measured) / float(REGION_PING_BUCKET_MS)))
		if bucket < best_bucket:
			best_bucket = bucket
			best_id = region_id
	if best_id.is_empty():
		return fallback_id
	return best_id


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	preferred_region_id = String(config.get_value("network", "preferred_region", "auto"))
	var stored: Variant = config.get_value("network", "measured_region_pings", {})
	if stored is Dictionary:
		measured_region_pings = (stored as Dictionary).duplicate(true)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("network", "preferred_region", preferred_region_id)
	config.set_value("network", "measured_region_pings", measured_region_pings)
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Network settings could not be saved: %s" % error_string(error))
