class_name OnlineMatchHUD
extends CanvasLayer

signal movement_changed(value: Vector2)
signal command_requested(command_type: StringName, payload: Dictionary)
signal exit_requested

const BASE_LANDSCAPE := Vector2(1280.0, 720.0)
const BASE_PORTRAIT_WIDTH: float = 800.0
const SAFE_MARGIN: float = 16.0

var _root: Control
var _top_panel: PanelContainer
var _production_panel: PanelContainer
var _stick: ColonyVirtualStick
var _status_label: Label
var _resource_label: Label
var _army_label: Label
var _queue_label: Label
var _toast_label: Label
var _exit_button: Button
var _state_panel: PanelContainer
var _state_title: Label
var _state_body: Label
var _state_exit_button: Button
var _last_player_state: Dictionary = {}
var _interaction_enabled: bool = true
var _lifecycle_state: StringName = &"active"
var _action_buttons: Array[TouchActionButton] = []
var _production_buttons: Array[Button] = []
var _toast_tween: Tween = null


func _ready() -> void:
	layer = 100
	_build_ui()
	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.connect(_apply_responsive_layout)
	NetworkSession.metrics_changed.connect(_refresh_status.unbind(3))
	NetworkSession.region_changed.connect(_refresh_status.unbind(2))
	NetworkSession.connection_state_changed.connect(_on_connection_state_changed)
	_refresh_status()
	call_deferred("_apply_responsive_layout")


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.disconnect(_apply_responsive_layout)


func _process(_delta: float) -> void:
	var movement := Vector2.ZERO
	if _interaction_enabled and is_instance_valid(_stick):
		movement = _stick.value
	movement_changed.emit(movement)


func apply_player_state(state: Dictionary) -> void:
	_last_player_state = state.duplicate(true)
	var inventory_variant: Variant = state.get("inventory", {})
	var inventory: Dictionary = inventory_variant if inventory_variant is Dictionary else {}
	var seed: int = int(inventory.get(&"seed", inventory.get("seed", 0)))
	var nectar: int = int(inventory.get(&"nectar", inventory.get("nectar", 0)))
	var protein: int = int(inventory.get(&"protein", inventory.get("protein", 0)))
	var leaf: int = int(inventory.get(&"leaf", inventory.get("leaf", 0)))
	var stone: int = int(inventory.get(&"stone", inventory.get("stone", 0)))
	if _is_portrait():
		_resource_label.text = (
			"TOHUM %d  •  NEKTAR %d  •  PROTEİN %d\nYAPRAK %d  •  TAŞ %d"
			% [seed, nectar, protein, leaf, stone]
		)
	else:
		_resource_label.text = (
			"TOHUM %d  NEKTAR %d  PROTEİN %d  YAPRAK %d  TAŞ %d"
			% [seed, nectar, protein, leaf, stone]
		)
	_army_label.text = (
		"YUVA %d  •  ORDU %d/%d  •  SKOR %d"
		% [
			int(state.get("level", 1)),
			int(state.get("army", 0)),
			int(state.get("capacity", 0)),
			int(state.get("score", 0)),
		]
	)
	var queue_variant: Variant = state.get("queue", [])
	var queue: Array = queue_variant if queue_variant is Array else []
	if queue.is_empty():
		_queue_label.text = "Üretim kuyruğu boş"
	else:
		_queue_label.text = (
			"%s • %%%d"
			% [
				String(queue[0]).to_upper(),
				roundi(float(state.get("production_progress", 0.0)) * 100.0),
			]
		)


func set_lifecycle_state(state: StringName, detail: String = "") -> void:
	if state == _lifecycle_state and state == &"active":
		return
	_lifecycle_state = state
	match state:
		&"active":
			_state_panel.visible = false
			_set_interaction_enabled(true)
		&"respawning":
			_state_title.text = "KOMUTAN YENİDEN DOĞUYOR"
			_state_title.add_theme_color_override("font_color", Color("ffd45a"))
			_state_body.text = (
				detail
				if not detail.is_empty()
				else "Komutanın öldü. Kamera yuvayı takip ediyor; yeniden doğana kadar kontroller kilitli."
			)
			_state_exit_button.visible = true
			_state_panel.visible = true
			_set_interaction_enabled(false)
		&"eliminated":
			_state_title.text = "ELENDİN"
			_state_title.add_theme_color_override("font_color", Color("ff685d"))
			_state_body.text = (
				detail
				if not detail.is_empty()
				else "Yuvan ve komutanın yok edildi. Maçta kontrol edilebilir bir birimin kalmadı."
			)
			_state_exit_button.visible = true
			_state_panel.visible = true
			_set_interaction_enabled(false)
		_:
			push_warning("Unknown online HUD lifecycle state: %s" % String(state))
	_apply_responsive_layout()


func show_match_result(winner_name: String, player_won: bool) -> void:
	_lifecycle_state = &"finished"
	_state_title.text = "ZAFER" if player_won else "MAÇ BİTTİ"
	_state_title.add_theme_color_override(
		"font_color", Color("ffd45a") if player_won else Color("ff8b61")
	)
	_state_body.text = "Kazanan: %s" % winner_name
	_state_exit_button.visible = true
	_state_panel.visible = true
	_set_interaction_enabled(false)
	_apply_responsive_layout()


func show_toast(message: String) -> void:
	if message.is_empty():
		return
	if is_instance_valid(_toast_tween):
		_toast_tween.kill()
	_toast_label.text = message
	_toast_label.modulate.a = 1.0
	_toast_label.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(
		func() -> void:
			_toast_label.visible = false
			_toast_label.modulate.a = 1.0
	)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "OnlineHUDRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_top_panel = PanelContainer.new()
	_top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.03, 0.02, 0.92)))
	_root.add_child(_top_panel)
	var top_box := VBoxContainer.new()
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_box.add_theme_constant_override("separation", 2)
	_top_panel.add_child(top_box)
	_resource_label = _make_label("Kaynaklar yükleniyor", 18)
	_resource_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_army_label = _make_label("Ordu yükleniyor", 18)
	_queue_label = _make_label("Üretim kuyruğu", 15)
	top_box.add_child(_resource_label)
	top_box.add_child(_army_label)
	top_box.add_child(_queue_label)

	_status_label = _make_label("BAĞLANIYOR", 18)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_status_label)

	_stick = ColonyVirtualStick.new()
	_stick.configure(78.0, 31.0)
	_root.add_child(_stick)

	var attack := _make_action("SALDIR", Vector2(164.0, 164.0), true)
	attack.pressed.connect(func() -> void: command_requested.emit(&"attack", {}))
	var gather := _make_action("HASAT", Vector2(116.0, 54.0), false)
	gather.pressed.connect(func() -> void: command_requested.emit(&"gather", {}))
	var rally := _make_action("TOPLA", Vector2(116.0, 54.0), false)
	rally.pressed.connect(func() -> void: command_requested.emit(&"rally", {}))
	var split := _make_action("BÖL", Vector2(92.0, 52.0), false)
	split.pressed.connect(func() -> void: command_requested.emit(&"split", {}))
	var spread := _make_action("DAĞIT", Vector2(96.0, 52.0), false)
	spread.pressed.connect(func() -> void: command_requested.emit(&"spread", {}))
	var merge := _make_action("BİRLEŞ", Vector2(100.0, 52.0), false)
	merge.pressed.connect(func() -> void: command_requested.emit(&"merge", {}))

	_production_panel = PanelContainer.new()
	_production_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.035, 0.03, 0.02, 0.94))
	)
	_root.add_child(_production_panel)
	var production_grid := GridContainer.new()
	production_grid.columns = 3
	production_grid.add_theme_constant_override("h_separation", 4)
	production_grid.add_theme_constant_override("v_separation", 4)
	_production_panel.add_child(production_grid)
	for unit_id in [&"worker", &"soldier", &"guard", &"scout", &"acid_ant"]:
		var definition: UnitDefinition = UnitCatalog.get_definition(unit_id)
		var unit_button := Button.new()
		unit_button.text = definition.display_name if definition != null else String(unit_id)
		unit_button.custom_minimum_size = Vector2(108.0, 42.0)
		unit_button.pressed.connect(_emit_production.bind(unit_id))
		production_grid.add_child(unit_button)
		_production_buttons.append(unit_button)
	var upgrade_button := Button.new()
	upgrade_button.text = "YUVA YÜKSELT"
	upgrade_button.custom_minimum_size = Vector2(108.0, 42.0)
	upgrade_button.pressed.connect(func() -> void: command_requested.emit(&"upgrade", {}))
	production_grid.add_child(upgrade_button)
	_production_buttons.append(upgrade_button)

	_exit_button = Button.new()
	_exit_button.text = "MAÇTAN ÇIK"
	_exit_button.pressed.connect(func() -> void: exit_requested.emit())
	_root.add_child(_exit_button)

	_toast_label = _make_label("", 22)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.visible = false
	_toast_label.z_index = 300
	_root.add_child(_toast_label)

	_build_state_panel()


func _build_state_panel() -> void:
	_state_panel = PanelContainer.new()
	_state_panel.visible = false
	_state_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_state_panel.z_index = 500
	_state_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.025, 0.022, 0.016, 0.985), Color(1.0, 0.72, 0.16, 0.96))
	)
	_root.add_child(_state_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_state_panel.add_child(box)
	_state_title = _make_label("", 34)
	_state_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_state_title)
	_state_body = _make_label("", 18)
	_state_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_state_body)
	_state_exit_button = Button.new()
	_state_exit_button.text = "ANA MENÜ"
	_state_exit_button.custom_minimum_size = Vector2(280.0, 56.0)
	_state_exit_button.pressed.connect(func() -> void: exit_requested.emit())
	box.add_child(_state_exit_button)


func _emit_production(unit_id: StringName) -> void:
	if _interaction_enabled:
		command_requested.emit(&"produce", {"unit_id": unit_id})


func _make_action(text: String, size_value: Vector2, circular: bool) -> TouchActionButton:
	var button := TouchActionButton.new()
	button.configure(text, size_value, circular)
	_root.add_child(button)
	_action_buttons.append(button)
	return button


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.74, 1.0))
	return label


func _refresh_status() -> void:
	_status_label.text = NetworkSession.get_status_text()
	if NetworkSession.ping_ms >= 0 and NetworkSession.ping_ms <= 70:
		_status_label.add_theme_color_override("font_color", Color(0.42, 1.0, 0.52, 1.0))
	elif NetworkSession.ping_ms >= 0 and NetworkSession.ping_ms <= 140:
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.28, 1.0))
	else:
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.30, 1.0))


func _on_connection_state_changed(_state: int, message: String) -> void:
	_refresh_status()
	if not message.is_empty():
		show_toast(message)


func _set_interaction_enabled(value: bool) -> void:
	_interaction_enabled = value
	if is_instance_valid(_stick):
		_stick.set_interaction_enabled(value)
	for button in _action_buttons:
		if is_instance_valid(button):
			button.set_interaction_enabled(value)
	for button in _production_buttons:
		if is_instance_valid(button):
			button.disabled = not value


func _apply_responsive_layout() -> void:
	if not is_instance_valid(_root):
		return
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe_rect := MainMenuLayoutGuard._get_logical_safe_rect(get_viewport())
	if safe_rect.size.x <= 1.0 or safe_rect.size.y <= 1.0:
		return
	var portrait := safe_rect.size.y > safe_rect.size.x * 1.08
	var ui_scale: float
	if portrait:
		ui_scale = clampf(safe_rect.size.x / BASE_PORTRAIT_WIDTH, 0.72, 1.0)
	else:
		ui_scale = clampf(
			minf(safe_rect.size.x / BASE_LANDSCAPE.x, safe_rect.size.y / BASE_LANDSCAPE.y),
			0.70,
			1.0
		)
	var margin := SAFE_MARGIN * ui_scale
	var top_height: float = 112.0 if portrait else 88.0
	var top_width: float = (safe_rect.size.x - margin * 2.0) / ui_scale
	if not portrait:
		top_width = minf(top_width, 670.0)
	_place(
		_top_panel,
		safe_rect.position + Vector2(margin, margin),
		Vector2(top_width, top_height),
		ui_scale
	)

	if portrait:
		var status_y: float = _top_panel.position.y + top_height * ui_scale + 6.0 * ui_scale
		var exit_size := Vector2(150.0, 48.0)
		_place(
			_exit_button,
			Vector2(safe_rect.end.x - margin - exit_size.x * ui_scale, status_y),
			exit_size,
			ui_scale
		)
		var status_width: float = maxf(
			180.0, (safe_rect.size.x - margin * 3.0 - exit_size.x * ui_scale) / ui_scale
		)
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_place(
			_status_label,
			Vector2(safe_rect.position.x + margin, status_y),
			Vector2(status_width, 48.0),
			ui_scale
		)
		_layout_portrait_controls(safe_rect, ui_scale, margin)
	else:
		var exit_size := Vector2(166.0, 48.0)
		_place(
			_exit_button,
			Vector2(
				safe_rect.end.x - margin - exit_size.x * ui_scale,
				safe_rect.position.y + 72.0 * ui_scale
			),
			exit_size,
			ui_scale
		)
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_place(
			_status_label,
			Vector2(
				safe_rect.end.x - margin - 410.0 * ui_scale, safe_rect.position.y + 18.0 * ui_scale
			),
			Vector2(410.0, 40.0),
			ui_scale
		)
		_layout_landscape_controls(safe_rect, ui_scale, margin)

	var toast_width: float = minf(500.0, (safe_rect.size.x - margin * 2.0) / ui_scale)
	_place(
		_toast_label,
		Vector2(
			safe_rect.get_center().x - toast_width * ui_scale * 0.5,
			_top_panel.position.y + top_height * ui_scale + 64.0 * ui_scale
		),
		Vector2(toast_width, 54.0),
		ui_scale
	)
	_layout_state_panel(safe_rect)


func _layout_portrait_controls(safe_rect: Rect2, ui_scale: float, margin: float) -> void:
	var bottom: float = safe_rect.end.y - margin
	var stick_size := Vector2(170.0, 170.0)
	var attack_size := Vector2(150.0, 150.0)
	_place(
		_stick,
		Vector2(safe_rect.position.x + margin, bottom - stick_size.y * ui_scale),
		stick_size,
		ui_scale
	)
	var attack_position := Vector2(
		safe_rect.end.x - margin - attack_size.x * ui_scale, bottom - attack_size.y * ui_scale
	)
	_place(_action_buttons[0], attack_position, attack_size, ui_scale)
	_place(
		_action_buttons[1],
		Vector2(attack_position.x - 122.0 * ui_scale, bottom - 118.0 * ui_scale),
		Vector2(112.0, 54.0),
		ui_scale
	)
	_place(
		_action_buttons[2],
		Vector2(attack_position.x - 122.0 * ui_scale, bottom - 56.0 * ui_scale),
		Vector2(112.0, 54.0),
		ui_scale
	)
	var production_size := Vector2(350.0, 100.0)
	_place(
		_production_panel,
		Vector2(
			safe_rect.get_center().x - production_size.x * ui_scale * 0.5, bottom - 302.0 * ui_scale
		),
		production_size,
		ui_scale
	)
	var command_sizes := [Vector2(92.0, 52.0), Vector2(96.0, 52.0), Vector2(100.0, 52.0)]
	var total_width: float = 92.0 + 96.0 + 100.0 + 12.0
	var command_x: float = safe_rect.get_center().x - total_width * ui_scale * 0.5
	for index in range(3):
		_place(
			_action_buttons[index + 3],
			Vector2(command_x, bottom - 364.0 * ui_scale),
			command_sizes[index],
			ui_scale
		)
		command_x += (command_sizes[index].x + 6.0) * ui_scale


func _layout_landscape_controls(safe_rect: Rect2, ui_scale: float, margin: float) -> void:
	var bottom: float = safe_rect.end.y - margin
	var stick_size := Vector2(190.0, 190.0)
	var attack_size := Vector2(164.0, 164.0)
	_place(
		_stick,
		Vector2(safe_rect.position.x + margin, bottom - stick_size.y * ui_scale),
		stick_size,
		ui_scale
	)
	var attack_position := Vector2(
		safe_rect.end.x - margin - attack_size.x * ui_scale, bottom - attack_size.y * ui_scale
	)
	_place(_action_buttons[0], attack_position, attack_size, ui_scale)
	_place(
		_action_buttons[1],
		Vector2(attack_position.x - 132.0 * ui_scale, bottom - 116.0 * ui_scale),
		Vector2(116.0, 54.0),
		ui_scale
	)
	_place(
		_action_buttons[2],
		Vector2(attack_position.x - 132.0 * ui_scale, bottom - 54.0 * ui_scale),
		Vector2(116.0, 54.0),
		ui_scale
	)
	var production_size := Vector2(350.0, 100.0)
	_place(
		_production_panel,
		Vector2(
			safe_rect.get_center().x - production_size.x * ui_scale * 0.5,
			bottom - production_size.y * ui_scale
		),
		production_size,
		ui_scale
	)
	var command_sizes := [Vector2(92.0, 52.0), Vector2(96.0, 52.0), Vector2(100.0, 52.0)]
	var command_x: float = (
		_production_panel.position.x - (92.0 + 96.0 + 100.0 + 12.0) * ui_scale - 12.0 * ui_scale
	)
	command_x = maxf(command_x, _stick.position.x + stick_size.x * ui_scale + 10.0 * ui_scale)
	for index in range(3):
		_place(
			_action_buttons[index + 3],
			Vector2(command_x, bottom - 52.0 * ui_scale),
			command_sizes[index],
			ui_scale
		)
		command_x += (command_sizes[index].x + 6.0) * ui_scale


func _layout_state_panel(safe_rect: Rect2) -> void:
	var available := Vector2(
		maxf(safe_rect.size.x - SAFE_MARGIN * 2.0, 280.0),
		maxf(safe_rect.size.y - SAFE_MARGIN * 2.0, 220.0)
	)
	var target := Vector2(minf(520.0, available.x), minf(300.0, available.y))
	_state_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_state_panel.scale = Vector2.ONE
	_state_panel.size = target
	_state_panel.position = (safe_rect.position + (safe_rect.size - target) * 0.5).floor()


func _place(control: Control, position: Vector2, size: Vector2, ui_scale: float) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.scale = Vector2.ONE * ui_scale
	control.size = size
	control.position = position.floor()


func _is_portrait() -> bool:
	var safe_rect := MainMenuLayoutGuard._get_logical_safe_rect(get_viewport())
	return safe_rect.size.y > safe_rect.size.x * 1.08


func _panel_style(background: Color, border: Color = Color(0.95, 0.72, 0.16, 0.82)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style
