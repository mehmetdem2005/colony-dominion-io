class_name ColonyMinimap
extends Control

const REFRESH_INTERVAL: float = 0.12
const MAP_PADDING: float = 6.0
const GRID_COLUMNS: int = 8
const GRID_ROWS: int = 6
const BIOME_COLORS := {
	&"meadow": Color(0.29, 0.38, 0.16, 0.92),
	&"forest": Color(0.13, 0.27, 0.12, 0.94),
	&"rocky": Color(0.35, 0.31, 0.25, 0.94),
	&"dry": Color(0.43, 0.30, 0.14, 0.94),
}
const RESOURCE_COLORS := {
	&"seed": Color(0.96, 0.72, 0.20, 1.0),
	&"nectar": Color(1.0, 0.45, 0.72, 1.0),
	&"protein": Color(0.94, 0.28, 0.22, 1.0),
	&"leaf": Color(0.36, 0.88, 0.31, 1.0),
	&"stone": Color(0.72, 0.76, 0.80, 1.0),
}

var _read_model: Node = null
var _snapshot: Dictionary = {}
var _known_chunks: Dictionary = {}
var _refresh_left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(true)


func bind_match(match_node: Node) -> void:
	bind_source(match_node)


func bind_source(read_model: Node) -> void:
	_read_model = read_model
	if not is_instance_valid(_read_model) or not _read_model.has_method("get_minimap_snapshot"):
		push_error("ColonyMinimap received an invalid minimap read model")
		_read_model = null
		return
	_known_chunks.clear()
	_snapshot.clear()
	_refresh_snapshot()


func _process(delta: float) -> void:
	if not is_instance_valid(_read_model):
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_INTERVAL
		_refresh_snapshot()


func _refresh_snapshot() -> void:
	if not is_instance_valid(_read_model):
		return
	var next_snapshot_variant: Variant = _read_model.call("get_minimap_snapshot")
	if not next_snapshot_variant is Dictionary:
		return
	var next_snapshot: Dictionary = next_snapshot_variant
	var known_chunk_coords: Array = _known_chunks.keys()
	for chunk_coord in known_chunk_coords:
		var cached_entry: Dictionary = _known_chunks[chunk_coord]
		cached_entry["active"] = false
		_known_chunks[chunk_coord] = cached_entry
	var current_chunks: Array = next_snapshot.get("chunk_entries", [])
	for entry_variant in current_chunks:
		var entry: Dictionary = entry_variant
		var coord: Vector2i = entry.get("coord", Vector2i.ZERO)
		_known_chunks[coord] = {
			"coord": coord,
			"biome": entry.get("biome", &"forest"),
			"active": bool(entry.get("active", false)),
		}
	next_snapshot["chunk_entries"] = _known_chunks.values()
	_snapshot = next_snapshot
	if is_inside_tree() and not is_queued_for_deletion():
		queue_redraw()


func get_known_chunk_count() -> int:
	return _known_chunks.size()


func _draw() -> void:
	if size.x <= MAP_PADDING * 2.0 or size.y <= MAP_PADDING * 2.0:
		return
	var content_rect := Rect2(Vector2.ONE * MAP_PADDING, size - Vector2.ONE * MAP_PADDING * 2.0)
	draw_rect(content_rect, Color(0.055, 0.065, 0.045, 1.0), true)
	_draw_terrain_base(content_rect)
	if _snapshot.is_empty():
		draw_rect(content_rect, Color(0.92, 0.72, 0.22, 0.72), false, 2.0)
		return

	var world_bounds: Rect2 = _snapshot.get("world_bounds", Rect2())
	if world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return

	_draw_grid(content_rect)
	_draw_loaded_chunks(content_rect, world_bounds)
	_draw_resources(content_rect, world_bounds)
	_draw_colonies(content_rect, world_bounds)
	_draw_camera_view(content_rect, world_bounds)
	_draw_compass(content_rect)
	draw_rect(content_rect.grow(-1.0), Color(0.96, 0.79, 0.30, 0.95), false, 2.0)
	draw_rect(content_rect.grow(-4.0), Color(0.12, 0.08, 0.025, 0.72), false, 1.0)


func _draw_terrain_base(content_rect: Rect2) -> void:
	# A single calm, dark base. The previous version stacked three big
	# semi-transparent coloured circles (green/brown/grey) under the biome tiles,
	# grid and borders, which read as a muddy "colour mess". A flat base lets the
	# meaningful markers (chunks, resources, colonies, the player) stand out.
	draw_rect(content_rect, Color(0.09, 0.10, 0.07, 1.0), true)


func _draw_grid(content_rect: Rect2) -> void:
	var grid_color := Color(0.94, 0.82, 0.48, 0.11)
	for column in range(1, GRID_COLUMNS):
		var x: float = (
			content_rect.position.x + (content_rect.size.x * float(column) / float(GRID_COLUMNS))
		)
		draw_line(
			Vector2(x, content_rect.position.y), Vector2(x, content_rect.end.y), grid_color, 1.0
		)
	for row in range(1, GRID_ROWS):
		var y: float = (
			content_rect.position.y + (content_rect.size.y * float(row) / float(GRID_ROWS))
		)
		draw_line(
			Vector2(content_rect.position.x, y), Vector2(content_rect.end.x, y), grid_color, 1.0
		)


func _draw_loaded_chunks(content_rect: Rect2, world_bounds: Rect2) -> void:
	var chunk_entries: Array = _snapshot.get("chunk_entries", [])
	var chunk_size_variant: Variant = _snapshot.get("chunk_size", 1200.0)
	var chunk_size: float = (
		float(chunk_size_variant)
		if chunk_size_variant is int or chunk_size_variant is float
		else 1200.0
	)
	if not is_finite(chunk_size) or chunk_size <= 0.0:
		chunk_size = 1200.0
	for entry_variant in chunk_entries:
		var entry: Dictionary = entry_variant
		var chunk_coord: Vector2i = entry.get("coord", Vector2i.ZERO)
		var world_rect := Rect2(
			world_bounds.position + Vector2(chunk_coord) * chunk_size, Vector2.ONE * chunk_size
		)
		var local_start: Vector2 = _world_to_local(world_rect.position, content_rect, world_bounds)
		var local_end: Vector2 = _world_to_local(world_rect.end, content_rect, world_bounds)
		var local_rect := Rect2(local_start, local_end - local_start).intersection(content_rect)
		if local_rect.size.x <= 0.0 or local_rect.size.y <= 0.0:
			continue
		var biome: StringName = entry.get("biome", &"forest")
		var biome_color: Color = BIOME_COLORS.get(biome, BIOME_COLORS[&"forest"])
		# Keep explored biome tiles as a subtle tint over the calm base so they
		# read as terrain, not a wall of colour. (Loaded/warm state is shown by
		# the border below, not a large alpha jump.)
		biome_color.a = 0.34
		draw_rect(local_rect, biome_color, true)
		var is_active: bool = bool(entry.get("active", false))
		var border_color := (
			Color(1.0, 0.86, 0.42, 0.78) if is_active else Color(0.94, 0.83, 0.50, 0.18)
		)
		draw_rect(local_rect.grow(-0.5), border_color, false, 1.0)


func _draw_resources(content_rect: Rect2, world_bounds: Rect2) -> void:
	var resources: Array = _snapshot.get("resources", [])
	for entry_variant in resources:
		var entry: Dictionary = entry_variant
		var world_position: Vector2 = entry.get("position", Vector2.INF)
		if world_position == Vector2.INF:
			continue
		var local_position: Vector2 = _world_to_local(world_position, content_rect, world_bounds)
		var resource_type: StringName = entry.get("type", &"seed")
		var color: Color = RESOURCE_COLORS.get(resource_type, Color.WHITE)
		draw_circle(local_position, 2.6, Color(0.02, 0.015, 0.01, 0.86))
		draw_circle(local_position, 1.65, color)


func _draw_colonies(content_rect: Rect2, world_bounds: Rect2) -> void:
	var colonies: Array = _snapshot.get("colonies", [])
	for entry_variant in colonies:
		var entry: Dictionary = entry_variant
		if not bool(entry.get("active", false)):
			continue
		var color: Color = entry.get("color", Color.WHITE)
		var army_size: int = int(entry.get("army_size", 0))
		var commander_position: Vector2 = entry.get("commander", Vector2.INF)
		var nest_position: Vector2 = entry.get("nest", Vector2.INF)
		var facing: Vector2 = entry.get("facing", Vector2.UP)
		if not facing.is_finite():
			facing = Vector2.UP
		var is_player: bool = bool(entry.get("is_player", false))

		if nest_position != Vector2.INF:
			var nest_local: Vector2 = _world_to_local(nest_position, content_rect, world_bounds)
			var nest_shape := PackedVector2Array(
				[
					nest_local + Vector2(0.0, -5.0),
					nest_local + Vector2(5.0, 0.0),
					nest_local + Vector2(0.0, 5.0),
					nest_local + Vector2(-5.0, 0.0),
				]
			)
			draw_colored_polygon(nest_shape, Color(0.025, 0.018, 0.01, 0.96))
			var inner_shape := PackedVector2Array()
			for point in nest_shape:
				inner_shape.append(nest_local + (point - nest_local) * 0.68)
			draw_colored_polygon(inner_shape, color.darkened(0.12))

		if commander_position == Vector2.INF:
			continue
		var commander_local: Vector2 = _world_to_local(
			commander_position, content_rect, world_bounds
		)
		var army_radius: float = clampf(3.4 + sqrt(float(army_size)) * 0.30, 4.0, 7.0)
		draw_circle(commander_local, army_radius + 2.2, Color(0.015, 0.01, 0.005, 0.94))
		draw_circle(commander_local, army_radius, color)
		var safe_facing: Vector2 = facing.normalized()
		if safe_facing.length_squared() < 0.01:
			safe_facing = Vector2.UP
		var side := Vector2(-safe_facing.y, safe_facing.x)
		var arrow := PackedVector2Array(
			[
				commander_local + safe_facing * (army_radius + 4.5),
				commander_local - safe_facing * 1.5 + side * 2.8,
				commander_local - safe_facing * 1.5 - side * 2.8,
			]
		)
		draw_colored_polygon(arrow, Color.WHITE if is_player else color.lightened(0.25))
		if is_player:
			draw_arc(
				commander_local,
				army_radius + 4.8,
				0.0,
				TAU,
				24,
				Color(1.0, 1.0, 1.0, 0.92),
				1.5,
				false
			)


func _draw_camera_view(content_rect: Rect2, world_bounds: Rect2) -> void:
	var view_rect: Rect2 = _snapshot.get("view_rect", Rect2())
	if view_rect.size == Vector2.ZERO:
		return
	var local_start: Vector2 = _world_to_local(view_rect.position, content_rect, world_bounds)
	var local_end: Vector2 = _world_to_local(view_rect.end, content_rect, world_bounds)
	var local_rect := Rect2(local_start, local_end - local_start).intersection(content_rect)
	if local_rect.size.x > 0.0 and local_rect.size.y > 0.0:
		# Outline only: a filled white rectangle read as a fog flash whenever
		# the camera rect moved across chunk boundaries.
		draw_rect(local_rect, Color(1.0, 1.0, 1.0, 0.92), false, 1.5)


func _draw_compass(content_rect: Rect2) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 10
	var color := Color(1.0, 0.88, 0.53, 0.88)
	draw_string(
		font,
		Vector2(content_rect.get_center().x - 3.0, content_rect.position.y + 13.0),
		"N",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)
	draw_string(
		font,
		Vector2(content_rect.position.x + 5.0, content_rect.get_center().y + 4.0),
		"W",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


func _world_to_local(world_position: Vector2, content_rect: Rect2, world_bounds: Rect2) -> Vector2:
	if not world_position.is_finite() or world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return content_rect.get_center()
	var normalized := Vector2(
		clampf((world_position.x - world_bounds.position.x) / world_bounds.size.x, 0.0, 1.0),
		clampf((world_position.y - world_bounds.position.y) / world_bounds.size.y, 0.0, 1.0)
	)
	return content_rect.position + normalized * content_rect.size
