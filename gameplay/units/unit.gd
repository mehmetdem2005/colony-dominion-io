class_name ColonyUnit
extends CharacterBody2D

enum SimulationTier { FULL, REDUCED, DORMANT }

signal died(unit: ColonyUnit, killer: Node)

const UNIT_COLLISION_BIT: int = 1 << 0
const WORLD_OBSTACLE_BIT: int = 1 << 6
const LOCAL_AVOIDANCE_SCRIPT := preload("res://gameplay/units/local_obstacle_avoidance.gd")

const TARGET_REFRESH_MIN: float = 0.28
const TARGET_REFRESH_MAX: float = 0.48
const SEPARATION_REFRESH_MIN: float = 0.12
const SEPARATION_REFRESH_MAX: float = 0.20
const SWARM_VISUAL_SMOOTH_TIME: float = 1.0 / 20.0
const SWARM_REDUCED_VISUAL_SMOOTH_TIME: float = 0.12
const SWARM_VISUAL_MAX_OFFSET: float = 56.0
const SWARM_ROTATION_SMOOTH_SPEED: float = 18.0
const ACTIVATION_RECOVERY_DIRECTIONS: int = 12
const ACTIVATION_RECOVERY_RINGS: int = 5
const MAX_WORLD_SLIDE_ITERATIONS: int = 3

@onready var visual_root: ColonyUnitVisual = $VisualRoot
@onready var sprite: Sprite2D = $VisualRoot/Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
var name_label: Label = null

var definition: UnitDefinition
var controller
var network_entity_id: int = 0
var team_id: int = -1
var team_color := Color.WHITE
var health: float = 1.0
var target: Node2D = null
var resource_target: WorldResourceNode = null
var facing_direction := Vector2.UP
var is_dead: bool = false
var squad_id: int = 0
var simulation_tier: int = SimulationTier.FULL
var simulation_slot: int = 0

var _attack_left: float = 0.0
var _retarget_left: float = 0.0
var _gather_left: float = 0.0
var _hit_flash_left: float = 0.0
var _separation_left: float = 0.0
var _cached_separation := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _simulation_accumulator: float = 0.0
var _target_entity_id: int = 0
var _visual_smoothing_left: float = 0.0
var _visual_rotation_target: float = 0.0
var _z_sort_bucket: int = 0
var _presentation_enabled: bool = true
var _local_avoidance: UnitLocalObstacleAvoidance


func _ready() -> void:
	add_to_group("units")
	add_to_group("damageables")
	collision_layer = 0
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.25
	set_physics_process(false)


func configure(
	unit_definition: UnitDefinition,
	owner_controller,
	id: int,
	color: Color,
	commander_name: String = "",
	entity_id: int = 0
) -> void:
	if unit_definition == null or not is_instance_valid(owner_controller):
		push_error("ColonyUnit.configure rejected an invalid definition or controller")
		deactivate_for_pool()
		return
	if not is_in_group("units"):
		add_to_group("units")
	if not is_in_group("damageables"):
		add_to_group("damageables")
	definition = unit_definition
	controller = owner_controller
	network_entity_id = entity_id
	team_id = id
	team_color = color
	health = definition.max_health
	is_dead = false
	target = null
	resource_target = null
	_target_entity_id = 0
	squad_id = 0
	velocity = Vector2.ZERO
	facing_direction = Vector2.UP
	_attack_left = 0.0
	_gather_left = 0.0
	_hit_flash_left = 0.0
	_simulation_accumulator = 0.0
	_cached_separation = Vector2.ZERO
	_visual_smoothing_left = 0.0
	_visual_rotation_target = 0.0
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_update_z_index(true)
	visual_root.position = Vector2.ZERO
	sprite.modulate = Color.WHITE
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE
	_rng.seed = maxi(1, network_entity_id * 104729 + team_id * 8191)
	if _local_avoidance == null:
		_local_avoidance = LOCAL_AVOIDANCE_SCRIPT.new() as UnitLocalObstacleAvoidance
	_local_avoidance.configure(_rng.seed + 31337, global_position)
	_presentation_enabled = true
	if is_instance_valid(controller) and controller.has_method("is_presentation_enabled"):
		_presentation_enabled = bool(controller.is_presentation_enabled())
	sprite.texture = definition.texture if _presentation_enabled else null
	if _presentation_enabled and definition.texture != null:
		var longest: float = float(
			max(definition.texture.get_width(), definition.texture.get_height())
		)
		sprite.scale = Vector2.ONE * (definition.sprite_world_size / maxf(longest, 1.0))
	visual_root.configure(
		definition.body_radius,
		definition.role == &"commander",
		team_color,
		squad_id,
		_presentation_enabled
	)
	var circle := collision_shape.shape as CircleShape2D
	if circle != null:
		circle.radius = definition.body_radius
	_retarget_left = _rng.randf_range(0.04, TARGET_REFRESH_MAX)
	_separation_left = _rng.randf_range(0.02, SEPARATION_REFRESH_MAX)
	_apply_collision_profile()
	if _presentation_enabled:
		_configure_name_label(commander_name)
	set_physics_process(definition.role == &"commander")
	reset_physics_interpolation()
	_request_redraw()


func set_commander_display_name(value: String) -> void:
	if definition == null or definition.role != &"commander":
		return
	_configure_name_label(value.strip_edges().left(24))


func set_squad_id(value: int) -> void:
	var next_id: int = clampi(value, 0, 1)
	if squad_id == next_id:
		return
	squad_id = next_id
	visual_root.set_squad_id(squad_id)
	_request_redraw()


func _configure_name_label(commander_name: String) -> void:
	var is_commander: bool = definition != null and definition.role == &"commander"
	if not is_commander:
		if is_instance_valid(name_label):
			name_label.visible = false
		return
	_ensure_name_label()
	name_label.visible = true
	name_label.text = commander_name if not commander_name.is_empty() else "QueenAnt"
	name_label.add_theme_color_override("font_color", team_color.lightened(0.28))
	name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.015, 0.01, 0.98))
	name_label.add_theme_constant_override("outline_size", 5)


func _ensure_name_label() -> void:
	if is_instance_valid(name_label):
		return
	name_label = Label.new()
	name_label.name = "CommanderNameLabel"
	name_label.z_index = 30
	name_label.position = Vector2(-92.0, -82.0)
	name_label.size = Vector2(184.0, 32.0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	visual_root.add_child(name_label)


func _physics_process(delta: float) -> void:
	if definition == null or definition.role != &"commander":
		return
	_simulate_step(delta)


func simulate_swarm_step(delta: float) -> void:
	if definition == null or definition.role == &"commander":
		return
	var previous_position: Vector2 = global_position
	_simulate_step(delta)
	if _presentation_enabled and is_instance_valid(visual_root):
		var movement_delta: Vector2 = global_position - previous_position
		if movement_delta.length_squared() > 0.0001:
			visual_root.position = (visual_root.position - movement_delta).limit_length(
				SWARM_VISUAL_MAX_OFFSET
			)
			_visual_smoothing_left = (
				SWARM_REDUCED_VISUAL_SMOOTH_TIME
				if simulation_tier == SimulationTier.REDUCED
				else SWARM_VISUAL_SMOOTH_TIME
			)


func advance_visual_presentation(delta: float) -> void:
	if (
		is_dead
		or definition == null
		or not _presentation_enabled
		or not is_instance_valid(visual_root)
	):
		return
	if _visual_smoothing_left > 0.0:
		var blend: float = clampf(delta / maxf(_visual_smoothing_left, 0.0001), 0.0, 1.0)
		visual_root.position = visual_root.position.lerp(Vector2.ZERO, blend)
		_visual_smoothing_left = maxf(0.0, _visual_smoothing_left - delta)
	else:
		visual_root.position = Vector2.ZERO
	if definition.role != &"commander":
		var rotation_blend: float = clampf(delta * SWARM_ROTATION_SMOOTH_SPEED, 0.0, 1.0)
		sprite.rotation = lerp_angle(sprite.rotation, _visual_rotation_target, rotation_blend)


func _simulate_step(delta: float) -> void:
	if (
		is_dead
		or definition == null
		or not is_instance_valid(controller)
		or not is_finite(delta)
		or delta <= 0.0
	):
		return
	if simulation_tier == SimulationTier.DORMANT:
		return
	var simulation_delta: float = delta
	if simulation_tier == SimulationTier.REDUCED:
		_simulation_accumulator += delta
		if _simulation_accumulator < 0.12:
			return
		simulation_delta = _simulation_accumulator
		_simulation_accumulator = 0.0
	_attack_left = maxf(0.0, _attack_left - simulation_delta)
	_retarget_left = maxf(0.0, _retarget_left - simulation_delta)
	_gather_left = maxf(0.0, _gather_left - simulation_delta)
	_hit_flash_left = maxf(0.0, _hit_flash_left - simulation_delta)
	_separation_left = maxf(0.0, _separation_left - simulation_delta)
	if _hit_flash_left <= 0.0:
		sprite.modulate = Color.WHITE

	if definition.role == &"commander":
		_tick_commander(simulation_delta)
	elif definition.role == &"worker":
		_tick_worker(simulation_delta)
	else:
		_tick_combat_unit(simulation_delta)

	if velocity.length_squared() > 25.0:
		facing_direction = velocity.normalized()
		_visual_rotation_target = facing_direction.angle() + PI * 0.5
		if definition.role == &"commander":
			sprite.rotation = _visual_rotation_target
	_clamp_to_world()
	_update_z_index()


func set_simulation_tier(value: int) -> void:
	var new_tier: int = clampi(value, SimulationTier.FULL, SimulationTier.DORMANT)
	if simulation_tier == new_tier and (new_tier != SimulationTier.DORMANT or not visible):
		return
	simulation_tier = new_tier
	_simulation_accumulator = 0.0
	if is_dead:
		return
	if simulation_tier == SimulationTier.DORMANT:
		velocity = Vector2.ZERO
		visible = false
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
	else:
		_apply_collision_profile()
		recover_from_world_obstacles()
		visible = true
		set_physics_process(definition != null and definition.role == &"commander")
		reset_physics_interpolation()


func get_simulation_tier() -> int:
	return simulation_tier


func _tick_commander(delta: float) -> void:
	_refresh_target(definition.aggro_range)
	var input_vector := Vector2.ZERO
	if controller.is_human:
		input_vector = controller.get_movement_input()
	else:
		input_vector = controller.get_bot_move_direction(global_position)
	_apply_motion(input_vector * definition.move_speed, delta)
	if is_instance_valid(target) and _distance_to_target(target) <= definition.attack_range:
		_perform_attack(target)


func _tick_worker(delta: float) -> void:
	if controller.get_commander_distance(self) > controller.get_hard_recall_radius():
		_assign_target(null)
		resource_target = null
		_follow_formation(delta)
		return

	_refresh_target(definition.aggro_range)
	if is_instance_valid(target) and _distance_to_target(target) <= 78.0:
		_engage_target(delta)
		return

	if not controller.should_workers_gather():
		resource_target = null
		_follow_formation(delta)
		return

	var active_resource: WorldResourceNode = controller.get_active_resource_target()
	if not is_instance_valid(active_resource):
		resource_target = null
		_follow_formation(delta)
		return
	resource_target = active_resource
	if not controller.can_worker_reach_resource(self, resource_target):
		resource_target = null
		_follow_formation(delta)
		return

	var distance: float = global_position.distance_to(resource_target.global_position)
	if distance > 30.0:
		_move_toward_point(resource_target.global_position, delta, 1.12)
	else:
		_apply_motion(Vector2.ZERO, delta)
		if _gather_left <= 0.0:
			_gather_left = 0.5
			var gather_amount: int = controller.get_gather_amount(maxi(definition.gather_rate, 1))
			var gathered: int = resource_target.harvest(gather_amount)
			if gathered > 0:
				controller.add_resource(resource_target.resource_type, gathered)
				AudioSystem.play_resource(
					resource_target.resource_type,
					global_position,
					{"emitter_id": network_entity_id, "intensity": 0.65}
				)


func _tick_combat_unit(delta: float) -> void:
	if controller.get_commander_distance(self) > controller.get_hard_recall_radius():
		_assign_target(null)
		_follow_formation(delta)
		return
	_refresh_target(definition.aggro_range)
	if is_instance_valid(target):
		_engage_target(delta)
	else:
		_follow_formation(delta)


func _refresh_target(scan_range: float) -> void:
	if _retarget_left > 0.0:
		if (
			is_instance_valid(target)
			and _target_reference_is_current(target)
			and _is_enemy_alive(target)
			and controller.can_unit_pursue_target(self, target)
		):
			return
	_retarget_left = _rng.randf_range(TARGET_REFRESH_MIN, TARGET_REFRESH_MAX)
	var forced: Node2D = controller.get_forced_target()
	if (
		is_instance_valid(forced)
		and _is_enemy_alive(forced)
		and controller.can_unit_pursue_target(self, forced)
	):
		_assign_target(forced)
		return
	_assign_target(controller.find_enemy_for_unit(self, scan_range))


func _engage_target(delta: float) -> void:
	if (
		not is_instance_valid(target)
		or not _target_reference_is_current(target)
		or not _is_enemy_alive(target)
		or not controller.can_unit_pursue_target(self, target)
	):
		_assign_target(null)
		return
	var distance: float = _distance_to_target(target)
	if distance > definition.attack_range:
		_move_toward_point(target.global_position, delta, 1.04)
	else:
		_apply_motion(Vector2.ZERO, delta)
		_perform_attack(target)


func _perform_attack(victim: Node2D) -> void:
	if _attack_left > 0.0 or not is_instance_valid(victim):
		return
	_attack_left = definition.attack_interval
	if definition.ranged:
		controller.spawn_projectile(
			self, victim, definition.attack_damage, definition.projectile_speed
		)
	elif victim.has_method("take_damage"):
		victim.take_damage(definition.attack_damage, self)
		AudioSystem.play_sfx(
			&"unit_melee_attack",
			global_position,
			{"emitter_id": network_entity_id, "intensity": 0.68}
		)


func _follow_formation(delta: float) -> void:
	var formation_position: Vector2 = controller.get_formation_position(self)
	var distance: float = global_position.distance_to(formation_position)
	if distance > 12.0:
		var speed_multiplier: float = clampf(distance / 120.0, 0.72, 1.85)
		speed_multiplier = maxf(
			speed_multiplier, controller.get_minimum_follow_speed_multiplier(self)
		)
		if controller.get_commander_distance(self) > controller.get_hard_recall_radius():
			speed_multiplier = 2.55
		_move_toward_point(formation_position, delta, speed_multiplier)
	else:
		_apply_motion(Vector2.ZERO, delta)


func _move_toward_point(point: Vector2, delta: float, speed_multiplier: float) -> void:
	if not point.is_finite() or not is_finite(speed_multiplier):
		_apply_motion(Vector2.ZERO, delta)
		return
	var offset: Vector2 = point - global_position
	if offset.length_squared() < 1.0:
		_apply_motion(Vector2.ZERO, delta)
		return
	var desired: Vector2 = offset.normalized() * definition.move_speed * speed_multiplier
	_apply_motion(desired, delta)


func _apply_motion(desired_velocity: Vector2, delta: float) -> void:
	if not desired_velocity.is_finite() or not is_finite(delta) or delta <= 0.0:
		velocity = Vector2.ZERO
		return
	if (
		definition.role != &"commander"
		and controller.get_commander_distance(self) <= controller.get_hard_recall_radius()
	):
		if _separation_left <= 0.0:
			_separation_left = _rng.randf_range(SEPARATION_REFRESH_MIN, SEPARATION_REFRESH_MAX)
			_cached_separation = controller.get_separation_vector(
				self, definition.body_radius * 3.0 + 18.0
			)
		if _cached_separation.length_squared() > 0.0:
			desired_velocity += _cached_separation * definition.move_speed * 0.24

	if _local_avoidance != null and desired_velocity.length_squared() >= 4.0:
		desired_velocity = _local_avoidance.resolve_velocity(
			self, desired_velocity, definition.body_radius, delta, WORLD_OBSTACLE_BIT
		)
	if desired_velocity.length_squared() < 1.0 and velocity.length_squared() < 4.0:
		velocity = Vector2.ZERO
		return
	velocity = velocity.move_toward(desired_velocity, definition.acceleration * delta)
	if definition.role == &"commander" and simulation_tier == SimulationTier.FULL:
		move_and_slide()
		for collision_index in get_slide_collision_count():
			var slide_collision: KinematicCollision2D = get_slide_collision(collision_index)
			if slide_collision != null and _local_avoidance != null:
				_local_avoidance.notify_collision(slide_collision.get_normal(), desired_velocity)
		return
	_move_with_world_slide(velocity * delta, desired_velocity)


func apply_dormant_translation(offset: Vector2) -> void:
	if (
		is_dead
		or definition == null
		or not is_instance_valid(controller)
		or simulation_tier != SimulationTier.DORMANT
		or not offset.is_finite()
		or offset.length_squared() <= 0.0001
	):
		return
	global_position += offset
	facing_direction = offset.normalized()
	_visual_rotation_target = facing_direction.angle() + PI * 0.5
	if is_instance_valid(sprite):
		sprite.rotation = _visual_rotation_target
	_clamp_to_world()
	_update_z_index()


func take_damage(amount: float, attacker: Node = null, attacker_team_id: int = -1) -> void:
	if is_dead or definition == null or not is_finite(amount) or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	(
		AudioSystem
		. play_sfx(
			&"unit_hurt",
			global_position,
			{
				"emitter_id": network_entity_id,
				"intensity": clampf(amount / maxf(definition.max_health * 0.12, 1.0), 0.35, 1.0),
			}
		)
	)
	if (
		definition.role == &"commander"
		and is_instance_valid(controller)
		and bool(controller.get("is_player"))
	):
		AudioSystem.request_haptic(24, 0.48)
	_hit_flash_left = 0.09
	sprite.modulate = Color(1.0, 0.48, 0.42, 1.0)
	visual_root.set_health_ratio(get_health_ratio())
	_request_redraw()
	if health <= 0.0:
		_die(attacker, attacker_team_id)


func _die(killer: Node, killer_team_id: int = -1) -> void:
	if is_dead:
		return
	is_dead = true
	AudioSystem.play_sfx(
		&"unit_death", global_position, {"emitter_id": network_entity_id, "intensity": 0.85}
	)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	died.emit(self, killer)
	if is_instance_valid(controller) and controller.has_method("on_unit_died"):
		controller.on_unit_died(self, killer, killer_team_id)
	else:
		deactivate_for_pool()


func deactivate_for_pool() -> void:
	is_dead = true
	health = 0.0
	velocity = Vector2.ZERO
	target = null
	resource_target = null
	_target_entity_id = 0
	_visual_smoothing_left = 0.0
	_visual_rotation_target = 0.0
	_presentation_enabled = false
	if _local_avoidance != null:
		_local_avoidance.reset(global_position)
	controller = null
	definition = null
	network_entity_id = 0
	team_id = -1
	squad_id = 0
	visible = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	process_mode = Node.PROCESS_MODE_DISABLED
	remove_from_group("units")
	remove_from_group("damageables")
	if is_instance_valid(visual_root):
		visual_root.deactivate()
	if is_instance_valid(sprite):
		sprite.texture = null
		sprite.modulate = Color.WHITE
		sprite.position = Vector2.ZERO
		sprite.rotation = 0.0
	if is_instance_valid(name_label):
		name_label.visible = false


func _is_enemy_alive(candidate: Node) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate is ColonyUnit and not candidate.visible:
		return false
	var candidate_team: int = int(candidate.get("team_id"))
	if candidate_team == team_id:
		return false
	if candidate.has_method("is_alive"):
		return bool(candidate.is_alive())
	return not bool(candidate.get("is_dead"))


func is_alive() -> bool:
	return not is_dead and health > 0.0


func get_health_ratio() -> float:
	if definition == null:
		return 0.0
	return clampf(health / maxf(definition.max_health, 1.0), 0.0, 1.0)


func get_combat_radius() -> float:
	return definition.body_radius if definition != null else 0.0


func _distance_to_target(candidate: Node2D) -> float:
	if (
		not is_instance_valid(candidate)
		or not global_position.is_finite()
		or not candidate.global_position.is_finite()
	):
		return INF
	var radius: float = 18.0
	if candidate.has_method("get_combat_radius"):
		radius = float(candidate.get_combat_radius())
	elif candidate is ColonyNest:
		radius = 68.0
	return maxf(0.0, global_position.distance_to(candidate.global_position) - radius)


func _clamp_to_world() -> void:
	if not is_instance_valid(controller) or not global_position.is_finite():
		velocity = Vector2.ZERO
		return
	var bounds: Rect2 = controller.get_world_bounds()
	if bounds.size.x <= 60.0 or bounds.size.y <= 60.0:
		velocity = Vector2.ZERO
		return
	global_position.x = clampf(global_position.x, bounds.position.x + 30.0, bounds.end.x - 30.0)
	global_position.y = clampf(global_position.y, bounds.position.y + 30.0, bounds.end.y - 30.0)


func _update_z_index(force_bucket_refresh: bool = false) -> void:
	# Stable entity sublayers prevent equal-depth units from swapping draw order.
	# Hysteresis keeps small separation corrections from bouncing across a bucket
	# boundary while preserving deterministic top-down depth ordering.
	if force_bucket_refresh:
		_z_sort_bucket = WorldDepthPolicy.bucket_for_world_y(global_position.y)
	else:
		var lower_boundary: float = (
			float(_z_sort_bucket) * WorldDepthPolicy.WORLD_STEP - WorldDepthPolicy.HYSTERESIS
		)
		var upper_boundary: float = (
			float(_z_sort_bucket + 1) * WorldDepthPolicy.WORLD_STEP + WorldDepthPolicy.HYSTERESIS
		)
		if global_position.y < lower_boundary or global_position.y >= upper_boundary:
			_z_sort_bucket = WorldDepthPolicy.bucket_for_world_y(global_position.y)
	var stable_sub_layer: int = WorldDepthPolicy.unit_sub_layer(network_entity_id)
	z_index = WorldDepthPolicy.depth_z_from_bucket(_z_sort_bucket, stable_sub_layer)


func _apply_collision_profile() -> void:
	if team_id < 0:
		collision_layer = 0
		collision_mask = WORLD_OBSTACLE_BIT
		return
	collision_layer = UNIT_COLLISION_BIT
	collision_mask = WORLD_OBSTACLE_BIT


func clear_combat_target() -> void:
	_assign_target(null)


func recover_from_world_obstacles(max_radius: float = 260.0) -> bool:
	if (
		is_dead
		or definition == null
		or not is_inside_tree()
		or not is_instance_valid(collision_shape)
		or collision_shape.shape == null
	):
		return true
	var shape: Shape2D = collision_shape.shape
	if _is_world_position_free(global_position, shape):
		return true
	var base_radius: float = maxf(definition.body_radius * 2.0 + 12.0, 42.0)
	var angle_offset: float = (
		float(posmod(network_entity_id, ACTIVATION_RECOVERY_DIRECTIONS))
		* TAU
		/ float(ACTIVATION_RECOVERY_DIRECTIONS)
	)
	for ring in range(1, ACTIVATION_RECOVERY_RINGS + 1):
		var distance: float = minf(base_radius * float(ring), max_radius)
		for direction_index in ACTIVATION_RECOVERY_DIRECTIONS:
			var angle: float = (
				angle_offset + TAU * float(direction_index) / float(ACTIVATION_RECOVERY_DIRECTIONS)
			)
			var candidate: Vector2 = _clamp_candidate_to_world(
				global_position + Vector2.from_angle(angle) * distance
			)
			if _is_world_position_free(candidate, shape):
				global_position = candidate
				velocity = Vector2.ZERO
				if _local_avoidance != null:
					_local_avoidance.reset(global_position)
				reset_physics_interpolation()
				return true
	return false


func _move_with_world_slide(motion: Vector2, desired_velocity: Vector2) -> void:
	var remaining: Vector2 = motion
	for _iteration in MAX_WORLD_SLIDE_ITERATIONS:
		if remaining.length_squared() <= 0.25:
			break
		var collision: KinematicCollision2D = move_and_collide(remaining)
		if collision == null:
			break
		var collision_normal: Vector2 = collision.get_normal()
		if _local_avoidance != null:
			_local_avoidance.notify_collision(collision_normal, desired_velocity)
		velocity = velocity.slide(collision_normal)
		remaining = collision.get_remainder().slide(collision_normal)


func _is_world_position_free(candidate: Vector2, shape: Shape2D) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, candidate)
	query.collision_mask = WORLD_OBSTACLE_BIT
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _clamp_candidate_to_world(candidate: Vector2) -> Vector2:
	if not is_instance_valid(controller):
		return candidate
	var bounds: Rect2 = controller.get_world_bounds().grow(-30.0)
	return Vector2(
		clampf(candidate.x, bounds.position.x, bounds.end.x),
		clampf(candidate.y, bounds.position.y, bounds.end.y)
	)


func _assign_target(candidate: Node2D) -> void:
	target = candidate
	_target_entity_id = _get_entity_id(candidate)


func _target_reference_is_current(candidate: Node2D) -> bool:
	return (
		is_instance_valid(candidate)
		and _target_entity_id > 0
		and _get_entity_id(candidate) == _target_entity_id
	)


func _get_entity_id(candidate: Object) -> int:
	if not is_instance_valid(candidate):
		return 0
	var value: Variant = candidate.get("network_entity_id")
	return int(value) if value is int and int(value) > 0 else 0


func _request_redraw() -> void:
	if is_instance_valid(visual_root):
		visual_root.set_health_ratio(get_health_ratio())
