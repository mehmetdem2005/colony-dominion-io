class_name ColonyVirtualStick
extends Control

signal vector_changed(value: Vector2)

var radius: float = 78.0
var knob_radius: float = 31.0
var value := Vector2.ZERO

var _touch_index: int = -1
var _mouse_active: bool = false
var _base: Panel
var _inner: Panel
var _knob: Panel
var _interaction_enabled: bool = true


func configure(new_radius: float, new_knob_radius: float) -> void:
	radius = maxf(new_radius, 24.0)
	knob_radius = clampf(new_knob_radius, 12.0, radius * 0.55)
	custom_minimum_size = Vector2.ONE * radius * 2.0
	size = custom_minimum_size


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 200
	_build_visuals()
	_update_knob()


func _exit_tree() -> void:
	_touch_index = -1
	_mouse_active = false
	value = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touch_index = -1
		_mouse_active = false
		_set_value(Vector2.ZERO)


func set_interaction_enabled(enabled: bool) -> void:
	if _interaction_enabled == enabled:
		return
	_interaction_enabled = enabled
	self_modulate.a = 1.0 if enabled else 0.52
	if not enabled:
		_touch_index = -1
		_mouse_active = false
		_set_value(Vector2.ZERO)


func _input(event: InputEvent) -> void:
	if not _interaction_enabled or not is_visible_in_tree():
		return
	if get_viewport().is_input_handled() and not _owns_event(event):
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _owns_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.index == _touch_index
	if event is InputEventScreenDrag:
		return event.index == _touch_index
	if event is InputEventMouseButton:
		return _mouse_active
	if event is InputEventMouseMotion:
		return _mouse_active
	return false


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and _contains_viewport_point(event.position):
			_touch_index = event.index
			_mouse_active = false
			_update_from_viewport(event.position)
			get_viewport().set_input_as_handled()
	elif event.index == _touch_index:
		_touch_index = -1
		_set_value(Vector2.ZERO)
		get_viewport().set_input_as_handled()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index != _touch_index:
		return
	_update_from_viewport(event.position)
	get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT or _touch_index != -1:
		return
	if event.pressed:
		if not _contains_viewport_point(event.position):
			return
		_mouse_active = true
		_update_from_viewport(event.position)
		get_viewport().set_input_as_handled()
	elif _mouse_active:
		_mouse_active = false
		_set_value(Vector2.ZERO)
		get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_active or _touch_index != -1:
		return
	_update_from_viewport(event.position)
	get_viewport().set_input_as_handled()


func _contains_viewport_point(viewport_position: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var local_point: Vector2 = (
		get_global_transform_with_canvas().affine_inverse() * viewport_position
	)
	return local_point.distance_squared_to(size * 0.5) <= radius * radius


func _update_from_viewport(viewport_position: Vector2) -> void:
	var local_point: Vector2 = (
		get_global_transform_with_canvas().affine_inverse() * viewport_position
	)
	var normalized: Vector2 = (local_point - size * 0.5) / maxf(radius, 1.0)
	_set_value(normalized.limit_length(1.0))


func _set_value(new_value: Vector2) -> void:
	var clamped := new_value.limit_length(1.0)
	if value.is_equal_approx(clamped):
		return
	value = clamped
	_update_knob()
	vector_changed.emit(value)


func _build_visuals() -> void:
	_base = Panel.new()
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_base.add_theme_stylebox_override(
		"panel", _circle_style(Color(0.025, 0.03, 0.025, 0.80), Color(1.0, 0.76, 0.13, 0.98), 5)
	)
	add_child(_base)

	_inner = Panel.new()
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := radius * 0.24
	_inner.position = Vector2.ONE * inset
	_inner.size = Vector2.ONE * (radius * 2.0 - inset * 2.0)
	_inner.add_theme_stylebox_override(
		"panel", _circle_style(Color(0.14, 0.15, 0.13, 0.55), Color(0.0, 0.0, 0.0, 0.0), 0)
	)
	add_child(_inner)

	_knob = Panel.new()
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.size = Vector2.ONE * knob_radius * 2.0
	_knob.add_theme_stylebox_override(
		"panel", _circle_style(Color(0.91, 0.93, 0.91, 1.0), Color(0.08, 0.09, 0.08, 0.98), 4)
	)
	add_child(_knob)


func _update_knob() -> void:
	if not is_instance_valid(_knob):
		return
	var center := size * 0.5
	var travel := radius * 0.62
	_knob.position = center + value * travel - _knob.size * 0.5


func _circle_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(999)
	style.anti_aliasing = true
	return style
