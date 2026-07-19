class_name NetworkSnapshotBuilder
extends RefCounted

const DEFAULT_RADIUS: float = 2300.0
const MIN_RADIUS: float = 128.0
const MAX_RADIUS: float = 5000.0
const KEYFRAME_INTERVAL_TICKS: int = 40
const COLONY_SUMMARY_INTERVAL_TICKS: int = 20
const NEAR_ENTITY_DISTANCE_SQUARED: float = 1_440_000.0
const RESOURCE_STATE_INTERVAL_TICKS: int = 10
const MAX_RESOURCE_STATES: int = 72

var _host: Node = null
var _last_tick_by_viewer_entity: Dictionary = {}
var _known_entities_by_team: Dictionary = {}


func configure(host: Node) -> void:
	_host = host
	reset()


func build_for_team(team_id: int, radius: float = DEFAULT_RADIUS) -> Dictionary:
	var controllers: Array = _get_controllers()
	if team_id < 0 or team_id >= controllers.size():
		return {}
	var safe_radius: float = radius if is_finite(radius) else DEFAULT_RADIUS
	safe_radius = clampf(safe_radius, MIN_RADIUS, MAX_RADIUS)
	var viewer: ColonyController = controllers[team_id] as ColonyController
	if not is_instance_valid(viewer):
		return _build_empty(team_id)
	var viewer_anchor: Node2D = _resolve_viewer_anchor(viewer)
	if not is_instance_valid(viewer_anchor) or not viewer_anchor.global_position.is_finite():
		return _build_empty(team_id)

	var server_tick: int = _get_server_tick()
	var origin: Vector2 = viewer_anchor.global_position
	var radius_squared: float = safe_radius * safe_radius
	var entities: Array[Dictionary] = []
	var current_relevant: Dictionary = {}
	var full_keyframe: bool = server_tick % KEYFRAME_INTERVAL_TICKS == 0
	for controller_variant in controllers:
		var controller: ColonyController = controller_variant as ColonyController
		if not is_instance_valid(controller):
			continue
		_append_relevant_units(
			entities, controller, team_id, origin, radius_squared, server_tick, full_keyframe
		)
		_append_relevant_nest(
			entities, controller, team_id, origin, radius_squared, server_tick, full_keyframe
		)

	_finalize_entity_batch(entities, current_relevant, team_id, server_tick)
	var despawned: PackedInt64Array = _collect_despawns(team_id, current_relevant)
	var colony_summaries: Array[Dictionary] = []
	if server_tick % COLONY_SUMMARY_INTERVAL_TICKS == 0:
		for controller_variant in controllers:
			var controller: ColonyController = controller_variant as ColonyController
			if not is_instance_valid(controller):
				continue
			(
				colony_summaries
				. append(
					{
						"team": controller.team_id,
						"army": controller.get_army_size(),
						"active": controller.is_active(),
						"score": controller.get_score(),
					}
				)
			)
	var resource_states: Array[Dictionary] = []
	if full_keyframe or server_tick % RESOURCE_STATE_INTERVAL_TICKS == 0:
		var world_stream := _host.get("world_stream") as WorldStreamManager
		if is_instance_valid(world_stream):
			resource_states = world_stream.get_network_resource_states(
				origin, safe_radius, MAX_RESOURCE_STATES
			)
	return {
		"server_tick": server_tick,
		"keyframe": full_keyframe,
		"entities": entities,
		"despawned": despawned,
		"colonies": colony_summaries,
		"player": _build_player_state(viewer),
		"resource_states": resource_states,
	}


func _build_player_state(viewer: ColonyController) -> Dictionary:
	var inventory_snapshot: Dictionary = {}
	if viewer.inventory != null:
		inventory_snapshot = viewer.inventory.snapshot()
	var queue: Array[StringName] = []
	var production_progress: float = 0.0
	if is_instance_valid(viewer.nest):
		queue = viewer.nest.production_queue.duplicate()
		production_progress = clampf(viewer.nest.production_progress, 0.0, 1.0)
	return {
		"team_id": viewer.team_id,
		"inventory": inventory_snapshot,
		"level": viewer.progression.level if viewer.progression != null else 1,
		"army": viewer.get_army_size(),
		"capacity": viewer.get_unit_capacity(),
		"score": viewer.get_score(),
		"queue": queue,
		"production_progress": production_progress,
		"match_time": float(_host.get("match_seconds_left")) if is_instance_valid(_host) else 0.0,
	}


func retire_entity(entity_id: int) -> void:
	if entity_id <= 0:
		return
	var controllers: Array = _get_controllers()
	for team_index in controllers.size():
		_last_tick_by_viewer_entity.erase(_make_viewer_entity_key(team_index, entity_id))
		var known: Dictionary = _known_entities_by_team.get(team_index, {})
		if known.erase(entity_id):
			_known_entities_by_team[team_index] = known


func clear_team(team_id: int) -> void:
	_known_entities_by_team.erase(team_id)
	for key_variant in _last_tick_by_viewer_entity.keys():
		var key: int = int(key_variant)
		if (key >> 32) == team_id:
			_last_tick_by_viewer_entity.erase(key)


func reset() -> void:
	_last_tick_by_viewer_entity.clear()
	_known_entities_by_team.clear()


func get_stats() -> Dictionary:
	return {
		"viewer_entity_cadence_entries": _last_tick_by_viewer_entity.size(),
		"viewer_relevance_sets": _known_entities_by_team.size(),
	}


func _append_relevant_units(
	entities: Array[Dictionary],
	controller: ColonyController,
	viewer_team_id: int,
	origin: Vector2,
	radius_squared: float,
	server_tick: int,
	full_keyframe: bool
) -> void:
	for unit in controller.units:
		if (
			not is_instance_valid(unit)
			or unit.definition == null
			or unit.network_entity_id <= 0
			or not unit.is_alive()
			or not unit.global_position.is_finite()
		):
			continue
		var distance_squared: float = origin.distance_squared_to(unit.global_position)
		if distance_squared > radius_squared:
			continue
		var interval_ticks: int = 2 if distance_squared <= NEAR_ENTITY_DISTANCE_SQUARED else 5
		if unit.definition.role == &"commander":
			interval_ticks = 1
		var due: bool = (
			full_keyframe
			or _is_entity_due(viewer_team_id, unit.network_entity_id, interval_ticks, server_tick)
		)
		(
			entities
			. append(
				{
					"id": unit.network_entity_id,
					"team": unit.team_id,
					"kind": unit.definition.unit_id,
					"position": _quantize_position(unit.global_position),
					"health": roundi(unit.get_health_ratio() * 255.0),
					"_distance_sq": distance_squared,
					"_due": due,
				}
			)
		)


func _append_relevant_nest(
	entities: Array[Dictionary],
	controller: ColonyController,
	viewer_team_id: int,
	origin: Vector2,
	radius_squared: float,
	server_tick: int,
	full_keyframe: bool
) -> void:
	if (
		not is_instance_valid(controller.nest)
		or controller.nest.network_entity_id <= 0
		or not controller.nest.is_alive()
		or not controller.nest.global_position.is_finite()
		or origin.distance_squared_to(controller.nest.global_position) > radius_squared
	):
		return
	var due: bool = (
		full_keyframe
		or _is_entity_due(viewer_team_id, controller.nest.network_entity_id, 10, server_tick)
	)
	(
		entities
		. append(
			{
				"id": controller.nest.network_entity_id,
				"team": controller.team_id,
				"kind": &"nest",
				"position": _quantize_position(controller.nest.global_position),
				"health": roundi(controller.nest.get_health_ratio() * 255.0),
				"_distance_sq": origin.distance_squared_to(controller.nest.global_position),
				"_due": due,
			}
		)
	)


func _finalize_entity_batch(
	entities: Array[Dictionary], current_relevant: Dictionary, viewer_team_id: int, server_tick: int
) -> void:
	entities.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var priority_a: int = _snapshot_priority(a, viewer_team_id)
			var priority_b: int = _snapshot_priority(b, viewer_team_id)
			if priority_a != priority_b:
				return priority_a < priority_b
			return float(a.get("_distance_sq", INF)) < float(b.get("_distance_sq", INF))
	)
	if entities.size() > NetworkProtocol.MAX_SNAPSHOT_ENTITIES:
		entities.resize(NetworkProtocol.MAX_SNAPSHOT_ENTITIES)
	current_relevant.clear()
	for index in range(entities.size() - 1, -1, -1):
		var entity: Dictionary = entities[index]
		var entity_id: int = int(entity.get("id", 0))
		if entity_id <= 0:
			entities.remove_at(index)
			continue
		current_relevant[entity_id] = true
		var due: bool = bool(entity.get("_due", false))
		entity.erase("_distance_sq")
		entity.erase("_due")
		if not due:
			entities.remove_at(index)
			continue
		_mark_entity_sent(viewer_team_id, entity_id, server_tick)


func _snapshot_priority(entity: Dictionary, viewer_team_id: int) -> int:
	var kind := StringName(entity.get("kind", &""))
	var team: int = int(entity.get("team", -1))
	if team == viewer_team_id and kind == &"commander":
		return 0
	if kind == &"nest":
		return 1 if team == viewer_team_id else 2
	if team == viewer_team_id:
		return 3
	return 4


func _collect_despawns(team_id: int, current_relevant: Dictionary) -> PackedInt64Array:
	var previous_known: Dictionary = _known_entities_by_team.get(team_id, {})
	var despawned := PackedInt64Array()
	for entity_id_variant in previous_known.keys():
		var entity_id: int = int(entity_id_variant)
		if not current_relevant.has(entity_id):
			despawned.append(entity_id)
	_known_entities_by_team[team_id] = current_relevant
	return despawned


func _build_empty(team_id: int) -> Dictionary:
	var previous_known: Dictionary = _known_entities_by_team.get(team_id, {})
	var despawned := PackedInt64Array()
	for entity_id_variant in previous_known.keys():
		var entity_id: int = int(entity_id_variant)
		if entity_id > 0:
			despawned.append(entity_id)
	clear_team(team_id)
	return {
		"server_tick": _get_server_tick(),
		"keyframe": true,
		"entities": [],
		"despawned": despawned,
		"colonies": [],
		"player": {},
		"resource_states": [],
	}


func _resolve_viewer_anchor(viewer: ColonyController) -> Node2D:
	if is_instance_valid(viewer.commander) and viewer.commander.is_alive():
		return viewer.commander
	if is_instance_valid(viewer.nest) and viewer.nest.is_alive():
		return viewer.nest
	return null


func _is_entity_due(team_id: int, entity_id: int, interval_ticks: int, server_tick: int) -> bool:
	var key: int = _make_viewer_entity_key(team_id, entity_id)
	var last_tick: int = int(_last_tick_by_viewer_entity.get(key, -1_000_000))
	return server_tick - last_tick >= maxi(interval_ticks, 1)


func _mark_entity_sent(team_id: int, entity_id: int, server_tick: int) -> void:
	_last_tick_by_viewer_entity[_make_viewer_entity_key(team_id, entity_id)] = server_tick


func _make_viewer_entity_key(team_id: int, entity_id: int) -> int:
	return (team_id << 32) ^ entity_id


func _quantize_position(value: Vector2) -> Vector2i:
	return Vector2i(roundi(value.x * 2.0), roundi(value.y * 2.0))


func _get_controllers() -> Array:
	if not is_instance_valid(_host):
		return []
	var controllers_variant: Variant = _host.get("controllers")
	return controllers_variant if controllers_variant is Array else []


func _get_server_tick() -> int:
	if not is_instance_valid(_host) or not _host.has_method("get_server_tick"):
		return 0
	return maxi(int(_host.call("get_server_tick")), 0)
