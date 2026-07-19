class_name ColonyProgression
extends RefCounted

signal changed(level: int, capacity: int, next_cost: Dictionary)

const MAX_LEVEL: int = 4
const CAPACITY_BY_LEVEL: Array[int] = [0, 18, 30, 44, 60]
const GATHER_MULTIPLIER_BY_LEVEL: Array[float] = [0.0, 1.0, 1.12, 1.25, 1.40]
const PRODUCTION_TIME_MULTIPLIER_BY_LEVEL: Array[float] = [0.0, 1.0, 0.90, 0.80, 0.70]
const UPGRADE_COSTS := {
	1: {&"seed": 80, &"nectar": 35, &"protein": 0, &"leaf": 20, &"stone": 0},
	2: {&"seed": 140, &"nectar": 0, &"protein": 65, &"leaf": 50, &"stone": 30},
	3: {&"seed": 220, &"nectar": 120, &"protein": 100, &"leaf": 80, &"stone": 55},
}

var level: int = 1


func get_capacity() -> int:
	return CAPACITY_BY_LEVEL[clampi(level, 1, MAX_LEVEL)]


func get_gather_multiplier() -> float:
	return GATHER_MULTIPLIER_BY_LEVEL[clampi(level, 1, MAX_LEVEL)]


func get_production_time_multiplier() -> float:
	return PRODUCTION_TIME_MULTIPLIER_BY_LEVEL[clampi(level, 1, MAX_LEVEL)]


func is_max_level() -> bool:
	return level >= MAX_LEVEL


func get_next_upgrade_cost() -> Dictionary:
	if is_max_level():
		return {}
	return (UPGRADE_COSTS.get(level, {}) as Dictionary).duplicate(true)


func can_upgrade(inventory: ColonyInventory) -> bool:
	return not is_max_level() and inventory.can_afford_cost(get_next_upgrade_cost())


func try_upgrade(inventory: ColonyInventory) -> bool:
	if not can_upgrade(inventory):
		return false
	if not inventory.spend_cost(get_next_upgrade_cost()):
		return false
	level += 1
	changed.emit(level, get_capacity(), get_next_upgrade_cost())
	return true


func emit_state() -> void:
	changed.emit(level, get_capacity(), get_next_upgrade_cost())
