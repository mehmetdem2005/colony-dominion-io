class_name SwarmSimulationScheduler
extends RefCounted

const BUCKET_COUNT: int = 3
const TICK_INTERVAL: float = 1.0 / 20.0
const BUCKET_PHASE_INTERVAL: float = TICK_INTERVAL / float(BUCKET_COUNT)
const MAX_BACKLOG: float = TICK_INTERVAL * 3.0
const MAX_BUCKET_STEPS_PER_FRAME: int = 6
const TICK_EPSILON: float = 0.00001

var _buckets: Array = [[], [], []]
var _bucket_elapsed := PackedFloat32Array([0.0, 0.0, 0.0])
var _bucket_cursor: int = 0
var _simulation_step_count: int = 0
var _dropped_time: float = 0.0


func configure(team_id: int) -> void:
	_buckets = [[], [], []]
	_bucket_elapsed = PackedFloat32Array([0.0, 0.0, 0.0])
	for slot in range(BUCKET_COUNT):
		var phase_slot: int = posmod(slot + team_id, BUCKET_COUNT)
		_bucket_elapsed[slot] = float(phase_slot) * BUCKET_PHASE_INTERVAL
	_bucket_cursor = posmod(team_id, BUCKET_COUNT)
	_simulation_step_count = 0
	_dropped_time = 0.0


func advance(delta: float) -> void:
	var safe_delta: float = clampf(delta, 0.0, MAX_BACKLOG)
	if delta > safe_delta:
		_dropped_time += delta - safe_delta
	for bucket_index in range(BUCKET_COUNT):
		var next_elapsed: float = _bucket_elapsed[bucket_index] + safe_delta
		if next_elapsed > MAX_BACKLOG:
			_dropped_time += next_elapsed - MAX_BACKLOG
		_bucket_elapsed[bucket_index] = minf(next_elapsed, MAX_BACKLOG)

	var steps_this_frame: int = 0
	var slots_without_step: int = 0
	while steps_this_frame < MAX_BUCKET_STEPS_PER_FRAME:
		var slot: int = _bucket_cursor
		_bucket_cursor = (_bucket_cursor + 1) % BUCKET_COUNT
		if _bucket_elapsed[slot] + TICK_EPSILON < TICK_INTERVAL:
			slots_without_step += 1
			if slots_without_step >= BUCKET_COUNT:
				break
			continue
		slots_without_step = 0
		_bucket_elapsed[slot] = maxf(0.0, _bucket_elapsed[slot] - TICK_INTERVAL)
		_simulate_bucket(slot)
		steps_this_frame += 1
		_simulation_step_count += 1


func advance_visuals(delta: float, presentation_enabled: bool) -> void:
	if not presentation_enabled:
		return
	for bucket_variant in _buckets:
		var bucket: Array = bucket_variant
		for unit_variant in bucket:
			var unit := unit_variant as ColonyUnit
			if is_instance_valid(unit) and unit.is_alive():
				unit.advance_visual_presentation(delta)


func register_unit(unit: ColonyUnit) -> void:
	if not is_instance_valid(unit):
		return
	unit.simulation_slot = posmod(unit.network_entity_id, BUCKET_COUNT)
	var bucket: Array = _buckets[unit.simulation_slot]
	if not bucket.has(unit):
		bucket.append(unit)


func unregister_unit(unit: ColonyUnit) -> void:
	if not is_instance_valid(unit):
		return
	var slot: int = clampi(unit.simulation_slot, 0, BUCKET_COUNT - 1)
	var bucket: Array = _buckets[slot]
	bucket.erase(unit)


func compact(valid_units: Array[ColonyUnit]) -> void:
	for slot in range(BUCKET_COUNT):
		var bucket: Array = _buckets[slot]
		for index in range(bucket.size() - 1, -1, -1):
			var unit := bucket[index] as ColonyUnit
			if (
				not is_instance_valid(unit)
				or unit.definition == null
				or not unit.is_alive()
				or not valid_units.has(unit)
			):
				bucket.remove_at(index)


func get_scheduled_count() -> int:
	var count: int = 0
	for bucket_variant in _buckets:
		var bucket: Array = bucket_variant
		count += bucket.size()
	return count


func get_stats() -> Dictionary:
	var maximum_backlog: float = 0.0
	for elapsed_variant in _bucket_elapsed:
		maximum_backlog = maxf(maximum_backlog, float(elapsed_variant))
	return {
		"tick_hz": roundi(1.0 / TICK_INTERVAL),
		"simulation_steps": _simulation_step_count,
		"maximum_backlog": maximum_backlog,
		"dropped_time": _dropped_time,
	}


func reset() -> void:
	_buckets = [[], [], []]
	_bucket_elapsed = PackedFloat32Array([0.0, 0.0, 0.0])
	_bucket_cursor = 0
	_simulation_step_count = 0
	_dropped_time = 0.0


func _simulate_bucket(slot: int) -> void:
	var bucket: Array = _buckets[slot]
	for unit_variant in bucket:
		var unit := unit_variant as ColonyUnit
		if is_instance_valid(unit) and unit.is_alive():
			unit.simulate_swarm_step(TICK_INTERVAL)
