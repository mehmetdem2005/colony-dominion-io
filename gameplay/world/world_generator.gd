class_name WorldGenerator
extends Node

const RESOURCE_SCENE := preload("res://scenes/resources/resource_node.tscn")
const GROUND_WORLD_TEXTURE := preload("res://assets/ground/ground_world.png")

const PROP_CONFIGS := [
	{
		"path": "res://assets/props/tall_grass.png",
		"count": 22,
		"size": 185.0,
		"radius": 42.0,
		"solid": false
	},
	{
		"path": "res://assets/props/medium_grass.png",
		"count": 20,
		"size": 145.0,
		"radius": 34.0,
		"solid": false
	},
	{
		"path": "res://assets/props/low_bush.png",
		"count": 18,
		"size": 130.0,
		"radius": 32.0,
		"solid": false
	},
	{
		"path": "res://assets/props/broad_leaf.png",
		"count": 13,
		"size": 210.0,
		"radius": 56.0,
		"solid": true
	},
	{
		"path": "res://assets/props/large_rock.png",
		"count": 11,
		"size": 155.0,
		"radius": 54.0,
		"solid": true
	},
	{
		"path": "res://assets/props/medium_rock.png",
		"count": 15,
		"size": 105.0,
		"radius": 37.0,
		"solid": true
	},
	{
		"path": "res://assets/props/small_rock.png",
		"count": 20,
		"size": 72.0,
		"radius": 24.0,
		"solid": true
	},
	{
		"path": "res://assets/props/mushroom_large.png",
		"count": 8,
		"size": 132.0,
		"radius": 35.0,
		"solid": true
	},
	{
		"path": "res://assets/props/mushroom_pair.png",
		"count": 10,
		"size": 116.0,
		"radius": 31.0,
		"solid": true
	},
	{
		"path": "res://assets/props/stump.png",
		"count": 7,
		"size": 245.0,
		"radius": 72.0,
		"solid": true
	},
	{
		"path": "res://assets/props/mud_puddle.png",
		"count": 10,
		"size": 250.0,
		"radius": 80.0,
		"solid": false,
		"ground": true
	},
]

const RESOURCE_CONFIGS := [
	{
		"type": &"seed",
		"path": "res://assets/resources/seeds.png",
		"count": 18,
		"amount": 70,
		"size": 82.0
	},
	{
		"type": &"nectar",
		"path": "res://assets/resources/nectar.png",
		"count": 15,
		"amount": 58,
		"size": 86.0
	},
	{
		"type": &"protein",
		"path": "res://assets/resources/protein.png",
		"count": 14,
		"amount": 64,
		"size": 144.0
	},
	{
		"type": &"leaf",
		"path": "res://assets/resources/leaves.png",
		"count": 16,
		"amount": 65,
		"size": 82.0
	},
	{
		"type": &"leaf",
		"path": "res://assets/resources/pod.png",
		"count": 10,
		"amount": 78,
		"size": 88.0
	},
	{
		"type": &"stone",
		"path": "res://assets/resources/stone.png",
		"count": 13,
		"amount": 58,
		"size": 92.0
	},
]

var _rng := RandomNumberGenerator.new()
var _bounds := Rect2()
var _safe_positions: Array[Vector2] = []


func generate(
	bounds: Rect2,
	ground_root: Node2D,
	decoration_root: Node2D,
	resource_root: Node2D,
	safe_positions: Array[Vector2]
) -> void:
	_rng.seed = 738291
	_bounds = bounds
	_safe_positions = safe_positions
	_create_ground_tiles(ground_root)
	_create_decorations(decoration_root)
	_create_resources(resource_root)


func _create_ground_tiles(parent: Node2D) -> void:
	var underlay := Polygon2D.new()
	underlay.name = "GroundOverscan"
	var padded_bounds: Rect2 = _bounds.grow(760.0)
	underlay.polygon = PackedVector2Array(
		[
			padded_bounds.position,
			Vector2(padded_bounds.end.x, padded_bounds.position.y),
			padded_bounds.end,
			Vector2(padded_bounds.position.x, padded_bounds.end.y),
		]
	)
	underlay.color = Color("9d6a35")
	underlay.z_index = WorldDepthPolicy.GROUND_UNDERLAY_LOCAL_Z
	parent.add_child(underlay)

	var ground := Sprite2D.new()
	ground.name = "GroundWorld"
	ground.texture = GROUND_WORLD_TEXTURE
	ground.centered = false
	ground.position = _bounds.position
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ground.z_index = WorldDepthPolicy.GROUND_SURFACE_LOCAL_Z
	parent.add_child(ground)


func _create_decorations(parent: Node2D) -> void:
	for config in PROP_CONFIGS:
		var texture := load(String(config["path"])) as Texture2D
		var count := int(config["count"])
		for _index in count:
			var position := _random_valid_position(
				190.0 if bool(config.get("solid", false)) else 125.0
			)
			_spawn_prop(
				parent,
				texture,
				position,
				float(config["size"]),
				float(config["radius"]),
				bool(config.get("solid", false)),
				bool(config.get("ground", false))
			)


func _spawn_prop(
	parent: Node2D,
	texture: Texture2D,
	world_position: Vector2,
	world_size: float,
	radius: float,
	solid: bool,
	ground_prop: bool
) -> void:
	var holder: Node2D
	if solid:
		var body := StaticBody2D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var shape_node := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = radius
		shape_node.shape = shape
		body.add_child(shape_node)
		holder = body
	else:
		holder = Node2D.new()
	holder.y_sort_enabled = true
	holder.z_index = (
		WorldDepthPolicy.FLAT_GROUND_PROP_Z
		if ground_prop
		else WorldDepthPolicy.depth_z(world_position.y, WorldDepthPolicy.PROP_SUB_LAYER)
	)
	parent.add_child(holder)
	holder.global_position = world_position
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if texture != null:
		var longest := float(max(texture.get_width(), texture.get_height()))
		sprite.scale = Vector2.ONE * (world_size / maxf(longest, 1.0))
	holder.add_child(sprite)


func _create_resources(parent: Node2D) -> void:
	for config in RESOURCE_CONFIGS:
		var texture := load(String(config["path"])) as Texture2D
		for _index in int(config["count"]):
			var resource := RESOURCE_SCENE.instantiate() as WorldResourceNode
			parent.add_child(resource)
			resource.global_position = _random_valid_position(145.0)
			resource.configure(
				config["type"], texture, int(config["amount"]), float(config["size"])
			)
			resource.refresh_world_depth()
			resource.respawn_delay = _rng.randf_range(18.0, 30.0)


func _random_valid_position(safe_radius: float) -> Vector2:
	for _attempt in 70:
		var point := Vector2(
			_rng.randf_range(_bounds.position.x + 95.0, _bounds.end.x - 95.0),
			_rng.randf_range(_bounds.position.y + 95.0, _bounds.end.y - 95.0)
		)
		var valid := true
		for safe_position in _safe_positions:
			if point.distance_to(safe_position) < safe_radius:
				valid = false
				break
		if valid:
			return point
	return _bounds.get_center()
