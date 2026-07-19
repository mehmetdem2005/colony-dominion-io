class_name ProductionTouchCard
extends PanelContainer

signal pressed

const RESOURCE_TEXTURES := {
	&"seed": "res://assets/resources/seeds.png",
	&"nectar": "res://assets/resources/nectar.png",
	&"protein": "res://assets/resources/protein.png",
	&"leaf": "res://assets/resources/leaves.png",
	&"stone": "res://assets/resources/stone.png",
}
const RESOURCE_ORDER: Array[StringName] = [&"seed", &"nectar", &"protein", &"leaf", &"stone"]

var icon_texture: Texture2D
var title_text: String = "Birim"
var role_text: String = ""
var costs: Dictionary = {}

var _touch_index: int = -1
var _mouse_active: bool = false
var _pressed_visual: bool = false
var _icon: TextureRect
var _title: Label
var _role: Label
var _interaction_enabled: bool = true


func configure(
	texture: Texture2D, unit_name: String, unit_role: String, unit_costs: Dictionary
) -> void:
	icon_texture = texture
	title_text = unit_name
	role_text = unit_role
	costs = unit_costs.duplicate(true)
	custom_minimum_size = Vector2(122.0, 108.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 40
	_build_contents()
	_apply_visual_state()


func _exit_tree() -> void:
	_reset_capture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_capture()
		_apply_visual_state()


func set_interaction_enabled(value: bool) -> void:
	if _interaction_enabled == value:
		return
	_interaction_enabled = value
	if not value:
		_reset_capture()
	_apply_visual_state()


func _input(event: InputEvent) -> void:
	if not _interaction_enabled or not is_visible_in_tree():
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
	return Rect2(Vector2.ZERO, size).has_point(local_point)


func _set_pressed_visual(is_pressed: bool) -> void:
	if _pressed_visual == is_pressed:
		return
	_pressed_visual = is_pressed
	_apply_visual_state()


func _build_contents() -> void:
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 0)
	add_child(content)

	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.texture = icon_texture
	_icon.custom_minimum_size = Vector2(72.0, 44.0)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(_icon)

	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.text = title_text
	_title.custom_minimum_size = Vector2(0.0, 20.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_font_size_override("font_size", 16 if title_text.length() <= 10 else 14)
	_title.add_theme_color_override("font_color", Color(0.10, 0.055, 0.015, 1.0))
	content.add_child(_title)

	_role = Label.new()
	_role.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_role.text = role_text
	_role.custom_minimum_size = Vector2(0.0, 14.0)
	_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_role.add_theme_font_size_override("font_size", 10)
	_role.add_theme_color_override("font_color", Color(0.34, 0.19, 0.045, 1.0))
	content.add_child(_role)

	var cost_row := HBoxContainer.new()
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_row.custom_minimum_size = Vector2(0.0, 24.0)
	cost_row.add_theme_constant_override("separation", 2)
	content.add_child(cost_row)

	var has_cost: bool = false
	for resource_id in RESOURCE_ORDER:
		var amount: int = int(costs.get(resource_id, 0))
		if amount <= 0:
			continue
		has_cost = true
		cost_row.add_child(_create_cost_chip(resource_id, amount))

	if not has_cost:
		var free_label := Label.new()
		free_label.text = "ÜCRETSİZ"
		free_label.add_theme_font_size_override("font_size", 12)
		free_label.add_theme_color_override("font_color", Color(0.16, 0.08, 0.015, 1.0))
		cost_row.add_child(free_label)


func _create_cost_chip(resource_id: StringName, amount: int) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(34.0, 24.0)
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0.28, 0.20, 0.08, 0.13)
	chip_style.border_color = Color(0.26, 0.15, 0.03, 0.38)
	chip_style.set_border_width_all(1)
	chip_style.set_corner_radius_all(7)
	chip_style.content_margin_left = 1.0
	chip_style.content_margin_right = 2.0
	chip_style.content_margin_top = 1.0
	chip_style.content_margin_bottom = 1.0
	chip.add_theme_stylebox_override("panel", chip_style)

	var pair := HBoxContainer.new()
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.add_theme_constant_override("separation", 0)
	chip.add_child(pair)

	var resource_icon := TextureRect.new()
	resource_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resource_icon.texture = load(String(RESOURCE_TEXTURES[resource_id])) as Texture2D
	resource_icon.custom_minimum_size = Vector2(20.0, 20.0)
	resource_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	resource_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pair.add_child(resource_icon)

	var amount_label := Label.new()
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_label.text = str(amount)
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount_label.add_theme_font_size_override("font_size", 13)
	amount_label.add_theme_color_override("font_color", Color(0.13, 0.065, 0.01, 1.0))
	pair.add_child(amount_label)
	return chip


func _apply_visual_state() -> void:
	var style := StyleBoxFlat.new()
	if not _interaction_enabled:
		style.bg_color = Color(0.52, 0.49, 0.42, 0.86)
	elif _pressed_visual:
		style.bg_color = Color(0.80, 0.68, 0.43, 1.0)
	else:
		style.bg_color = Color(0.97, 0.90, 0.73, 1.0)
	style.border_color = Color(0.22, 0.14, 0.045, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(13)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	style.anti_aliasing = true
	add_theme_stylebox_override("panel", style)
	modulate = Color(1.0, 1.0, 1.0, 1.0 if _interaction_enabled else 0.62)
