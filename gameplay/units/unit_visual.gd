class_name ColonyUnitVisual
extends Node2D

const NON_COMMANDER_SEGMENT_COUNT: int = 4
const NON_COMMANDER_SEGMENT_HALF_ANGLE: float = 0.31

var _body_radius: float = 0.0
var _is_commander: bool = false
var _team_color := Color.WHITE
var _squad_id: int = 0
var _health_ratio: float = 1.0
var _presentation_enabled: bool = true


func configure(
	body_radius: float,
	is_commander: bool,
	team_color: Color,
	squad_id: int,
	presentation_enabled: bool
) -> void:
	_body_radius = maxf(body_radius, 0.0)
	_is_commander = is_commander
	_team_color = team_color
	_squad_id = clampi(squad_id, 0, 1)
	_health_ratio = 1.0
	_presentation_enabled = presentation_enabled
	visible = presentation_enabled
	_request_redraw()


func set_squad_id(value: int) -> void:
	var next_id: int = clampi(value, 0, 1)
	if _squad_id == next_id:
		return
	_squad_id = next_id
	_request_redraw()


func set_health_ratio(value: float) -> void:
	var next_ratio: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(_health_ratio, next_ratio):
		return
	_health_ratio = next_ratio
	_request_redraw()


func deactivate() -> void:
	_body_radius = 0.0
	_health_ratio = 0.0
	_presentation_enabled = false
	position = Vector2.ZERO
	visible = false


func _request_redraw() -> void:
	if _presentation_enabled and is_inside_tree() and not is_queued_for_deletion():
		queue_redraw()


func _draw() -> void:
	if not _presentation_enabled or _body_radius <= 0.0:
		return
	var radius: float = _body_radius + (9.0 if _is_commander else 5.5)
	var solid_team_color := Color(_team_color.r, _team_color.g, _team_color.b, 1.0)
	var solid_outline := Color(0.01, 0.01, 0.01, 1.0)

	if _is_commander:
		# Only the commander keeps a complete ring. Antialiasing is disabled so
		# overlapping edge pixels cannot accumulate into a blue/grey haze.
		draw_arc(Vector2.ZERO, radius + 1.5, 0.0, TAU, 40, solid_outline, 5.0, false)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, solid_team_color, 2.5, false)
		_draw_commander_ticks(radius + 7.0, solid_team_color, solid_outline)
	else:
		# Dense swarms no longer draw hundreds of full circles. Four stable,
		# low-overdraw segments retain team readability without alpha accumulation,
		# moire, or depth-order flashes when units cross each other.
		_draw_segmented_ring(radius + 1.0, solid_outline, 4.0)
		_draw_segmented_ring(radius, solid_team_color, 2.2)
		if _squad_id == 1:
			draw_circle(Vector2(radius - 1.5, -radius + 1.5), 3.6, Color(1.0, 1.0, 1.0, 1.0))

	if _health_ratio < 0.999:
		var width: float = _body_radius * 2.4
		var y: float = -_body_radius - 17.0
		draw_rect(Rect2(-width * 0.5, y, width, 6.0), Color(0.04, 0.03, 0.02, 1.0), true)
		draw_rect(
			Rect2(-width * 0.5 + 1.0, y + 1.0, (width - 2.0) * _health_ratio, 4.0),
			Color(0.32, 0.92, 0.27, 1.0),
			true
		)


func _draw_segmented_ring(radius: float, color: Color, width: float) -> void:
	for segment_index in NON_COMMANDER_SEGMENT_COUNT:
		var center_angle: float = PI * 0.25 + float(segment_index) * PI * 0.5
		draw_arc(
			Vector2.ZERO,
			radius,
			center_angle - NON_COMMANDER_SEGMENT_HALF_ANGLE,
			center_angle + NON_COMMANDER_SEGMENT_HALF_ANGLE,
			6,
			color,
			width,
			false
		)


func _draw_commander_ticks(radius: float, team_color: Color, outline_color: Color) -> void:
	for tick_index in 4:
		var direction := Vector2.from_angle(float(tick_index) * PI * 0.5)
		var tangent := Vector2(-direction.y, direction.x)
		var center: Vector2 = direction * radius
		draw_line(center - tangent * 4.0, center + tangent * 4.0, outline_color, 5.0, false)
		draw_line(center - tangent * 3.0, center + tangent * 3.0, team_color, 2.0, false)
