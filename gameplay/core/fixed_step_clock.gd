class_name FixedStepClock
extends RefCounted

const MAX_FRAME_DELTA: float = 0.25

var interval: float = 1.0 / 20.0
var max_steps_per_frame: int = 6
var accumulator: float = 0.0
var tick: int = 0
var dropped_time: float = 0.0


func _init(step_interval: float = 1.0 / 20.0, max_steps: int = 6) -> void:
	configure(step_interval, max_steps)


func configure(step_interval: float, max_steps: int) -> void:
	interval = step_interval if is_finite(step_interval) and step_interval > 0.0 else 1.0 / 20.0
	max_steps_per_frame = maxi(max_steps, 1)
	reset()


func advance(delta: float) -> int:
	if not is_finite(delta) or delta <= 0.0:
		return 0
	var accepted_delta: float = minf(delta, MAX_FRAME_DELTA)
	dropped_time += maxf(0.0, delta - accepted_delta)
	accumulator += accepted_delta
	var steps: int = 0
	while accumulator >= interval and steps < max_steps_per_frame:
		accumulator -= interval
		tick += 1
		steps += 1
	if accumulator >= interval:
		var retained: float = fmod(accumulator, interval)
		dropped_time += accumulator - retained
		accumulator = retained
	return steps


func get_interpolation_alpha() -> float:
	return clampf(accumulator / interval, 0.0, 1.0) if interval > 0.0 else 0.0


func reset(start_tick: int = 0) -> void:
	accumulator = 0.0
	tick = maxi(start_tick, 0)
	dropped_time = 0.0
