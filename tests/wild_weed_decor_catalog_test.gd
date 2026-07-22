extends SceneTree

const CATALOG := preload("res://gameplay/world/world_content_catalog.gd")
const EXPECTED_WEED_COUNT: int = 10


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var seen_keys: Dictionary = {}
	var seen_paths: Dictionary = {}

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
			failures.append("Wild weed is outside the yabani_otlar group: %s" % key)
		if bool(config.get("solid", true)):
			failures.append("Decor-only wild weed has collision enabled: %s" % key)
		if bool(config.get("ground", true)):
			failures.append("Wild weed must use normal world depth: %s" % key)
		if not bool(config.get("decor_only", false)):
			failures.append("Wild weed is missing decor_only metadata: %s" % key)
		if not path.begins_with("res://assets/props/wild_weeds/"):
			failures.append("Wild weed path is outside its asset pack: %s" % path)
		if seen_keys.has(key):
			failures.append("Duplicate wild weed key: %s" % key)
		if seen_paths.has(path):
			failures.append("Duplicate wild weed path: %s" % path)
		seen_keys[key] = true
		seen_paths[path] = true
		_validate_texture(path, failures)

	for biome_variant in CATALOG.BIOME_PROP_INDICES.keys():
		var biome := StringName(biome_variant)
		var indices: Array = CATALOG.BIOME_PROP_INDICES[biome]
		var contains_wild_weed: bool = false
		for index_variant in indices:
			var index := int(index_variant)
			if index < 0 or index >= CATALOG.PROP_VARIANTS.size():
				failures.append("Biome %s contains invalid prop index %d" % [biome, index])
			if CATALOG.WILD_WEED_PROP_INDICES.has(index):
				contains_wild_weed = true
		if not contains_wild_weed:
			failures.append("Biome %s contains no wild weed decoration" % biome)

	var prop_source := FileAccess.get_file_as_string(
		"res://gameplay/world/streamed_world_prop.gd"
	)
	for marker in [
		'WILD_WEED_GROUP: StringName = &"yabani_otlar"',
		"WILD_WEED_VISUAL_GAP",
		"_refresh_wild_weed_overlap",
		"_overlap_suppressed",
	]:
		if not prop_source.contains(marker):
			failures.append("Wild weed overlap guard is missing marker: %s" % marker)

	if failures.is_empty():
		print("PASS wild_weed_decor_catalog_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_texture(path: String, failures: PackedStringArray) -> void:
	if not FileAccess.file_exists(path):
		failures.append("Wild weed texture is missing: %s" % path)
		return
	var image := Image.load_from_file(path)
	if image.is_empty():
		failures.append("Wild weed texture cannot be decoded: %s" % path)
		return
	if image.get_width() != 384 or image.get_height() != 384:
		failures.append("Wild weed texture must be 384x384: %s" % path)
	for corner in [
		Vector2i(0, 0),
		Vector2i(image.get_width() - 1, 0),
		Vector2i(0, image.get_height() - 1),
		Vector2i(image.get_width() - 1, image.get_height() - 1),
	]:
		if image.get_pixelv(corner).a > 0.01:
			failures.append("Wild weed texture background is not transparent: %s" % path)
			break
