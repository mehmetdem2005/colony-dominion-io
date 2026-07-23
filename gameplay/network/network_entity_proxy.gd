class_name NetworkEntityProxy
extends CharacterBody2D

const SNAPSHOT_BUFFER_LIMIT: int = 8
# Milliseconds between authoritative snapshots (server tick spacing). Remote
# interpolation runs on this even clock rather than on jittery packet-arrival
# times, which is what previously made the units shimmer/"titriyor".
const TICK_MS: float = 1000.0 / NetworkProtocol.SNAPSHOT_HZ
const RENDER_CLOCK_MAX_LAG_MS: float = 250.0
const LOCAL_SOFT_CORRECTION_SPEED: float = 7.0
const LOCAL_IDLE_CORRECTION_SPEED: float = 12.0
const LOCAL_HARD_SNAP_DISTANCE: float = 320.0

var entity_id: int = 0
var team_id: int = -1
var kind: StringName = &"worker"
var health_ratio: float = 1.0
var is_local_commander: bool = false
var authoritative_position := Vector2.ZERO
var facing_direction := Vector2.UP
var nest_level: int = 1

var _definition: UnitDefinition = null
var _has_position: bool = false
var _prediction_input := Vector2.ZERO
var _move_speed: float = 280.0
var _last_snapshot_tick: int = -1
var _snapshot_buffer: Array[Dictionary] = []
var _newest_server_ms: float = 0.0
var _render_ms: float = -1.0
var _last_visual_team_id: int = -2
var _last_visual_kind: StringName = &""
var _display_name: String = ""
var _name_label: Label = null

@onready var visual_root: ColonyUnitVisual = get_node_or_null("VisualRoot") as ColonyUnitVisual
@onready var sprite: Sprite2D = get_node_or_null("VisualRoot/Sprite2D") as Sprite2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_ensure_visual_nodes()
	_refresh_visual_if_needed(true)


func configure(id_value: int, team_value: int, kind_value: StringName) -> void:
	entity_id = id_value
	team_id = team_value
	kind = kind_value
	_definition = _get_unit_definition(kind)
	_move_speed = _resolve_move_speed()
	_ensure_visual_nodes()
	_refresh_visual_if_needed(true)


func apply_snapshot(data: Dictionary, server_tick: int) -> void:
	if server_tick < _last_snapshot_tick:
		return
	_last_snapshot_tick = server_tick

	var next_team_id: int = int(data.get("team", team_id))
	var next_kind := StringName(data.get("kind", kind))
	var visual_changed: bool = next_team_id != team_id or next_kind != kind
	team_id = next_team_id
	kind = next_kind
	if visual_changed:
		_definition = _get_unit_definition(kind)
		_move_speed = _resolve_move_speed()
		_refresh_visual_if_needed(true)

	var next_health_ratio: float = clampf(float(data.get("health", 255)) / 255.0, 0.0, 1.0)
	if not is_equal_approx(next_health_ratio, health_ratio):
		health_ratio = next_health_ratio
		if kind == &"nest":
			queue_redraw()
		elif is_instance_valid(visual_root):
			visual_root.set_health_ratio(health_ratio)
	var next_nest_level: int = clampi(int(data.get("level", nest_level)), 1, 4)
	if next_nest_level != nest_level:
		nest_level = next_nest_level
		if kind == &"nest":
			queue_redraw()

	var next_display_name: String = String(data.get("name", _display_name)).strip_edges().left(24)
	if next_display_name != _display_name:
		_display_name = next_display_name
		_refresh_name_label()

	var position_variant: Variant = data.get("position", Vector2i.ZERO)
	var decoded := Vector2.ZERO
	if position_variant is Vector2i:
		decoded = Vector2(position_variant as Vector2i) * 0.5
	elif position_variant is Vector2:
		decoded = position_variant as Vector2
	if not decoded.is_finite():
		return

	authoritative_position = decoded
	if kind == &"nest":
		z_index = WorldDepthPolicy.depth_z(decoded.y, WorldDepthPolicy.RESOURCE_STRUCTURE_SUB_LAYER)
	if not _has_position:
		global_position = decoded
		_has_position = true
		reset_physics_interpolation()
		return
	if is_local_commander:
		_snapshot_buffer.clear()
		return
	# Timestamp each sample by the SERVER tick (evenly spaced), not local arrival
	# time, so interpolation speed is constant regardless of network jitter.
	var server_ms: float = float(server_tick) * TICK_MS
	_newest_server_ms = maxf(_newest_server_ms, server_ms)
	_snapshot_buffer.append({"server_ms": server_ms, "position": decoded})
	while _snapshot_buffer.size() > SNAPSHOT_BUFFER_LIMIT:
		_snapshot_buffer.pop_front()


func set_local_commander(value: bool) -> void:
	if is_local_commander == value:
		return
	is_local_commander = value
	_snapshot_buffer.clear()
	_render_ms = -1.0
	_newest_server_ms = 0.0
	queue_redraw()


func set_prediction_input(value: Vector2) -> void:
	_prediction_input = value.limit_length(1.0) if value.is_finite() else Vector2.ZERO


func _physics_process(delta: float) -> void:
	if not _has_position or not is_finite(delta) or delta <= 0.0:
		return
	if kind == &"nest":
		global_position = authoritative_position
		velocity = Vector2.ZERO
		return
	if is_local_commander:
		_advance_local_prediction(delta)
	else:
		_advance_remote_interpolation(delta)
	_refresh_world_presentation()


func _advance_local_prediction(delta: float) -> void:
	velocity = _prediction_input * _move_speed
	global_position += velocity * delta
	var one_way_seconds: float = 0.0
	var ping_msec: int = _get_network_metric("ping_ms")
	if ping_msec >= 0:
		one_way_seconds = clampf(float(ping_msec) * 0.0005, 0.0, 0.12)
	var server_estimate: Vector2 = (
		authoritative_position + _prediction_input * _move_speed * one_way_seconds
	)
	var error: Vector2 = server_estimate - global_position
	if error.length_squared() >= LOCAL_HARD_SNAP_DISTANCE * LOCAL_HARD_SNAP_DISTANCE:
		global_position = server_estimate
		reset_physics_interpolation()
		return
	var correction_speed: float = (
		LOCAL_IDLE_CORRECTION_SPEED
		if _prediction_input.length_squared() < 0.01
		else LOCAL_SOFT_CORRECTION_SPEED
	)
	var correction_weight: float = 1.0 - exp(-correction_speed * delta)
	global_position += error * correction_weight


func _advance_remote_interpolation(delta: float) -> void:
	var previous: Vector2 = global_position
	var render_target: Vector2 = _sample_remote_position(delta)
	# The render clock already produces smooth, evenly-paced positions, so we set
	# the position directly — no second smoothing pass that would add latency or
	# re-introduce chase jitter.
	global_position = render_target
	velocity = (render_target - previous) / maxf(delta, 0.001)


func _sample_remote_position(delta: float) -> Vector2:
	if _snapshot_buffer.is_empty():
		return authoritative_position
	var newest: Dictionary = _snapshot_buffer[_snapshot_buffer.size() - 1]
	if _snapshot_buffer.size() == 1:
		return newest.get("position", authoritative_position) as Vector2

	# Render slightly in the past so there is always a "future" sample to
	# interpolate toward. Advance a local clock by real time and keep it inside
	# the buffered window: never ahead of the newest sample (no extrapolation),
	# and re-synced if it drifts too far behind after a stall.
	var delay_ms: float = float(
		NetworkProtocol.get_interpolation_delay_msec(_get_network_metric("jitter_ms"))
	)
	var target_ms: float = _newest_server_ms - delay_ms
	if _render_ms < 0.0:
		_render_ms = target_ms
	else:
		_render_ms += delta * 1000.0
		_render_ms = clampf(_render_ms, target_ms - RENDER_CLOCK_MAX_LAG_MS, _newest_server_ms)

	var oldest: Dictionary = _snapshot_buffer[0]
	if _render_ms <= float(oldest.get("server_ms", 0.0)):
		return oldest.get("position", authoritative_position) as Vector2
	if _render_ms >= float(newest.get("server_ms", 0.0)):
		return newest.get("position", authoritative_position) as Vector2
	for index in range(_snapshot_buffer.size() - 1):
		var older: Dictionary = _snapshot_buffer[index]
		var newer: Dictionary = _snapshot_buffer[index + 1]
		var older_ms: float = float(older.get("server_ms", 0.0))
		var newer_ms: float = float(newer.get("server_ms", older_ms + 1.0))
		if _render_ms >= older_ms and _render_ms <= newer_ms:
			var older_position: Vector2 = older.get("position", authoritative_position) as Vector2
			var newer_position: Vector2 = newer.get("position", authoritative_position) as Vector2
			var span: float = maxf(newer_ms - older_ms, 1.0)
			return older_position.lerp(
				newer_position, clampf((_render_ms - older_ms) / span, 0.0, 1.0)
			)
	return newest.get("position", authoritative_position) as Vector2


func _refresh_world_presentation() -> void:
	z_index = WorldDepthPolicy.depth_z(
		global_position.y, WorldDepthPolicy.unit_sub_layer(entity_id)
	)
	if velocity.length_squared() <= 4.0:
		return
	facing_direction = velocity.normalized()
	if is_instance_valid(sprite):
		sprite.rotation = facing_direction.angle() + PI * 0.5


func _refresh_visual_if_needed(force: bool = false) -> void:
	if not force and _last_visual_team_id == team_id and _last_visual_kind == kind:
		return
	_last_visual_team_id = team_id
	_last_visual_kind = kind
	_ensure_visual_nodes()
	if not is_instance_valid(visual_root) or not is_instance_valid(sprite):
		return

	var color: Color = ColonyVisualCatalog.team_color(team_id)
	if kind == &"nest":
		# Keep the shared visual root visible so its Sprite2D is rendered. A zero
		# body radius suppresses the unit ring while preserving the nest asset.
		visual_root.configure(0.0, false, color, 0, true)
		ColonyVisualCatalog.configure_nest_sprite(sprite, team_id)
		z_index = WorldDepthPolicy.depth_z(
			global_position.y, WorldDepthPolicy.RESOURCE_STRUCTURE_SUB_LAYER
		)
	else:
		_definition = _get_unit_definition(kind)
		ColonyVisualCatalog.configure_unit_sprite(sprite, _definition)
		var body_radius: float = _definition.body_radius if _definition != null else 12.0
		visual_root.configure(body_radius, kind == &"commander", color, 0, true)
		visual_root.set_health_ratio(health_ratio)
	_refresh_name_label()
	queue_redraw()


func _ensure_visual_nodes() -> void:
	if not is_instance_valid(visual_root):
		visual_root = get_node_or_null("VisualRoot") as ColonyUnitVisual
	if not is_instance_valid(visual_root):
		visual_root = ColonyUnitVisual.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)
	if not is_instance_valid(sprite):
		sprite = visual_root.get_node_or_null("Sprite2D") as Sprite2D
	if not is_instance_valid(sprite):
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		visual_root.add_child(sprite)


func _refresh_name_label() -> void:
	var should_show: bool = kind == &"commander" and not _display_name.is_empty()
	if not should_show:
		if is_instance_valid(_name_label):
			_name_label.visible = false
		return
	if not is_instance_valid(_name_label):
		_name_label = Label.new()
		_name_label.name = "CommanderNameLabel"
		_name_label.z_index = 30
		_name_label.position = Vector2(-92.0, -82.0)
		_name_label.size = Vector2(184.0, 32.0)
		_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name_label.add_theme_font_size_override("font_size", 18)
		_name_label.add_theme_color_override("font_outline_color", Color(0.02, 0.015, 0.01, 0.98))
		_name_label.add_theme_constant_override("outline_size", 5)
		visual_root.add_child(_name_label)
	_name_label.text = _display_name
	_name_label.visible = true
	_name_label.add_theme_color_override(
		"font_color", ColonyVisualCatalog.team_color(team_id).lightened(0.28)
	)


func _draw() -> void:
	var color: Color = ColonyVisualCatalog.team_color(team_id)
	if kind == &"nest":
		_draw_nest_presentation(color)
		return
	if is_local_commander:
		var radius: float = (_definition.body_radius if _definition != null else 20.0) + 16.0
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(0.80, 0.95, 1.0, 0.94), 3.0, false)


func _draw_nest_presentation(color: Color) -> void:
	var solid_team_color := Color(color.r, color.g, color.b, 0.98)
	draw_circle(Vector2.ZERO, 91.0, Color(0.015, 0.012, 0.008, 0.52))
	draw_circle(Vector2.ZERO, 87.0, Color(color.r, color.g, color.b, 0.20))
	draw_arc(Vector2.ZERO, 88.0, 0.0, TAU, 32, Color(0.01, 0.01, 0.01, 0.94), 8.0)
	draw_arc(Vector2.ZERO, 87.0, 0.0, TAU, 32, solid_team_color, 4.0)
	for index in nest_level:
		draw_circle(Vector2(-18.0 + float(index) * 12.0, -102.0), 4.0, solid_team_color)
	if health_ratio < 0.999:
		var width: float = 118.0
		var y: float = -118.0
		draw_rect(Rect2(-width * 0.5, y, width, 9.0), Color(0.08, 0.06, 0.04, 0.85), true)
		draw_rect(
			Rect2(-width * 0.5 + 2.0, y + 2.0, (width - 4.0) * health_ratio, 5.0),
			Color(0.3, 0.9, 0.24, 1.0),
			true
		)


func _resolve_move_speed() -> float:
	_definition = _get_unit_definition(kind)
	return _definition.move_speed if _definition != null else 280.0


func _get_unit_definition(unit_id: StringName) -> UnitDefinition:
	var catalog: Node = get_node_or_null("/root/UnitCatalog")
	if not is_instance_valid(catalog) or not catalog.has_method("get_definition"):
		return null
	return catalog.call("get_definition", unit_id) as UnitDefinition


func _get_network_metric(property_name: StringName) -> int:
	var session: Node = get_node_or_null("/root/NetworkSession")
	if not is_instance_valid(session):
		return -1
	return int(session.get(property_name))
