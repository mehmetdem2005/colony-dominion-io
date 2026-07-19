class_name WorldChunkBuildJob
extends RefCounted

enum Stage { PROPS, RESOURCES, COMPLETE }

var coord := Vector2i.ZERO
var desired_residency: int = WorldChunkRuntime.Residency.ACTIVE
var chunk_rect := Rect2()
var runtime: WorldChunkRuntime
var rng := RandomNumberGenerator.new()
var stage: int = Stage.PROPS
var prop_count: int = 0
var resource_count: int = 0
var prop_index: int = 0
var resource_index: int = 0
var occupied_positions: Array[Vector2] = []
var occupied_radii: Array[float] = []
var stored_resources: Dictionary = {}
var elapsed_unloaded: float = 0.0


func _init(
	chunk_coord: Vector2i,
	chunk_biome: StringName,
	world_rect: Rect2,
	seed_value: int,
	requested_residency: int,
	requested_prop_count: int,
	requested_resource_count: int
) -> void:
	coord = chunk_coord
	desired_residency = requested_residency
	chunk_rect = world_rect
	runtime = WorldChunkRuntime.new(chunk_coord, chunk_biome)
	# Keep partially built chunks completely dormant. The manager applies the
	# requested residency atomically after every prop/resource has been created.
	runtime.residency = -1
	rng.seed = seed_value
	prop_count = maxi(requested_prop_count, 0)
	resource_count = maxi(requested_resource_count, 0)


func is_complete() -> bool:
	return stage == Stage.COMPLETE
