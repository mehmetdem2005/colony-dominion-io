class_name ColonyInventory
extends RefCounted

signal changed(snapshot: Dictionary)

const RESOURCE_IDS: Array[StringName] = [&"seed", &"nectar", &"protein", &"leaf", &"stone"]
var _values: Dictionary = {}


func _init(starting_values: Dictionary = {}) -> void:
	for resource_id in RESOURCE_IDS:
		_values[resource_id] = int(starting_values.get(resource_id, 0))


func add(resource_id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	_values[resource_id] = int(_values.get(resource_id, 0)) + amount
	changed.emit(snapshot())


func add_batch(deltas: Dictionary) -> void:
	var changed_any: bool = false
	for resource_id in RESOURCE_IDS:
		var amount: int = int(deltas.get(resource_id, 0))
		if amount <= 0:
			continue
		_values[resource_id] = int(_values.get(resource_id, 0)) + amount
		changed_any = true
	if changed_any:
		changed.emit(snapshot())


func can_afford(definition: UnitDefinition) -> bool:
	return can_afford_cost(definition.get_cost())


func spend(definition: UnitDefinition) -> bool:
	return spend_cost(definition.get_cost())


func can_afford_cost(cost: Dictionary) -> bool:
	for resource_id in RESOURCE_IDS:
		var required: int = maxi(int(cost.get(resource_id, 0)), 0)
		if int(_values.get(resource_id, 0)) < required:
			return false
	return true


func spend_cost(cost: Dictionary) -> bool:
	if not can_afford_cost(cost):
		return false
	for resource_id in RESOURCE_IDS:
		var required: int = maxi(int(cost.get(resource_id, 0)), 0)
		_values[resource_id] = int(_values.get(resource_id, 0)) - required
	changed.emit(snapshot())
	return true


func get_amount(resource_id: StringName) -> int:
	return int(_values.get(resource_id, 0))


func snapshot() -> Dictionary:
	return _values.duplicate(true)
