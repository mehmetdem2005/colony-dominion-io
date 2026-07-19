class_name WorldChunkRuntime
extends RefCounted

enum Residency { WARM, ACTIVE }

var coord := Vector2i.ZERO
var biome: StringName = &"forest"
var props: Array[StreamedWorldProp] = []
var resources: Array[WorldResourceNode] = []
var residency: int = Residency.ACTIVE


func _init(chunk_coord: Vector2i = Vector2i.ZERO, chunk_biome: StringName = &"forest") -> void:
	coord = chunk_coord
	biome = chunk_biome


func set_residency(value: int) -> void:
	var next_residency: int = clampi(value, Residency.WARM, Residency.ACTIVE)
	if residency == next_residency:
		return
	residency = next_residency
	var should_simulate: bool = residency == Residency.ACTIVE
	for prop in props:
		if is_instance_valid(prop):
			prop.set_stream_residency(should_simulate)
	for resource in resources:
		if is_instance_valid(resource):
			resource.set_stream_residency(should_simulate)


func is_active() -> bool:
	return residency == Residency.ACTIVE


func get_valid_resource_count() -> int:
	var count: int = 0
	for resource in resources:
		if is_instance_valid(resource):
			count += 1
	return count
