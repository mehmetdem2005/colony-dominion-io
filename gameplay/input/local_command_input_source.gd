class_name LocalCommandInputSource
extends RefCounted

var _request_command: Callable
var _tick_interval_provider: Callable
var _clear_movement: Callable
var _cancel_gesture: Callable
var _enabled: bool = true
var _joystick := Vector2.ZERO
var _move_left: float = 0.0
var _last_sent_movement := Vector2.INF


func configure(
	request_command: Callable,
	tick_interval_provider: Callable,
	clear_movement: Callable,
	cancel_gesture: Callable = Callable()
) -> void:
	_request_command = request_command
	_tick_interval_provider = tick_interval_provider
	_clear_movement = clear_movement
	_cancel_gesture = cancel_gesture
	reset()


func advance(delta: float) -> void:
	if not _enabled:
		return
	if Input.is_action_just_pressed("attack_command"):
		_request(&"attack")
	if Input.is_action_just_pressed("rally_command"):
		_request(&"rally")
	if Input.is_action_just_pressed("gather_command"):
		_request(&"gather")
	if Input.is_action_just_pressed("split_command"):
		_request(&"split")
	if Input.is_action_just_pressed("spread_command"):
		_request(&"spread")
	if Input.is_action_just_pressed("merge_command"):
		_request(&"merge")

	_move_left -= maxf(delta, 0.0)
	if _move_left > 0.0:
		return
	_move_left = _get_tick_interval()
	var keyboard := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var movement: Vector2 = (
		keyboard.limit_length(1.0) if keyboard.length_squared() > 0.01 else _joystick
	)
	if movement.is_equal_approx(_last_sent_movement) and movement == Vector2.ZERO:
		return
	_last_sent_movement = movement
	_request(&"move", {"vector": movement})


func set_joystick(value: Vector2) -> void:
	_joystick = value.limit_length(1.0) if _enabled and value.is_finite() else Vector2.ZERO


func set_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return
	_enabled = enabled
	if not enabled:
		_joystick = Vector2.ZERO
		_last_sent_movement = Vector2.INF
		_move_left = 0.0
		if _clear_movement.is_valid():
			_clear_movement.call()
		if _cancel_gesture.is_valid():
			_cancel_gesture.call()


func is_enabled() -> bool:
	return _enabled


func reset() -> void:
	_enabled = true
	_joystick = Vector2.ZERO
	_move_left = 0.0
	_last_sent_movement = Vector2.INF


func _request(command_type: StringName, payload: Dictionary = {}) -> bool:
	if not _request_command.is_valid():
		return false
	return bool(_request_command.call(command_type, payload))


func _get_tick_interval() -> float:
	if not _tick_interval_provider.is_valid():
		return 1.0 / 20.0
	var interval: float = float(_tick_interval_provider.call())
	return maxf(interval, 0.001)
