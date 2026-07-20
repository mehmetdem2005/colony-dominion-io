extends SceneTree

const TRANSPORT_PATH := "res://network/game_transport.gd"
const RIVET_TRANSPORT_PATH := "res://network/rivet_game_transport.gd"
const CONTROL_SERVER_PATH := "res://backend/rivet-control/src/server-full-online.ts"
const GAME_ACTOR_PATH := "res://backend/rivet-control/src/game-server-actor.ts"
const REGISTRY_PATH := "res://backend/rivet-control/src/registry.ts"
const TYPES_PATH := "res://backend/rivet-control/src/types.ts"
const RESULT_MIGRATION_PATH := "res://backend/supabase/migrations/202607190005_authoritative_ranked_results.sql"


func _initialize() -> void:
	var failures: Array[String] = []
	var transport: String = FileAccess.get_file_as_string(TRANSPORT_PATH)
	var rivet_transport: String = FileAccess.get_file_as_string(RIVET_TRANSPORT_PATH)
	var server: String = FileAccess.get_file_as_string(CONTROL_SERVER_PATH)
	var game_actor: String = FileAccess.get_file_as_string(GAME_ACTOR_PATH)
	var registry: String = FileAccess.get_file_as_string(REGISTRY_PATH)
	var types: String = FileAccess.get_file_as_string(TYPES_PATH)
	var result_migration: String = FileAccess.get_file_as_string(RESULT_MIGRATION_PATH)
	for required in [
		"MATCH_ID",
		"SERVER_ID",
		"GAME_SERVER_AUTH_TOKEN",
		"_validate_server_identity_claims",
		"_rpc_client_leave",
		"unreliable_ordered",
	]:
		if not transport.contains(required):
			failures.append("Transport contract missing: %s" % required)
	for required in [
		"WebSocketMultiplayerPeer",
		"NETWORK_TRANSPORT",
		"127.0.0.1",
		"NetworkProtocol.TRANSPORT_WEBSOCKET",
	]:
		if not rivet_transport.contains(required):
			failures.append("Rivet transport security missing: %s" % required)
	for required in [
		"/v1/internal/sessions/consume",
		"/v1/internal/matches/result",
		"/v1/health/config",
		"hashTicket",
		"isTicketOwner",
		"SUPABASE_SECRET_KEY",
		"actorClient.gameServer",
	]:
		if not server.contains(required):
			failures.append("Control-plane security missing: %s" % required)
	for required in [
		"127.0.0.1",
		"serverAuthToken",
		"stopRuntime",
		"onDestroy",
		"onWebSocket",
		"RESTART_LIMIT",
	]:
		if not game_actor.contains(required):
			failures.append("Rivet game actor isolation missing: %s" % required)
	for required in [
		"serverCredentials",
		"releaseMatch",
		"activeTicketByPlayer",
		"ticketOwners",
		"join_ticket_already_used",
		"join_ticket_claim_mismatch",
		"consumeSessionTicket",
		"displayName",
		"timingSafeEqual",
		"constantTimeHashEqual",
	]:
		if not registry.contains(required):
			failures.append("Actor ticket contract missing: %s" % required)
	for required in ["displayName", "SessionTicketRecord", "SessionTicketConsumeResult"]:
		if not types.contains(required):
			failures.append("Trusted ticket identity type missing: %s" % required)
	for required in [
		"security definer",
		"grant execute on function",
		"to service_role",
		"revoke all on function",
	]:
		if not result_migration.to_lower().contains(required):
			failures.append("Authoritative result migration missing: %s" % required)
	for source in [transport, rivet_transport, server, game_actor]:
		for forbidden in ["sbp_", "sb_secret_", "service_role", "cloud.eyJ", "cloud_api_"]:
			if source.contains(forbidden):
				failures.append("Secret-like value leaked into online runtime source")
	if failures.is_empty():
		print("PASS online_security_contract_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
