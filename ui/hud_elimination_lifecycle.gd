class_name HudEliminationLifecycle
extends Node

const PANEL_SIZE := Vector2(520.0, 320.0)
const SAFE_MARGIN: float = 20.0

var _hud: ColonyHUD = null
var _overlay: Control = null
var _panel: PanelContainer = null
var _presented: bool = false
var _transition_requested: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud = get_parent() as ColonyHUD
	call_deferred("_build_overlay")
	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_apply_layout):
		viewport.size_changed.connect(_apply_layout)


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport.size_changed.is_connected(_apply_layout):
		viewport.size_changed.disconnect(_apply_layout)


func _process(_delta: float) -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_overlay):
		return
	if is_instance_valid(_hud.game_over_panel) and _hud.game_over_panel.visible:
		_overlay.visible = false
		return
	if _presented or not is_instance_valid(_hud.player_controller):
		return
	if not _hud.player_controller.eliminated:
		return
	_presented = true
	_overlay.visible = true
	_hud.modal_input_blocker.visible = true
	_hud.call("_set_gameplay_interaction_enabled", false)
	_apply_layout()


func _build_overlay() -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_hud.root_control):
		call_deferred("_build_overlay")
		return
	_overlay = Control.new()
	_overlay.name = "EliminationOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.z_index = 490
	_overlay.visible = false
	_hud.root_control.add_child(_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_overlay.add_child(_panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "ELENDİN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("ff685d"))
	box.add_child(title)

	var detail := Label.new()
	detail.text = "Yuvan ve komutanın yok edildi. Maçta kontrol edilebilir bir birimin kalmadı."
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 18)
	detail.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76, 1.0))
	box.add_child(detail)

	var restart := Button.new()
	restart.text = "YENİDEN OYNA"
	restart.custom_minimum_size = Vector2(300.0, 58.0)
	restart.pressed.connect(_restart_match)
	box.add_child(restart)

	var menu := Button.new()
	menu.text = "ANA MENÜ"
	menu.custom_minimum_size = Vector2(300.0, 54.0)
	menu.pressed.connect(_return_to_menu)
	box.add_child(menu)
	_apply_layout()


func _restart_match() -> void:
	if _transition_requested or not is_instance_valid(_hud.match_controller):
		return
	_transition_requested = true
	_hud.match_controller.restart_match()


func _return_to_menu() -> void:
	if _transition_requested or not is_instance_valid(_hud.match_controller):
		return
	_transition_requested = true
	_hud.match_controller.return_to_menu()


func _apply_layout() -> void:
	if not is_instance_valid(_panel):
		return
	var safe_rect := MainMenuLayoutGuard._get_logical_safe_rect(get_viewport())
	if safe_rect.size.x <= 1.0 or safe_rect.size.y <= 1.0:
		return
	var available := Vector2(
		maxf(safe_rect.size.x - SAFE_MARGIN * 2.0, 280.0),
		maxf(safe_rect.size.y - SAFE_MARGIN * 2.0, 240.0)
	)
	var target := Vector2(minf(PANEL_SIZE.x, available.x), minf(PANEL_SIZE.y, available.y))
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.size = target
	_panel.position = (safe_rect.position + (safe_rect.size - target) * 0.5).floor()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.03, 0.02, 0.98)
	style.border_color = Color(1.0, 0.40, 0.34, 0.96)
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	return style
