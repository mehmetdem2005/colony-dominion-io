class_name MatchController
extends Node2D

const COLONY_CONTROLLER_SCRIPT := preload("res://gameplay/colony/colony_controller.gd")
const WORLD_STREAM_MANAGER_SCRIPT := preload("res://gameplay/world/world_stream_manager.gd")
const ENTITY_REGISTRY_SCRIPT := preload("res://gameplay/network/network_entity_registry.gd")
const COMMAND_VALIDATOR_SCRIPT := preload("res://gameplay/network/network_command_validator.gd")
const DEFAULT_MATCH_RULES := preload("res://data/match/default_match_rules.tres")
const FIXED_STEP_CLOCK_SCRIPT := preload("res://gameplay/core/fixed_step_clock.gd")
const UNIT_POOL_SCRIPT := preload("res://gameplay/performance/unit_pool.gd")
const PROJECTILE_SYSTEM_SCRIPT := preload("res://gameplay/combat/projectile_system.gd")
const COMMAND_JOURNAL_SCRIPT := preload("res://gameplay/network/authoritative_command_journal.gd")
const INVARIANT_MONITOR_SCRIPT := preload("res://gameplay/diagnostics/runtime_invariant_monitor.gd")
const SNAPSHOT_BUILDER_SCRIPT := preload("res://gameplay/network/network_snapshot_builder.gd")
const COMMAND_ROUTER_SCRIPT := preload("res://gameplay/network/authoritative_command_router.gd")
const LOCAL_INPUT_SOURCE_SCRIPT := preload("res://gameplay/input/local_command_input_source.gd")
const MATCH_EVENT_HUB_SCRIPT := preload("res://gameplay/presentation/match_event_hub.gd")

const SPATIAL_CELL_SIZE: float = 256.0

@onready var ground_root: Node2D = $World/Ground
@onready var decoration_root: Node2D = $World/Decorations
@onready var resources_root: Node2D = $World/Resources
@onready var structures_root: Node2D = $World/Structures
@onready var units_root: Node2D = $World/Units
@onready var projectiles_root: Node2D = $World/Projectiles
@onready
var camera: PlayerCameraController = get_node_or_null("PlayerCamera") as PlayerCameraController
@onready var hud: MatchPresentationAdapter = get_node_or_null("HUD") as MatchPresentationAdapter

var world_bounds := Rect2(-18000.0, -12000.0, 36000.0, 24000.0)
var unit_cap_per_colony: int = 72
var match_rules: MatchRules
var events: MatchEventHub
var controllers: Array[ColonyController] = []
var world_stream: WorldStreamManager
var match_seconds_left: float = 1200.0
var match_finished: bool = false
var is_headless_server: bool = false

var _spatial_index := UnitSpatialIndex.new(SPATIAL_CELL_SIZE)
var _unit_pool_service: ColonyUnitPool
var _projectile_system: ProjectileSystem
var _server_clock: FixedStepClock
var _command_journal: AuthoritativeCommandJournal
var _invariant_monitor: RuntimeInvariantMonitor
var _snapshot_builder: NetworkSnapshotBuilder
var _entity_registry: NetworkEntityRegistry
var _leaderboard_left: float = 0.0
var _simulation_tier_left: float = 0.0
var _spatial_rebuild_left: float = 0.0
var _spatial_dirty: bool = true
var _last_emitted_second: int = -1
var _match_seed: int = 738291
var _command_router: AuthoritativeCommandRouter
var _local_input_source: LocalCommandInputSource
var _audio_context_left: float = 0.0

const SPAWN_POSITIONS: Array[Vector2] = [
	Vector2(-6000.0, 3000.0),
	Vector2(6000.0, -3000.0),
	Vector2(6000.0, 3000.0),
	Vector2(-6000.0, -3000.0),
	Vector2(0.0, -7000.0),
	Vector2(0.0, 7000.0),
]
const COLONY_NAMES: Array[String] = [
	"QueenAnt",
	"Red Swarm",
	"Bug Dominion",
	"Forest Legion",
	"Tiny Stompers",
	"Leaf Lickers",
]
const TEAM_COLORS: Array[Color] = [
	Color("2a9cff"),
	Color("ff3d49"),
	Color("35e06f"),
	Color("c252ff"),
	Color("ff9f1a"),
	Color("18d9e8"),
]


func _game_session():
	return get_node_or_null("/root/GameSession")


func _ready() -> void:
	is_headless_server = _detect_headless_server()
	_match_seed = (
		_game_session().get_match_seed() if _game_session().has_method("get_match_seed") else 738291
	)
	match_rules = DEFAULT_MATCH_RULES.duplicate(true) as MatchRules
	if match_rules == null:
		match_rules = MatchRules.new()
	match_rules.sanitize()
	events = MATCH_EVENT_HUB_SCRIPT.new() as MatchEventHub
	events.name = "MatchEvents"
	add_child(events)
	match_seconds_left = match_rules.match_duration_seconds
	unit_cap_per_colony = match_rules.unit_cap_per_colony
	_server_clock = (
		FIXED_STEP_CLOCK_SCRIPT.new(
			match_rules.get_server_tick_interval(), match_rules.max_server_steps_per_frame
		)
		as FixedStepClock
	)
	_unit_pool_service = UNIT_POOL_SCRIPT.new() as ColonyUnitPool
	_unit_pool_service.configure(units_root, match_rules.unit_pool_limit)
	_projectile_system = PROJECTILE_SYSTEM_SCRIPT.new() as ProjectileSystem
	_projectile_system.configure(self, projectiles_root, is_headless_server, match_rules)
	_command_journal = COMMAND_JOURNAL_SCRIPT.new() as AuthoritativeCommandJournal
	_command_journal.configure(match_rules.command_journal_capacity)
	_snapshot_builder = SNAPSHOT_BUILDER_SCRIPT.new() as NetworkSnapshotBuilder
	_snapshot_builder.configure(self)
	_entity_registry = ENTITY_REGISTRY_SCRIPT.new() as NetworkEntityRegistry
	_command_router = COMMAND_ROUTER_SCRIPT.new() as AuthoritativeCommandRouter
	var initial_peer_map: Dictionary = {} if is_headless_server else {1: 0}
	_command_router.configure(
		self, match_rules, _server_clock, _command_journal, _snapshot_builder, initial_peer_map
	)
	if not is_headless_server:
		_local_input_source = LOCAL_INPUT_SOURCE_SCRIPT.new() as LocalCommandInputSource
		_local_input_source.configure(
			request_local_command,
			_get_server_tick_interval,
			_clear_local_movement,
			_cancel_camera_gestures
		)
	_game_session().bind_match(self)
	GameTransport.bind_match(self)
	units_root.y_sort_enabled = false
	structures_root.y_sort_enabled = not is_headless_server
	decoration_root.y_sort_enabled = not is_headless_server
	resources_root.y_sort_enabled = not is_headless_server
	projectiles_root.y_sort_enabled = false

	world_stream = WORLD_STREAM_MANAGER_SCRIPT.new() as WorldStreamManager
	add_child(world_stream)
	world_stream.configure(
		world_bounds,
		ground_root,
		decoration_root,
		resources_root,
		SPAWN_POSITIONS,
		not is_headless_server
	)

	for index in SPAWN_POSITIONS.size():
		var controller := COLONY_CONTROLLER_SCRIPT.new() as ColonyController
		add_child(controller)
		var colony_name: String = _game_session().player_name if index == 0 else COLONY_NAMES[index]
		var local_human: bool = index == 0 and not is_headless_server
		controller.configure(
			self,
			index,
			colony_name,
			TEAM_COLORS[index],
			local_human,
			SPAWN_POSITIONS[index],
			local_human,
			1 if local_human else 0
		)
		controllers.append(controller)

	var player_controller: ColonyController = controllers[0]
	if is_headless_server:
		if is_instance_valid(camera):
			camera.enabled = false
		if is_instance_valid(hud):
			hud.visible = false
			hud.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		if not is_instance_valid(camera) or not is_instance_valid(hud):
			push_error("Client match scene requires PlayerCamera and HUD")
			return
		if not hud.safe_frame_insets_changed.is_connected(camera.set_safe_frame_insets):
			hud.safe_frame_insets_changed.connect(camera.set_safe_frame_insets)
		hud.bind_match(self, player_controller)
		_game_session().bind_player(player_controller)
		AudioSystem.enter_match()
		_update_audio_context()
		_audio_context_left = match_rules.audio_context_interval
		camera.set_world_bounds(world_bounds)
		camera.set_safe_frame_insets(hud.get_world_safe_frame_insets())
		camera.set_target(player_controller.commander)
	_refresh_world_interest_targets()
	world_stream.prime_initial_area()
	if not events.player_commander_changed.is_connected(_on_player_commander_changed):
		events.player_commander_changed.connect(_on_player_commander_changed)
	_rebuild_spatial_index()
	_update_ai_simulation_tiers()
	_emit_match_second()
	_emit_leaderboard()
	_invariant_monitor = INVARIANT_MONITOR_SCRIPT.new() as RuntimeInvariantMonitor
	add_child(_invariant_monitor)
	_invariant_monitor.configure(self)


func _exit_tree() -> void:
	_free_detached_pools()
	_game_session().clear()


func _free_detached_pools() -> void:
	if _unit_pool_service != null:
		_unit_pool_service.shutdown()
	if _projectile_system != null:
		_projectile_system.shutdown()
	if _snapshot_builder != null:
		_snapshot_builder.reset()
	if _command_router != null:
		_command_router.reset()
	if _local_input_source != null:
		_local_input_source.reset()


func _physics_process(delta: float) -> void:
	if match_finished:
		return
	match_seconds_left = maxf(0.0, match_seconds_left - delta)
	_emit_match_second()
	if _command_router != null:
		_command_router.advance_server_tick(delta)
	if _projectile_system != null:
		_projectile_system.advance(delta)
	if not is_headless_server:
		if _local_input_source != null:
			_local_input_source.advance(delta)
		_audio_context_left -= delta
		if _audio_context_left <= 0.0:
			_audio_context_left = match_rules.audio_context_interval
			_update_audio_context()

	_spatial_rebuild_left -= delta
	if _spatial_rebuild_left <= 0.0:
		_spatial_rebuild_left = match_rules.spatial_rebuild_interval
		_rebuild_spatial_index()

	_leaderboard_left -= delta
	if _leaderboard_left <= 0.0:
		_leaderboard_left = match_rules.leaderboard_interval
		_emit_leaderboard()
		_check_victory()

	_simulation_tier_left -= delta
	if _simulation_tier_left <= 0.0:
		_simulation_tier_left = match_rules.simulation_tier_interval
		_update_ai_simulation_tiers()

	if match_seconds_left <= 0.0:
		_finish_by_score()


func mark_spatial_index_dirty() -> void:
	_spatial_dirty = true


func find_nearest_enemy(team_id: int, origin: Vector2, max_range: float) -> Node2D:
	if _spatial_dirty and _spatial_index.get_indexed_unit_count() == 0:
		_rebuild_spatial_index()
	return _spatial_index.find_nearest_enemy(team_id, origin, max_range)


func calculate_ally_separation(
	team_id: int, origin: Vector2, radius: float, requester: Node2D
) -> Vector2:
	return _spatial_index.calculate_separation(team_id, origin, radius, requester)


func find_nearest_enemy_nest(team_id: int, origin: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance_squared: float = INF
	for controller in controllers:
		if (
			controller.team_id != team_id
			and is_instance_valid(controller.nest)
			and controller.nest.is_alive()
		):
			var distance_squared: float = origin.distance_squared_to(
				controller.nest.global_position
			)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best = controller.nest
	return best


func find_nearest_resource(
	origin: Vector2, max_range: float, preferred_type: StringName = &""
) -> WorldResourceNode:
	if not is_instance_valid(world_stream):
		return null
	return world_stream.find_nearest_resource(origin, max_range, preferred_type)


func spawn_projectile(
	attacker: ColonyUnit, victim: Node2D, damage: float, speed: float, color: Color
) -> void:
	if _projectile_system == null:
		return
	_projectile_system.spawn(attacker, victim, damage, speed, color)


func on_colony_eliminated(_controller: ColonyController) -> void:
	mark_spatial_index_dirty()
	_check_victory()


func _check_victory() -> void:
	var active: Array[ColonyController] = []
	for controller in controllers:
		if controller.is_active():
			active.append(controller)
	if active.size() == 1:
		_finish_match(active[0])
	elif active.is_empty():
		_finish_by_score()


func _finish_by_score() -> void:
	var sorted: Array[ColonyController] = controllers.duplicate()
	sorted.sort_custom(
		func(a: ColonyController, b: ColonyController) -> bool: return a.get_score() > b.get_score()
	)
	if not sorted.is_empty():
		_finish_match(sorted[0])


func _finish_match(winner: ColonyController) -> void:
	if match_finished:
		return
	match_finished = true
	set_local_input_enabled(false)
	if not is_headless_server:
		AudioSystem.notify_match_end(winner.is_player)
	events.match_ended.emit(winner.display_name, winner.is_player)


func restart_match() -> void:
	AudioSystem.play_ui(&"ui_select")
	_game_session().prepare_new_match()
	var error: int = get_tree().reload_current_scene()
	if error != OK:
		push_error("Match reload failed: %s" % error_string(error))


func return_to_menu() -> void:
	AudioSystem.play_ui(&"ui_select")
	AudioSystem.enter_menu()
	var error: int = get_tree().change_scene_to_file("res://scenes/boot.tscn")
	if error != OK:
		push_error("Return to menu failed: %s" % error_string(error))


func get_stream_stats() -> Dictionary:
	var projectile_stats: Dictionary = (
		_projectile_system.get_stats() if _projectile_system != null else {}
	)
	var unit_pool_stats: Dictionary = (
		_unit_pool_service.get_stats() if _unit_pool_service != null else {}
	)
	var snapshot_stats: Dictionary = (
		_snapshot_builder.get_stats() if _snapshot_builder != null else {}
	)
	var scheduled_minions: int = 0
	var swarm_simulation_steps: int = 0
	var swarm_dropped_time: float = 0.0
	for controller in controllers:
		scheduled_minions += controller.get_scheduled_swarm_count()
		var scheduler_stats: Dictionary = controller.get_swarm_scheduler_stats()
		swarm_simulation_steps += int(scheduler_stats.get("simulation_steps", 0))
		swarm_dropped_time += float(scheduler_stats.get("dropped_time", 0.0))
	if not is_instance_valid(world_stream):
		return {
			"chunks": 0,
			"active_chunks": 0,
			"warm_chunks": 0,
			"resources": 0,
			"pending_chunks": 0,
			"indexed_units": 0,
			"spatial_cells": 0,
			"stale_spatial_entries": 0,
			"projectile_pool": 0,
			"active_projectiles": 0,
			"logical_projectiles": int(projectile_stats.get("logical", 0)),
			"dropped_projectiles": int(projectile_stats.get("dropped", 0)),
			"unit_pool": int(unit_pool_stats.get("pooled", 0)),
			"registered_entities":
			_entity_registry.get_registered_count() if _entity_registry != null else 0,
			"dropped_server_time": _server_clock.dropped_time if _server_clock != null else 0.0,
			"dropped_projectile_time": float(projectile_stats.get("dropped_time", 0.0)),
			"scheduled_minions": scheduled_minions,
			"swarm_simulation_steps": swarm_simulation_steps,
			"swarm_dropped_time": swarm_dropped_time,
			"snapshot_cadence_entries": int(snapshot_stats.get("viewer_entity_cadence_entries", 0)),
			"snapshot_viewers": int(snapshot_stats.get("viewer_relevance_sets", 0)),
		}
	var pool_stats: Dictionary = world_stream.get_pool_stats()
	return {
		"chunks": world_stream.get_loaded_chunk_count(),
		"active_chunks": world_stream.get_active_chunk_count(),
		"warm_chunks": world_stream.get_warm_chunk_count(),
		"resources": world_stream.get_active_resource_count(),
		"pending_chunks": world_stream.get_pending_load_count(),
		"stream_cost_usec": world_stream.get_last_stream_cost_usec(),
		"pooled_props": int(pool_stats.get("props", 0)),
		"pooled_resources": int(pool_stats.get("resources", 0)),
		"indexed_units": _spatial_index.get_indexed_unit_count(),
		"spatial_cells": _spatial_index.get_cell_count(),
		"stale_spatial_entries": _spatial_index.get_stale_entry_skip_count(),
		"projectile_pool": int(projectile_stats.get("pooled", 0)),
		"active_projectiles": int(projectile_stats.get("active", 0)),
		"logical_projectiles": int(projectile_stats.get("logical", 0)),
		"dropped_projectiles": int(projectile_stats.get("dropped", 0)),
		"unit_pool": int(unit_pool_stats.get("pooled", 0)),
		"registered_entities":
		_entity_registry.get_registered_count() if _entity_registry != null else 0,
		"dropped_server_time": _server_clock.dropped_time if _server_clock != null else 0.0,
		"dropped_projectile_time": float(projectile_stats.get("dropped_time", 0.0)),
		"scheduled_minions": scheduled_minions,
		"swarm_simulation_steps": swarm_simulation_steps,
		"swarm_dropped_time": swarm_dropped_time,
		"snapshot_cadence_entries": int(snapshot_stats.get("viewer_entity_cadence_entries", 0)),
		"snapshot_viewers": int(snapshot_stats.get("viewer_relevance_sets", 0)),
		"interest_targets": world_stream.get_interest_target_count(),
		"desired_chunks": world_stream.get_desired_chunk_count(),
		"resident_chunk_limit": world_stream.get_resident_chunk_limit(),
	}


func get_minimap_snapshot() -> Dictionary:
	var colony_entries: Array[Dictionary] = []
	for controller in controllers:
		var commander_position := Vector2.INF
		var commander_facing := Vector2.UP
		var nest_position := Vector2.INF
		if is_instance_valid(controller.commander):
			commander_position = controller.commander.global_position
			commander_facing = controller.commander.facing_direction
		if is_instance_valid(controller.nest) and controller.nest.is_alive():
			nest_position = controller.nest.global_position
		(
			colony_entries
			. append(
				{
					"team_id": controller.team_id,
					"color": controller.team_color,
					"commander": commander_position,
					"facing": commander_facing,
					"nest": nest_position,
					"army_size": controller.get_army_size(),
					"active": controller.is_active(),
					"is_player": controller.is_player,
				}
			)
		)
	var loaded_chunks: Array[Vector2i] = []
	var chunk_entries: Array[Dictionary] = []
	var resource_points: Array[Dictionary] = []
	if is_instance_valid(world_stream):
		loaded_chunks = world_stream.get_loaded_chunk_coords()
		chunk_entries = world_stream.get_minimap_chunk_entries()
		resource_points = world_stream.get_minimap_resource_points()
	return {
		"world_bounds": world_bounds,
		"colonies": colony_entries,
		"view_rect": camera.get_world_view_rect() if is_instance_valid(camera) else Rect2(),
		"loaded_chunks": loaded_chunks,
		"chunk_entries": chunk_entries,
		"resources": resource_points,
		"chunk_size": world_stream.get_chunk_size() if is_instance_valid(world_stream) else 1200.0,
	}


func _update_audio_context() -> void:
	if is_headless_server or controllers.is_empty():
		return
	var player_controller: ColonyController = controllers[0]
	if not is_instance_valid(player_controller):
		return
	var commander: ColonyUnit = player_controller.commander
	var listener_anchor: Node2D = commander
	if not is_instance_valid(listener_anchor):
		if is_instance_valid(player_controller.nest) and player_controller.nest.is_alive():
			listener_anchor = player_controller.nest
		else:
			return
	var listener_position: Vector2 = listener_anchor.global_position
	var friendly_moving: int = 0
	var nearby_enemies: int = 0
	var active_combatants: int = 0
	var radius_squared: float = match_rules.audio_context_radius * match_rules.audio_context_radius
	for controller in controllers:
		for unit in controller.units:
			if (
				not is_instance_valid(unit)
				or not unit.is_alive()
				or unit.simulation_tier == ColonyUnit.SimulationTier.DORMANT
				or unit.global_position.distance_squared_to(listener_position) > radius_squared
			):
				continue
			if controller.team_id == player_controller.team_id:
				if unit.velocity.length_squared() > 225.0:
					friendly_moving += 1
			else:
				nearby_enemies += 1
			if is_instance_valid(unit.target):
				active_combatants += 1
	var queen_health: float = commander.get_health_ratio() if is_instance_valid(commander) else 1.0
	var growth: float = 0.0
	if player_controller.should_workers_gather():
		growth += 0.55
	if (
		is_instance_valid(player_controller.nest)
		and not player_controller.nest.production_queue.is_empty()
	):
		growth += 0.55
	var biome: StringName = &"forest"
	if is_instance_valid(world_stream) and world_stream.has_method("get_biome_at"):
		biome = world_stream.get_biome_at(listener_position)
	(
		AudioSystem
		. update_gameplay_context(
			{
				"listener_position": listener_position,
				"threat": clampf(float(nearby_enemies) / 16.0, 0.0, 1.0),
				"combat": clampf(float(active_combatants) / 12.0, 0.0, 1.0),
				"queen_health": queen_health,
				"growth": clampf(growth, 0.0, 1.0),
				"biome": biome,
				"swarm_intensity": clampf(float(friendly_moving) / 26.0, 0.0, 1.0),
			}
		)
	)


func _on_player_commander_changed(new_commander: Node2D) -> void:
	if not is_headless_server and is_instance_valid(camera):
		camera.set_target(new_commander)
	if is_instance_valid(world_stream):
		world_stream.prime_initial_area()
	mark_spatial_index_dirty()


func on_controller_commander_changed(changed_controller: ColonyController) -> void:
	if (
		not is_headless_server
		and is_instance_valid(changed_controller)
		and changed_controller.is_local_player
		and is_instance_valid(camera)
	):
		var camera_anchor: Node2D = changed_controller.commander
		if (
			not is_instance_valid(camera_anchor)
			and is_instance_valid(changed_controller.nest)
			and changed_controller.nest.is_alive()
		):
			camera_anchor = changed_controller.nest
		if is_instance_valid(camera_anchor):
			camera.set_target(camera_anchor)
	if is_instance_valid(world_stream) and not controllers.is_empty():
		_refresh_world_interest_targets()
	mark_spatial_index_dirty()


func _update_ai_simulation_tiers() -> void:
	if controllers.is_empty():
		return
	var simulation_interest_positions: Array[Vector2] = []
	for candidate in controllers:
		var owns_interest: bool = is_headless_server or candidate.is_local_player
		if owns_interest and is_instance_valid(candidate.commander):
			simulation_interest_positions.append(candidate.commander.global_position)
	for controller in controllers:
		if controller.is_human and (is_headless_server or controller.is_local_player):
			controller.set_simulation_tier(ColonyController.SimulationTier.FULL)
			continue
		var anchor_position: Vector2 = Vector2.INF
		if is_instance_valid(controller.commander):
			anchor_position = controller.commander.global_position
		elif is_instance_valid(controller.nest):
			anchor_position = controller.nest.global_position
		if anchor_position == Vector2.INF:
			continue
		var distance: float = INF
		for interest_position in simulation_interest_positions:
			distance = minf(distance, interest_position.distance_to(anchor_position))
		var tier: int = ColonyController.SimulationTier.DORMANT
		if distance <= 2200.0:
			tier = ColonyController.SimulationTier.FULL
		elif distance <= 4600.0:
			tier = ColonyController.SimulationTier.REDUCED
		controller.set_simulation_tier(tier)
	mark_spatial_index_dirty()


func _emit_leaderboard() -> void:
	var entries: Array[Dictionary] = []
	for controller in controllers:
		(
			entries
			. append(
				{
					"name": controller.display_name,
					"score": controller.get_score(),
					"team_color": controller.team_color,
					"eliminated": controller.eliminated,
				}
			)
		)
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"])
	)
	events.leaderboard_changed.emit(entries)


func _emit_match_second() -> void:
	var current_second: int = int(ceil(match_seconds_left))
	if current_second == _last_emitted_second:
		return
	_last_emitted_second = current_second
	events.match_time_changed.emit(current_second)


func _rebuild_spatial_index() -> void:
	_spatial_index.rebuild(controllers)
	_spatial_dirty = false


func acquire_unit() -> ColonyUnit:
	return _unit_pool_service.acquire() if _unit_pool_service != null else null


func release_unit(unit: ColonyUnit) -> void:
	if _unit_pool_service != null:
		_unit_pool_service.release(unit)


func register_network_entity(node: Node, preferred_entity_id: int = 0) -> int:
	if _entity_registry == null or not is_instance_valid(node):
		return 0
	var entity_id: int = _entity_registry.register(node, preferred_entity_id)
	if entity_id <= 0:
		return 0
	node.set("network_entity_id", entity_id)
	return entity_id


func unregister_network_entity(entity_id: int, expected_node: Node = null) -> void:
	if _snapshot_builder != null:
		_snapshot_builder.retire_entity(entity_id)
	if _entity_registry != null:
		_entity_registry.unregister(entity_id, expected_node)


func resolve_network_entity(entity_id: int) -> Node:
	return _entity_registry.resolve(entity_id) if _entity_registry != null else null


func get_controller_by_team_id(team_id: int) -> ColonyController:
	if team_id < 0 or team_id >= controllers.size():
		return null
	return controllers[team_id]


func get_match_seed() -> int:
	return _match_seed


func get_server_tick() -> int:
	return _command_router.get_server_tick() if _command_router != null else 0


func request_local_movement(value: Vector2) -> void:
	if _local_input_source != null:
		_local_input_source.set_joystick(value)


func set_local_input_enabled(enabled: bool) -> void:
	if _local_input_source != null:
		_local_input_source.set_enabled(enabled)


func request_local_command(command_type: StringName, payload: Dictionary = {}) -> bool:
	if (
		match_finished
		or _command_router == null
		or (_local_input_source != null and not _local_input_source.is_enabled())
	):
		return false
	return _command_router.request_local_command(command_type, payload)


func receive_authoritative_command(peer_id: int, command: Dictionary) -> bool:
	return _command_router.receive(peer_id, command) if _command_router != null else false


func assign_peer_to_team(peer_id: int, team_id: int) -> bool:
	return (
		_command_router.assign_peer_to_team(peer_id, team_id) if _command_router != null else false
	)


func assign_peer_to_available_team(peer_id: int) -> int:
	return _command_router.assign_peer_to_available_team(peer_id) if _command_router != null else -1


func get_team_for_peer(peer_id: int) -> int:
	return _command_router.get_team_for_peer(peer_id) if _command_router != null else -1


func release_peer(peer_id: int) -> void:
	if _command_router != null:
		_command_router.release_peer(peer_id)


func detach_peer_for_reconnect(peer_id: int) -> int:
	return _command_router.detach_peer_for_reconnect(peer_id) if _command_router != null else -1


func release_reserved_team_to_ai(team_id: int) -> void:
	if _command_router != null:
		_command_router.release_team_to_ai(team_id)


func get_last_command_sequence(peer_id: int) -> int:
	return _command_router.get_last_sequence(peer_id) if _command_router != null else -1


func build_network_snapshot_for_team(team_id: int, radius: float = 2300.0) -> Dictionary:
	if _command_router == null:
		return {}
	return _command_router.build_snapshot_for_team(team_id, radius)


func get_recent_authoritative_commands() -> Array[Dictionary]:
	return _command_router.get_recent_commands() if _command_router != null else []


func refresh_world_interest_targets() -> void:
	_refresh_world_interest_targets()


func refresh_ai_simulation_tiers() -> void:
	_update_ai_simulation_tiers()


func _get_server_tick_interval() -> float:
	return match_rules.get_server_tick_interval() if match_rules != null else 1.0 / 20.0


func _clear_local_movement() -> void:
	if not controllers.is_empty() and is_instance_valid(controllers[0]):
		controllers[0].set_joystick_input(Vector2.ZERO)


func _cancel_camera_gestures() -> void:
	if is_instance_valid(camera):
		camera.cancel_gesture_state()


func get_runtime_invariant_counts() -> Dictionary:
	return (
		_invariant_monitor.get_violation_counts() if is_instance_valid(_invariant_monitor) else {}
	)


func _refresh_world_interest_targets() -> void:
	if not is_instance_valid(world_stream):
		return
	world_stream.clear_interest_targets()
	for controller in controllers:
		var should_anchor: bool = is_headless_server or controller.is_local_player
		if not should_anchor or not controller.is_active():
			continue
		var anchor: Node2D = controller.commander
		if not is_instance_valid(anchor) and is_instance_valid(controller.nest):
			anchor = controller.nest
		if is_instance_valid(anchor):
			world_stream.add_interest_target(controller.team_id, anchor)


func _quantize_position(value: Vector2) -> Vector2i:
	return Vector2i(roundi(value.x * 0.25), roundi(value.y * 0.25))


func _detect_headless_server() -> bool:
	return (
		OS.has_feature("dedicated_server")
		or DisplayServer.get_name() == "headless"
		or "--server" in OS.get_cmdline_user_args()
	)
