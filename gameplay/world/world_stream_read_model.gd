class_name WorldStreamReadModel
extends RefCounted


static func find_nearest_resource(
	loaded_chunks: Dictionary,
	world_to_chunk_callable: Callable,
	origin: Vector2,
	max_range: float,
	preferred_type: StringName = &""
) -> WorldResourceNode:
	if (
		not origin.is_finite()
		or not is_finite(max_range)
		or max_range <= 0.0
		or not world_to_chunk_callable.is_valid()
	):
		return null
	var best: WorldResourceNode = null
	var best_distance_squared: float = max_range * max_range
	var minimum_chunk: Vector2i = world_to_chunk_callable.call(origin - Vector2.ONE * max_range)
	var maximum_chunk: Vector2i = world_to_chunk_callable.call(origin + Vector2.ONE * max_range)
	for chunk_x in range(minimum_chunk.x, maximum_chunk.x + 1):
		for chunk_y in range(minimum_chunk.y, maximum_chunk.y + 1):
			var coord := Vector2i(chunk_x, chunk_y)
			if not loaded_chunks.has(coord):
				continue
			var runtime: WorldChunkRuntime = loaded_chunks[coord] as WorldChunkRuntime
			if runtime == null or not runtime.is_active():
				continue
			for resource in runtime.resources:
				if (
					not is_instance_valid(resource)
					or not resource.is_available()
					or (preferred_type != &"" and resource.resource_type != preferred_type)
				):
					continue
				var distance_squared: float = origin.distance_squared_to(resource.global_position)
				if distance_squared < best_distance_squared:
					best_distance_squared = distance_squared
					best = resource
	return best


static func get_active_chunk_count(loaded_chunks: Dictionary) -> int:
	var count: int = 0
	for runtime_variant in loaded_chunks.values():
		var runtime: WorldChunkRuntime = runtime_variant as WorldChunkRuntime
		if runtime != null and runtime.is_active():
			count += 1
	return count


static func get_sorted_loaded_chunk_coords(loaded_chunks: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key_variant in loaded_chunks.keys():
		if key_variant is Vector2i:
			var coord: Vector2i = key_variant
			result.append(coord)
	result.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


static func get_minimap_chunk_entries(loaded_chunks: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for coord in get_sorted_loaded_chunk_coords(loaded_chunks):
		var runtime: WorldChunkRuntime = loaded_chunks[coord] as WorldChunkRuntime
		if runtime == null:
			continue
		(
			result
			. append(
				{
					"coord": coord,
					"biome": runtime.biome,
					"active": runtime.is_active(),
				}
			)
		)
	return result


static func get_minimap_resource_points(
	loaded_chunks: Dictionary, max_points: int = 56
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if max_points <= 0:
		return result
	for coord in get_sorted_loaded_chunk_coords(loaded_chunks):
		var runtime: WorldChunkRuntime = loaded_chunks[coord] as WorldChunkRuntime
		if runtime == null or not runtime.is_active():
			continue
		var sorted_resources: Array[WorldResourceNode] = []
		for resource in runtime.resources:
			if is_instance_valid(resource):
				sorted_resources.append(resource)
		sorted_resources.sort_custom(
			func(a: WorldResourceNode, b: WorldResourceNode) -> bool:
				return a.stream_local_id < b.stream_local_id
		)
		for resource in sorted_resources:
			if not resource.is_available():
				continue
			(
				result
				. append(
					{
						"position": resource.global_position,
						"type": resource.resource_type,
					}
				)
			)
			if result.size() >= max_points:
				return result
	return result
