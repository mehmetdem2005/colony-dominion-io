class_name ColonyBotBrain
extends RefCounted

const DORMANT_NAVIGATION_SPEED_SCALE: float = 0.88
const DORMANT_GOAL_ARRIVAL_RADIUS: float = 72.0
const DORMANT_PATROL_MIN_RADIUS: float = 700.0
const DORMANT_PATROL_MAX_RADIUS: float = 1800.0
const DORMANT_ASSAULT_MAX_RANGE: float = 3000.0
const BOT_ASSAULT_MAX_RANGE: float = 3000.0
const BOT_THREAT_HOLD_RADIUS: float = 300.0
const BOT_ATTACK_COMMIT_ARMY_SIZE: int = 5
const BOT_DECISION_MIN_INTERVAL: float = 0.34
const BOT_DECISION_MAX_INTERVAL: float = 0.56
const BOT_PATROL_MIN_RADIUS: float = 420.0
const BOT_PATROL_MAX_RADIUS: float = 1450.0
const BOT_PATROL_GOAL_MIN_TIME: float = 3.5
const BOT_PATROL_GOAL_MAX_TIME: float = 7.5
const BOT_PATROL_ARRIVAL_RADIUS: float = 78.0
const GATHER_COMMAND_RADIUS: float = 310.0

var _host: Node = null
var _rng: RandomNumberGenerator = null
var _decision_left: float = 0.0
var _goal := Vector2.INF
var _goal_left: float = 0.0


func configure(host: Node, rng: RandomNumberGenerator) -> void:
	_host = host
	_rng = rng
	_goal = Vector2.INF
	_goal_left = 0.0
	_decision_left = _random_range(0.08, 0.20)


func advance_active(delta: float) -> void:
	if not _is_host_ready() or not is_finite(delta) or delta <= 0.0:
		return
	_goal_left = maxf(0.0, _goal_left - delta)
	_decision_left -= delta
	if _decision_left > 0.0:
		return
	_decision_left = _random_range(BOT_DECISION_MIN_INTERVAL, BOT_DECISION_MAX_INTERVAL)
	_run_active_decision()


func advance_dormant_navigation(delta: float) -> void:
	if not _is_host_ready() or not is_finite(delta) or delta <= 0.0:
		return
	var commander: ColonyUnit = _get_commander()
	if commander == null or commander.definition == null:
		return
	_goal_left = maxf(0.0, _goal_left - delta)
	_decision_left -= delta
	if _decision_left <= 0.0:
		_decision_left = _random_range(1.4, 2.2)
		if _goal == Vector2.INF or _goal_left <= 0.0:
			_run_dormant_decision()
	if _goal == Vector2.INF or _goal_left <= 0.0:
		_run_dormant_decision()
	if _goal == Vector2.INF:
		return
	var offset: Vector2 = _goal - commander.global_position
	if offset.length() <= DORMANT_GOAL_ARRIVAL_RADIUS:
		_goal = Vector2.INF
		_run_dormant_decision()
		if _goal == Vector2.INF:
			return
		offset = _goal - commander.global_position
	var maximum_distance: float = (
		commander.definition.move_speed * DORMANT_NAVIGATION_SPEED_SCALE * delta
	)
	var requested_translation: Vector2 = (
		offset.normalized() * minf(offset.length(), maximum_distance)
	)
	var translation: Vector2 = _clamp_dormant_group_translation(requested_translation)
	for unit in _get_units():
		if is_instance_valid(unit) and unit.is_alive():
			unit.apply_dormant_translation(translation)


func run_dormant_economy() -> void:
	if not _is_host_ready():
		return
	var nest: ColonyNest = _get_nest()
	if nest == null or not nest.is_alive():
		return
	var counts: Dictionary = _host.call("get_unit_counts")
	var worker_count: int = maxi(1, int(counts.get(&"worker", 0)))
	var inventory: ColonyInventory = _host.get("inventory") as ColonyInventory
	var progression: ColonyProgression = _host.get("progression") as ColonyProgression
	if inventory == null or progression == null:
		return
	(
		inventory
		. add_batch(
			{
				&"seed": maxi(1, roundi(float(worker_count) * 0.9)),
				&"nectar": maxi(1, roundi(float(worker_count) * 0.48)),
				&"protein": maxi(1, roundi(float(worker_count) * 0.42)),
				&"leaf": maxi(1, roundi(float(worker_count) * 0.55)),
				&"stone": maxi(1, roundi(float(worker_count) * 0.24)),
			}
		)
	)
	if progression.can_upgrade(inventory) and _random_float() < 0.18:
		_host.call("request_nest_upgrade")
	if nest.production_queue.size() >= 2:
		return
	var preferred: StringName = &"soldier"
	if int(counts.get(&"worker", 0)) < 6:
		preferred = &"worker"
	elif int(counts.get(&"soldier", 0)) < 8:
		preferred = &"soldier"
	elif int(counts.get(&"guard", 0)) < 4:
		preferred = &"guard"
	elif int(counts.get(&"acid_ant", 0)) < 4:
		preferred = &"acid_ant"
	elif int(counts.get(&"scout", 0)) < 4:
		preferred = &"scout"
	else:
		var options: Array[StringName] = UnitCatalog.get_producible_ids()
		if not options.is_empty():
			preferred = options[_random_index(options.size())]
	_host.call("request_production", preferred)


func get_move_direction(origin: Vector2) -> Vector2:
	var commander: ColonyUnit = _get_commander()
	if commander == null or not origin.is_finite():
		return Vector2.ZERO
	var forced_variant: Variant = _host.call("get_forced_target")
	var forced: Node2D = forced_variant as Node2D
	if is_instance_valid(forced):
		return (forced.global_position - commander.global_position).normalized()
	if (
		is_instance_valid(commander.target)
		and (
			commander.global_position.distance_to(commander.target.global_position)
			<= BOT_THREAT_HOLD_RADIUS
		)
	):
		return Vector2.ZERO
	if _goal == Vector2.INF or _goal_left <= 0.0:
		return Vector2.ZERO
	var offset: Vector2 = _goal - origin
	if offset.length() < BOT_PATROL_ARRIVAL_RADIUS:
		_goal_left = 0.0
		return Vector2.ZERO
	return offset.normalized()


func on_simulation_tier_changed(dormant: bool) -> void:
	if dormant:
		_goal = Vector2.INF
		_goal_left = 0.0
	else:
		_decision_left = 0.0
		_goal_left = 0.0


func _run_active_decision() -> void:
	var commander: ColonyUnit = _get_commander()
	if commander == null:
		return
	var inventory: ColonyInventory = _host.get("inventory") as ColonyInventory
	var progression: ColonyProgression = _host.get("progression") as ColonyProgression
	if (
		inventory != null
		and progression != null
		and progression.can_upgrade(inventory)
		and _random_float() < 0.45
	):
		_host.call("request_nest_upgrade")
	var counts: Dictionary = _host.call("get_unit_counts")
	var preferred: StringName = _pick_active_production(counts)
	if preferred != &"":
		_host.call("request_production", preferred)
	var army_strength: int = int(_host.call("get_army_size")) - int(counts.get(&"worker", 0))
	var close_enemy_variant: Variant = _host.call(
		"find_nearest_enemy", commander.global_position, 420.0
	)
	var close_enemy: Node2D = close_enemy_variant as Node2D
	if is_instance_valid(close_enemy):
		if army_strength >= BOT_ATTACK_COMMIT_ARMY_SIZE:
			_host.call("set_bot_forced_target", close_enemy, 3.0)
			_goal = close_enemy.global_position
			_goal_left = 3.0
		else:
			_host.call("set_bot_forced_target", null, 0.0)
			_goal = commander.global_position
			_goal_left = 0.8
		return
	var match_controller: Node = _host.get("match_controller") as Node
	var team_id: int = int(_host.get("team_id"))
	if army_strength >= 11 and is_instance_valid(match_controller):
		var enemy_nest_variant: Variant = match_controller.call(
			"find_nearest_enemy_nest", team_id, commander.global_position
		)
		var enemy_nest: Node2D = enemy_nest_variant as Node2D
		if (
			is_instance_valid(enemy_nest)
			and (
				commander.global_position.distance_to(enemy_nest.global_position)
				<= BOT_ASSAULT_MAX_RANGE
			)
		):
			_goal = enemy_nest.global_position
			_goal_left = 12.0
			if commander.global_position.distance_to(_goal) < 460.0:
				_host.call("set_bot_forced_target", enemy_nest, 4.0)
			return
	var preferred_resource: StringName = StringName(_host.call("get_lowest_resource_type_for_bot"))
	var resource: WorldResourceNode = null
	if is_instance_valid(match_controller):
		resource = (
			match_controller.call(
				"find_nearest_resource", commander.global_position, 1300.0, preferred_resource
			)
			as WorldResourceNode
		)
	if resource != null:
		_goal = resource.global_position
		_goal_left = _random_range(4.0, 6.5)
		if (
			commander.global_position.distance_to(resource.global_position) <= GATHER_COMMAND_RADIUS
			and not bool(_host.call("should_workers_gather"))
		):
			_host.call("command_gather")
	elif (
		_goal == Vector2.INF
		or _goal_left <= 0.0
		or commander.global_position.distance_to(_goal) <= BOT_PATROL_ARRIVAL_RADIUS
	):
		_goal = _pick_patrol_goal(BOT_PATROL_MIN_RADIUS, BOT_PATROL_MAX_RADIUS, 10, 260.0)
		_goal_left = _random_range(BOT_PATROL_GOAL_MIN_TIME, BOT_PATROL_GOAL_MAX_TIME)


func _run_dormant_decision() -> void:
	var commander: ColonyUnit = _get_commander()
	if commander == null:
		_goal = Vector2.INF
		return
	var counts: Dictionary = _host.call("get_unit_counts")
	var army_strength: int = int(_host.call("get_army_size")) - int(counts.get(&"worker", 0))
	var match_controller: Node = _host.get("match_controller") as Node
	if army_strength >= 11 and is_instance_valid(match_controller):
		var enemy_nest_variant: Variant = match_controller.call(
			"find_nearest_enemy_nest", int(_host.get("team_id")), commander.global_position
		)
		var enemy_nest: Node2D = enemy_nest_variant as Node2D
		if (
			is_instance_valid(enemy_nest)
			and (
				commander.global_position.distance_to(enemy_nest.global_position)
				<= DORMANT_ASSAULT_MAX_RANGE
			)
		):
			_goal = enemy_nest.global_position
			_goal_left = 12.0
			return
	_goal = _pick_patrol_goal(DORMANT_PATROL_MIN_RADIUS, DORMANT_PATROL_MAX_RADIUS, 8, 280.0)
	_goal_left = _random_range(BOT_PATROL_GOAL_MIN_TIME, BOT_PATROL_GOAL_MAX_TIME)


func _pick_active_production(counts: Dictionary) -> StringName:
	if int(counts.get(&"worker", 0)) < 5:
		return &"worker"
	if int(counts.get(&"soldier", 0)) < 6:
		return &"soldier"
	if int(counts.get(&"scout", 0)) < 3:
		return &"scout"
	if int(counts.get(&"guard", 0)) < 3:
		return &"guard"
	if int(counts.get(&"acid_ant", 0)) < 4:
		return &"acid_ant"
	var options: Array[StringName] = UnitCatalog.get_producible_ids()
	return options[_random_index(options.size())] if not options.is_empty() else &""


func _pick_patrol_goal(
	minimum_radius: float, maximum_radius: float, attempts: int, minimum_travel_distance: float
) -> Vector2:
	var commander: ColonyUnit = _get_commander()
	if commander == null:
		return Vector2.INF
	var center: Vector2 = commander.global_position
	var nest: ColonyNest = _get_nest()
	if nest != null:
		center = nest.global_position
	var bounds_variant: Variant = _host.call("get_world_bounds")
	var bounds: Rect2 = bounds_variant if bounds_variant is Rect2 else Rect2()
	bounds = bounds.grow(-160.0)
	for _attempt in attempts:
		var radius: float = _random_range(minimum_radius, maximum_radius)
		var candidate: Vector2 = center + Vector2.from_angle(_random_range(0.0, TAU)) * radius
		candidate.x = clampf(candidate.x, bounds.position.x, bounds.end.x)
		candidate.y = clampf(candidate.y, bounds.position.y, bounds.end.y)
		if candidate.distance_to(commander.global_position) >= minimum_travel_distance:
			return candidate
	return center


func _clamp_dormant_group_translation(requested: Vector2) -> Vector2:
	if requested.length_squared() <= 0.0001:
		return Vector2.ZERO
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var has_live_unit: bool = false
	for unit in _get_units():
		if not is_instance_valid(unit) or not unit.is_alive():
			continue
		has_live_unit = true
		minimum.x = minf(minimum.x, unit.global_position.x)
		minimum.y = minf(minimum.y, unit.global_position.y)
		maximum.x = maxf(maximum.x, unit.global_position.x)
		maximum.y = maxf(maximum.y, unit.global_position.y)
	if not has_live_unit:
		return Vector2.ZERO
	var bounds_variant: Variant = _host.call("get_world_bounds")
	var bounds: Rect2 = bounds_variant if bounds_variant is Rect2 else Rect2()
	bounds = bounds.grow(-30.0)
	return Vector2(
		clampf(requested.x, bounds.position.x - minimum.x, bounds.end.x - maximum.x),
		clampf(requested.y, bounds.position.y - minimum.y, bounds.end.y - maximum.y)
	)


func _get_commander() -> ColonyUnit:
	if not _is_host_ready():
		return null
	var candidate: Variant = _host.get("commander")
	return candidate as ColonyUnit if is_instance_valid(candidate) else null


func _get_nest() -> ColonyNest:
	if not _is_host_ready():
		return null
	var candidate: Variant = _host.get("nest")
	return candidate as ColonyNest if is_instance_valid(candidate) else null


func _get_units() -> Array[ColonyUnit]:
	var result: Array[ColonyUnit] = []
	if not _is_host_ready():
		return result
	var units_variant: Variant = _host.get("units")
	if not units_variant is Array:
		return result
	for candidate in units_variant:
		if is_instance_valid(candidate) and candidate is ColonyUnit:
			result.append(candidate as ColonyUnit)
	return result


func _is_host_ready() -> bool:
	return is_instance_valid(_host) and not bool(_host.get("eliminated"))


func _random_float() -> float:
	return _rng.randf() if _rng != null else 0.5


func _random_range(minimum: float, maximum: float) -> float:
	return _rng.randf_range(minimum, maximum) if _rng != null else (minimum + maximum) * 0.5


func _random_index(size: int) -> int:
	if size <= 1:
		return 0
	return _rng.randi_range(0, size - 1) if _rng != null else 0
