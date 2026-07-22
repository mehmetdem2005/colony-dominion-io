class_name ColonyHUD
extends MatchPresentationAdapter

const HUD_EVENT_BINDER_SCRIPT := preload("res://ui/hud_event_binder.gd")
const HUD_LAYOUT_CONTEXT_SCRIPT := preload("res://ui/hud_layout_context.gd")
const HUD_RESPONSIVE_LAYOUT_SCRIPT := preload("res://ui/hud_responsive_layout.gd")

const RESOURCE_INFO := {
	&"seed": {"texture": "res://assets/resources/seeds.png"},
	&"nectar": {"texture": "res://assets/resources/nectar.png"},
	&"protein": {"texture": "res://assets/resources/protein.png"},
	&"leaf": {"texture": "res://assets/resources/leaves.png"},
	&"stone": {"texture": "res://assets/resources/stone.png"},
}
const ROLE_LABELS := {
	&"worker": "TOPLAYICI",
	&"frontline": "ÖN HAT",
	&"tank": "AĞIR",
	&"flanker": "HIZLI",
	&"ranged": "MENZİLLİ",
}

var match_controller: MatchController
var player_controller: ColonyController
var _event_binder: HudEventBinder
var _layout_context: HudLayoutContext
var _responsive_layout: HudResponsiveLayout
var root_control: Control
var resources_panel: PanelContainer
var minimap_panel: PanelContainer
var leaderboard_panel: PanelContainer
var production_panel: PanelContainer
var resource_labels: Dictionary = {}
var leaderboard_box: VBoxContainer
var leaderboard_title: Label
var leaderboard_rows: Array[Label] = []
var minimap: ColonyMinimap
var timer_label: Label
var queue_label: Label
var queue_progress: ProgressBar
var level_label: Label
var toast_label: Label
var game_over_panel: PanelContainer
var result_label: Label
var stick: ColonyVirtualStick
var gather_button: TouchActionButton
var rally_button: TouchActionButton
var attack_button: TouchActionButton
var split_button: TouchActionButton
var spread_button: TouchActionButton
var merge_button: TouchActionButton
var upgrade_button: TouchActionButton
var audio_settings_button: Button
var audio_settings_panel: PanelContainer
var settings_button: Button
var settings_panel: SettingsPanel
var modal_input_blocker: Control
var production_cards: Array[ProductionTouchCard] = []
var _toast_left: float = 0.0
var _gameplay_interaction_enabled: bool = true
var _scene_transition_requested: bool = false


func _ready() -> void:
	layer = 100
	_event_binder = HUD_EVENT_BINDER_SCRIPT.new() as HudEventBinder
	_responsive_layout = HUD_RESPONSIVE_LAYOUT_SCRIPT.new() as HudResponsiveLayout
	_build_ui()
	_configure_layout_context()
	if not get_viewport().size_changed.is_connected(_apply_responsive_layout):
		get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")


func bind_match(match_node: Node, controller: Node) -> void:
	if _event_binder != null:
		_event_binder.unbind()
	match_controller = match_node as MatchController
	player_controller = controller as ColonyController
	if not is_instance_valid(match_controller) or not is_instance_valid(player_controller):
		push_error("ColonyHUD received an invalid match presentation binding")
		return
	if _event_binder != null:
		_event_binder.bind(match_controller.events, self)
	if not stick.vector_changed.is_connected(match_controller.request_local_movement):
		stick.vector_changed.connect(match_controller.request_local_movement)
	_on_inventory_changed(player_controller.team_id, player_controller.inventory.snapshot())
	_on_colony_progress_changed(
		player_controller.team_id,
		player_controller.progression.level,
		player_controller.get_unit_capacity(),
		player_controller.get_army_size(),
		player_controller.progression.get_next_upgrade_cost()
	)
	_on_squad_state_changed(player_controller.team_id, false)
	_on_formation_spread_changed(player_controller.team_id, false)
	_on_gather_state_changed(player_controller.team_id, false, 0, &"")
	if is_instance_valid(minimap):
		minimap.bind_match(match_controller)
	_apply_responsive_layout()


func _exit_tree() -> void:
	if _event_binder != null:
		_event_binder.unbind()


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left -= delta
	if _toast_left <= 0.0 and is_instance_valid(toast_label):
		toast_label.visible = false


func _build_ui() -> void:
	root_control = Control.new()
	root_control.name = "HUDRoot"
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_resources_panel()
	_build_leaderboard_panel()
	_build_minimap_panel()
	_build_timer()
	_build_modal_input_blocker()
	_build_audio_settings()
	_build_full_settings()
	_build_production_panel()
	_build_mobile_controls()
	_build_toast()
	_build_game_over()


func _build_resources_panel() -> void:
	resources_panel = PanelContainer.new()
	resources_panel.name = "ResourceDock"
	resources_panel.position = Vector2(14.0, 14.0)
	resources_panel.size = Vector2(142.0, 224.0)
	resources_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resources_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.02, 0.03, 0.02, 0.90), Color(0.38, 0.65, 0.18, 0.82), 16)
	)
	root_control.add_child(resources_panel)

	var resources_vbox := VBoxContainer.new()
	resources_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resources_vbox.add_theme_constant_override("separation", 1)
	resources_panel.add_child(resources_vbox)
	for resource_id in ColonyInventory.RESOURCE_IDS:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size = Vector2(120.0, 40.0)
		row.add_theme_constant_override("separation", 6)

		var icon_back := PanelContainer.new()
		icon_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_back.custom_minimum_size = Vector2(42.0, 38.0)
		icon_back.add_theme_stylebox_override(
			"panel", _badge_style(Color(0.13, 0.11, 0.055, 0.88), Color(0.72, 0.63, 0.26, 0.32), 9)
		)
		row.add_child(icon_back)

		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = load(String(RESOURCE_INFO[resource_id]["texture"])) as Texture2D
		icon.custom_minimum_size = Vector2(38.0, 34.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_back.add_child(icon)

		var amount_label := Label.new()
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amount_label.text = "0"
		amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.add_theme_font_size_override("font_size", 22)
		amount_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.84, 1.0))
		amount_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
		amount_label.add_theme_constant_override("shadow_offset_x", 1)
		amount_label.add_theme_constant_override("shadow_offset_y", 2)
		row.add_child(amount_label)
		resource_labels[resource_id] = amount_label
		resources_vbox.add_child(row)


func _build_leaderboard_panel() -> void:
	leaderboard_panel = PanelContainer.new()
	leaderboard_panel.anchor_left = 1.0
	leaderboard_panel.anchor_right = 1.0
	leaderboard_panel.offset_left = -262.0
	leaderboard_panel.offset_top = 16.0
	leaderboard_panel.offset_right = -16.0
	leaderboard_panel.offset_bottom = 238.0
	leaderboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaderboard_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.02, 0.03, 0.02, 0.84), Color(0.95, 0.72, 0.14, 0.64), 18)
	)
	root_control.add_child(leaderboard_panel)

	leaderboard_box = VBoxContainer.new()
	leaderboard_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaderboard_box.add_theme_constant_override("separation", 2)
	leaderboard_panel.add_child(leaderboard_box)

	leaderboard_title = Label.new()
	leaderboard_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leaderboard_title.text = "KOLONİ SIRALAMASI"
	leaderboard_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leaderboard_title.add_theme_font_size_override("font_size", 17)
	leaderboard_title.add_theme_color_override("font_color", Color("ffd447"))
	leaderboard_box.add_child(leaderboard_title)
	for index in 6:
		var row_label := Label.new()
		row_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_label.text = "%d. ---" % (index + 1)
		row_label.add_theme_font_size_override("font_size", 15)
		row_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.76, 1.0))
		row_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		leaderboard_box.add_child(row_label)
		leaderboard_rows.append(row_label)


func _build_minimap_panel() -> void:
	minimap_panel = PanelContainer.new()
	minimap_panel.name = "MinimapDock"
	minimap_panel.position = Vector2(164.0, 14.0)
	minimap_panel.size = Vector2(224.0, 224.0)
	minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.02, 0.03, 0.02, 0.94), Color(0.95, 0.72, 0.14, 0.82), 16)
	)
	root_control.add_child(minimap_panel)

	minimap = ColonyMinimap.new()
	minimap.custom_minimum_size = Vector2(204.0, 204.0)
	minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	minimap_panel.add_child(minimap)


func _build_timer() -> void:
	timer_label = Label.new()
	timer_label.anchor_left = 0.5
	timer_label.anchor_right = 0.5
	timer_label.offset_left = -76.0
	timer_label.offset_top = 16.0
	timer_label.offset_right = 76.0
	timer_label.offset_bottom = 60.0
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.text = "20:00"
	timer_label.add_theme_font_size_override("font_size", 26)
	timer_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.86, 1.0))
	timer_label.add_theme_stylebox_override(
		"normal", _panel_style(Color(0.03, 0.03, 0.03, 0.80), Color(1.0, 0.76, 0.12, 0.70), 15)
	)
	root_control.add_child(timer_label)


func _build_modal_input_blocker() -> void:
	modal_input_blocker = Control.new()
	modal_input_blocker.name = "ModalInputBlocker"
	modal_input_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_input_blocker.z_index = 370
	modal_input_blocker.visible = false
	modal_input_blocker.gui_input.connect(_on_modal_blocker_gui_input)
	root_control.add_child(modal_input_blocker)


func _on_modal_blocker_gui_input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _build_audio_settings() -> void:
	audio_settings_button = Button.new()
	audio_settings_button.name = "AudioSettingsButton"
	audio_settings_button.position = Vector2(398.0, 14.0)
	audio_settings_button.size = Vector2(90.0, 44.0)
	audio_settings_button.text = "SES"
	audio_settings_button.add_theme_font_size_override("font_size", 16)
	audio_settings_button.add_theme_stylebox_override(
		"normal", _panel_style(Color(0.03, 0.035, 0.025, 0.94), Color(0.82, 0.66, 0.20, 0.82), 13)
	)
	audio_settings_button.pressed.connect(_on_audio_settings_pressed)
	root_control.add_child(audio_settings_button)

	audio_settings_panel = PanelContainer.new()
	audio_settings_panel.name = "AudioSettingsPanel"
	audio_settings_panel.position = Vector2(400.0, 66.0)
	audio_settings_panel.size = Vector2(348.0, 326.0)
	audio_settings_panel.z_index = 380
	audio_settings_panel.visible = false
	audio_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	audio_settings_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.025, 0.028, 0.02, 0.98), Color(0.95, 0.72, 0.16, 0.92), 18)
	)
	root_control.add_child(audio_settings_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	audio_settings_panel.add_child(box)

	var title := Label.new()
	title.text = "SES AYARLARI"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("ffd447"))
	box.add_child(title)

	_create_audio_slider_row(box, "Ana ses", &"master")
	_create_audio_slider_row(box, "Müzik", &"music")
	_create_audio_slider_row(box, "Efekt", &"sfx")
	_create_audio_slider_row(box, "Çevre", &"ambient")
	_create_audio_slider_row(box, "Arayüz", &"ui")
	_create_audio_toggle(box, "Titreşim", &"vibration")
	_create_audio_toggle(box, "Arka planda sesi kapat", &"mute_background")

	var close_button := Button.new()
	close_button.text = "KAPAT"
	close_button.custom_minimum_size = Vector2(0.0, 40.0)
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.pressed.connect(_close_audio_settings)
	box.add_child(close_button)


func _create_audio_slider_row(
	parent: VBoxContainer, label_text: String, setting_id: StringName
) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 40.0)
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(92.0, 36.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.94, 0.91, 0.78, 1.0))
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "Audio_%s" % String(setting_id)
	slider.custom_minimum_size = Vector2(210.0, 36.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(AudioSystem.get_setting(setting_id))
	slider.value_changed.connect(_on_audio_volume_changed.bind(setting_id))
	row.add_child(slider)


func _create_audio_toggle(
	parent: VBoxContainer, label_text: String, setting_id: StringName
) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.custom_minimum_size = Vector2(0.0, 34.0)
	toggle.button_pressed = bool(AudioSystem.get_setting(setting_id))
	toggle.add_theme_font_size_override("font_size", 15)
	toggle.toggled.connect(_on_audio_toggle_changed.bind(setting_id))
	parent.add_child(toggle)


func _build_production_panel() -> void:
	production_panel = PanelContainer.new()
	production_panel.name = "ProductionDock"
	production_panel.anchor_left = 0.5
	production_panel.anchor_top = 1.0
	production_panel.anchor_right = 0.5
	production_panel.anchor_bottom = 1.0
	production_panel.offset_left = -346.0
	production_panel.offset_top = -166.0
	production_panel.offset_right = 316.0
	production_panel.offset_bottom = -10.0
	production_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	production_panel.z_index = 30
	production_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.045, 0.038, 0.025, 0.95), Color(0.95, 0.72, 0.16, 0.90), 16)
	)
	root_control.add_child(production_panel)

	var production_vbox := VBoxContainer.new()
	production_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	production_vbox.add_theme_constant_override("separation", 4)
	production_panel.add_child(production_vbox)

	var cards := HBoxContainer.new()
	cards.name = "ProductionCards"
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 8)
	production_vbox.add_child(cards)
	for unit_id in UnitCatalog.get_producible_ids():
		var definition := UnitCatalog.get_definition(unit_id)
		if definition == null:
			continue
		var card := _create_production_button(definition)
		card.pressed.connect(_on_produce_pressed.bind(unit_id))
		cards.add_child(card)
		production_cards.append(card)

	var status_row := HBoxContainer.new()
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.custom_minimum_size = Vector2(0.0, 28.0)
	status_row.add_theme_constant_override("separation", 7)
	production_vbox.add_child(status_row)

	level_label = Label.new()
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.text = "YUVA 1 • 4/18"
	level_label.custom_minimum_size = Vector2(126.0, 28.0)
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override("font_color", Color("ffd447"))
	status_row.add_child(level_label)

	queue_label = Label.new()
	queue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_label.text = "Kuyruk boş"
	queue_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	queue_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	queue_label.add_theme_font_size_override("font_size", 13)
	queue_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.70, 1.0))
	status_row.add_child(queue_label)

	queue_progress = ProgressBar.new()
	queue_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_progress.custom_minimum_size = Vector2(94.0, 16.0)
	queue_progress.max_value = 1.0
	queue_progress.show_percentage = false
	status_row.add_child(queue_progress)

	upgrade_button = _command_button("YÜKSELT", Vector2(88.0, 34.0), false)
	status_row.add_child(upgrade_button)
	upgrade_button.pressed.connect(_on_upgrade_pressed)


func _create_production_button(definition: UnitDefinition) -> ProductionTouchCard:
	var card := ProductionTouchCard.new()
	card.name = "Produce_%s" % String(definition.unit_id)
	var role_label: String = String(ROLE_LABELS.get(definition.role, "BİRİM"))
	card.configure(definition.texture, definition.display_name, role_label, definition.get_cost())
	return card


func _build_mobile_controls() -> void:
	stick = ColonyVirtualStick.new()
	stick.configure(78.0, 31.0)
	stick.anchor_top = 1.0
	stick.anchor_bottom = 1.0
	stick.offset_left = 20.0
	stick.offset_top = -190.0
	stick.offset_right = 176.0
	stick.offset_bottom = -34.0
	root_control.add_child(stick)

	split_button = _command_button("BÖL", Vector2(104.0, 50.0), false)
	_position_bottom_right(split_button, -340.0, -244.0, -236.0, -194.0)
	root_control.add_child(split_button)
	split_button.pressed.connect(_on_split_pressed)

	spread_button = _command_button("DAĞIT", Vector2(104.0, 50.0), false)
	_position_bottom_right(spread_button, -230.0, -244.0, -126.0, -194.0)
	root_control.add_child(spread_button)
	spread_button.pressed.connect(_on_spread_pressed)

	merge_button = _command_button("BİRLEŞ", Vector2(110.0, 50.0), false)
	_position_bottom_right(merge_button, -120.0, -244.0, -10.0, -194.0)
	root_control.add_child(merge_button)
	merge_button.pressed.connect(_on_merge_pressed)

	gather_button = _command_button("HASAT", Vector2(112.0, 58.0), false)
	_position_bottom_right(gather_button, -310.0, -180.0, -198.0, -122.0)
	root_control.add_child(gather_button)
	gather_button.pressed.connect(_on_gather_pressed)

	rally_button = _command_button("GERİ ÇAĞIR", Vector2(112.0, 58.0), false)
	_position_bottom_right(rally_button, -310.0, -114.0, -198.0, -56.0)
	root_control.add_child(rally_button)
	rally_button.pressed.connect(_on_rally_pressed)

	attack_button = _command_button("SALDIR", Vector2(162.0, 162.0), true)
	_position_bottom_right(attack_button, -180.0, -184.0, -18.0, -22.0)
	root_control.add_child(attack_button)
	attack_button.pressed.connect(_on_attack_pressed)


func _position_bottom_right(
	control: Control, left: float, top: float, right: float, bottom: float
) -> void:
	control.anchor_left = 1.0
	control.anchor_top = 1.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


func _build_toast() -> void:
	toast_label = Label.new()
	toast_label.anchor_left = 0.5
	toast_label.anchor_top = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_bottom = 0.5
	toast_label.offset_left = -250.0
	toast_label.offset_top = -128.0
	toast_label.offset_right = 250.0
	toast_label.offset_bottom = -72.0
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 20)
	toast_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.68, 1.0))
	toast_label.add_theme_stylebox_override(
		"normal", _panel_style(Color(0.02, 0.02, 0.02, 0.90), Color(1.0, 0.75, 0.14, 0.74), 16)
	)
	toast_label.visible = false
	toast_label.z_index = 300
	root_control.add_child(toast_label)


func _build_game_over() -> void:
	game_over_panel = PanelContainer.new()
	game_over_panel.anchor_left = 0.5
	game_over_panel.anchor_top = 0.5
	game_over_panel.anchor_right = 0.5
	game_over_panel.anchor_bottom = 0.5
	game_over_panel.offset_left = -260.0
	game_over_panel.offset_top = -160.0
	game_over_panel.offset_right = 260.0
	game_over_panel.offset_bottom = 160.0
	game_over_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.035, 0.03, 0.02, 0.97), Color(1.0, 0.76, 0.15, 0.96), 24)
	)
	game_over_panel.visible = false
	game_over_panel.z_index = 500
	root_control.add_child(game_over_panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	game_over_panel.add_child(box)

	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 34)
	box.add_child(result_label)

	var restart := Button.new()
	restart.text = "YENİDEN OYNA"
	restart.custom_minimum_size = Vector2(300.0, 58.0)
	restart.pressed.connect(_on_restart_pressed)
	box.add_child(restart)

	var menu := Button.new()
	menu.text = "ANA MENÜ"
	menu.custom_minimum_size = Vector2(300.0, 52.0)
	menu.pressed.connect(_on_menu_pressed)
	box.add_child(menu)


func _command_button(
	text_value: String, size_value: Vector2, is_circular: bool
) -> TouchActionButton:
	var button := TouchActionButton.new()
	button.configure(text_value, size_value, is_circular)
	return button


func _on_attack_pressed() -> void:
	_execute_command(&"attack", &"command_attack", 34, 0.62)


func _on_gather_pressed() -> void:
	_execute_command(&"gather", &"command_gather", 24, 0.42)


func _on_rally_pressed() -> void:
	_execute_command(&"rally", &"command_rally", 26, 0.44)


func _on_split_pressed() -> void:
	_execute_command(&"split", &"command_split", 20, 0.36)


func _on_spread_pressed() -> void:
	_execute_command(&"spread", &"command_spread", 20, 0.36)


func _on_merge_pressed() -> void:
	_execute_command(&"merge", &"command_merge", 20, 0.36)


func _on_upgrade_pressed() -> void:
	if not is_instance_valid(match_controller):
		return
	var accepted: bool = match_controller.request_local_command(&"upgrade")
	if not accepted:
		AudioSystem.play_ui(&"ui_invalid")


func _on_restart_pressed() -> void:
	if _scene_transition_requested:
		return
	_scene_transition_requested = true
	game_over_panel.visible = false
	modal_input_blocker.visible = false
	_set_gameplay_interaction_enabled(true)
	if is_instance_valid(match_controller):
		match_controller.restart_match()


func _on_menu_pressed() -> void:
	if _scene_transition_requested:
		return
	_scene_transition_requested = true
	_set_gameplay_interaction_enabled(false)
	if is_instance_valid(match_controller):
		match_controller.return_to_menu()


func _on_produce_pressed(unit_id: StringName) -> void:
	if not is_instance_valid(match_controller):
		return
	var accepted: bool = match_controller.request_local_command(&"produce", {"unit_id": unit_id})
	if not accepted:
		AudioSystem.play_ui(&"ui_invalid")


func _execute_command(
	command_id: StringName, audio_event: StringName, haptic_ms: int, haptic_strength: float
) -> void:
	if not is_instance_valid(match_controller):
		return
	var accepted: bool = match_controller.request_local_command(command_id)
	AudioSystem.play_ui(audio_event if accepted else &"ui_invalid")
	if accepted:
		AudioSystem.request_haptic(haptic_ms, haptic_strength)


func _on_audio_settings_pressed() -> void:
	AudioSystem.play_ui(&"ui_press")
	var will_open: bool = not audio_settings_panel.visible
	audio_settings_panel.visible = will_open
	modal_input_blocker.visible = will_open or game_over_panel.visible
	_set_gameplay_interaction_enabled(not will_open and not game_over_panel.visible)
	_apply_responsive_layout()


func _close_audio_settings() -> void:
	if not is_instance_valid(audio_settings_panel) or not audio_settings_panel.visible:
		return
	AudioSystem.play_ui(&"ui_press", {"intensity": 0.72})
	audio_settings_panel.visible = false
	modal_input_blocker.visible = game_over_panel.visible
	_set_gameplay_interaction_enabled(not game_over_panel.visible)


func _on_audio_volume_changed(value: float, setting_id: StringName) -> void:
	AudioSystem.set_volume(setting_id, value)


func _on_audio_toggle_changed(enabled: bool, setting_id: StringName) -> void:
	AudioSystem.set_toggle(setting_id, enabled)
	AudioSystem.play_ui(&"ui_press", {"intensity": 0.72})


func _build_full_settings() -> void:
	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	settings_button.position = Vector2(500.0, 14.0)
	settings_button.size = Vector2(96.0, 44.0)
	settings_button.text = "AYAR"
	settings_button.add_theme_font_size_override("font_size", 16)
	settings_button.add_theme_stylebox_override(
		"normal", _panel_style(Color(0.03, 0.035, 0.025, 0.94), Color(0.82, 0.66, 0.20, 0.82), 13)
	)
	settings_button.pressed.connect(_on_settings_button_pressed)
	root_control.add_child(settings_button)

	settings_panel = SettingsPanel.new()
	settings_panel.name = "FullSettingsPanel"
	settings_panel.z_index = 400
	settings_panel.closed.connect(_on_settings_panel_closed)
	root_control.add_child(settings_panel)


func _on_settings_button_pressed() -> void:
	AudioSystem.play_ui(&"ui_press")
	_close_audio_settings()
	modal_input_blocker.visible = true
	_set_gameplay_interaction_enabled(false)
	settings_panel.open_panel()


func _on_settings_panel_closed() -> void:
	modal_input_blocker.visible = game_over_panel.visible
	_set_gameplay_interaction_enabled(not game_over_panel.visible)


func _on_inventory_changed(team_id: int, inventory: Dictionary) -> void:
	if not is_instance_valid(player_controller) or team_id != player_controller.team_id:
		return
	for resource_id in resource_labels:
		var amount_label := resource_labels[resource_id] as Label
		if amount_label != null:
			amount_label.text = str(int(inventory.get(resource_id, 0)))


func _on_colony_progress_changed(
	team_id: int, level: int, capacity: int, army_size: int, _next_cost: Dictionary
) -> void:
	if not is_instance_valid(player_controller) or team_id != player_controller.team_id:
		return
	level_label.text = "YUVA %d • %d/%d" % [level, army_size, capacity]
	var nest_active: bool = (
		is_instance_valid(player_controller.nest) and player_controller.nest.is_alive()
	)
	var can_upgrade: bool = nest_active and level < ColonyProgression.MAX_LEVEL
	upgrade_button.set_enabled(can_upgrade)
	upgrade_button.set_label_text(
		"YÜKSELT" if can_upgrade else ("YUVA YOK" if not nest_active else "MAKS.")
	)


func _on_squad_state_changed(team_id: int, split_mode: bool) -> void:
	if not is_instance_valid(player_controller) or team_id != player_controller.team_id:
		return
	split_button.set_enabled(not split_mode)
	merge_button.set_enabled(split_mode)


func _on_formation_spread_changed(team_id: int, spread_mode: bool) -> void:
	if not is_instance_valid(player_controller) or team_id != player_controller.team_id:
		return
	spread_button.set_label_text("SIKILAŞ" if spread_mode else "DAĞIT")


func _on_gather_state_changed(
	team_id: int, active: bool, seconds_left: int, _resource_id: StringName
) -> void:
	if not is_instance_valid(player_controller) or team_id != player_controller.team_id:
		return
	gather_button.set_label_text("HASAT %d" % seconds_left if active else "HASAT")
	gather_button.set_enabled(not active)


func _on_leaderboard_changed(entries: Array) -> void:
	for index in leaderboard_rows.size():
		var row_label: Label = leaderboard_rows[index]
		if index >= entries.size():
			row_label.text = "%d. ---" % (index + 1)
			row_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52, 1.0))
			continue
		var entry: Dictionary = entries[index]
		row_label.text = (
			"%d. %s     %d%s"
			% [
				index + 1,
				String(entry.get("name", "Colony")),
				int(entry.get("score", 0)),
				"  ELENDİ" if bool(entry.get("eliminated", false)) else ""
			]
		)
		var row_color: Color = entry.get("team_color", Color.WHITE)
		row_label.add_theme_color_override("font_color", row_color)


func _on_match_time_changed(seconds_left: int) -> void:
	var minutes: int = floori(float(seconds_left) / 60.0)
	var seconds: int = seconds_left % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]


func _on_production_queue_changed(team_id: int, queue: Array, progress: float) -> void:
	if not is_instance_valid(player_controller) or team_id != player_controller.team_id:
		return
	queue_progress.value = progress
	if queue.is_empty():
		queue_label.text = "Kuyruk boş"
		return
	var definition := UnitCatalog.get_definition(StringName(queue[0]))
	if definition != null:
		queue_label.text = "%s • %d sırada" % [definition.display_name, queue.size()]
	else:
		queue_label.text = "Geçersiz üretim kaydı temizleniyor"


func _show_toast(message: String) -> void:
	toast_label.text = message
	toast_label.visible = true
	_toast_left = 2.2


func _on_match_ended(winner_name: String, player_won: bool) -> void:
	audio_settings_panel.visible = false
	modal_input_blocker.visible = true
	_set_gameplay_interaction_enabled(false)
	result_label.text = ("ZAFER\n" if player_won else "MAĞLUBİYET\n") + winner_name
	result_label.add_theme_color_override(
		"font_color", Color("ffd447") if player_won else Color("ff685d")
	)
	game_over_panel.visible = true


func get_world_safe_frame_insets() -> Vector4:
	if _responsive_layout == null:
		return Vector4(24.0, 72.0, 24.0, 190.0)
	return _responsive_layout.get_world_safe_frame_insets(_layout_context)


func _apply_responsive_layout() -> void:
	if _responsive_layout == null or _layout_context == null:
		return
	var insets: Vector4 = _responsive_layout.apply(_layout_context)
	safe_frame_insets_changed.emit(insets)


func _configure_layout_context() -> void:
	_layout_context = HUD_LAYOUT_CONTEXT_SCRIPT.new() as HudLayoutContext
	_layout_context.viewport = get_viewport()
	_layout_context.root_control = root_control
	_layout_context.resources_panel = resources_panel
	_layout_context.minimap_panel = minimap_panel
	_layout_context.leaderboard_panel = leaderboard_panel
	_layout_context.production_panel = production_panel
	_layout_context.timer_label = timer_label
	_layout_context.audio_settings_button = audio_settings_button
	_layout_context.audio_settings_panel = audio_settings_panel
	_layout_context.stick = stick
	_layout_context.gather_button = gather_button
	_layout_context.rally_button = rally_button
	_layout_context.attack_button = attack_button
	_layout_context.split_button = split_button
	_layout_context.spread_button = spread_button
	_layout_context.merge_button = merge_button
	_layout_context.toast_label = toast_label
	_layout_context.game_over_panel = game_over_panel


func _set_gameplay_interaction_enabled(value: bool) -> void:
	if _gameplay_interaction_enabled == value:
		return
	_gameplay_interaction_enabled = value
	if is_instance_valid(match_controller):
		match_controller.set_local_input_enabled(value)
	if is_instance_valid(stick):
		stick.set_interaction_enabled(value)
	for button in [
		gather_button,
		rally_button,
		attack_button,
		split_button,
		spread_button,
		merge_button,
		upgrade_button,
	]:
		if is_instance_valid(button):
			button.set_interaction_enabled(value)
	for card in production_cards:
		if is_instance_valid(card):
			card.set_interaction_enabled(value)


func _badge_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	style.anti_aliasing = true
	return style


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.anti_aliasing = true
	return style
