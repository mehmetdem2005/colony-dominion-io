extends SceneTree

const REQUIRED_FILES: Array[String] = [
	"res://network/reconnect_session_store.gd",
	"res://network/secure_local_vault.gd",
	"res://tools/online_soak_client.gd",
	"res://scenes/online_soak_client.tscn",
	"res://backend/game-server/entrypoint.sh",
	"res://backend/game-server/Dockerfile",
	"res://backend/observability/prometheus-alerts.yml",
	"res://backend/supabase/migrations/202607190004_ranked_schema.sql",
	"res://backend/supabase/migrations/202607190005_authoritative_ranked_results.sql",
]
const BUILD_ID: String = "PHASE-05.3-ONLINE-PRODUCTION-COMPLETION"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for path in REQUIRED_FILES:
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			failures.append("Missing production file: %s" % path)
	if NetworkProtocol.VERSION != 3:
		failures.append("Network protocol must be version 3")
	if NetworkProtocol.DEFAULT_MAX_PLAYERS != 6:
		failures.append("Online capacity must match the six colony slots")
	var config: String = FileAccess.get_file_as_string("res://config/backend_config.json")
	if not config.contains(BUILD_ID) or not config.contains('"protocol_version": 3'):
		failures.append("Client backend configuration is not pinned to Phase 05.3")
	var transport: String = FileAccess.get_file_as_string("res://network/game_transport.gd")
	for marker in [
		"resume_persisted_session",
		"_metric_reconnect_success_total",
		"RANKED_MATCH",
	]:
		if not transport.contains(marker):
			failures.append("Game transport is missing: %s" % marker)
	var allocator: String = FileAccess.get_file_as_string(
		"res://backend/rivet-control/src/allocator.ts"
	)
	if not allocator.contains("RIVET_ALLOCATOR_CLOUD_TOKEN"):
		failures.append("Allocator does not use a scoped runtime token")
	if allocator.contains('requiredEnvironment("RIVET_CLOUD_TOKEN")'):
		failures.append("Broad Rivet deployment token leaks into allocator runtime")
	var ranked_sql: String = FileAccess.get_file_as_string(
		"res://backend/supabase/migrations/202607190005_authoritative_ranked_results.sql"
	)
	for marker in ["pg_advisory_xact_lock", "ratings_processed_at", "rating_history"]:
		if not ranked_sql.contains(marker):
			failures.append("Ranked SQL is missing: %s" % marker)
	if failures.is_empty():
		print("PASS online_production_completion_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
