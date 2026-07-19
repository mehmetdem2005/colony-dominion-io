class_name WorldDepthPolicy
extends RefCounted

# One deterministic depth domain is shared by every world-space visual. The
# playable world currently spans Y=-12000..12000, which maps safely into the
# CanvasItem Z range without ever crossing the ground render band.
const WORLD_STEP: float = 16.0
const SUB_LAYERS: int = 4
const HYSTERESIS: float = 4.0

const GROUND_ROOT_Z: int = -4090
const GROUND_UNDERLAY_LOCAL_Z: int = 0
const GROUND_SURFACE_LOCAL_Z: int = 1
const FLAT_GROUND_PROP_Z: int = -3500

const DEPTH_MIN_Z: int = -3200
const DEPTH_MAX_Z: int = 3203

const PROP_SUB_LAYER: int = 0
const RESOURCE_STRUCTURE_SUB_LAYER: int = 1
const UNIT_SUB_LAYER_BASE: int = 2
const UNIT_SUB_LAYER_COUNT: int = 2
const PROJECTILE_SUB_LAYER: int = 3


static func bucket_for_world_y(world_y: float) -> int:
	if not is_finite(world_y):
		return 0
	return floori(world_y / WORLD_STEP)


static func depth_z_from_bucket(bucket: int, sub_layer: int) -> int:
	var safe_sub_layer: int = clampi(sub_layer, 0, SUB_LAYERS - 1)
	return clampi(bucket * SUB_LAYERS + safe_sub_layer, DEPTH_MIN_Z, DEPTH_MAX_Z)


static func depth_z(world_y: float, sub_layer: int = PROP_SUB_LAYER) -> int:
	return depth_z_from_bucket(bucket_for_world_y(world_y), sub_layer)


static func unit_sub_layer(entity_id: int) -> int:
	return UNIT_SUB_LAYER_BASE + posmod(entity_id, UNIT_SUB_LAYER_COUNT)
