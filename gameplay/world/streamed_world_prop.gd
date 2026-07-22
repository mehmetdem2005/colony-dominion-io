class_name StreamedWorldProp
extends StaticBody2D

const WILD_WEED_GROUP: StringName = &"yabani_otlar"
const WILD_WEED_KEY_PREFIX: String = "wild_weed_"
const WILD_WEED_VISUAL_GAP: float = 12.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var pool_key: StringName = &""
var active: bool = false
var stream_resident: bool = false

var _solid_when_resident: bool = false
var _proximity_suppressed: bool = false
var _overlap_suppressed: bool = false
var _collision_radius: float = 1.0
var _is_wild_weed: bool = false


func _ready() -> void:
	collision_mask = 0
	deactivate()


func activate(
	texture: Texture2D,
	world_position: Vector2,
	world_size: float,
	radius: float,
	solid: bool,
	ground_prop: bool,
	rotation_value: float,
	flip_h_value: bool,
	modulate_value: Color,
	key: StringName
) -> void:
	_leave_wild_weed_group()
	pool_key = key
	active = true
	_solid_when_resident = solid
	_proximity_suppressed = false
	_overlap_suppressed = false
	_collision_radius = maxf(radius, 1.0)
	_is_wild_weed = String(key).begins_with(WILD_WEED_KEY_PREFIX)
	if _is_wild_weed and is_inside_tree():
		add_to_group(WILD_WEED_GROUP)
	global_position = world_position
	rotation = rotation_value
	z_index = (
		WorldDepthPolicy.FLAT_GROUND_PROP_Z
		if ground_prop
		else WorldDepthPolicy.depth_z(world_position.y, WorldDepthPolicy.PROP_SUB_LAYER)
	)
	sprite.texture = texture
	sprite.flip_h = flip_h_value
	sprite.modulate = modulate_value
	if texture != null:
		var longest: float = float(max(texture.get_width(), texture.get_height()))
		sprite.scale = Vector2.ONE * (world_size / maxf(longest, 1.0))
	else:
		sprite.scale = Vector2.ONE
	reset_physics_interpolation()
	var circle := collision_shape.shape as CircleShape2D
	if circle != null:
		circle.radius = _collision_radius
	# Build jobs may span several rendered frames. Keep the prop completely dormant
	# until the chunk residency owner atomically applies the requested state.
	set_stream_residency(false)


func set_stream_residency(enabled: bool) -> void:
	stream_resident = enabled and active
	if stream_resident and _is_wild_weed:
		_refresh_wild_weed_overlap()
	else:
		_overlap_suppressed = false
	_refresh_residency_state()


func set_proximity_suppressed(value: bool) -> void:
	if _proximity_suppressed == value:
		return
	_proximity_suppressed = value
	_refresh_residency_state()


func get_collision_radius() -> float:
	return _collision_radius


func is_proximity_suppressed() -> bool:
	return _proximity_suppressed


func is_overlap_suppressed() -> bool:
	return _overlap_suppressed


func _refresh_wild_weed_overlap() -> void:
	_overlap_suppressed = false
	if not _is_wild_weed or not stream_resident or not is_inside_tree():
		return
	for candidate in get_tree().get_nodes_in_group(WILD_WEED_GROUP):
		if candidate == self or not candidate is StreamedWorldProp:
			continue
		var other := candidate as StreamedWorldProp
		if (
			not other.active
			or not other.stream_resident
			or other._overlap_suppressed
			or not other._is_wild_weed
		):
			continue
		var minimum_distance: float = (
			_collision_radius + other._collision_radius + WILD_WEED_VISUAL_GAP
		)
		if global_position.distance_squared_to(other.global_position) < minimum_distance * minimum_distance:
			_overlap_suppressed = true
			return


func _recheck_wild_weed_overlap() -> void:
	if not active or not stream_resident or not _is_wild_weed:
		return
	var was_suppressed: bool = _overlap_suppressed
	_refresh_wild_weed_overlap()
	if was_suppressed != _overlap_suppressed:
		_refresh_residency_state()


func _notify_wild_weed_registry_changed() -> void:
	if not is_inside_tree():
		return
	for candidate in get_tree().get_nodes_in_group(WILD_WEED_GROUP):
		if candidate == self or not candidate is StreamedWorldProp:
			continue
		(candidate as StreamedWorldProp).call_deferred("_recheck_wild_weed_overlap")


func _refresh_residency_state() -> void:
	visible = stream_resident and not _overlap_suppressed
	process_mode = Node.PROCESS_MODE_INHERIT if visible else Node.PROCESS_MODE_DISABLED
	var collision_enabled: bool = (
		stream_resident and _solid_when_resident and not _proximity_suppressed
	)
	collision_layer = (1 << 6) if collision_enabled else 0
	if is_instance_valid(collision_shape):
		collision_shape.disabled = not collision_enabled


func _leave_wild_weed_group() -> void:
	if is_inside_tree() and is_in_group(WILD_WEED_GROUP):
		remove_from_group(WILD_WEED_GROUP)


func deactivate() -> void:
	var notify_registry: bool = _is_wild_weed and is_inside_tree()
	_leave_wild_weed_group()
	active = false
	_solid_when_resident = false
	_proximity_suppressed = false
	_overlap_suppressed = false
	_collision_radius = 1.0
	_is_wild_weed = false
	set_stream_residency(false)
	if is_instance_valid(sprite):
		sprite.texture = null
	if notify_registry:
		_notify_wild_weed_registry_changed()
