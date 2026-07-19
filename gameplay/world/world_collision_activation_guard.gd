class_name WorldCollisionActivationGuard
extends RefCounted

const UNIT_COLLISION_BIT: int = 1 << 0

var _physics_context: Node2D = null
var _interest_target_provider: Callable
var _safety_shape := CircleShape2D.new()


func configure(physics_context: Node2D, interest_target_provider: Callable) -> void:
	_physics_context = physics_context
	_interest_target_provider = interest_target_provider


func should_suppress(position: Vector2, radius: float) -> bool:
	if not position.is_finite() or not is_finite(radius) or radius <= 0.0:
		return false
	return is_near_any_interest(position, radius) or is_unit_near_position(position, radius)


func is_unit_near_position(position: Vector2, radius: float) -> bool:
	if (
		not is_instance_valid(_physics_context)
		or not _physics_context.is_inside_tree()
		or not position.is_finite()
		or not is_finite(radius)
		or radius <= 0.0
	):
		return false
	_safety_shape.radius = maxf(radius, 1.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _safety_shape
	query.transform = Transform2D(0.0, position)
	query.collision_mask = UNIT_COLLISION_BIT
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var world_2d: World2D = _physics_context.get_world_2d()
	return not world_2d.direct_space_state.intersect_shape(query, 1).is_empty()


func is_near_any_interest(position: Vector2, radius: float) -> bool:
	if not _interest_target_provider.is_valid():
		return false
	var targets_variant: Variant = _interest_target_provider.call()
	if not targets_variant is Array:
		return false
	var radius_squared: float = radius * radius
	for target_variant in targets_variant:
		var target := target_variant as Node2D
		if (
			is_instance_valid(target)
			and target.global_position.is_finite()
			and position.distance_squared_to(target.global_position) < radius_squared
		):
			return true
	return false
