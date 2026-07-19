class_name AcidProjectile
extends Node2D

var damage: float = 10.0
var speed: float = 420.0
var team_color := Color(0.35, 1.0, 0.12, 1.0)
var life_left: float = 2.5
var active: bool = false

var _resolver: Node = null
var _attacker_entity_id: int = 0
var _attacker_team_id: int = -1
var _target_entity_id: int = 0


func _ready() -> void:
	deactivate(false)


func configure(
	entity_resolver: Node,
	from_unit: Node,
	target_node: Node2D,
	hit_damage: float,
	travel_speed: float,
	color: Color
) -> void:
	if (
		not is_instance_valid(entity_resolver)
		or not is_instance_valid(from_unit)
		or not is_instance_valid(target_node)
		or not is_finite(hit_damage)
		or hit_damage <= 0.0
		or not is_finite(travel_speed)
		or travel_speed <= 0.0
	):
		deactivate(false)
		return
	_resolver = entity_resolver
	_attacker_entity_id = _get_entity_id(from_unit)
	_attacker_team_id = int(from_unit.get("team_id")) if is_instance_valid(from_unit) else -1
	_target_entity_id = _get_entity_id(target_node)
	if _attacker_entity_id <= 0 or _target_entity_id <= 0:
		deactivate(false)
		return
	damage = hit_damage
	speed = travel_speed
	team_color = color
	life_left = 2.5
	active = true
	z_index = WorldDepthPolicy.depth_z(global_position.y, WorldDepthPolicy.PROJECTILE_SUB_LAYER)
	visible = true
	set_physics_process(false)
	_request_redraw()


func _physics_process(delta: float) -> void:
	simulate_step(delta)


func simulate_step(delta: float) -> bool:
	if (
		not active
		or not is_finite(delta)
		or delta <= 0.0
		or not is_finite(damage)
		or damage <= 0.0
		or not is_finite(speed)
		or speed <= 0.0
		or not global_position.is_finite()
	):
		deactivate()
		return false
	life_left -= delta
	var target_node: Node2D = _resolve_target()
	if life_left <= 0.0 or target_node == null or not target_node.global_position.is_finite():
		deactivate()
		return false

	var to_target: Vector2 = target_node.global_position - global_position
	var distance: float = to_target.length()
	if distance <= 13.0:
		_apply_hit(target_node)
		deactivate()
		return false

	global_position += to_target.normalized() * minf(speed * delta, distance)
	rotation = to_target.angle()
	z_index = WorldDepthPolicy.depth_z(global_position.y, WorldDepthPolicy.PROJECTILE_SUB_LAYER)
	return true


func deactivate(_emit_release: bool = true) -> void:
	active = false
	visible = false
	set_physics_process(false)
	_resolver = null
	_attacker_entity_id = 0
	_attacker_team_id = -1
	_target_entity_id = 0
	life_left = 0.0


func _apply_hit(target_node: Node2D) -> void:
	if not is_instance_valid(target_node) or not target_node.has_method("take_damage"):
		return
	AudioSystem.play_sfx(
		&"acid_hit", global_position, {"emitter_id": _attacker_entity_id, "intensity": 0.82}
	)
	var attacker_node: Node = null
	if is_instance_valid(_resolver) and _resolver.has_method("resolve_network_entity"):
		attacker_node = _resolver.resolve_network_entity(_attacker_entity_id)
	target_node.take_damage(damage, attacker_node, _attacker_team_id)


func _resolve_target() -> Node2D:
	if (
		_target_entity_id <= 0
		or not is_instance_valid(_resolver)
		or not _resolver.has_method("resolve_network_entity")
	):
		return null
	var target_object: Node = _resolver.resolve_network_entity(_target_entity_id)
	if not is_instance_valid(target_object) or not target_object is Node2D:
		return null
	var target_node := target_object as Node2D
	if target_node.is_queued_for_deletion() or not target_node.is_inside_tree():
		return null
	return target_node


func _get_entity_id(candidate: Object) -> int:
	if not is_instance_valid(candidate):
		return 0
	var value: Variant = candidate.get("network_entity_id")
	return int(value) if value is int and int(value) > 0 else 0


func _request_redraw() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 7.0, Color(0.18, 0.25, 0.05, 0.45))
	draw_circle(Vector2.ZERO, 5.0, team_color)
	draw_circle(Vector2(-1.5, -1.5), 1.7, Color.WHITE)
