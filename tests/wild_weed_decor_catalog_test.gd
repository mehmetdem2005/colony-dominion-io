extends SceneTree

const CATALOG := preload("res://gameplay/world/world_content_catalog.gd")
const PROP_SCENE := preload("res://scenes/world_stream_prop.tscn")
const EXPECTED_WEED_COUNT: int = 10
const ATLAS_PATH: String = "res://assets/props/wild_weeds/wild_weeds_atlas.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var seen_keys: Dictionary = {}
	var seen_paths: Dictionary = {}

	_validate_atlas(failures)
	_validate_catalog(failures, seen_keys, seen_paths)
	_validate_biome_coverage(failures)
	_validate_placement_contract(failures)
	await _validate_runtime_prop(failures)

	if failures.is_empty():
		print("PASS wild_weed_decor_catalog_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_atlas(failures: PackedStringArray) -> void:
	if not FileAccess.file_exists(ATLAS_PATH):
		failures.append("Wild weed atlas is missing")
		return
	var image := Image.load_from_file(ATLAS_PATH)
	if image.is_empty():
		failures.append("Wild weed atlas cannot be decoded")
		return
	if image.get_width() != 1280 or image.get_height() != 512:
		failures.append("Wild weed atlas must be 1280x512")
	for corner in [
		Vector2i(0, 0),
		Vector2i(image.get_width() - 1, 0),
		Vector2i(0, image.get_height() - 1),
		Vector2i(image.get_width() - 1, image.get_height() - 1),
	]:
		if image.get_pixelv(corner).a > 0.01:
			failures.append("Wild weed atlas background is not transparent")
			break


func _validate_catalog(
	failures: PackedStringArray, seen_keys: Dictionary, seen_paths: Dictionary
) -> void:
	if CATALOG.WILD_WEED_PROP_INDICES.size() != EXPECTED_WEED_COUNT:
		failures.append("Wild weed catalog must contain exactly %d variants" % EXPECTED_WEED_COUNT)
	for index in CATALOG.WILD_WEED_PROP_INDICES:
		if index < 0 or index >= CATALOG.PROP_VARIANTS.size():
			failures.append("Wild weed index is out of range: %d" % index)
			continue
		var config: Dictionary = CATALOG.PROP_VARIANTS[index]
		var key := StringName(config.get("key", &""))
		var path := String(config.get("path", ""))
		if not String(key).begins_with("wild_weed_"):
			failures.append("Wild weed key is invalid: %s" % key)
		if config.get("group", &"") != CATALOG.GROUP_WILD_WEEDS:
			failures.append("Wild weed is outside yabani_otlar: %s" % key)
		if not bool(config.get("solid", false)):
			failures.append("Wild weed does not reserve placement space: %s" % key)
		if bool(config.get("collision", true)):
			failures.append("Decor-only wild weed has runtime collision: %s" % key)
		if bool(config.get("ground", true)):
			failures.append("Wild weed must use normal world depth: %s" % key)
		if not bool(config.get("decor_only", false)):
			failures.append("Wild weed lacks decor_only metadata: %s" % key)
		if not path.begins_with("res://assets/props/wild_weeds/") or not path.ends_with(".tres"):
			failures.append("Wild weed does not use an atlas region resource: %s" % path)
		if seen_keys.has(key):
			failures.append("Duplicate wild weed key: %s" % key)
		if seen_paths.has(path):
			failures.append("Duplicate wild weed region path: %s" % path)
		seen_keys[key] = true
		seen_paths[path] = true
		if CATALOG.is_collision_enabled(key, true):
			failures.append("Catalog collision policy is not fail-closed: %s" % key)
		_validate_region_resource(path, failures)


func _validate_region_resource(path: String, failures: PackedStringArray) -> void:
	if not ResourceLoader.exists(path, "Texture2D"):
		failures.append("Wild weed region is missing: %s" % path)
		return
	var texture := load(path) as Texture2D
	if texture == null:
		failures.append("Wild weed region cannot be loaded: %s" % path)
		return
	if texture.get_width() != 256 or texture.get_height() != 256:
		failures.append("Wild weed atlas region must be 256x256: %s" % path)


func _validate_biome_coverage(failures: PackedStringArray) -> void:
	for biome_variant in CATALOG.BIOME_PROP_INDICES.keys():
		var biome := StringName(biome_variant)
		var indices: Array = CATALOG.BIOME_PROP_INDICES[biome]
		var contains_wild_weed: bool = false
		for index_variant in indices:
			var index := int(index_variant)
			if index < 0 or index >= CATALOG.PROP_VARIANTS.size():
				failures.append("Biome %s contains invalid prop index %d" % [biome, index])
				continue
			if CATALOG.WILD_WEED_PROP_INDICES.has(index):
				contains_wild_weed = true
		if not contains_wild_weed:
			failures.append("Biome %s contains no wild weed decoration" % biome)


func _validate_placement_contract(failures: PackedStringArray) -> void:
	var source := FileAccess.get_file_as_string("res://gameplay/world/world_stream_manager.gd")
	for marker in [
		"var is_solid: bool = bool(prop_config.get(\"solid\", false))",
		"job.occupied_positions.append(position)",
		"job.occupied_radii.append(radius)",
	]:
		if not source.contains(marker):
			failures.append("Deterministic prop spacing contract is missing: %s" % marker)
	var prop_source := FileAccess.get_file_as_string(
		"res://gameplay/world/streamed_world_prop.gd"
	)
	if prop_source.contains("get_nodes_in_group"):
		failures.append("Wild weed overlap must not use runtime O(n²) group scans")
	for marker in [
		"CONTENT_CATALOG_SCRIPT.is_collision_enabled",
		"add_to_group(_content_group)",
		"remove_from_group(_content_group)",
	]:
		if not prop_source.contains(marker):
			failures.append("Decor-only runtime policy is missing: %s" % marker)


func _validate_runtime_prop(failures: PackedStringArray) -> void:
	var config: Dictionary = CATALOG.PROP_VARIANTS[CATALOG.WILD_WEED_PROP_INDICES[0]]
	var prop := PROP_SCENE.instantiate() as StreamedWorldProp
	root.add_child(prop)
	await process_frame
	var texture := load(String(config.get("path", ""))) as Texture2D
	prop.activate(
		texture,
		Vector2(300.0, 300.0),
		float(config.get("size", 160.0)),
		float(config.get("radius", 64.0)),
		bool(config.get("solid", true)),
		bool(config.get("ground", false)),
		0.0,
		false,
		Color.WHITE,
		StringName(config.get("key", &""))
	)
	prop.set_stream_residency(true)
	await process_frame
	if not prop.visible:
		failures.append("Resident wild weed is not visible")
	if prop.collision_layer != 0:
		failures.append("Wild weed entered a physics collision layer")
	var shape := prop.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null or not shape.disabled:
		failures.append("Wild weed collision shape is enabled")
	if not prop.is_in_group(CATALOG.GROUP_WILD_WEEDS):
		failures.append("Wild weed was not registered in yabani_otlar")
	prop.deactivate()
	if prop.is_in_group(CATALOG.GROUP_WILD_WEEDS):
		failures.append("Pooled wild weed remained in yabani_otlar")
	prop.queue_free()
