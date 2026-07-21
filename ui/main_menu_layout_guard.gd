class_name MainMenuLayoutGuard
extends Node

const OUTER_MARGIN: float = 18.0
const MIN_PANEL_SIZE := Vector2(300.0, 240.0)

var _preferred_sizes: Dictionary = {}
var _last_signature: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var viewport := get_viewport()
	if not viewport.size_changed.is_connected(_request_layout):
		viewport.size_changed.connect(_request_layout)
	var root := get_parent() as Control
	if is_instance_valid(root) and not root.child_entered_tree.is_connected(_on_child_entered):
		root.child_entered_tree.connect(_on_child_entered)
	call_deferred("_apply_layout")


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport.size_changed.is_connected(_request_layout):
		viewport.size_changed.disconnect(_request_layout)
	var root := get_parent() as Control
	if is_instance_valid(root) and root.child_entered_tree.is_connected(_on_child_entered):
		root.child_entered_tree.disconnect(_on_child_entered)


func _process(_delta: float) -> void:
	var signature := _layout_signature()
	if signature == _last_signature:
		return
	_last_signature = signature
	_apply_layout()


func _on_child_entered(_child: Node) -> void:
	call_deferred("_apply_layout")


func _request_layout() -> void:
	call_deferred("_apply_layout")


func _apply_layout() -> void:
	var root := get_parent() as Control
	if not is_instance_valid(root):
		return
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe_rect := _get_logical_safe_rect(get_viewport())
	if safe_rect.size.x <= 1.0 or safe_rect.size.y <= 1.0:
		return
	var available := Vector2(
		maxf(safe_rect.size.x - OUTER_MARGIN * 2.0, MIN_PANEL_SIZE.x),
		maxf(safe_rect.size.y - OUTER_MARGIN * 2.0, MIN_PANEL_SIZE.y)
	)
	for child in root.get_children():
		if not child is PanelContainer:
			continue
		var panel := child as PanelContainer
		if not _preferred_sizes.has(panel.get_instance_id()):
			var preferred := panel.size
			if preferred.x <= 1.0 or preferred.y <= 1.0:
				preferred = panel.custom_minimum_size
			_preferred_sizes[panel.get_instance_id()] = preferred.max(MIN_PANEL_SIZE)
		if not panel.visible:
			continue
		var preferred: Vector2 = _preferred_sizes[panel.get_instance_id()]
		var target := Vector2(minf(preferred.x, available.x), minf(preferred.y, available.y))
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.scale = Vector2.ONE
		panel.custom_minimum_size = Vector2.ZERO
		panel.size = target
		panel.position = safe_rect.position + (safe_rect.size - target) * 0.5
		panel.position = panel.position.floor()


func _layout_signature() -> String:
	var root := get_parent() as Control
	if not is_instance_valid(root):
		return ""
	var viewport_size := get_viewport().get_visible_rect().size
	var visible_panels: PackedStringArray = PackedStringArray()
	for child in root.get_children():
		if child is PanelContainer and child.visible:
			visible_panels.append(str(child.get_instance_id()))
	return "%s:%s:%s" % [viewport_size.x, viewport_size.y, ",".join(visible_panels)]


static func _get_logical_safe_rect(viewport: Viewport) -> Rect2:
	var viewport_size := viewport.get_visible_rect().size
	var full_rect := Rect2(Vector2.ZERO, viewport_size)
	if not OS.has_feature("mobile"):
		return full_rect
	var screen_size := DisplayServer.screen_get_size()
	var safe_area := DisplayServer.get_display_safe_area()
	if screen_size.x <= 0 or screen_size.y <= 0 or safe_area.size == Vector2i.ZERO:
		return full_rect
	var scale_to_viewport := Vector2(
		viewport_size.x / float(screen_size.x), viewport_size.y / float(screen_size.y)
	)
	var logical_safe := Rect2(
		Vector2(safe_area.position) * scale_to_viewport, Vector2(safe_area.size) * scale_to_viewport
	)
	return logical_safe.intersection(full_rect)
