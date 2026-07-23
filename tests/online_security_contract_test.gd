extends SceneTree

const TRANSPORT_PATH := "res://network/game_transport.gd"
const EDGEGAP_CLIENT_PATH := "res://network/edgegap_matchmaking_client.gd"
const MATCHMAKING_FUNCTION_PATH := "res://backend/supabase/functions/matchmaking/index.ts"
const RESULT_MIGRATION_PATH := "res://backend/supabase/migrations/202607190005_authoritative_ranked_results.sql"


func _initialize() -> void:
	var failures: Array[String] = []
	var transport: String = FileAccess.get_file_as_string(TRANSPORT_PATH)
	var edgegap_client: String = FileAccess.get_file_as_string(EDGEGAP_CLIENT_PATH)
	var matchmaking: String = FileAccess.get_file_as_string(MATCHMAKING_FUNCTION_PATH)
	var result_migration: String = FileAccess.get_file_as_string(RESULT_MIGRATION_PATH)

	for required in [
		"MATCH_ID",
		"SERVER_ID",
		"_validate_server_identity_claims",
		"EXPECTED_JOIN_TICKET",
		"EXPECTED_PLAYER_ID",
		"_constant_time_equal",
		"_consumed_join_ticket_hashes",
		"_rpc_client_leave",
		"unreliable_ordered",
	]:
		if not transport.contains(required):
			failures.append("Transport security contract missing: %s" % required)
	for required in [
		"authenticatedUserId",
		"player_identity_mismatch",
		"EXPECTED_JOIN_TICKET",
		"is_hidden: true",
		"ip_list",
		"REGION_TARGETS",
		"EDGEGAP_API_TOKEN",
	]:
		if not matchmaking.contains(required):
			failures.append("Edgegap function security contract missing: %s" % required)
	for required in [
		'"player_id": player_id.strip_edges()',
		'"selected_region_id": selected_id',
		"Authorization: Bearer",
	]:
		if not edgegap_client.contains(required):
			failures.append("Edgegap client identity contract missing: %s" % required)
	if edgegap_client.contains("EDGEGAP_API_TOKEN"):
		failures.append("The game client must never reference the Edgegap API token")
	if matchmaking.contains("DEV_ACCEPT_JOIN_TICKETS"):
		failures.append("The Edgegap function enables insecure development ticket acceptance")
	for required in [
		"security definer",
		"grant execute on function",
		"to service_role",
		"revoke all on function",
	]:
		if not result_migration.to_lower().contains(required):
			failures.append("Authoritative result migration missing: %s" % required)
	for source in [transport, edgegap_client]:
		for forbidden in ["sbp_", "sb_secret_", "service_role", "cloud.eyJ", "cloud_api_"]:
			if source.contains(forbidden):
				failures.append("Secret-like value leaked into client/runtime source")
	if failures.is_empty():
		print("PASS online_security_contract_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
