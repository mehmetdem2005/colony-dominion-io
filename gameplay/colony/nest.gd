class_name ColonyNest
extends StaticBody2D

const PRODUCTION_RETRY_DELAY: float = 0.25

signal destroyed(nest: ColonyNest, attacker: Node)

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var controller: Node
var network_entity_id: int = 0
var team_id: int = -1
var team_color := Color.WHITE
var nest_level: int = 0
var max_health: float = 1200.0
var health: float = 1200.0
var production_queue: Array[StringName] = []
var production_progress: float = 0.0
var destroyed_state: bool = false
var _rng := RandomNumberGenerator.new()
var _queue_emit_left: float = 0.0


func _ready() -> void:
	add_to_group("damageables")
	add_to_group("nests")
	collision_layer = 0
	collision_mask = 0
	_request_redraw()


func configure(
	owner_controller: Node, id: int, color: Color, texture: Texture2D, entity_id: int = 0
) -> void:
	controller = owner_controller
	network_entity_id = entity_id
	team_id = id
	team_color = color
	z_index = WorldDepthPolicy.depth_z(
		global_position.y, WorldDepthPolicy.RESOURCE_STRUCTURE_SUB_LAYER
	)
	collision_layer = 0
	collision_mask = 0
	_rng.seed = maxi(1, network_entity_id * 65537 + team_id * 4099)
	sprite.texture = texture
	if texture != null:
		var longest: float = float(max(texture.get_width(), texture.get_height()))
		sprite.scale = Vector2.ONE * (205.0 / maxf(longest, 1.0))
	var circle := collision_shape.shape as CircleShape2D
	if circle != null:
		circle.radius = 74.0
	collision_shape.disabled = true
	apply_level(1)
	_request_redraw()


func refresh_world_depth() -> void:
	z_index = WorldDepthPolicy.depth_z(
		global_position.y, WorldDepthPolicy.RESOURCE_STRUCTURE_SUB_LAYER
	)


func apply_level(value: int) -> void:
	var previous_level: int = nest_level
	var old_max: float = max_health
	nest_level = clampi(value, 1, 4)
	max_health = 1200.0 + float(nest_level - 1) * 320.0
	if old_max <= 0.0:
		health = max_health
	else:
		health = minf(max_health, health + maxf(0.0, max_health - old_max) * 0.65)
	_request_redraw()
	reset_physics_interpolation()
	if (
		previous_level > 0
		and nest_level > previous_level
		and is_instance_valid(controller)
		and bool(controller.get("is_player"))
	):
		AudioSystem.play_ui(&"nest_upgrade")
		AudioSystem.request_haptic(70, 0.62)


func enqueue(unit_id: StringName) -> bool:
	if destroyed_state or production_queue.size() >= 5:
		return false
	production_queue.append(unit_id)
	if is_instance_valid(controller) and bool(controller.get("is_player")):
		AudioSystem.play_ui(&"production_start")
	if production_queue.size() == 1:
		production_progress = 0.0
	_emit_queue()
	return true


func _physics_process(delta: float) -> void:
	if destroyed_state or production_queue.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	if not is_instance_valid(controller):
		return
	_queue_emit_left = maxf(0.0, _queue_emit_left - delta)
	var definition := UnitCatalog.get_definition(production_queue[0])
	if definition == null:
		production_queue.pop_front()
		production_progress = 0.0
		_emit_queue()
		return
	var production_time: float = definition.spawn_time
	if controller.has_method("get_production_time_multiplier"):
		var multiplier: float = float(controller.get_production_time_multiplier())
		if is_finite(multiplier) and multiplier > 0.0:
			production_time *= multiplier
	production_time = maxf(production_time, 0.12)
	production_progress += delta
	if production_progress >= production_time:
		var finished_id: StringName = production_queue[0]
		production_queue.remove_at(0)
		var spawned_unit: Node = null
		if is_instance_valid(controller) and controller.has_method("spawn_unit"):
			var angle: float = _rng.randf_range(0.0, TAU)
			var spawn_position: Vector2 = global_position + Vector2.from_angle(angle) * 112.0
			spawned_unit = controller.spawn_unit(finished_id, spawn_position)
		if spawned_unit == null:
			production_queue.push_front(finished_id)
			production_progress = maxf(production_time - PRODUCTION_RETRY_DELAY, 0.0)
			_emit_queue()
			return
		production_progress = 0.0
		AudioSystem.play_sfx(
			&"production_complete",
			global_position,
			{"emitter_id": network_entity_id, "intensity": 0.78}
		)
		_emit_queue()
	elif _queue_emit_left <= 0.0:
		_queue_emit_left = 0.10
		_emit_queue()


func take_damage(amount: float, attacker: Node = null, _attacker_team_id: int = -1) -> void:
	if destroyed_state or not is_finite(amount) or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	(
		AudioSystem
		. play_sfx(
			&"nest_hurt",
			global_position,
			{
				"emitter_id": network_entity_id,
				"intensity": clampf(amount / 90.0, 0.45, 1.0),
			}
		)
	)
	_request_redraw()
	if health <= 0.0:
		destroyed_state = true
		production_queue.clear()
		production_progress = 0.0
		_emit_queue()
		AudioSystem.play_sfx(
			&"nest_destroyed", global_position, {"emitter_id": network_entity_id, "intensity": 1.0}
		)
		collision_layer = 0
		modulate = Color(0.36, 0.28, 0.22, 0.65)
		destroyed.emit(self, attacker)


func is_alive() -> bool:
	return not destroyed_state and health > 0.0


func get_health_ratio() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


func _emit_queue() -> void:
	if not is_instance_valid(controller) or not bool(controller.get("is_player")):
		return
	var ratio: float = 0.0
	if not production_queue.is_empty():
		var definition := UnitCatalog.get_definition(production_queue[0])
		if definition != null:
			var production_time: float = definition.spawn_time
			if (
				is_instance_valid(controller)
				and controller.has_method("get_production_time_multiplier")
			):
				var multiplier: float = float(controller.get_production_time_multiplier())
				if is_finite(multiplier) and multiplier > 0.0:
					production_time *= multiplier
			ratio = clampf(production_progress / maxf(production_time, 0.01), 0.0, 1.0)
	if controller.has_method("emit_production_queue_state"):
		controller.emit_production_queue_state(production_queue.duplicate(), ratio)


func _request_redraw() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		queue_redraw()


func _draw() -> void:
	var solid_team_color := Color(team_color.r, team_color.g, team_color.b, 0.98)
	draw_circle(Vector2.ZERO, 91.0, Color(0.015, 0.012, 0.008, 0.52))
	draw_circle(Vector2.ZERO, 87.0, Color(team_color.r, team_color.g, team_color.b, 0.20))
	draw_arc(Vector2.ZERO, 88.0, 0.0, TAU, 32, Color(0.01, 0.01, 0.01, 0.94), 8.0)
	draw_arc(Vector2.ZERO, 87.0, 0.0, TAU, 32, solid_team_color, 4.0)
	for index in nest_level:
		draw_circle(Vector2(-18.0 + float(index) * 12.0, -102.0), 4.0, solid_team_color)
	if health < max_health:
		var width: float = 118.0
		var y: float = -118.0
		draw_rect(Rect2(-width * 0.5, y, width, 9.0), Color(0.08, 0.06, 0.04, 0.85), true)
		draw_rect(
			Rect2(-width * 0.5 + 2.0, y + 2.0, (width - 4.0) * get_health_ratio(), 5.0),
			Color(0.3, 0.9, 0.24, 1.0),
			true
		)
