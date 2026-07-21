extends Node
## Persistent key rebinding for gameplay actions.
##
## Captures the project's default bindings at boot, then layers stored player
## overrides on top of them in the InputMap. Only the primary keyboard key of
## each managed action is rebindable; secondary bindings (arrow keys, gamepad)
## from the project defaults are preserved.

signal bindings_changed

const SETTINGS_PATH: String = "user://input_bindings.cfg"

const MANAGED_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"attack_command",
	&"rally_command",
	&"gather_command",
	&"split_command",
	&"spread_command",
	&"merge_command",
]
const ACTION_LABELS: Dictionary = {
	&"move_up": "Yukarı git",
	&"move_down": "Aşağı git",
	&"move_left": "Sola git",
	&"move_right": "Sağa git",
	&"attack_command": "Saldır",
	&"rally_command": "Topla (rally)",
	&"gather_command": "Kaynak topla",
	&"split_command": "Böl",
	&"spread_command": "Yay",
	&"merge_command": "Birleştir",
}

var _defaults: Dictionary = {}
var _overrides: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_defaults()
	_load()
	apply_all()


func get_action_labels() -> Dictionary:
	return ACTION_LABELS.duplicate(true)


func get_primary_keycode(action: StringName) -> int:
	if not InputMap.has_action(action):
		return -1
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return -1


func get_key_label(action: StringName) -> String:
	var keycode: int = get_primary_keycode(action)
	if keycode <= 0:
		return "—"
	var label: String = OS.get_keycode_string(keycode)
	return label if not label.is_empty() else "?"


func rebind(action: StringName, physical_keycode: int) -> void:
	if not MANAGED_ACTIONS.has(action) or physical_keycode <= 0:
		return
	var previous_keycode: int = get_primary_keycode(action)
	var conflicting_action: StringName = _find_action_using(physical_keycode, action)
	if conflicting_action != &"" and previous_keycode > 0:
		_overrides[conflicting_action] = previous_keycode
	_overrides[action] = physical_keycode
	_save()
	apply_all()
	bindings_changed.emit()


func reset_action(action: StringName) -> void:
	if not MANAGED_ACTIONS.has(action):
		return
	_overrides.erase(action)
	_save()
	apply_all()
	bindings_changed.emit()


func reset_all() -> void:
	_overrides.clear()
	_save()
	apply_all()
	bindings_changed.emit()


func apply_all() -> void:
	for action in MANAGED_ACTIONS:
		_apply_action(action)


func _apply_action(action: StringName) -> void:
	if not _defaults.has(action) or not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	var override_keycode: int = int(_overrides.get(action, -1))
	var replaced: bool = false
	for event in _defaults[action]:
		if override_keycode > 0 and not replaced and event is InputEventKey:
			var rebound := InputEventKey.new()
			rebound.physical_keycode = override_keycode
			InputMap.action_add_event(action, rebound)
			replaced = true
		else:
			InputMap.action_add_event(action, (event as InputEvent).duplicate())


func _capture_defaults() -> void:
	for action in MANAGED_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			events.append(event.duplicate())
		_defaults[action] = events


func _find_action_using(physical_keycode: int, exclude: StringName) -> StringName:
	for action in MANAGED_ACTIONS:
		if action == exclude:
			continue
		if get_primary_keycode(action) == physical_keycode:
			return action
	return &""


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for action in MANAGED_ACTIONS:
		var key: String = String(action)
		if config.has_section_key("bindings", key):
			var keycode: int = int(config.get_value("bindings", key, -1))
			if keycode > 0:
				_overrides[action] = keycode


func _save() -> void:
	var config := ConfigFile.new()
	for action in _overrides:
		config.set_value("bindings", String(action), int(_overrides[action]))
	config.save(SETTINGS_PATH)
