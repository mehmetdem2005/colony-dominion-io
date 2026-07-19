class_name ProjectileSystem
extends RefCounted

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")

var _host: Node = null
var _root: Node2D = null
var _is_headless: bool = false
var _pool_limit: int = 96
var _max_visual: int = 120
var _max_logical: int = 2048
var _clock := FixedStepClock.new(1.0 / 30.0, 5)
var _pool: Array[AcidProjectile] = []
var _active: Array[AcidProjectile] = []
var _logical: Array[Dictionary] = []
var _dropped_count: int = 0
var _created_count: int = 0
var _reused_count: int = 0


func configure(host: Node, root: Node2D, headless: bool, rules: MatchRules) -> void:
	_host = host
	_root = root
	_is_headless = headless
	if rules != null:
		_pool_limit = rules.projectile_pool_limit
		_max_visual = rules.max_visual_projectiles
		_max_logical = rules.max_logical_projectiles
		_clock.configure(rules.get_projectile_tick_interval(), rules.max_projectile_steps_per_frame)


func spawn(attacker: ColonyUnit, victim: Node2D, damage: float, speed: float, color: Color) -> void:
	if (
		not is_instance_valid(attacker)
		or not is_instance_valid(victim)
		or attacker.network_entity_id <= 0
		or int(victim.get("network_entity_id")) <= 0
		or not is_finite(damage)
		or damage <= 0.0
		or not is_finite(speed)
		or speed <= 0.0
	):
		return
	if (_is_headless or _active.size() >= _max_visual) and _logical.size() >= _max_logical:
		_dropped_count += 1
		return
	if not _is_headless:
		AudioSystem.play_sfx(
			&"acid_launch",
			attacker.global_position,
			{"emitter_id": attacker.network_entity_id, "intensity": 0.72}
		)
	if _is_headless or _active.size() >= _max_visual:
		(
			_logical
			. append(
				{
					"attacker_id": attacker.network_entity_id,
					"attacker_team": attacker.team_id,
					"target_id": int(victim.get("network_entity_id")),
					"damage": damage,
					"speed": speed,
					"position": attacker.global_position,
					"life": 2.5,
				}
			)
		)
		return
	var projectile: AcidProjectile = _acquire()
	if not is_instance_valid(projectile):
		_dropped_count += 1
		return
	projectile.global_position = attacker.global_position
	projectile.configure(_host, attacker, victim, damage, speed, color.lerp(Color("75ff24"), 0.65))
	projectile.reset_physics_interpolation()
	_active.append(projectile)


func advance(delta: float) -> void:
	var steps: int = _clock.advance(delta)
	for _step in steps:
		_tick_step(_clock.interval)


func shutdown() -> void:
	for projectile in _active:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_active.clear()
	for projectile in _pool:
		if is_instance_valid(projectile) and projectile.get_parent() == null:
			projectile.free()
	_pool.clear()
	_logical.clear()
	_host = null
	_root = null


func get_stats() -> Dictionary:
	return {
		"pooled": _pool.size(),
		"active": _active.size(),
		"logical": _logical.size(),
		"dropped": _dropped_count,
		"dropped_time": _clock.dropped_time,
		"created": _created_count,
		"reused": _reused_count,
	}


func _tick_step(delta: float) -> void:
	for index in range(_active.size() - 1, -1, -1):
		var projectile: AcidProjectile = _active[index]
		if not is_instance_valid(projectile) or not projectile.simulate_step(delta):
			_active.remove_at(index)
			_release(projectile)
	_tick_logical(delta)


func _tick_logical(delta: float) -> void:
	for index in range(_logical.size() - 1, -1, -1):
		var state: Dictionary = _logical[index]
		var life: float = float(state.get("life", 0.0)) - delta
		var target: Node = _resolve_entity(int(state.get("target_id", 0)))
		if life <= 0.0 or not is_instance_valid(target) or not target is Node2D:
			_logical.remove_at(index)
			continue
		var target_node := target as Node2D
		if not target_node.global_position.is_finite():
			_logical.remove_at(index)
			continue
		var projectile_position: Vector2 = state.get("position", Vector2.ZERO)
		if not projectile_position.is_finite():
			_logical.remove_at(index)
			continue
		var offset: Vector2 = target_node.global_position - projectile_position
		var distance: float = offset.length()
		if distance <= 13.0:
			if target_node.has_method("take_damage"):
				var attacker: Node = _resolve_entity(int(state.get("attacker_id", 0)))
				target_node.take_damage(
					float(state.get("damage", 0.0)), attacker, int(state.get("attacker_team", -1))
				)
			_logical.remove_at(index)
			continue
		var travel_speed: float = float(state.get("speed", 0.0))
		if not is_finite(travel_speed) or travel_speed <= 0.0:
			_logical.remove_at(index)
			continue
		projectile_position += offset.normalized() * minf(travel_speed * delta, distance)
		state["position"] = projectile_position
		state["life"] = life
		_logical[index] = state


func _acquire() -> AcidProjectile:
	while not _pool.is_empty():
		var pooled: AcidProjectile = _pool.pop_back()
		if not is_instance_valid(pooled) or pooled.is_queued_for_deletion():
			continue
		if pooled.get_parent() == null and is_instance_valid(_root):
			_root.add_child(pooled)
		_reused_count += 1
		return pooled
	if not is_instance_valid(_root):
		return null
	var projectile := PROJECTILE_SCENE.instantiate() as AcidProjectile
	_root.add_child(projectile)
	_created_count += 1
	return projectile


func _release(projectile: AcidProjectile) -> void:
	if not is_instance_valid(projectile):
		return
	projectile.deactivate(false)
	if _pool.size() < _pool_limit and not _pool.has(projectile):
		var parent: Node = projectile.get_parent()
		if is_instance_valid(parent):
			parent.remove_child(projectile)
		_pool.append(projectile)
		return
	projectile.queue_free()


func _resolve_entity(entity_id: int) -> Node:
	if (
		entity_id <= 0
		or not is_instance_valid(_host)
		or not _host.has_method("resolve_network_entity")
	):
		return null
	return _host.resolve_network_entity(entity_id)
