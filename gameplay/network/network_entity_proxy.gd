class_name NetworkEntityProxy
extends CharacterBody2D

const TEAM_COLORS: Array[Color] = [
	Color("2a9cff"),
	Color("ff3d49"),
	Color("35e06f"),
	Color("c252ff"),
	Color("ff9f1a"),
	Color("18d9e8"),
]
const RECONCILIATION_SPEED: float = 12.0
const REMOTE_INTERPOLATION_SPEED: float = 14.0
const SNAPSHOT_BUFFER_LIMIT: int = 10

var entity_id: int = 0
var team_id: int = -1
var kind: StringName = &"worker"
var health_ratio: float = 1.0
var is_local_commander: bool = false
var authoritative_position := Vector2.ZERO
var _has_position: bool = false
var _prediction_input := Vector2.ZERO
var _move_speed: float = 280.0
var _last_snapshot_tick: int = -1
var _snapshot_buffer: Array[Dictionary] = []


func configure(id_value: int, team_value: int, kind_value: StringName) -> void:
	entity_id = id_value
	team_id = team_value
	kind = kind_value
	_move_speed = _resolve_move_speed()
	queue_redraw()


func apply_snapshot(data: Dictionary, server_tick: int) -> void:
	if server_tick < _last_snapshot_tick:
		return
	_last_snapshot_tick = server_tick
	team_id = int(data.get("team", team_id))
	kind = StringName(data.get("kind", kind))
	health_ratio = clampf(float(data.get("health", 255)) / 255.0, 0.0, 1.0)
	var position_variant: Variant = data.get("position", Vector2i.ZERO)
	var decoded := Vector2.ZERO
	if position_variant is Vector2i:
		decoded = Vector2(position_variant as Vector2i) * 0.5
	elif position_variant is Vector2:
		decoded = position_variant as Vector2
	if not decoded.is_finite():
		return
	authoritative_position = decoded
	(
		_snapshot_buffer
		. append(
			{
				"received_msec": Time.get_ticks_msec(),
				"position": decoded,
				"tick": server_tick,
			}
		)
	)
	while _snapshot_buffer.size() > SNAPSHOT_BUFFER_LIMIT:
		_snapshot_buffer.pop_front()
	if not _has_position:
		global_position = decoded
		_has_position = true
		reset_physics_interpolation()
	_move_speed = _resolve_move_speed()
	queue_redraw()


func set_local_commander(value: bool) -> void:
	is_local_commander = value
	queue_redraw()


func set_prediction_input(value: Vector2) -> void:
	_prediction_input = value.limit_length(1.0) if value.is_finite() else Vector2.ZERO


func _physics_process(delta: float) -> void:
	if not _has_position or not is_finite(delta) or delta <= 0.0:
		return
	if is_local_commander:
		velocity = _prediction_input * _move_speed
		global_position += velocity * delta
		var correction_weight: float = 1.0 - exp(-RECONCILIATION_SPEED * delta)
		global_position = global_position.lerp(authoritative_position, correction_weight)
	else:
		var render_target: Vector2 = _sample_remote_position()
		velocity = (render_target - global_position) / maxf(delta, 0.001)
		var interpolation_weight: float = 1.0 - exp(-REMOTE_INTERPOLATION_SPEED * delta)
		global_position = global_position.lerp(render_target, interpolation_weight)
	z_index = WorldDepthPolicy.depth_z(
		global_position.y,
		(
			WorldDepthPolicy.RESOURCE_STRUCTURE_SUB_LAYER
			if kind == &"nest"
			else WorldDepthPolicy.unit_sub_layer(entity_id)
		)
	)
	if kind != &"nest" and velocity.length_squared() > 4.0:
		rotation = velocity.angle()
	queue_redraw()


func _sample_remote_position() -> Vector2:
	if _snapshot_buffer.is_empty():
		return authoritative_position
	var target_msec: int = Time.get_ticks_msec() - NetworkProtocol.INTERPOLATION_DELAY_MSEC
	while (
		_snapshot_buffer.size() >= 2
		and int(_snapshot_buffer[1].get("received_msec", 0)) <= target_msec
	):
		_snapshot_buffer.pop_front()
	if _snapshot_buffer.size() < 2:
		return _snapshot_buffer[0].get("position", authoritative_position) as Vector2
	var older: Dictionary = _snapshot_buffer[0]
	var newer: Dictionary = _snapshot_buffer[1]
	var older_time: int = int(older.get("received_msec", target_msec))
	var newer_time: int = int(newer.get("received_msec", older_time + 1))
	var span: int = maxi(newer_time - older_time, 1)
	var weight: float = clampf(float(target_msec - older_time) / float(span), 0.0, 1.0)
	var older_position: Vector2 = older.get("position", authoritative_position) as Vector2
	var newer_position: Vector2 = newer.get("position", authoritative_position) as Vector2
	return older_position.lerp(newer_position, weight)


func _draw() -> void:
	var color: Color = TEAM_COLORS[posmod(team_id, TEAM_COLORS.size())]
	if kind == &"nest":
		draw_circle(Vector2.ZERO, 48.0, Color(0.15, 0.09, 0.035, 0.98))
		draw_circle(Vector2.ZERO, 38.0, color.darkened(0.28))
		draw_arc(Vector2.ZERO, 45.0, 0.0, TAU, 28, color, 5.0, true)
		_draw_health_bar(70.0)
		return
	var body_length: float = 22.0
	var body_radius: float = 8.0
	match kind:
		&"commander":
			body_length = 34.0
			body_radius = 12.0
		&"soldier", &"guard":
			body_length = 27.0
			body_radius = 10.0
		&"acid_ant":
			body_length = 25.0
			body_radius = 9.0
		&"scout":
			body_length = 20.0
			body_radius = 7.0
	draw_circle(Vector2(-body_length * 0.35, 0.0), body_radius * 0.8, color.darkened(0.18))
	draw_circle(Vector2.ZERO, body_radius, color)
	draw_circle(Vector2(body_length * 0.38, 0.0), body_radius * 0.72, color.lightened(0.16))
	for side in [-1.0, 1.0]:
		for x_value in [-7.0, 0.0, 7.0]:
			draw_line(
				Vector2(x_value, side * 3.0),
				Vector2(x_value - 5.0, side * (body_radius + 7.0)),
				Color(0.10, 0.07, 0.04, 0.95),
				2.0,
				true
			)
	if is_local_commander:
		draw_arc(Vector2.ZERO, body_length, 0.0, TAU, 28, Color(0.80, 0.95, 1.0, 0.92), 3.0, true)
	if health_ratio < 0.999 or kind == &"commander":
		_draw_health_bar(body_length + 12.0)


func _draw_health_bar(width: float) -> void:
	var top: float = -26.0 if kind != &"nest" else -62.0
	var size := Vector2(width, 6.0)
	var start := Vector2(-width * 0.5, top)
	draw_rect(Rect2(start, size), Color(0.09, 0.06, 0.04, 0.94), true)
	draw_rect(
		Rect2(start + Vector2.ONE, Vector2((width - 2.0) * health_ratio, 4.0)),
		Color(0.31, 0.92, 0.38, 1.0) if health_ratio > 0.35 else Color(1.0, 0.28, 0.18, 1.0),
		true
	)


func _resolve_move_speed() -> float:
	var definition: UnitDefinition = UnitCatalog.get_definition(kind)
	return definition.move_speed if definition != null else 280.0
