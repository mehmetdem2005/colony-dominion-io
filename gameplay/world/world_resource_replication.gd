class_name WorldResourceReplication
extends RefCounted

const MAX_CACHED_STATES: int = 1024
var _states: Dictionary = {}


func collect_states(
	loaded_chunks: Dictionary, origin: Vector2, max_range: float, max_points: int
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not origin.is_finite() or not is_finite(max_range) or max_range <= 0.0:
		return candidates
	var radius_squared: float = max_range * max_range
	for runtime_variant in loaded_chunks.values():
		var runtime := runtime_variant as WorldChunkRuntime
		if runtime == null or not runtime.is_active():
			continue
		for resource in runtime.resources:
			if not is_instance_valid(resource) or resource.stream_local_id < 0:
				continue
			var distance_squared: float = origin.distance_squared_to(resource.global_position)
			if distance_squared > radius_squared:
				continue
			(
				candidates
				. append(
					{
						"chunk_x": resource.stream_chunk.x,
						"chunk_y": resource.stream_chunk.y,
						"local_id": resource.stream_local_id,
						"amount": resource.amount,
						"max_amount": resource.max_amount,
						"_distance_sq": distance_squared,
					}
				)
			)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("_distance_sq", INF)) < float(b.get("_distance_sq", INF))
	)
	if candidates.size() > maxi(max_points, 0):
		candidates.resize(maxi(max_points, 0))
	for state in candidates:
		state.erase("_distance_sq")
	return candidates


func apply_states(loaded_chunks: Dictionary, states: Array, chunk_count: Vector2i) -> void:
	var now_msec: int = Time.get_ticks_msec()
	for variant in states:
		if not variant is Dictionary:
			continue
		var state: Dictionary = (variant as Dictionary).duplicate(true)
		var coord := Vector2i(int(state.get("chunk_x", -1)), int(state.get("chunk_y", -1)))
		var local_id: int = int(state.get("local_id", -1))
		if (
			coord.x < 0
			or coord.y < 0
			or coord.x >= chunk_count.x
			or coord.y >= chunk_count.y
			or local_id < 0
		):
			continue
		state["received_msec"] = now_msec
		_states[_key(coord, local_id)] = state
		_apply_loaded(loaded_chunks, coord, local_id, state)
	_prune()


func apply_cached(resource: WorldResourceNode) -> void:
	if not is_instance_valid(resource) or resource.stream_local_id < 0:
		return
	var key: String = _key(resource.stream_chunk, resource.stream_local_id)
	if _states.has(key):
		_apply(resource, _states[key])


func clear() -> void:
	_states.clear()


func _apply_loaded(
	loaded_chunks: Dictionary, coord: Vector2i, local_id: int, state: Dictionary
) -> void:
	if not loaded_chunks.has(coord):
		return
	var runtime := loaded_chunks[coord] as WorldChunkRuntime
	if runtime == null:
		return
	for resource in runtime.resources:
		if is_instance_valid(resource) and resource.stream_local_id == local_id:
			_apply(resource, state)
			return


func _apply(resource: WorldResourceNode, state: Dictionary) -> void:
	resource.apply_authoritative_state(
		int(state.get("amount", resource.amount)), int(state.get("max_amount", resource.max_amount))
	)


func _prune() -> void:
	if _states.size() <= MAX_CACHED_STATES:
		return
	var keys: Array = _states.keys()
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return (
				int((_states.get(a, {}) as Dictionary).get("received_msec", 0))
				< int((_states.get(b, {}) as Dictionary).get("received_msec", 0))
			)
	)
	for index in _states.size() - MAX_CACHED_STATES:
		_states.erase(keys[index])


func _key(coord: Vector2i, local_id: int) -> String:
	return "%d:%d:%d" % [coord.x, coord.y, local_id]
