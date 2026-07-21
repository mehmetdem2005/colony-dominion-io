class_name MainMenuModalVisibility
extends Node

var _main_panel: PanelContainer
var _last_modal_state: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := get_parent()
	if is_instance_valid(root) and not root.child_entered_tree.is_connected(_on_child_entered):
		root.child_entered_tree.connect(_on_child_entered)
	call_deferred("_refresh_references")


func _exit_tree() -> void:
	var root := get_parent()
	if is_instance_valid(root) and root.child_entered_tree.is_connected(_on_child_entered):
		root.child_entered_tree.disconnect(_on_child_entered)


func _process(_delta: float) -> void:
	if not is_instance_valid(_main_panel):
		_refresh_references()
	var modal_visible := _has_visible_modal()
	if modal_visible == _last_modal_state:
		return
	_last_modal_state = modal_visible
	if is_instance_valid(_main_panel):
		_main_panel.visible = not modal_visible
	_apply_backdrop(modal_visible)


func _on_child_entered(_child: Node) -> void:
	call_deferred("_refresh_references")


func _refresh_references() -> void:
	var root := get_parent()
	if not is_instance_valid(root):
		return
	_main_panel = null
	for child in root.get_children():
		if child is PanelContainer and not child.has_signal("closed"):
			_main_panel = child as PanelContainer
			break
	_last_modal_state = not _has_visible_modal()


func _has_visible_modal() -> bool:
	var root := get_parent()
	if not is_instance_valid(root):
		return false
	for child in root.get_children():
		if child is PanelContainer and child.has_signal("closed") and child.visible:
			return true
	return false


func _apply_backdrop(modal_visible: bool) -> void:
	var root := get_parent()
	if not is_instance_valid(root):
		return
	for child in root.get_children():
		if child is ColorRect:
			var backdrop := child as ColorRect
			if modal_visible and backdrop.visible:
				backdrop.color = Color(0.0, 0.0, 0.0, 0.88)
			return
