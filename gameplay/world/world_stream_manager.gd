class_name WorldStreamManager
extends Node2D

const GROUND_TEXTURE := preload("res://assets/ground/dirt_stream_tile.png")
const CHUNK_BUILD_JOB_SCRIPT := preload("res://gameplay/world/world_chunk_build_job.gd")
const CONTENT_CATALOG_SCRIPT := preload("res://gameplay/world/world_content_catalog.gd")
const RESIDENCY_PLANNER_SCRIPT := preload("res://gameplay/world/world_residency_planner.gd")
const OBJECT_POOL_SCRIPT := preload("res://gameplay/world/world_object_pool.gd")
const READ_MODEL_SCRIPT := preload("res://gameplay/world/world_stream_read_model.gd")
const COLLISION_GUARD_SCRIPT := preload("res://gameplay/world/world_collision_activation_guard.gd")
const RESOURCE_REPLICATION_SCRIPT := preload("res://gameplay/world/world_resource_replication.gd")

const CHUNK_SIZE: float = 1200.0
const ACTIVE_RADIUS: int = 1
const CACHE_RADIUS: int = 2
const BASE_MAX_RESIDENT_CHUNKS: int = 18
const MAX_RESIDENT_CHUNKS: int = 84
const STREAM_PLAN_INTERVAL: float = 0.16
const STREAM_FRAME_BUDGET_USEC: int = 1400
const MAX_BUILD_STEPS_PER_FRAME: int = 5
const MAX_UNLOADS_PER_FRAME: int = 1
const PREDICTION_SECONDS: float = 0.85
const MAX_PREDICTION_DISTANCE: float = CHUNK_SIZE * 0.82
const PROP_POOL_LIMIT: int = 260
const RESOURCE_POOL_LIMIT: int = 120
const GROUND_REPEAT_WORLD_SIZE: float = 1024.0
const RESOURCE_SIMULATION_INTERVAL: float = 0.25
const MAX_RESOURCE_SIMULATION_STEPS_PER_FRAME: int = 4
const GLOBAL_SEED: int = 738291

var world_bounds := Rect2()
var ground_root: Node2D
var decoration_root: Node2D
var resource_root: Node2D
var safe_positions: Array[Vector2] = []
var presentation_enabled: bool = true
var resource_simulation_enabled: bool = true

var _loaded_chunks: Dictionary = {}
var _chunk_states: Dictionary = {}
var _desired_residency: Dictionary = {}
var _queued_loads: Dictionary = {}
var _load_queue: Array[Vector2i] = []
var _queued_unloads: Dictionary = {}
var _unload_queue: Array[Vector2i] = []
var _noise := FastNoiseLite.new()
var _stream_left: float = 0.0
var _chunk_count := Vector2i.ZERO
var _build_job: WorldChunkBuildJob
var _interest_target_instance_ids: Dictionary = {}
var _interest_last_positions: Dictionary = {}
var _interest_velocities: Dictionary = {}
var _active_resource_count: int = 0
var _last_stream_cost_usec: int = 0
var _resource_simulation_accumulator: float = 0.0
var _resource_simulation_dropped_time: float = 0.0
var _resident_chunk_limit: int = BASE_MAX_RESIDENT_CHUNKS
var _collision_guard: WorldCollisionActivationGuard
var _residency_planner: WorldResidencyPlanner
var _object_pool: WorldObjectPool
var _resource_replication: WorldResourceReplication


func configure(
	bounds: Rect2,
	ground_parent: Node2D,
	decoration_parent: Node2D,
	resource_parent: Node2D,
	spawn_safe_positions: Array[Vector2],
	visuals_enabled: bool = true,
	simulate_resources: bool = true
) -> void:
	world_bounds = bounds
	ground_root = ground_parent
	decoration_root = decoration_parent
	resource_root = resource_parent
	presentation_enabled = visuals_enabled
	resource_simulation_enabled = simulate_resources
	safe_positions = spawn_safe_positions.duplicate()
	_chunk_count = Vector2i(
		ceili(world_bounds.size.x / CHUNK_SIZE), ceili(world_bounds.size.y / CHUNK_SIZE)
	)
	_residency_planner = RESIDENCY_PLANNER_SCRIPT.new() as WorldResidencyPlanner
	_residency_planner.configure(
		_chunk_count, ACTIVE_RADIUS, CACHE_RADIUS, BASE_MAX_RESIDENT_CHUNKS, MAX_RESIDENT_CHUNKS
	)
	_object_pool = OBJECT_POOL_SCRIPT.new() as WorldObjectPool
	_object_pool.configure(
		decoration_root, resource_root, presentation_enabled, PROP_POOL_LIMIT, RESOURCE_POOL_LIMIT
	)
	_collision_guard = COLLISION_GUARD_SCRIPT.new() as WorldCollisionActivationGuard
	_resource_replication = RESOURCE_REPLICATION_SCRIPT.new() as WorldResourceReplication
	_collision_guard.configure(resource_root, _get_interest_targets)
	_noise.seed = GLOBAL_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.00018
	if presentation_enabled:
		_object_pool.prewarm_texture_cache()
		_create_repeating_ground()


func set_interest_target(target: Node2D) -> void:
	clear_interest_targets()
	add_interest_target(0, target)


func add_interest_target(key: int, target: Node2D) -> void:
	if not is_instance_valid(target) or not target.global_position.is_finite():
		return
	_interest_target_instance_ids[key] = target.get_instance_id()
	_interest_last_positions[key] = target.global_position
	_interest_velocities[key] = Vector2.ZERO
	_invalidate_stream_plan()


func remove_interest_target(key: int) -> void:
	_interest_target_instance_ids.erase(key)
	_interest_last_positions.erase(key)
	_interest_velocities.erase(key)
	_invalidate_stream_plan()


func clear_interest_targets() -> void:
	_cancel_build_job()
	_interest_target_instance_ids.clear()
	_interest_last_positions.clear()
	_interest_velocities.clear()
	_invalidate_stream_plan()


func _invalidate_stream_plan() -> void:
	_stream_left = 0.0
	_desired_residency.clear()
	_load_queue.clear()
	_queued_loads.clear()
	_unload_queue.clear()
	_queued_unloads.clear()


func prime_initial_area() -> void:
	var targets: Array[Node2D] = _get_interest_targets()
	if targets.is_empty():
		return
	var center: Vector2i = world_to_chunk(targets[0].global_position)
	_desired_residency[center] = WorldChunkRuntime.Residency.ACTIVE
	_load_chunk_immediate(center, WorldChunkRuntime.Residency.ACTIVE)
	_update_stream_plan(true)


func _process(delta: float) -> void:
	if _interest_target_instance_ids.is_empty():
		return
	_update_interest_velocities(delta)
	if resource_simulation_enabled:
		_advance_active_resources(delta)
	_stream_left -= delta
	if _stream_left <= 0.0:
		_stream_left = STREAM_PLAN_INTERVAL
		_update_stream_plan(false)
	_process_stream_budget()


func _exit_tree() -> void:
	if _resource_replication != null:
		_resource_replication.clear()
	if _object_pool != null:
		_object_pool.shutdown()


func _advance_active_resources(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_resource_simulation_accumulator += minf(delta, 0.5)
	var steps: int = 0
	while (
		_resource_simulation_accumulator >= RESOURCE_SIMULATION_INTERVAL
		and steps < MAX_RESOURCE_SIMULATION_STEPS_PER_FRAME
	):
		_resource_simulation_accumulator -= RESOURCE_SIMULATION_INTERVAL
		_advance_resource_step(RESOURCE_SIMULATION_INTERVAL)
		steps += 1
	if _resource_simulation_accumulator >= RESOURCE_SIMULATION_INTERVAL:
		var retained: float = fmod(_resource_simulation_accumulator, RESOURCE_SIMULATION_INTERVAL)
		_resource_simulation_dropped_time += _resource_simulation_accumulator - retained
		_resource_simulation_accumulator = retained


func _advance_resource_step(step_delta: float) -> void:
	for runtime_variant in _loaded_chunks.values():
		var runtime: WorldChunkRuntime = runtime_variant
		if runtime == null or not runtime.is_active():
			continue
		for resource in runtime.resources:
			if is_instance_valid(resource):
				resource.advance_simulation(step_delta)


func _update_interest_velocities(delta: float) -> void:
	for key_variant in _interest_target_instance_ids.keys():
		var key: int = int(key_variant)
		var target: Node2D = _resolve_interest_target(key)
		if target == null:
			continue
		var current_position: Vector2 = target.global_position
		if not current_position.is_finite():
			_drop_stale_interest(key)
			continue
		var last_position: Vector2 = _interest_last_positions.get(key, current_position)
		if not last_position.is_finite():
			last_position = current_position
		var measured_velocity: Vector2 = (current_position - last_position) / maxf(delta, 0.001)
		var current_velocity: Vector2 = _interest_velocities.get(key, Vector2.ZERO)
		var blend: float = clampf(delta * 7.0, 0.0, 1.0)
		_interest_velocities[key] = current_velocity.lerp(measured_velocity, blend)
		_interest_last_positions[key] = current_position


func _update_stream_plan(_force: bool) -> void:
	var anchors: Array[Dictionary] = []
	for key_variant in _interest_target_instance_ids.keys():
		var key: int = int(key_variant)
		var target: Node2D = _resolve_interest_target(key)
		if target == null:
			continue
		var velocity: Vector2 = _interest_velocities.get(key, Vector2.ZERO)
		if not velocity.is_finite():
			velocity = Vector2.ZERO
		var prediction_offset: Vector2 = (velocity * PREDICTION_SECONDS).limit_length(
			MAX_PREDICTION_DISTANCE
		)
		var predicted_position: Vector2 = target.global_position + prediction_offset
		predicted_position.x = clampf(
			predicted_position.x, world_bounds.position.x, world_bounds.end.x
		)
		predicted_position.y = clampf(
			predicted_position.y, world_bounds.position.y, world_bounds.end.y
		)
		(
			anchors
			. append(
				{
					"center": world_to_chunk(target.global_position),
					"predicted": world_to_chunk(predicted_position),
				}
			)
		)
	if anchors.is_empty():
		return
	_refresh_active_prop_collision_safety()
	_rebuild_desired_residency(anchors)


func _rebuild_desired_residency(anchors: Array[Dictionary]) -> void:
	if _residency_planner == null:
		return
	var plan: Dictionary = _residency_planner.build_plan(anchors, _get_sorted_loaded_chunk_coords())
	var desired_variant: Variant = plan.get("desired", {})
	if not desired_variant is Dictionary:
		return
	_desired_residency = desired_variant
	_resident_chunk_limit = int(plan.get("resident_limit", BASE_MAX_RESIDENT_CHUNKS))
	var centers_variant: Variant = plan.get("centers", [])
	var predicted_variant: Variant = plan.get("predicted_centers", [])
	var centers: Array[Vector2i] = []
	var predicted_centers: Array[Vector2i] = []
	if centers_variant is Array:
		centers.assign(centers_variant)
	if predicted_variant is Array:
		predicted_centers.assign(predicted_variant)
	_compact_load_queue()
	if _build_job != null:
		if not _desired_residency.has(_build_job.coord):
			_cancel_build_job()
		else:
			_build_job.desired_residency = int(_desired_residency[_build_job.coord])
	for key_variant in _loaded_chunks.keys():
		var coord: Vector2i = key_variant
		if _desired_residency.has(coord):
			_queued_unloads.erase(coord)
			_set_chunk_residency(coord, int(_desired_residency[coord]))
		else:
			_queue_unload(coord)
	for key_variant in _desired_residency.keys():
		var coord: Vector2i = key_variant
		if _loaded_chunks.has(coord):
			continue
		if _build_job != null and _build_job.coord == coord:
			continue
		_queue_load(coord)
	_sort_load_queue(centers, predicted_centers)


func _queue_load(coord: Vector2i) -> void:
	if _queued_loads.has(coord) or _loaded_chunks.has(coord):
		return
	_queued_loads[coord] = true
	_load_queue.append(coord)


func _compact_load_queue() -> void:
	for index in range(_load_queue.size() - 1, -1, -1):
		var coord: Vector2i = _load_queue[index]
		if _desired_residency.has(coord) and not _loaded_chunks.has(coord):
			continue
		_load_queue.remove_at(index)
		_queued_loads.erase(coord)


func _sort_load_queue(centers: Array[Vector2i], predicted_centers: Array[Vector2i]) -> void:
	_load_queue.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var residency_a: int = int(_desired_residency.get(a, WorldChunkRuntime.Residency.WARM))
			var residency_b: int = int(_desired_residency.get(b, WorldChunkRuntime.Residency.WARM))
			if residency_a != residency_b:
				return residency_a > residency_b
			var predicted_a: int = RESIDENCY_PLANNER_SCRIPT.minimum_chunk_distance_squared(
				a, predicted_centers
			)
			var predicted_b: int = RESIDENCY_PLANNER_SCRIPT.minimum_chunk_distance_squared(
				b, predicted_centers
			)
			if predicted_a != predicted_b:
				return predicted_a < predicted_b
			return (
				RESIDENCY_PLANNER_SCRIPT.minimum_chunk_distance_squared(a, centers)
				< RESIDENCY_PLANNER_SCRIPT.minimum_chunk_distance_squared(b, centers)
			)
	)


func _process_stream_budget() -> void:
	var started_at: int = Time.get_ticks_usec()
	var deadline: int = started_at + STREAM_FRAME_BUDGET_USEC
	_process_unload_budget(deadline)
	var build_steps: int = 0
	while build_steps < MAX_BUILD_STEPS_PER_FRAME and Time.get_ticks_usec() < deadline:
		if _build_job == null:
			if _load_queue.is_empty():
				break
			var coord: Vector2i = _load_queue.pop_front()
			_queued_loads.erase(coord)
			if (
				not _desired_residency.has(coord)
				or _loaded_chunks.has(coord)
				or not _is_valid_chunk(coord)
			):
				continue
			_begin_chunk_build(coord, int(_desired_residency[coord]))
		if _build_job == null:
			continue
		if not _desired_residency.has(_build_job.coord):
			_cancel_build_job()
			continue
		_build_job.desired_residency = int(_desired_residency[_build_job.coord])
		_advance_chunk_build()
		build_steps += 1
		if _build_job != null and _build_job.is_complete():
			_finish_chunk_build()
	_last_stream_cost_usec = Time.get_ticks_usec() - started_at


func _begin_chunk_build(coord: Vector2i, desired_residency: int) -> void:
	var seed_value: int = _chunk_seed(coord)
	var biome: StringName = _get_biome(coord)
	var chunk_rect: Rect2 = get_chunk_rect(coord)
	var count_rng := RandomNumberGenerator.new()
	count_rng.seed = seed_value ^ 0x41C64E6D
	var prop_count: int = _get_prop_count(biome, count_rng)
	var resource_count: int = _get_resource_count(biome, count_rng)
	_build_job = (
		CHUNK_BUILD_JOB_SCRIPT.new(
			coord, biome, chunk_rect, seed_value, desired_residency, prop_count, resource_count
		)
		as WorldChunkBuildJob
	)
	var stored_chunk_state: Dictionary = _chunk_states.get(coord, {})
	_build_job.stored_resources = stored_chunk_state.get("resources", {})
	var unloaded_at_msec: int = int(stored_chunk_state.get("unloaded_at_msec", 0))
	if unloaded_at_msec > 0:
		_build_job.elapsed_unloaded = maxf(
			0.0, float(Time.get_ticks_msec() - unloaded_at_msec) / 1000.0
		)


func _advance_chunk_build() -> void:
	if _build_job == null:
		return
	if _build_job.stage == WorldChunkBuildJob.Stage.PROPS:
		if _build_job.prop_index >= _build_job.prop_count:
			_build_job.stage = WorldChunkBuildJob.Stage.RESOURCES
			return
		_build_prop_step(_build_job)
		return
	if _build_job.stage == WorldChunkBuildJob.Stage.RESOURCES:
		if _build_job.resource_index >= _build_job.resource_count:
			_build_job.stage = WorldChunkBuildJob.Stage.COMPLETE
			return
		_build_resource_step(_build_job)


func _build_prop_step(job: WorldChunkBuildJob) -> void:
	job.prop_index += 1
	var prop_config: Dictionary = _pick_prop_config(job.runtime.biome, job.rng)
	var radius: float = float(prop_config.get("radius", 30.0))
	var position: Vector2 = _find_chunk_position(
		job.rng, job.chunk_rect, radius + 22.0, job.occupied_positions, job.occupied_radii
	)
	if position == Vector2.INF:
		return
	var texture_path: String = String(prop_config.get("path", ""))
	var is_solid: bool = bool(prop_config.get("solid", false))
	var rotation_value: float = job.rng.randf_range(-0.08, 0.08)
	var color_variation: float = job.rng.randf_range(0.94, 1.06)
	var tint := Color(color_variation, color_variation, color_variation, 1.0)
	var prop_key: StringName = prop_config.get("key", &"prop")
	var world_size: float = float(prop_config.get("size", 100.0)) * job.rng.randf_range(0.88, 1.12)
	var flip_h: bool = job.rng.randf() < 0.5
	if not presentation_enabled and not is_solid:
		return
	var prop: StreamedWorldProp = _object_pool.acquire_prop()
	var texture: Texture2D = (
		_object_pool.get_texture(texture_path) if presentation_enabled else null
	)
	prop.activate(
		texture,
		position,
		world_size,
		radius,
		is_solid,
		bool(prop_config.get("ground", false)),
		rotation_value,
		flip_h,
		tint,
		prop_key
	)
	var safe_distance: float = radius + 180.0
	prop.set_proximity_suppressed(_should_suppress_prop_collision(position, safe_distance))
	prop.set_stream_residency(false)
	job.runtime.props.append(prop)
	if is_solid:
		job.occupied_positions.append(position)
		job.occupied_radii.append(radius)


func _build_resource_step(job: WorldChunkBuildJob) -> void:
	var local_id: int = job.resource_index
	job.resource_index += 1
	var resource_config: Dictionary = _pick_resource_config(job.runtime.biome, job.rng)
	var world_size: float = float(resource_config.get("size", 82.0))
	var position: Vector2 = _find_chunk_position(
		job.rng,
		job.chunk_rect,
		world_size * 0.36 + 18.0,
		job.occupied_positions,
		job.occupied_radii
	)
	if position == Vector2.INF:
		return
	var resource: WorldResourceNode = _object_pool.acquire_resource()
	var texture_path: String = String(resource_config.get("path", ""))
	var saved_state: Dictionary = job.stored_resources.get(local_id, {})
	var resource_type: StringName = resource_config.get("type", &"seed")
	resource.activate_streamed(
		resource_type,
		_object_pool.get_texture(texture_path) if presentation_enabled else null,
		int(resource_config.get("amount", 60)),
		world_size,
		job.coord,
		local_id,
		saved_state,
		job.elapsed_unloaded,
		job.rng.randf_range(20.0, 34.0)
	)
	resource.global_position = position
	resource.refresh_world_depth()
	if _resource_replication != null:
		_resource_replication.apply_cached(resource)
	resource.set_stream_residency(false)
	resource.reset_physics_interpolation()
	job.runtime.resources.append(resource)


func _finish_chunk_build() -> void:
	if _build_job == null:
		return
	var job: WorldChunkBuildJob = _build_job
	_build_job = null
	if not _desired_residency.has(job.coord):
		_release_runtime_nodes(job.runtime)
		return
	var residency: int = int(_desired_residency[job.coord])
	if residency == WorldChunkRuntime.Residency.ACTIVE:
		_prepare_runtime_prop_collision_activation(job.runtime)
	job.runtime.set_residency(residency)
	_loaded_chunks[job.coord] = job.runtime
	_chunk_states.erase(job.coord)
	if job.runtime.is_active():
		_active_resource_count += job.runtime.get_valid_resource_count()
		_refresh_runtime_prop_collision_safety(job.runtime)


func _cancel_build_job() -> void:
	if _build_job == null:
		return
	_release_runtime_nodes(_build_job.runtime)
	_build_job = null


func _load_chunk_immediate(coord: Vector2i, residency: int) -> void:
	if _loaded_chunks.has(coord):
		_set_chunk_residency(coord, residency)
		return
	_cancel_build_job()
	_desired_residency[coord] = residency
	_begin_chunk_build(coord, residency)
	while _build_job != null and not _build_job.is_complete():
		_advance_chunk_build()
	_finish_chunk_build()


func _queue_unload(coord: Vector2i) -> void:
	if _queued_unloads.has(coord):
		return
	_queued_unloads[coord] = true
	_unload_queue.append(coord)


func _process_unload_budget(deadline: int) -> void:
	var unloaded_count: int = 0
	while (
		unloaded_count < MAX_UNLOADS_PER_FRAME
		and not _unload_queue.is_empty()
		and Time.get_ticks_usec() < deadline
	):
		var coord: Vector2i = _unload_queue.pop_front()
		_queued_unloads.erase(coord)
		if _desired_residency.has(coord):
			continue
		_unload_chunk(coord)
		unloaded_count += 1


func _set_chunk_residency(coord: Vector2i, residency: int) -> void:
	if not _loaded_chunks.has(coord):
		return
	var runtime: WorldChunkRuntime = _loaded_chunks[coord]
	var was_active: bool = runtime.is_active()
	if not was_active and residency == WorldChunkRuntime.Residency.ACTIVE:
		_prepare_runtime_prop_collision_activation(runtime)
	runtime.set_residency(residency)
	var is_active_now: bool = runtime.is_active()
	if was_active == is_active_now:
		return
	var resource_count: int = runtime.get_valid_resource_count()
	if is_active_now:
		_active_resource_count += resource_count
		_refresh_runtime_prop_collision_safety(runtime)
	else:
		_active_resource_count -= resource_count
	_active_resource_count = maxi(_active_resource_count, 0)


func _prepare_runtime_prop_collision_activation(runtime: WorldChunkRuntime) -> void:
	if runtime == null:
		return
	for prop in runtime.props:
		if not is_instance_valid(prop):
			continue
		var safe_distance: float = prop.get_collision_radius() + 180.0
		prop.set_proximity_suppressed(
			_should_suppress_prop_collision(prop.global_position, safe_distance)
		)


func _refresh_active_prop_collision_safety() -> void:
	if _interest_target_instance_ids.is_empty():
		return
	for runtime_variant in _loaded_chunks.values():
		var runtime: WorldChunkRuntime = runtime_variant
		if runtime.is_active():
			_refresh_runtime_prop_collision_safety(runtime)


func _refresh_runtime_prop_collision_safety(runtime: WorldChunkRuntime) -> void:
	if runtime == null or _interest_target_instance_ids.is_empty():
		return
	for prop in runtime.props:
		if not is_instance_valid(prop) or not prop.is_proximity_suppressed():
			continue
		var safe_distance: float = prop.get_collision_radius() + 180.0
		if not _should_suppress_prop_collision(prop.global_position, safe_distance):
			prop.set_proximity_suppressed(false)


func _unload_chunk(coord: Vector2i) -> void:
	if not _loaded_chunks.has(coord):
		return
	var runtime: WorldChunkRuntime = _loaded_chunks[coord]
	if runtime.is_active():
		_active_resource_count = maxi(
			0, _active_resource_count - runtime.get_valid_resource_count()
		)
	var stored_resources: Dictionary = {}
	for resource in runtime.resources:
		if not is_instance_valid(resource):
			continue
		stored_resources[resource.stream_local_id] = resource.capture_stream_state()
	_chunk_states[coord] = {
		"resources": stored_resources,
		"unloaded_at_msec": Time.get_ticks_msec(),
	}
	_release_runtime_nodes(runtime)
	_loaded_chunks.erase(coord)


func _release_runtime_nodes(runtime: WorldChunkRuntime) -> void:
	if runtime == null:
		return
	for resource in runtime.resources:
		if is_instance_valid(resource):
			_object_pool.release_resource(resource)
	for prop in runtime.props:
		if is_instance_valid(prop):
			_object_pool.release_prop(prop)
	runtime.resources.clear()
	runtime.props.clear()


func get_network_resource_states(
	origin: Vector2, max_range: float, max_points: int = 72
) -> Array[Dictionary]:
	return (
		_resource_replication.collect_states(_loaded_chunks, origin, max_range, max_points)
		if _resource_replication != null
		else []
	)


func apply_network_resource_states(states: Array) -> void:
	if _resource_replication != null:
		_resource_replication.apply_states(_loaded_chunks, states, _chunk_count)


func find_nearest_resource(
	origin: Vector2, max_range: float, preferred_type: StringName = &""
) -> WorldResourceNode:
	return READ_MODEL_SCRIPT.find_nearest_resource(
		_loaded_chunks, world_to_chunk, origin, max_range, preferred_type
	)


func world_to_chunk(world_position: Vector2) -> Vector2i:
	if not world_position.is_finite():
		return Vector2i.ZERO
	var local: Vector2 = world_position - world_bounds.position
	var coord := Vector2i(floori(local.x / CHUNK_SIZE), floori(local.y / CHUNK_SIZE))
	coord.x = clampi(coord.x, 0, maxi(_chunk_count.x - 1, 0))
	coord.y = clampi(coord.y, 0, maxi(_chunk_count.y - 1, 0))
	return coord


func get_chunk_rect(coord: Vector2i) -> Rect2:
	var position: Vector2 = world_bounds.position + Vector2(coord) * CHUNK_SIZE
	var remaining: Vector2 = world_bounds.end - position
	return Rect2(position, Vector2(minf(CHUNK_SIZE, remaining.x), minf(CHUNK_SIZE, remaining.y)))


func get_chunk_size() -> float:
	return CHUNK_SIZE


func get_loaded_chunk_count() -> int:
	return _loaded_chunks.size()


func get_active_chunk_count() -> int:
	return READ_MODEL_SCRIPT.get_active_chunk_count(_loaded_chunks)


func get_warm_chunk_count() -> int:
	return maxi(0, get_loaded_chunk_count() - get_active_chunk_count())


func get_active_resource_count() -> int:
	return _active_resource_count


func get_pending_load_count() -> int:
	return _load_queue.size() + (1 if _build_job != null else 0)


func get_interest_target_count() -> int:
	return _get_interest_targets().size()


func get_desired_chunk_count() -> int:
	return _desired_residency.size()


func get_resident_chunk_limit() -> int:
	return _resident_chunk_limit


func get_last_stream_cost_usec() -> int:
	return _last_stream_cost_usec


func get_pool_stats() -> Dictionary:
	var stats: Dictionary = _object_pool.get_stats() if _object_pool != null else {}
	stats["resource_dropped_time"] = _resource_simulation_dropped_time
	return stats


func get_loaded_chunk_coords() -> Array[Vector2i]:
	return READ_MODEL_SCRIPT.get_sorted_loaded_chunk_coords(_loaded_chunks)


func get_minimap_chunk_entries() -> Array[Dictionary]:
	return READ_MODEL_SCRIPT.get_minimap_chunk_entries(_loaded_chunks)


func get_minimap_resource_points(max_points: int = 56) -> Array[Dictionary]:
	return READ_MODEL_SCRIPT.get_minimap_resource_points(_loaded_chunks, max_points)


func _create_repeating_ground() -> void:
	if not presentation_enabled:
		return
	var underlay := Polygon2D.new()
	underlay.name = "WorldUnderlay"
	var padded_bounds: Rect2 = world_bounds.grow(1400.0)
	underlay.polygon = PackedVector2Array(
		[
			padded_bounds.position,
			Vector2(padded_bounds.end.x, padded_bounds.position.y),
			padded_bounds.end,
			Vector2(padded_bounds.position.x, padded_bounds.end.y),
		]
	)
	underlay.color = Color("9f6d38")
	underlay.z_index = WorldDepthPolicy.GROUND_UNDERLAY_LOCAL_Z
	ground_root.add_child(underlay)

	var ground := Polygon2D.new()
	ground.name = "StreamingGround"
	ground.texture = GROUND_TEXTURE
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ground.polygon = PackedVector2Array(
		[
			world_bounds.position,
			Vector2(world_bounds.end.x, world_bounds.position.y),
			world_bounds.end,
			Vector2(world_bounds.position.x, world_bounds.end.y),
		]
	)
	var texture_width: float = float(GROUND_TEXTURE.get_width())
	var texture_height: float = float(GROUND_TEXTURE.get_height())
	var uv_width: float = world_bounds.size.x / GROUND_REPEAT_WORLD_SIZE * texture_width
	var uv_height: float = world_bounds.size.y / GROUND_REPEAT_WORLD_SIZE * texture_height
	ground.uv = PackedVector2Array(
		[
			Vector2.ZERO,
			Vector2(uv_width, 0.0),
			Vector2(uv_width, uv_height),
			Vector2(0.0, uv_height),
		]
	)
	ground.z_index = WorldDepthPolicy.GROUND_SURFACE_LOCAL_Z
	ground_root.add_child(ground)


func _find_chunk_position(
	rng: RandomNumberGenerator,
	chunk_rect: Rect2,
	radius: float,
	occupied_positions: Array[Vector2],
	occupied_radii: Array[float]
) -> Vector2:
	for _attempt in 26:
		var point := Vector2(
			rng.randf_range(chunk_rect.position.x + 48.0, chunk_rect.end.x - 48.0),
			rng.randf_range(chunk_rect.position.y + 48.0, chunk_rect.end.y - 48.0)
		)
		if not _is_safe_point(point, radius):
			continue
		var blocked: bool = false
		for index in occupied_positions.size():
			var minimum_distance: float = radius + occupied_radii[index] + 18.0
			if (
				point.distance_squared_to(occupied_positions[index])
				< minimum_distance * minimum_distance
			):
				blocked = true
				break
		if not blocked:
			return point
	return Vector2.INF


func _is_safe_point(point: Vector2, radius: float) -> bool:
	for safe_position in safe_positions:
		var safe_distance: float = radius + 430.0
		if point.distance_squared_to(safe_position) < safe_distance * safe_distance:
			return false
	return true


func get_biome_at(world_position: Vector2) -> StringName:
	return _get_biome(world_to_chunk(world_position))


func _pick_prop_config(biome: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var indices: Array = CONTENT_CATALOG_SCRIPT.BIOME_PROP_INDICES.get(
		biome, CONTENT_CATALOG_SCRIPT.BIOME_PROP_INDICES[&"forest"]
	)
	var selected_index: int = int(indices[rng.randi_range(0, indices.size() - 1)])
	return CONTENT_CATALOG_SCRIPT.PROP_VARIANTS[selected_index]


func _pick_resource_config(biome: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var indices: Array = CONTENT_CATALOG_SCRIPT.BIOME_RESOURCE_INDICES.get(
		biome, CONTENT_CATALOG_SCRIPT.BIOME_RESOURCE_INDICES[&"forest"]
	)
	var selected_index: int = int(indices[rng.randi_range(0, indices.size() - 1)])
	return CONTENT_CATALOG_SCRIPT.RESOURCE_VARIANTS[selected_index]


func _get_prop_count(biome: StringName, rng: RandomNumberGenerator) -> int:
	match biome:
		&"forest":
			return rng.randi_range(16, 21)
		&"meadow":
			return rng.randi_range(13, 18)
		&"rocky":
			return rng.randi_range(11, 16)
		_:
			return rng.randi_range(9, 14)


func _get_resource_count(biome: StringName, rng: RandomNumberGenerator) -> int:
	match biome:
		&"forest":
			return rng.randi_range(6, 9)
		&"meadow":
			return rng.randi_range(7, 10)
		&"rocky":
			return rng.randi_range(5, 8)
		_:
			return rng.randi_range(5, 7)


func _get_biome(coord: Vector2i) -> StringName:
	var center: Vector2 = get_chunk_rect(coord).get_center()
	var value: float = _noise.get_noise_2d(center.x, center.y)
	if value > 0.36:
		return &"meadow"
	if value < -0.42:
		return &"dry"
	var ridge: float = _noise.get_noise_2d(center.x + 7800.0, center.y - 6400.0)
	if ridge > 0.48:
		return &"rocky"
	return &"forest"


func _chunk_seed(coord: Vector2i) -> int:
	var value: int = GLOBAL_SEED
	value ^= coord.x * 73856093
	value ^= coord.y * 19349663
	return absi(value)


func _get_interest_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for key_variant in _interest_target_instance_ids.keys():
		var target: Node2D = _resolve_interest_target(int(key_variant))
		if target != null:
			result.append(target)
	return result


func _resolve_interest_target(key: int) -> Node2D:
	if not _interest_target_instance_ids.has(key):
		return null
	var instance_id: int = int(_interest_target_instance_ids[key])
	if instance_id <= 0 or not is_instance_id_valid(instance_id):
		_drop_stale_interest(key)
		return null
	var candidate: Object = instance_from_id(instance_id)
	if not is_instance_valid(candidate) or not candidate is Node2D:
		_drop_stale_interest(key)
		return null
	var target := candidate as Node2D
	if target.is_queued_for_deletion() or not target.is_inside_tree():
		_drop_stale_interest(key)
		return null
	return target


func _drop_stale_interest(key: int) -> void:
	_interest_target_instance_ids.erase(key)
	_interest_last_positions.erase(key)
	_interest_velocities.erase(key)


func _should_suppress_prop_collision(position: Vector2, radius: float) -> bool:
	return _collision_guard.should_suppress(position, radius) if _collision_guard != null else false


func _is_valid_chunk(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < _chunk_count.x and coord.y < _chunk_count.y


func _get_sorted_loaded_chunk_coords() -> Array[Vector2i]:
	return READ_MODEL_SCRIPT.get_sorted_loaded_chunk_coords(_loaded_chunks)
