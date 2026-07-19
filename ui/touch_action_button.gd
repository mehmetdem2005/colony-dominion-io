class_name TouchActionButton
extends Control

signal pressed

var label_text: String = "BUTTON"
var button_size := Vector2(120.0, 72.0)
var circular: bool = false
var enabled: bool = true
var fill_color := Color(0.07, 0.075, 0.055, 0.96)
var border_color := Color(1.0, 0.76, 0.12, 0.99)

var _touch_index: int = -1
var _mouse_active: bool = false
var _pressed_visual: bool = false
var _panel: Panel
var _label: Label
var _interaction_enabled: bool = true


func configure(text_value: String, size_value: Vector2, is_circular: bool = true) -> void:
	label_text = text_value
	button_size = size_value
	circular = is_circular
	custom_minimum_size = button_size
	size = button_size


func set_label_text(value: String) -> void:
	label_text = value
	if is_instance_valid(_label):
		_label.text = value
		_label.add_theme_font_size_override("font_size", _get_label_font_size(value))


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		_reset_capture()
	_apply_visual_state()


func set_interaction_enabled(value: bool) -> void:
	if _interaction_enabled == value:
		return
	_interaction_enabled = value
	if not value:
		_reset_capture()
	_apply_visual_state()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 210
	_build_visuals()
	_apply_visual_state()


func _exit_tree() -> void:
	_reset_capture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_capture()
		_apply_visual_state()


func _input(event: InputEvent) -> void:
	if not enabled or not _interaction_enabled or not is_visible_in_tree():
		return
	if get_viewport().is_input_handled() and not _owns_event(event):
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)


func _owns_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.index == _touch_index
	if event is InputEventMouseButton:
		return _mouse_active
	return false


func _reset_capture() -> void:
	_touch_index = -1
	_mouse_active = false
	_pressed_visual = false


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and _contains_viewport_point(event.position):
			_touch_index = event.index
			_mouse_active = false
			_set_pressed_visual(true)
			pressed.emit()
			get_viewport().set_input_as_handled()
	elif event.index == _touch_index:
		_touch_index = -1
		_set_pressed_visual(false)
		get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT or _touch_index != -1:
		return
	if event.pressed:
		if not _contains_viewport_point(event.position):
			return
		_mouse_active = true
		_set_pressed_visual(true)
		pressed.emit()
		get_viewport().set_input_as_handled()
	elif _mouse_active:
		_mouse_active = false
		_set_pressed_visual(false)
		get_viewport().set_input_as_handled()


func _contains_viewport_point(viewport_position: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var local_point: Vector2 = (
		get_global_transform_with_canvas().affine_inverse() * viewport_position
	)
	var local_rect := Rect2(Vector2.ZERO, size)
	if not circular:
		return local_rect.has_point(local_point)
	var radius_value: float = minf(size.x, size.y) * 0.5
	return local_point.distance_squared_to(size * 0.5) <= radius_value * radius_value


func _set_pressed_visual(is_pressed: bool) -> void:
	if _pressed_visual == is_pressed:
		return
	_pressed_visual = is_pressed
	_apply_visual_state()


func _build_visuals() -> void:
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.text = label_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", _get_label_font_size(label_text))
	_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.54, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.90))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)


func _get_label_font_size(value: String) -> int:
	if value.length() <= 6:
		return 24
	if value.length() <= 9:
		return 18
	return 14


func _apply_visual_state() -> void:
	if not is_instance_valid(_panel):
		return
	var background: Color
	var border: Color
	if not enabled or not _interaction_enabled:
		background = Color(0.12, 0.12, 0.11, 0.72)
		border = Color(0.38, 0.38, 0.34, 0.72)
	elif _pressed_visual:
		background = fill_color.lightened(0.14)
		border = border_color
	else:
		background = fill_color
		border = border_color
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(5 if circular else 4)
	style.set_corner_radius_all(999 if circular else 18)
	style.anti_aliasing = true
	_panel.add_theme_stylebox_override("panel", style)
	if is_instance_valid(_label):
		var label_enabled: bool = enabled and _interaction_enabled
		_label.modulate = Color(1.0, 1.0, 1.0, 1.0 if label_enabled else 0.48)
		_label.position = Vector2(0.0, 2.0 if _pressed_visual else 0.0)
