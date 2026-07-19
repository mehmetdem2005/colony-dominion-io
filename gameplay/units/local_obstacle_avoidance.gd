class_name UnitLocalObstacleAvoidance
extends RefCounted

const MIN_REFRESH_INTERVAL: float = 0.10
const MAX_REFRESH_INTERVAL: float = 0.16
const MIN_LOOK_AHEAD: float = 58.0
const MAX_LOOK_AHEAD: float = 150.0
const STUCK_TRIGGER_TIME: float = 0.34
const SIDE_HOLD_TIME: float = 0.72

var _rng := RandomNumberGenerator.new()
var _refresh_left: float = 0.0
var _side_hold_left: float = 0.0
var _stuck_time: float = 0.0
var _avoidance_side: float = 1.0
var _cached_direction := Vector2.ZERO
var _last_position := Vector2.INF


func configure(seed_value: int, start_position: Vector2) -> void:
	_rng.seed = maxi(seed_value, 1)
	_avoidance_side = -1.0 if (_rng.randi() & 1) == 0 else 1.0
	reset(start_position)


func reset(start_position: Vector2) -> void:
	_refresh_left = 0.0
	_side_hold_left = 0.0
	_stuck_time = 0.0
	_cached_direction = Vector2.ZERO
	_last_position = start_position


func resolve_velocity(
	body: CharacterBody2D,
	desired_velocity: Vector2,
	body_radius: float,
	delta: float,
	collision_mask: int
) -> Vector2:
	if not is_instance_valid(body) or desired_velocity.length_squared() < 4.0:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.0)
		_cached_direction = Vector2.ZERO
		_last_position = body.global_position if is_instance_valid(body) else Vector2.INF
		return desired_velocity

	_update_stuck_state(body.global_position, desired_velocity.length(), delta)
	_refresh_left -= delta
	_side_hold_left = maxf(0.0, _side_hold_left - delta)
	if _refresh_left <= 0.0:
		_refresh_left = _rng.randf_range(MIN_REFRESH_INTERVAL, MAX_REFRESH_INTERVAL)
		_cached_direction = _sample_avoidance_direction(
			body, desired_velocity, body_radius, collision_mask
		)

	if _cached_direction.length_squared() < 0.01:
		return desired_velocity
	var desired_speed: float = desired_velocity.length()
	var steering_strength: float = 0.82
	if _stuck_time >= STUCK_TRIGGER_TIME:
		steering_strength = 1.0
	var blended_direction: Vector2 = (
		desired_velocity.normalized().lerp(_cached_direction, steering_strength).normalized()
	)
	return blended_direction * desired_speed


func notify_collision(collision_normal: Vector2, desired_velocity: Vector2) -> void:
	if collision_normal.length_squared() < 0.01 or desired_velocity.length_squared() < 0.01:
		return
	var direction: Vector2 = desired_velocity.normalized()
	var right := Vector2(-direction.y, direction.x)
	var tangent_a := Vector2(-collision_normal.y, collision_normal.x).normalized()
	var tangent_b := -tangent_a
	var a_score: float = tangent_a.dot(right) * _avoidance_side
	var b_score: float = tangent_b.dot(right) * _avoidance_side
	_cached_direction = tangent_a if a_score >= b_score else tangent_b
	_side_hold_left = SIDE_HOLD_TIME
	_refresh_left = 0.0
	_stuck_time = maxf(_stuck_time, STUCK_TRIGGER_TIME)


func _update_stuck_state(position: Vector2, desired_speed: float, delta: float) -> void:
	if _last_position == Vector2.INF:
		_last_position = position
		return
	var moved_distance: float = position.distance_to(_last_position)
	var minimum_expected: float = maxf(0.65, desired_speed * delta * 0.075)
	if moved_distance < minimum_expected:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.4)
	_last_position = position


func _sample_avoidance_direction(
	body: CharacterBody2D, desired_velocity: Vector2, body_radius: float, collision_mask: int
) -> Vector2:
	var direction: Vector2 = desired_velocity.normalized()
	var right := Vector2(-direction.y, direction.x)
	var look_ahead: float = clampf(
		body_radius * 3.1 + desired_velocity.length() * 0.24, MIN_LOOK_AHEAD, MAX_LOOK_AHEAD
	)
	var lateral_offset: float = maxf(body_radius * 0.72, 8.0)
	var origin: Vector2 = body.global_position
	var center_hit: Dictionary = _cast_ray(
		body, origin, origin + direction * look_ahead, collision_mask
	)
	var left_hit: Dictionary = _cast_ray(
		body,
		origin - right * lateral_offset,
		origin - right * lateral_offset + direction * look_ahead * 0.86,
		collision_mask
	)
	var right_hit: Dictionary = _cast_ray(
		body,
		origin + right * lateral_offset,
		origin + right * lateral_offset + direction * look_ahead * 0.86,
		collision_mask
	)

	var has_center: bool = not center_hit.is_empty()
	var has_left: bool = not left_hit.is_empty()
	var has_right: bool = not right_hit.is_empty()
	if not has_center and not has_left and not has_right and _stuck_time < STUCK_TRIGGER_TIME:
		return Vector2.ZERO

	if _side_hold_left <= 0.0:
		if has_left and not has_right:
			_avoidance_side = 1.0
		elif has_right and not has_left:
			_avoidance_side = -1.0
		elif _stuck_time >= STUCK_TRIGGER_TIME:
			_avoidance_side = -_avoidance_side
		_side_hold_left = SIDE_HOLD_TIME

	var obstacle_normal := Vector2.ZERO
	if has_center:
		obstacle_normal = center_hit.get("normal", Vector2.ZERO)
	elif has_left:
		obstacle_normal = left_hit.get("normal", Vector2.ZERO)
	elif has_right:
		obstacle_normal = right_hit.get("normal", Vector2.ZERO)
	if obstacle_normal.length_squared() < 0.01:
		obstacle_normal = -direction
	else:
		obstacle_normal = obstacle_normal.normalized()

	var preferred_tangent: Vector2 = right * _avoidance_side
	var tangent_a := Vector2(-obstacle_normal.y, obstacle_normal.x).normalized()
	var tangent_b := -tangent_a
	var tangent: Vector2 = (
		tangent_a
		if tangent_a.dot(preferred_tangent) >= tangent_b.dot(preferred_tangent)
		else tangent_b
	)
	var forward_weight: float = 0.18 if has_center else 0.48
	var escape_weight: float = 0.58 if _stuck_time >= STUCK_TRIGGER_TIME else 0.36
	return (
		(direction * forward_weight + tangent * 1.0 + obstacle_normal * escape_weight).normalized()
	)


func _cast_ray(
	body: CharacterBody2D, from: Vector2, to: Vector2, collision_mask: int
) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, [body.get_rid()])
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true
	return body.get_world_2d().direct_space_state.intersect_ray(query)
