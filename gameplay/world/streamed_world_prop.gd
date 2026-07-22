class_name StreamedWorldProp
extends StaticBody2D

const CONTENT_CATALOG_SCRIPT := preload("res://gameplay/world/world_content_catalog.gd")

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var pool_key: StringName = &""
var active: bool = false
var stream_resident: bool = false

var _solid_when_resident: bool = false
var _proximity_suppressed: bool = false
var _collision_radius: float = 1.0
var _content_group: StringName = &""


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
	_leave_content_group()
	pool_key = key
	active = true
	# `solid` reserves deterministic chunk-placement space. Runtime collision is
	# a separate catalog policy so decoration-only props never block units.
	_solid_when_resident = CONTENT_CATALOG_SCRIPT.is_collision_enabled(key, solid)
	_proximity_suppressed = false
	_collision_radius = maxf(radius, 1.0)
	_content_group = _resolve_content_group(key)
	if not _content_group.is_empty() and is_inside_tree():
		add_to_group(_content_group)
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


func _refresh_residency_state() -> void:
	visible = stream_resident
	process_mode = Node.PROCESS_MODE_INHERIT if stream_resident else Node.PROCESS_MODE_DISABLED
	var collision_enabled: bool = (
		stream_resident and _solid_when_resident and not _proximity_suppressed
	)
	collision_layer = (1 << 6) if collision_enabled else 0
	if is_instance_valid(collision_shape):
		collision_shape.disabled = not collision_enabled


func _resolve_content_group(key: StringName) -> StringName:
	for config in CONTENT_CATALOG_SCRIPT.PROP_VARIANTS:
		if StringName(config.get("key", &"")) == key:
			return StringName(config.get("group", &""))
	return &""


func _leave_content_group() -> void:
	if not _content_group.is_empty() and is_inside_tree() and is_in_group(_content_group):
		remove_from_group(_content_group)
	_content_group = &""


func deactivate() -> void:
	_leave_content_group()
	active = false
	_solid_when_resident = false
	_proximity_suppressed = false
	_collision_radius = 1.0
	set_stream_residency(false)
	if is_instance_valid(sprite):
		sprite.texture = null
