extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/main_game.tscn"
const GROUND_NODE_HEADER: String = '[node name="Ground" type="Node2D" parent="World"]'

const SAMPLE_WORLD_Y: Array[float] = [
	-12000.0,
	-7000.0,
	-1600.0,
	-848.0,
	-840.0,
	0.0,
	7000.0,
	12000.0,
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_text: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	if scene_text.is_empty():
		_fail("Main scene text could not be read")
		return
	var ground_header_index: int = scene_text.find(GROUND_NODE_HEADER)
	if ground_header_index < 0:
		_fail("Main scene is missing the world ground root")
		return
	var next_node_index: int = scene_text.find("\n[node ", ground_header_index + 1)
	if next_node_index < 0:
		next_node_index = scene_text.length()
	var ground_block: String = scene_text.substr(
		ground_header_index, next_node_index - ground_header_index
	)
	var expected_ground_z: String = "z_index = %d" % WorldDepthPolicy.GROUND_ROOT_Z
	if not ground_block.contains(expected_ground_z):
		_fail("Main scene ground root is outside the reserved render band")
		return

	var ground_surface_z: int = (
		WorldDepthPolicy.GROUND_ROOT_Z + WorldDepthPolicy.GROUND_SURFACE_LOCAL_Z
	)
	if WorldDepthPolicy.FLAT_GROUND_PROP_Z <= ground_surface_z:
		_fail("Flat ground props must render above the ground surface")
		return
	if WorldDepthPolicy.DEPTH_MIN_Z <= WorldDepthPolicy.FLAT_GROUND_PROP_Z:
		_fail("Gameplay depth band must render above flat ground props")
		return

	var previous_prop_z: int = -999999
	for world_y in SAMPLE_WORLD_Y:
		var prop_z: int = WorldDepthPolicy.depth_z(world_y, WorldDepthPolicy.PROP_SUB_LAYER)
		var resource_z: int = WorldDepthPolicy.depth_z(
			world_y, WorldDepthPolicy.RESOURCE_STRUCTURE_SUB_LAYER
		)
		var unit_z: int = WorldDepthPolicy.depth_z(world_y, WorldDepthPolicy.unit_sub_layer(17))
		var projectile_z: int = WorldDepthPolicy.depth_z(
			world_y, WorldDepthPolicy.PROJECTILE_SUB_LAYER
		)
		if prop_z <= ground_surface_z or unit_z <= ground_surface_z:
			_fail("World actor crossed behind ground at Y=%s" % world_y)
			return
		if not (prop_z <= resource_z and resource_z <= unit_z and unit_z <= projectile_z):
			_fail("World render sub-layer order is invalid at Y=%s" % world_y)
			return
		if prop_z < previous_prop_z:
			_fail("Depth order is not monotonic while moving south")
			return
		previous_prop_z = prop_z

	var old_failure_y: float = -848.0
	var repaired_unit_z: int = WorldDepthPolicy.depth_z(
		old_failure_y, WorldDepthPolicy.unit_sub_layer(1)
	)
	if repaired_unit_z <= ground_surface_z:
		_fail("The recorded north-travel disappearance boundary is still unsafe")
		return

	print(
		(
			"PASS north_world_depth_regression_test ground=%d north_unit=%d old_boundary=%d"
			% [
				ground_surface_z,
				WorldDepthPolicy.depth_z(-12000.0, WorldDepthPolicy.unit_sub_layer(1)),
				repaired_unit_z,
			]
		)
	)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
