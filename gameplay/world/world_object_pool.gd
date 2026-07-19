class_name WorldObjectPool
extends RefCounted

const RESOURCE_SCENE := preload("res://scenes/resources/resource_node.tscn")
const PROP_SCENE := preload("res://scenes/world_stream_prop.tscn")

var _decoration_root: Node2D = null
var _resource_root: Node2D = null
var _presentation_enabled: bool = true
var _prop_limit: int = 260
var _resource_limit: int = 120
var _prop_pool: Array[StreamedWorldProp] = []
var _resource_pool: Array[WorldResourceNode] = []
var _texture_cache: Dictionary = {}
var _created_props: int = 0
var _created_resources: int = 0
var _reused_props: int = 0
var _reused_resources: int = 0


func configure(
	decoration_root: Node2D,
	resource_root: Node2D,
	presentation_enabled: bool,
	prop_limit: int,
	resource_limit: int
) -> void:
	_decoration_root = decoration_root
	_resource_root = resource_root
	_presentation_enabled = presentation_enabled
	_prop_limit = clampi(prop_limit, 0, 2048)
	_resource_limit = clampi(resource_limit, 0, 1024)


func acquire_prop() -> StreamedWorldProp:
	while not _prop_pool.is_empty():
		var pooled: StreamedWorldProp = _prop_pool.pop_back()
		if not is_instance_valid(pooled) or pooled.is_queued_for_deletion():
			continue
		if pooled.get_parent() == null and is_instance_valid(_decoration_root):
			_decoration_root.add_child(pooled)
		_reused_props += 1
		return pooled
	if not is_instance_valid(_decoration_root):
		return null
	var prop := PROP_SCENE.instantiate() as StreamedWorldProp
	_decoration_root.add_child(prop)
	_created_props += 1
	return prop


func acquire_resource() -> WorldResourceNode:
	while not _resource_pool.is_empty():
		var pooled: WorldResourceNode = _resource_pool.pop_back()
		if not is_instance_valid(pooled) or pooled.is_queued_for_deletion():
			continue
		if pooled.get_parent() == null and is_instance_valid(_resource_root):
			_resource_root.add_child(pooled)
		_reused_resources += 1
		return pooled
	if not is_instance_valid(_resource_root):
		return null
	var resource := RESOURCE_SCENE.instantiate() as WorldResourceNode
	_resource_root.add_child(resource)
	_created_resources += 1
	return resource


func release_prop(prop: StreamedWorldProp) -> void:
	if not is_instance_valid(prop):
		return
	prop.deactivate()
	if _prop_pool.size() < _prop_limit and not _prop_pool.has(prop):
		var parent: Node = prop.get_parent()
		if is_instance_valid(parent):
			parent.remove_child(prop)
		_prop_pool.append(prop)
		return
	prop.queue_free()


func release_resource(resource: WorldResourceNode) -> void:
	if not is_instance_valid(resource):
		return
	resource.deactivate_streamed()
	if _resource_pool.size() < _resource_limit and not _resource_pool.has(resource):
		var parent: Node = resource.get_parent()
		if is_instance_valid(parent):
			parent.remove_child(resource)
		_resource_pool.append(resource)
		return
	resource.queue_free()


func get_texture(path: String) -> Texture2D:
	if not _presentation_enabled or path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path] as Texture2D
	var texture := load(path) as Texture2D
	_texture_cache[path] = texture
	return texture


func prewarm_texture_cache() -> void:
	for config in WorldContentCatalog.PROP_VARIANTS:
		get_texture(String(config.get("path", "")))
	for config in WorldContentCatalog.RESOURCE_VARIANTS:
		get_texture(String(config.get("path", "")))


func get_stats() -> Dictionary:
	return {
		"props": _prop_pool.size(),
		"resources": _resource_pool.size(),
		"created_props": _created_props,
		"created_resources": _created_resources,
		"reused_props": _reused_props,
		"reused_resources": _reused_resources,
		"cached_textures": _texture_cache.size(),
	}


func shutdown() -> void:
	for prop in _prop_pool:
		if is_instance_valid(prop) and prop.get_parent() == null:
			prop.free()
	_prop_pool.clear()
	for resource in _resource_pool:
		if is_instance_valid(resource) and resource.get_parent() == null:
			resource.free()
	_resource_pool.clear()
	_texture_cache.clear()
	_decoration_root = null
	_resource_root = null
