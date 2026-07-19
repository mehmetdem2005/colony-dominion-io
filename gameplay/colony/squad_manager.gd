class_name ColonySquadManager
extends RefCounted

var split_mode: bool = false
var spread_mode: bool = false
var split_distance: float = 185.0
var split_back_offset: float = 24.0
var normal_spacing_scale: float = 1.0
var spread_spacing_scale: float = 1.7


func split_units(units: Array[ColonyUnit], commander: ColonyUnit) -> bool:
	var candidates: Array[ColonyUnit] = []
	for unit in units:
		if (
			is_instance_valid(unit)
			and unit != commander
			and unit.definition != null
			and unit.is_alive()
		):
			candidates.append(unit)
	if candidates.size() < 4:
		return false

	candidates.sort_custom(_sort_units_for_balanced_split)
	for index in candidates.size():
		candidates[index].set_squad_id(index % 2)
	split_mode = true
	return true


func merge_units(units: Array[ColonyUnit]) -> void:
	for unit in units:
		if is_instance_valid(unit):
			unit.set_squad_id(0)
	split_mode = false


func toggle_spread() -> bool:
	spread_mode = not spread_mode
	return spread_mode


func set_spread(value: bool) -> void:
	spread_mode = value


func get_spacing_scale() -> float:
	return spread_spacing_scale if spread_mode else normal_spacing_scale


func assign_new_unit(unit: ColonyUnit, units: Array[ColonyUnit]) -> void:
	if not split_mode or unit.definition == null or unit.definition.role == &"commander":
		unit.set_squad_id(0)
		return
	var squad_zero: int = 0
	var squad_one: int = 0
	for candidate in units:
		if not is_instance_valid(candidate) or candidate == unit or candidate.definition == null:
			continue
		if candidate.definition.role == &"commander":
			continue
		if candidate.squad_id == 0:
			squad_zero += 1
		else:
			squad_one += 1
	unit.set_squad_id(0 if squad_zero <= squad_one else 1)


func get_anchor(commander: ColonyUnit, squad_id: int) -> Vector2:
	if not split_mode or not is_instance_valid(commander):
		return commander.global_position if is_instance_valid(commander) else Vector2.ZERO
	var direction: Vector2 = commander.facing_direction.normalized()
	if direction.length_squared() < 0.1:
		direction = Vector2.UP
	var right := Vector2(-direction.y, direction.x)
	var side: float = -1.0 if squad_id == 0 else 1.0
	var distance_scale: float = 1.25 if spread_mode else 1.0
	return (
		commander.global_position
		+ right * side * split_distance * distance_scale
		- direction * split_back_offset
	)


func _sort_units_for_balanced_split(a: ColonyUnit, b: ColonyUnit) -> bool:
	var a_role: String = String(a.definition.role) if a.definition != null else ""
	var b_role: String = String(b.definition.role) if b.definition != null else ""
	if a_role == b_role:
		return a.network_entity_id < b.network_entity_id
	return a_role < b_role
