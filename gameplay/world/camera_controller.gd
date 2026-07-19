class_name PlayerCameraController
extends Camera2D

@export var follow_speed: float = 9.5
@export var formation_screen_bias: float = 72.0
@export var smoothing_recovery_distance: float = 180.0
@export var framing_direction_response: float = 6.0

var target: Node2D = null
var _world_bounds := Rect2()
var _safe_frame_insets := Vector4(24.0, 72.0, 24.0, 190.0)
var _touches: Dictionary = {}
var _last_pinch_distance: float = 0.0
var _framing_direction := Vector2.ZERO


func _init() -> void:
	# Physics interpolation requires the camera itself to update on physics ticks.
	# Set this before the node enters the tree so Godot never has to override it.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	enabled = true
	make_current()
	position_smoothing_enabled = true
	position_smoothing_speed = follow_speed
	# Limit smoothing can fight position smoothing and create a visible correction flash
	# near world edges. Camera limits remain hard and deterministic instead.
	limit_smoothed = false
	zoom = Vector2.ONE
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)


func set_target(new_target: Node2D) -> void:
	target = new_target
	if not is_instance_valid(target) or not target.global_position.is_finite():
		target = null
		return
	_framing_direction = Vector2.ZERO
	global_position = _calculate_desired_camera_position(Vector2.ZERO)
	reset_smoothing()
	reset_physics_interpolation()


func set_world_bounds(bounds: Rect2) -> void:
	if (
		not bounds.position.is_finite()
		or not bounds.size.is_finite()
		or bounds.size.x <= 0.0
		or bounds.size.y <= 0.0
	):
		_world_bounds = Rect2()
	else:
		_world_bounds = bounds
	_refresh_limits()


func set_safe_frame_insets(insets: Vector4) -> void:
	if not insets.is_finite():
		return
	_safe_frame_insets = Vector4(
		maxf(insets.x, 0.0), maxf(insets.y, 0.0), maxf(insets.z, 0.0), maxf(insets.w, 0.0)
	)
	if is_instance_valid(target):
		global_position = _calculate_desired_camera_position(_framing_direction)
		reset_smoothing()


func get_safe_frame_insets() -> Vector4:
	return _safe_frame_insets


func get_gameplay_safe_rect_for_size(viewport_size: Vector2) -> Rect2:
	if not viewport_size.is_finite() or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var maximum_horizontal_inset: float = maxf(viewport_size.x * 0.42, 0.0)
	var maximum_vertical_inset: float = maxf(viewport_size.y * 0.42, 0.0)
	var left: float = clampf(_safe_frame_insets.x, 0.0, maximum_horizontal_inset)
	var top: float = clampf(_safe_frame_insets.y, 0.0, maximum_vertical_inset)
	var right: float = clampf(_safe_frame_insets.z, 0.0, maximum_horizontal_inset)
	var bottom: float = clampf(_safe_frame_insets.w, 0.0, maximum_vertical_inset)
	return Rect2(
		Vector2(left, top),
		Vector2(
			maxf(viewport_size.x - left - right, 1.0), maxf(viewport_size.y - top - bottom, 1.0)
		)
	)


func get_desired_target_screen_position(
	viewport_size: Vector2, movement_direction: Vector2
) -> Vector2:
	var safe_rect: Rect2 = get_gameplay_safe_rect_for_size(viewport_size)
	var direction: Vector2 = (
		movement_direction.normalized() if movement_direction.is_finite() else Vector2.ZERO
	)
	var desired: Vector2 = safe_rect.get_center() + direction * formation_screen_bias
	var target_margin: float = minf(42.0, minf(safe_rect.size.x, safe_rect.size.y) * 0.18)
	var inner_rect: Rect2 = safe_rect.grow(-target_margin)
	if inner_rect.size.x <= 1.0 or inner_rect.size.y <= 1.0:
		return safe_rect.get_center()
	return Vector2(
		clampf(desired.x, inner_rect.position.x, inner_rect.end.x),
		clampf(desired.y, inner_rect.position.y, inner_rect.end.y)
	)


func _physics_process(delta: float) -> void:
	if (
		not is_instance_valid(target)
		or not target.global_position.is_finite()
		or not is_finite(delta)
		or delta <= 0.0
	):
		return
	var raw_direction: Vector2 = _get_target_move_direction()
	var direction_weight: float = 1.0 - exp(-framing_direction_response * maxf(delta, 0.0))
	_framing_direction = _framing_direction.lerp(raw_direction, direction_weight)
	if _framing_direction.length_squared() < 0.0004:
		_framing_direction = Vector2.ZERO
	var desired_position: Vector2 = _calculate_desired_camera_position(_framing_direction)
	global_position = desired_position

	# Camera2D.global_position is the smoothing destination, not necessarily the
	# position currently rendered. Recover only when the rendered center falls far
	# behind the expected center, avoiding one-frame HUD occlusion and edge flashes.
	var actual_center: Vector2 = get_screen_center_position()
	var drift_world: float = actual_center.distance_to(desired_position)
	var safe_zoom: float = maxf(zoom.x, 0.01)
	if drift_world * safe_zoom > smoothing_recovery_distance:
		reset_smoothing()


func _get_target_move_direction() -> Vector2:
	var moving_body := target as CharacterBody2D
	if (
		moving_body == null
		or not moving_body.velocity.is_finite()
		or moving_body.velocity.length_squared() <= 64.0
	):
		return Vector2.ZERO
	return moving_body.velocity.normalized()


func _calculate_desired_camera_position(movement_direction: Vector2) -> Vector2:
	if not is_instance_valid(target) or not target.global_position.is_finite():
		return global_position
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_center: Vector2 = viewport_size * 0.5
	var desired_target_screen: Vector2 = get_desired_target_screen_position(
		viewport_size, movement_direction
	)
	var safe_zoom: float = maxf(zoom.x, 0.01)
	var desired_center: Vector2 = (
		target.global_position - (desired_target_screen - viewport_center) / safe_zoom
	)
	return _clamp_camera_center_to_world(desired_center, viewport_size)


func _clamp_camera_center_to_world(center: Vector2, viewport_size: Vector2) -> Vector2:
	if _world_bounds.size == Vector2.ZERO:
		return center
	var safe_zoom: float = maxf(zoom.x, 0.01)
	var half_view: Vector2 = viewport_size * 0.5 / safe_zoom
	var minimum_center: Vector2 = _world_bounds.position + half_view
	var maximum_center: Vector2 = _world_bounds.end - half_view
	if minimum_center.x > maximum_center.x:
		minimum_center.x = _world_bounds.get_center().x
		maximum_center.x = minimum_center.x
	if minimum_center.y > maximum_center.y:
		minimum_center.y = _world_bounds.get_center().y
		maximum_center.y = minimum_center.y
	return Vector2(
		clampf(center.x, minimum_center.x, maximum_center.x),
		clampf(center.y, minimum_center.y, maximum_center.y)
	)


func cancel_gesture_state() -> void:
	_touches.clear()
	_last_pinch_distance = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_gesture_state()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(-0.08)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(0.08)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
			_last_pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			var points: Array = _touches.values()
			var first: Vector2 = points[0]
			var second: Vector2 = points[1]
			var distance: float = first.distance_to(second)
			if _last_pinch_distance > 0.0:
				_apply_zoom((_last_pinch_distance - distance) * 0.0015)
			_last_pinch_distance = distance


func _apply_zoom(delta_zoom: float) -> void:
	if not is_finite(delta_zoom) or not is_finite(zoom.x):
		return
	var value: float = clampf(zoom.x + delta_zoom, 0.72, 1.18)
	zoom = Vector2.ONE * value
	_refresh_limits()
	if is_instance_valid(target):
		global_position = _calculate_desired_camera_position(_framing_direction)
		reset_smoothing()


func _on_viewport_size_changed() -> void:
	_refresh_limits()
	if is_instance_valid(target):
		global_position = _calculate_desired_camera_position(_framing_direction)
		reset_smoothing()


func _refresh_limits() -> void:
	if _world_bounds.size == Vector2.ZERO or not is_inside_tree():
		return
	# Camera2D limits constrain the rendered screen edges. Expanding them by half a
	# viewport allowed the camera to show outside the authored world and caused
	# transient edge corrections, so limits now match the world rectangle exactly.
	limit_left = floori(_world_bounds.position.x)
	limit_top = floori(_world_bounds.position.y)
	limit_right = ceili(_world_bounds.end.x)
	limit_bottom = ceili(_world_bounds.end.y)


func get_world_view_rect() -> Rect2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var safe_zoom: float = maxf(zoom.x, 0.01)
	var world_size: Vector2 = viewport_size / safe_zoom
	var rendered_center: Vector2 = (
		get_screen_center_position() if is_inside_tree() and enabled else global_position
	)
	return Rect2(rendered_center - world_size * 0.5, world_size)
