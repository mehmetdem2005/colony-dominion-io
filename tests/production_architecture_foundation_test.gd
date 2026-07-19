extends SceneTree

const FIXED_CLOCK_SCRIPT := preload("res://gameplay/core/fixed_step_clock.gd")
const MATCH_RULES_RESOURCE := preload("res://data/match/default_match_rules.tres")
const JOURNAL_SCRIPT := preload("res://gameplay/network/authoritative_command_journal.gd")
const RESIDENCY_PLANNER_SCRIPT := preload("res://gameplay/world/world_residency_planner.gd")
const SERVER_MATCH_SCENE := preload("res://scenes/server_game.tscn")

const REQUIRED_SERVICES: Array[String] = [
	"res://gameplay/performance/unit_pool.gd",
	"res://gameplay/combat/projectile_system.gd",
	"res://gameplay/diagnostics/runtime_invariant_monitor.gd",
	"res://gameplay/network/network_snapshot_builder.gd",
	"res://gameplay/colony/colony_bot_brain.gd",
	"res://gameplay/world/world_content_catalog.gd",
	"res://gameplay/world/world_object_pool.gd",
	"res://gameplay/network/authoritative_command_router.gd",
	"res://gameplay/input/local_command_input_source.gd",
	"res://gameplay/colony/swarm_simulation_scheduler.gd",
	"res://gameplay/colony/colony_gather_service.gd",
	"res://gameplay/presentation/match_event_hub.gd",
	"res://gameplay/presentation/match_presentation_adapter.gd",
	"res://ui/hud_responsive_layout.gd",
	"res://gameplay/world/world_stream_read_model.gd",
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for service_path in REQUIRED_SERVICES:
		if not ResourceLoader.exists(service_path, "Script"):
			_fail("Architecture service is missing: %s" % service_path)
			return

	var clock := FIXED_CLOCK_SCRIPT.new(0.05, 2) as FixedStepClock
	var completed_steps: int = clock.advance(0.30)
	if completed_steps != 2:
		_fail("Fixed clock exceeded or missed its bounded step budget")
		return
	if clock.tick != 2 or clock.dropped_time < 0.19:
		_fail("Fixed clock did not account for deliberately discarded backlog")
		return
	if clock.get_interpolation_alpha() < 0.0 or clock.get_interpolation_alpha() > 1.0:
		_fail("Fixed clock interpolation alpha escaped its normalized range")
		return

	var rules := MATCH_RULES_RESOURCE.duplicate(true) as MatchRules
	if rules == null:
		_fail("Default MatchRules resource could not be duplicated")
		return
	rules.server_tick_rate = -20.0
	rules.max_visual_projectiles = 9000
	rules.sanitize()
	if rules.server_tick_rate < 5.0 or rules.max_visual_projectiles > 1024:
		_fail("MatchRules sanitization did not enforce production limits")
		return

	var journal := JOURNAL_SCRIPT.new() as AuthoritativeCommandJournal
	journal.configure(10)
	for tick in 14:
		journal.record(tick, 1, 0, &"move", {"tick": tick}, true)
	var entries: Array[Dictionary] = journal.snapshot()
	if entries.size() != 10:
		_fail("Authoritative command journal did not preserve its ring capacity")
		return
	if int(entries[0].get("server_tick", -1)) != 4:
		_fail("Authoritative command journal ordering is not oldest-to-newest")
		return
	if int(entries[entries.size() - 1].get("server_tick", -1)) != 13:
		_fail("Authoritative command journal lost its newest command")
		return

	var planner := RESIDENCY_PLANNER_SCRIPT.new() as WorldResidencyPlanner
	planner.configure(Vector2i(10, 10), 1, 2, 18, 84)
	var anchors: Array[Dictionary] = [
		{"center": Vector2i(4, 4), "predicted": Vector2i(5, 4)},
	]
	var loaded: Array[Vector2i] = [Vector2i(3, 3), Vector2i(7, 4), Vector2i(9, 9)]
	var plan: Dictionary = planner.build_plan(anchors, loaded)
	var desired: Dictionary = plan.get("desired", {})
	if int(desired.get(Vector2i(4, 4), -1)) != WorldChunkRuntime.Residency.ACTIVE:
		_fail("Residency planner did not protect the authority center")
		return
	if desired.size() > int(plan.get("resident_limit", 0)):
		_fail("Residency planner exceeded its calculated resident budget")
		return

	var match := SERVER_MATCH_SCENE.instantiate() as MatchController
	if match == null:
		_fail("Server match composition root could not be instantiated")
		return
	root.add_child(match)
	await process_frame
	if match.match_rules == null:
		_fail("Match composition root did not own a MatchRules instance")
		return
	var stats: Dictionary = match.get_stream_stats()
	for required_key in [
		"unit_pool",
		"active_projectiles",
		"logical_projectiles",
		"dropped_server_time",
		"resident_chunk_limit",
	]:
		if not stats.has(required_key):
			_fail("Runtime observability is missing metric: %s" % required_key)
			return
	if not match.get_recent_authoritative_commands().is_empty():
		_fail("A fresh match unexpectedly inherited authoritative command history")
		return

	print(
		(
			"PASS production_architecture_foundation_test services=%d journal=%d chunks=%d"
			% [REQUIRED_SERVICES.size(), entries.size(), desired.size()]
		)
	)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
