class_name OnlineMatchHUD
extends CanvasLayer

signal movement_changed(value: Vector2)
signal command_requested(command_type: StringName, payload: Dictionary)
signal exit_requested

var _root: Control
var _stick: ColonyVirtualStick
var _status_label: Label
var _resource_label: Label
var _army_label: Label
var _queue_label: Label
var _toast_label: Label
var _last_player_state: Dictionary = {}


func _ready() -> void:
	layer = 100
	_build_ui()
	NetworkSession.metrics_changed.connect(_refresh_status.unbind(3))
	NetworkSession.region_changed.connect(_refresh_status.unbind(2))
	NetworkSession.connection_state_changed.connect(_on_connection_state_changed)
	_refresh_status()


func _process(_delta: float) -> void:
	if is_instance_valid(_stick):
		movement_changed.emit(_stick.value)


func apply_player_state(state: Dictionary) -> void:
	_last_player_state = state.duplicate(true)
	var inventory_variant: Variant = state.get("inventory", {})
	var inventory: Dictionary = inventory_variant if inventory_variant is Dictionary else {}
	_resource_label.text = (
		"TOHUM %d  NEKTAR %d  PROTEİN %d  YAPRAK %d  TAŞ %d"
		% [
			int(inventory.get(&"seed", inventory.get("seed", 0))),
			int(inventory.get(&"nectar", inventory.get("nectar", 0))),
			int(inventory.get(&"protein", inventory.get("protein", 0))),
			int(inventory.get(&"leaf", inventory.get("leaf", 0))),
			int(inventory.get(&"stone", inventory.get("stone", 0))),
		]
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
				roundi(float(state.get("production_progress", 0.0)) * 100.0)
			]
		)


func show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_label.visible = true
	var tween: Tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(_toast_label, "modulate:a", 0.0, 0.35)
	tween.tween_callback(
		func() -> void:
			_toast_label.visible = false
			_toast_label.modulate.a = 1.0
	)


func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var top_panel := PanelContainer.new()
	top_panel.position = Vector2(16.0, 14.0)
	top_panel.size = Vector2(670.0, 88.0)
	_root.add_child(top_panel)
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 2)
	top_panel.add_child(top_box)
	_resource_label = _make_label("Kaynaklar yükleniyor", 18)
	_army_label = _make_label("Ordu yükleniyor", 18)
	_queue_label = _make_label("Üretim kuyruğu", 15)
	top_box.add_child(_resource_label)
	top_box.add_child(_army_label)
	top_box.add_child(_queue_label)

	_status_label = _make_label("BAĞLANIYOR", 18)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.position = Vector2(850.0, 18.0)
	_status_label.size = Vector2(410.0, 40.0)
	_root.add_child(_status_label)

	_stick = ColonyVirtualStick.new()
	_stick.position = Vector2(24.0, 492.0)
	_stick.size = Vector2(190.0, 190.0)
	_stick.radius = 78.0
	_root.add_child(_stick)

	var attack := _make_action("SALDIR", Vector2(1092.0, 528.0), Vector2(164.0, 164.0), true)
	attack.pressed.connect(func() -> void: command_requested.emit(&"attack", {}))
	var gather := _make_action("HASAT", Vector2(956.0, 574.0), Vector2(116.0, 54.0), false)
	gather.pressed.connect(func() -> void: command_requested.emit(&"gather", {}))
	var rally := _make_action("TOPLA", Vector2(956.0, 636.0), Vector2(116.0, 54.0), false)
	rally.pressed.connect(func() -> void: command_requested.emit(&"rally", {}))
	var split := _make_action("BÖL", Vector2(824.0, 634.0), Vector2(92.0, 52.0), false)
	split.pressed.connect(func() -> void: command_requested.emit(&"split", {}))
	var spread := _make_action("DAĞIT", Vector2(722.0, 634.0), Vector2(96.0, 52.0), false)
	spread.pressed.connect(func() -> void: command_requested.emit(&"spread", {}))
	var merge := _make_action("BİRLEŞ", Vector2(616.0, 634.0), Vector2(100.0, 52.0), false)
	merge.pressed.connect(func() -> void: command_requested.emit(&"merge", {}))

	var production_panel := PanelContainer.new()
	production_panel.position = Vector2(250.0, 588.0)
	production_panel.size = Vector2(350.0, 100.0)
	_root.add_child(production_panel)
	var production_grid := GridContainer.new()
	production_grid.columns = 3
	production_grid.add_theme_constant_override("h_separation", 4)
	production_grid.add_theme_constant_override("v_separation", 4)
	production_panel.add_child(production_grid)
	for unit_id in [&"worker", &"soldier", &"guard", &"scout", &"acid_ant"]:
		var definition: UnitDefinition = UnitCatalog.get_definition(unit_id)
		var unit_button := Button.new()
		unit_button.text = definition.display_name if definition != null else String(unit_id)
		unit_button.custom_minimum_size = Vector2(108.0, 42.0)
		unit_button.pressed.connect(_emit_production.bind(unit_id))
		production_grid.add_child(unit_button)
	var upgrade_button := Button.new()
	upgrade_button.text = "YUVA YÜKSELT"
	upgrade_button.custom_minimum_size = Vector2(108.0, 42.0)
	upgrade_button.pressed.connect(func() -> void: command_requested.emit(&"upgrade", {}))
	production_grid.add_child(upgrade_button)

	var exit_button := Button.new()
	exit_button.text = "MAÇTAN ÇIK"
	exit_button.position = Vector2(1090.0, 72.0)
	exit_button.size = Vector2(166.0, 48.0)
	exit_button.pressed.connect(exit_requested.emit)
	_root.add_child(exit_button)

	_toast_label = _make_label("", 22)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.position = Vector2(390.0, 150.0)
	_toast_label.size = Vector2(500.0, 54.0)
	_toast_label.visible = false
	_root.add_child(_toast_label)


func _emit_production(unit_id: StringName) -> void:
	command_requested.emit(&"produce", {"unit_id": unit_id})


func _make_action(
	text: String, position_value: Vector2, size_value: Vector2, circular: bool
) -> TouchActionButton:
	var button := TouchActionButton.new()
	button.configure(text, size_value, circular)
	button.position = position_value
	_root.add_child(button)
	return button


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
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
