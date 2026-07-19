class_name WorldResidencyPlanner
extends RefCounted

var _chunk_count := Vector2i.ZERO
var _active_radius: int = 1
var _cache_radius: int = 2
var _base_resident_limit: int = 18
var _maximum_resident_limit: int = 84


func configure(
	chunk_count: Vector2i,
	active_radius: int,
	cache_radius: int,
	base_resident_limit: int,
	maximum_resident_limit: int
) -> void:
	_chunk_count = Vector2i(maxi(chunk_count.x, 0), maxi(chunk_count.y, 0))
	_active_radius = maxi(active_radius, 0)
	_cache_radius = maxi(cache_radius, _active_radius)
	_base_resident_limit = maxi(base_resident_limit, 1)
	_maximum_resident_limit = maxi(maximum_resident_limit, _base_resident_limit)


func build_plan(anchors: Array[Dictionary], loaded_coords: Array[Vector2i]) -> Dictionary:
	var next_desired: Dictionary = {}
	var centers: Array[Vector2i] = []
	var predicted_centers: Array[Vector2i] = []
	var resident_limit: int = mini(
		_maximum_resident_limit, maxi(_base_resident_limit, anchors.size() * 12 + 6)
	)
	for anchor in anchors:
		var center_variant: Variant = anchor.get("center", Vector2i(-1, -1))
		var predicted_variant: Variant = anchor.get("predicted", center_variant)
		if not center_variant is Vector2i or not predicted_variant is Vector2i:
			continue
		var center: Vector2i = center_variant
		var predicted_center: Vector2i = predicted_variant
		if not _is_valid_chunk(center):
			continue
		centers.append(center)
		predicted_centers.append(predicted_center if _is_valid_chunk(predicted_center) else center)
		_mark_radius(next_desired, center, _active_radius, WorldChunkRuntime.Residency.ACTIVE)
		_mark_radius(
			next_desired,
			predicted_centers[predicted_centers.size() - 1],
			_active_radius,
			WorldChunkRuntime.Residency.WARM
		)
	_trim_predicted_warm_chunks(next_desired, centers, predicted_centers, resident_limit)
	var warm_candidates: Array[Vector2i] = []
	for coord in loaded_coords:
		if next_desired.has(coord):
			continue
		if minimum_chebyshev_distance(coord, centers) <= _cache_radius:
			warm_candidates.append(coord)
	warm_candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (
				minimum_chunk_distance_squared(a, centers)
				< minimum_chunk_distance_squared(b, centers)
			)
	)
	for coord in warm_candidates:
		if next_desired.size() >= resident_limit:
			break
		_set_residency(next_desired, coord, WorldChunkRuntime.Residency.WARM)
	return {
		"desired": next_desired,
		"centers": centers,
		"predicted_centers": predicted_centers,
		"resident_limit": resident_limit,
	}


static func minimum_chunk_distance_squared(coord: Vector2i, anchors: Array[Vector2i]) -> int:
	var best: int = 2_147_483_647
	for anchor in anchors:
		var delta: Vector2i = coord - anchor
		best = mini(best, delta.x * delta.x + delta.y * delta.y)
	return best


static func minimum_chebyshev_distance(coord: Vector2i, anchors: Array[Vector2i]) -> int:
	var best: int = 2_147_483_647
	for anchor in anchors:
		var delta: Vector2i = coord - anchor
		best = mini(best, maxi(absi(delta.x), absi(delta.y)))
	return best


func _mark_radius(target_map: Dictionary, center: Vector2i, radius: int, residency: int) -> void:
	for offset_x in range(-radius, radius + 1):
		for offset_y in range(-radius, radius + 1):
			_set_residency(
				target_map, Vector2i(center.x + offset_x, center.y + offset_y), residency
			)


func _set_residency(target_map: Dictionary, coord: Vector2i, residency: int) -> void:
	if not _is_valid_chunk(coord):
		return
	if target_map.has(coord) and int(target_map[coord]) >= residency:
		return
	target_map[coord] = residency


func _trim_predicted_warm_chunks(
	target_map: Dictionary,
	centers: Array[Vector2i],
	predicted_centers: Array[Vector2i],
	resident_limit: int
) -> void:
	if target_map.size() <= resident_limit:
		return
	var warm_coords: Array[Vector2i] = []
	for key_variant in target_map.keys():
		var coord: Vector2i = key_variant
		if int(target_map[coord]) == WorldChunkRuntime.Residency.WARM:
			warm_coords.append(coord)
	warm_coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var predicted_a: int = minimum_chunk_distance_squared(a, predicted_centers)
			var predicted_b: int = minimum_chunk_distance_squared(b, predicted_centers)
			if predicted_a != predicted_b:
				return predicted_a < predicted_b
			return (
				minimum_chunk_distance_squared(a, centers)
				< minimum_chunk_distance_squared(b, centers)
			)
	)
	for index in range(warm_coords.size() - 1, -1, -1):
		if target_map.size() <= resident_limit:
			break
		target_map.erase(warm_coords[index])


func _is_valid_chunk(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < _chunk_count.x and coord.y < _chunk_count.y
