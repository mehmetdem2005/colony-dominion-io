class_name NetworkEntityRegistry
extends RefCounted

var _next_entity_id: int = 1
var _instance_ids_by_entity: Dictionary = {}


func register(node: Node, preferred_entity_id: int = 0) -> int:
	if not is_instance_valid(node):
		return 0
	var entity_id: int = preferred_entity_id
	if entity_id <= 0:
		entity_id = _allocate_entity_id()
	else:
		var existing: Node = resolve(entity_id)
		if is_instance_valid(existing):
			return entity_id if existing == node else 0
		_next_entity_id = maxi(_next_entity_id, entity_id + 1)
	_instance_ids_by_entity[entity_id] = node.get_instance_id()
	return entity_id


func _allocate_entity_id() -> int:
	while _instance_ids_by_entity.has(_next_entity_id):
		_next_entity_id += 1
	var entity_id: int = _next_entity_id
	_next_entity_id += 1
	return entity_id


func unregister(entity_id: int, expected_node: Node = null) -> void:
	if entity_id <= 0 or not _instance_ids_by_entity.has(entity_id):
		return
	if is_instance_valid(expected_node):
		var registered_id: int = int(_instance_ids_by_entity[entity_id])
		if registered_id != expected_node.get_instance_id():
			return
	_instance_ids_by_entity.erase(entity_id)


func resolve(entity_id: int) -> Node:
	if entity_id <= 0 or not _instance_ids_by_entity.has(entity_id):
		return null
	var instance_id: int = int(_instance_ids_by_entity[entity_id])
	if instance_id <= 0 or not is_instance_id_valid(instance_id):
		_instance_ids_by_entity.erase(entity_id)
		return null
	var candidate: Object = instance_from_id(instance_id)
	if not is_instance_valid(candidate) or not candidate is Node:
		_instance_ids_by_entity.erase(entity_id)
		return null
	var node := candidate as Node
	if node.is_queued_for_deletion() or not node.is_inside_tree():
		_instance_ids_by_entity.erase(entity_id)
		return null
	var registered_entity_id: int = int(node.get("network_entity_id"))
	if registered_entity_id != entity_id:
		_instance_ids_by_entity.erase(entity_id)
		return null
	return node


func get_registered_count() -> int:
	return _instance_ids_by_entity.size()


func clear() -> void:
	_instance_ids_by_entity.clear()
	_next_entity_id = 1
