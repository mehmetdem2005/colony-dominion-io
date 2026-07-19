extends SceneTree

const REGISTRY_SCRIPT := preload("res://gameplay/network/network_entity_registry.gd")


class EntityStub:
	extends Node

	var network_entity_id: int = 0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var registry: NetworkEntityRegistry = REGISTRY_SCRIPT.new()
	var entity := EntityStub.new()
	root.add_child(entity)
	var first_id: int = registry.register(entity)
	entity.network_entity_id = first_id
	if registry.resolve(first_id) != entity:
		_fail("Live entity could not be resolved")
		return

	registry.unregister(first_id, entity)
	var second_id: int = registry.register(entity)
	entity.network_entity_id = second_id
	if second_id == first_id:
		_fail("Entity id was reused inside a match")
		return
	if registry.resolve(first_id) != null:
		_fail("Retired entity id resolved to a pooled node")
		return
	if registry.resolve(second_id) != entity:
		_fail("Reactivated pooled entity could not be resolved")
		return

	entity.free()
	if registry.resolve(second_id) != null:
		_fail("Freed entity was returned by the registry")
		return
	print("PASS network_entity_registry_test")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
