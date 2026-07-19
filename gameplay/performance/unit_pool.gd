class_name ColonyUnitPool
extends RefCounted

const UNIT_SCENE := preload("res://scenes/units/unit.tscn")

var _root: Node2D = null
var _limit: int = 128
var _pool: Array[ColonyUnit] = []
var _created_count: int = 0
var _reused_count: int = 0
var _discarded_count: int = 0


func configure(root: Node2D, limit: int) -> void:
	_root = root
	_limit = clampi(limit, 0, 1024)


func acquire() -> ColonyUnit:
	while not _pool.is_empty():
		var pooled: ColonyUnit = _pool.pop_back()
		if not is_instance_valid(pooled) or pooled.is_queued_for_deletion():
			continue
		if pooled.get_parent() == null and is_instance_valid(_root):
			_root.add_child(pooled)
		_reused_count += 1
		return pooled
	if not is_instance_valid(_root):
		return null
	var unit := UNIT_SCENE.instantiate() as ColonyUnit
	_root.add_child(unit)
	_created_count += 1
	return unit


func release(unit: ColonyUnit) -> void:
	if not is_instance_valid(unit):
		return
	unit.deactivate_for_pool()
	if _pool.size() < _limit and not _pool.has(unit):
		var parent: Node = unit.get_parent()
		if is_instance_valid(parent):
			parent.remove_child(unit)
		_pool.append(unit)
		return
	_discarded_count += 1
	unit.queue_free()


func shutdown() -> void:
	for unit in _pool:
		if is_instance_valid(unit) and unit.get_parent() == null:
			unit.free()
	_pool.clear()
	_root = null


func get_stats() -> Dictionary:
	return {
		"pooled": _pool.size(),
		"created": _created_count,
		"reused": _reused_count,
		"discarded": _discarded_count,
	}


func get_pooled_count() -> int:
	return _pool.size()
