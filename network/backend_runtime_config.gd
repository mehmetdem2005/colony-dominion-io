class_name BackendRuntimeConfig
extends RefCounted

const PROJECT_CONFIG_PATH: String = "res://config/backend_config.json"
const USER_CONFIG_PATH: String = "user://backend_config.json"

var environment: String = "development"
var build_id: String = "UNKNOWN"
var protocol_version: int = 1
var supabase_url: String = ""
var supabase_publishable_key: String = ""
var rivet_control_base_url: String = ""
var persist_refresh_token: bool = false
var region_probe_interval_seconds: float = 12.0
var region_probe_timeout_seconds: float = 2.5
var regions: Array[Dictionary] = []
var source_path: String = ""


static func load_current() -> BackendRuntimeConfig:
	var config := BackendRuntimeConfig.new()
	var path: String = (
		USER_CONFIG_PATH if FileAccess.file_exists(USER_CONFIG_PATH) else PROJECT_CONFIG_PATH
	)
	config.source_path = path
	if not FileAccess.file_exists(path):
		push_warning("Backend configuration was not found: %s" % path)
		return config
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Backend configuration is not valid JSON: %s" % path)
		return config
	config._apply(parsed as Dictionary)
	return config


func is_supabase_configured() -> bool:
	return _is_https_url(supabase_url) and not supabase_publishable_key.strip_edges().is_empty()


func is_rivet_configured() -> bool:
	return _is_http_url(rivet_control_base_url)


func get_missing_client_settings() -> PackedStringArray:
	var missing := PackedStringArray()
	if not _is_https_url(supabase_url):
		missing.append("SUPABASE_URL")
	if supabase_publishable_key.strip_edges().is_empty():
		missing.append("SUPABASE_PUBLISHABLE_KEY")
	if not _is_http_url(rivet_control_base_url):
		missing.append("RIVET_CONTROL_BASE_URL")
	return missing


func get_region(region_id: String) -> Dictionary:
	for region in regions:
		if String(region.get("id", "")) == region_id:
			return region.duplicate(true)
	return {}


func _apply(data: Dictionary) -> void:
	environment = String(data.get("environment", environment)).strip_edges()
	build_id = String(data.get("build_id", build_id)).strip_edges()
	protocol_version = maxi(int(data.get("protocol_version", protocol_version)), 1)
	supabase_url = _normalize_base_url(String(data.get("supabase_url", "")))
	supabase_publishable_key = String(data.get("supabase_publishable_key", "")).strip_edges()
	rivet_control_base_url = _normalize_base_url(String(data.get("rivet_control_base_url", "")))
	persist_refresh_token = bool(data.get("persist_refresh_token", false))
	region_probe_interval_seconds = clampf(
		float(data.get("region_probe_interval_seconds", 12.0)), 5.0, 120.0
	)
	region_probe_timeout_seconds = clampf(
		float(data.get("region_probe_timeout_seconds", 2.5)), 0.5, 10.0
	)
	regions.clear()
	var regions_variant: Variant = data.get("regions", [])
	if not regions_variant is Array:
		return
	var seen_ids: Dictionary = {}
	for region_variant in regions_variant:
		if not region_variant is Dictionary:
			continue
		var region: Dictionary = region_variant
		var region_id: String = String(region.get("id", "")).strip_edges().to_lower()
		if region_id.is_empty() or seen_ids.has(region_id):
			continue
		seen_ids[region_id] = true
		(
			regions
			. append(
				{
					"id": region_id,
					"display_name": String(region.get("display_name", region_id)).strip_edges(),
					"short_name":
					String(region.get("short_name", region_id.to_upper())).strip_edges(),
					"probe_url": String(region.get("probe_url", "")).strip_edges(),
					"enabled": bool(region.get("enabled", true)),
				}
			)
		)


func _normalize_base_url(value: String) -> String:
	return value.strip_edges().trim_suffix("/")


func _is_https_url(value: String) -> bool:
	return value.begins_with("https://") and value.length() > 10


func _is_http_url(value: String) -> bool:
	return (
		(value.begins_with("https://") and value.length() > 10)
		or (environment == "development" and value.begins_with("http://"))
	)
