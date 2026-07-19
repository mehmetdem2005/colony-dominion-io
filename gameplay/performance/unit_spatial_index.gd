class_name UnitSpatialIndex
extends RefCounted

const DEFAULT_CELL_SIZE: float = 256.0

var cell_size: float = DEFAULT_CELL_SIZE
var _cells: Dictionary = {}
var _unit_count: int = 0
var _stale_entry_skips: int = 0


func _init(new_cell_size: float = DEFAULT_CELL_SIZE) -> void:
	cell_size = maxf(new_cell_size, 64.0) if is_finite(new_cell_size) else DEFAULT_CELL_SIZE


func rebuild(controllers: Array[ColonyController]) -> void:
	_cells.clear()
	_unit_count = 0
	_stale_entry_skips = 0
	for controller in controllers:
		if not is_instance_valid(controller) or not controller.is_active():
			continue
		for unit in controller.units:
			if not is_instance_valid(unit) or not unit.is_alive() or not unit.visible:
				continue
			_insert(unit)
		if is_instance_valid(controller.nest) and controller.nest.is_alive():
			_insert(controller.nest)


func find_nearest_enemy(team_id: int, origin: Vector2, max_range: float) -> Node2D:
	if not origin.is_finite() or not is_finite(max_range) or max_range <= 0.0:
		return null
	var best: Node2D = null
	var best_distance_squared: float = max_range * max_range
	var minimum_cell: Vector2i = _world_to_cell(origin - Vector2.ONE * max_range)
	var maximum_cell: Vector2i = _world_to_cell(origin + Vector2.ONE * max_range)
	for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
		for cell_y in range(minimum_cell.y, maximum_cell.y + 1):
			var key := Vector2i(cell_x, cell_y)
			if not _cells.has(key):
				continue
			var teams: Dictionary = _cells[key]
			for candidate_team_variant in teams.keys():
				var candidate_team: int = int(candidate_team_variant)
				if candidate_team == team_id:
					continue
				var bucket: PackedInt64Array = teams[candidate_team]
				for candidate_id in bucket:
					var candidate: Node2D = _resolve_node(candidate_id)
					if candidate == null:
						continue
					if not _is_valid_damageable(candidate, team_id, false):
						continue
					var distance_squared: float = origin.distance_squared_to(
						candidate.global_position
					)
					if distance_squared < best_distance_squared:
						best_distance_squared = distance_squared
						best = candidate
	return best


func calculate_separation(
	team_id: int, origin: Vector2, radius: float, requester: Node2D
) -> Vector2:
	if not origin.is_finite() or not is_finite(radius) or radius <= 0.0:
		return Vector2.ZERO
	var result := Vector2.ZERO
	var radius_squared: float = radius * radius
	var minimum_cell: Vector2i = _world_to_cell(origin - Vector2.ONE * radius)
	var maximum_cell: Vector2i = _world_to_cell(origin + Vector2.ONE * radius)
	for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
		for cell_y in range(minimum_cell.y, maximum_cell.y + 1):
			var key := Vector2i(cell_x, cell_y)
			if not _cells.has(key):
				continue
			var teams: Dictionary = _cells[key]
			if not teams.has(team_id):
				continue
			var bucket: PackedInt64Array = teams[team_id]
			for candidate_id in bucket:
				var candidate: Node2D = _resolve_node(candidate_id)
				if candidate == null:
					continue
				if (
					candidate == requester
					or not candidate is ColonyUnit
					or not _is_valid_damageable(candidate, team_id, true)
				):
					continue
				var away: Vector2 = origin - candidate.global_position
				var distance_squared: float = away.length_squared()
				if distance_squared <= 0.01 or distance_squared > radius_squared:
					continue
				var distance: float = sqrt(distance_squared)
				var weight: float = 1.0 - clampf(distance / radius, 0.0, 1.0)
				result += away / distance * weight
	return result.limit_length(1.0)


func get_indexed_unit_count() -> int:
	return _unit_count


func get_cell_count() -> int:
	return _cells.size()


func get_stale_entry_skip_count() -> int:
	return _stale_entry_skips


func _insert(node: Node2D) -> void:
	if not is_instance_valid(node) or not node.global_position.is_finite():
		return
	var key: Vector2i = _world_to_cell(node.global_position)
	if not _cells.has(key):
		_cells[key] = {}
	var teams: Dictionary = _cells[key]
	var team_id: int = int(node.get("team_id"))
	if not teams.has(team_id):
		teams[team_id] = PackedInt64Array()
	var bucket: PackedInt64Array = teams[team_id]
	bucket.append(node.get_instance_id())
	teams[team_id] = bucket
	_cells[key] = teams
	_unit_count += 1


func _world_to_cell(world_position: Vector2) -> Vector2i:
	if not world_position.is_finite():
		return Vector2i.ZERO
	return Vector2i(floori(world_position.x / cell_size), floori(world_position.y / cell_size))


func _resolve_node(instance_id: int) -> Node2D:
	if instance_id <= 0 or not is_instance_id_valid(instance_id):
		_stale_entry_skips += 1
		return null
	var candidate_object: Object = instance_from_id(instance_id)
	if not is_instance_valid(candidate_object) or not candidate_object is Node2D:
		_stale_entry_skips += 1
		return null
	return candidate_object as Node2D


func _is_valid_damageable(candidate: Node2D, team_id: int, require_same_team: bool) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate.is_queued_for_deletion() or not candidate.is_inside_tree():
		return false
	var candidate_team: int = int(candidate.get("team_id"))
	if require_same_team:
		if candidate_team != team_id:
			return false
	else:
		if candidate_team == team_id:
			return false
	if candidate.has_method("is_alive"):
		return bool(candidate.is_alive())
	return not bool(candidate.get("is_dead"))
