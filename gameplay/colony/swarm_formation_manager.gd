class_name SwarmFormationManager
extends RefCounted

const BASE_RING_RADIUS: float = 78.0
const RING_GAP: float = 48.0
const FIRST_RING_CAPACITY: int = 8
const RING_CAPACITY_STEP: int = 4

var _local_offsets: Dictionary = {}


func rebuild(
	units: Array[ColonyUnit], commander: ColonyUnit, squad_manager: ColonySquadManager
) -> void:
	_local_offsets.clear()
	if not is_instance_valid(commander):
		return

	var squad_zero: Array[ColonyUnit] = []
	var squad_one: Array[ColonyUnit] = []
	for unit in units:
		if (
			not is_instance_valid(unit)
			or unit == commander
			or unit.definition == null
			or not unit.is_alive()
		):
			continue
		if squad_manager.split_mode and unit.squad_id == 1:
			squad_one.append(unit)
		else:
			squad_zero.append(unit)

	_assign_slots(squad_zero, squad_manager.get_spacing_scale())
	_assign_slots(squad_one, squad_manager.get_spacing_scale())


func get_local_offset(unit: ColonyUnit) -> Vector2:
	if not is_instance_valid(unit):
		return Vector2.ZERO
	var offset: Vector2 = _local_offsets.get(unit.network_entity_id, Vector2.ZERO)
	return offset


func has_unit(unit: ColonyUnit) -> bool:
	return is_instance_valid(unit) and _local_offsets.has(unit.network_entity_id)


func _assign_slots(members: Array[ColonyUnit], spacing_scale: float) -> void:
	if members.is_empty():
		return
	members.sort_custom(_sort_by_tactical_priority)
	var available_slots: Array[Vector2] = _generate_slots(members.size(), spacing_scale)
	for unit in members:
		if available_slots.is_empty():
			break
		var slot_index: int = _choose_slot_index(unit, available_slots)
		var chosen_offset: Vector2 = available_slots[slot_index]
		available_slots.remove_at(slot_index)
		_local_offsets[unit.network_entity_id] = chosen_offset


func _generate_slots(count: int, spacing_scale: float) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var remaining: int = count
	var ring_index: int = 0
	while remaining > 0:
		var ring_capacity: int = FIRST_RING_CAPACITY + ring_index * RING_CAPACITY_STEP
		var used_slots: int = mini(remaining, ring_capacity)
		var radius: float = (BASE_RING_RADIUS + float(ring_index) * RING_GAP) * spacing_scale
		var phase: float = PI / float(maxi(used_slots, 1)) if ring_index % 2 == 1 else 0.0
		for slot_index in used_slots:
			var angle: float = TAU * float(slot_index) / float(maxi(used_slots, 1)) + phase
			slots.append(Vector2.from_angle(angle) * radius)
		remaining -= used_slots
		ring_index += 1
	return slots


func _choose_slot_index(unit: ColonyUnit, slots: Array[Vector2]) -> int:
	var best_index: int = 0
	var best_score: float = -INF
	for index in slots.size():
		var score: float = _score_slot(unit.definition.role, slots[index])
		if score > best_score:
			best_score = score
			best_index = index
	return best_index


func _score_slot(role: StringName, offset: Vector2) -> float:
	var radius: float = offset.length()
	match role:
		&"tank":
			return offset.y * 1.45 - absf(offset.x) * 0.14 - radius * 0.08
		&"frontline":
			return offset.y * 1.20 - absf(offset.x) * 0.06 - radius * 0.03
		&"ranged":
			return -offset.y * 1.30 - radius * 0.02
		&"worker":
			return -offset.y * 1.05 - radius * 0.12
		&"flanker":
			return absf(offset.x) * 1.30 - absf(offset.y) * 0.12
		_:
			return -radius


func _sort_by_tactical_priority(a: ColonyUnit, b: ColonyUnit) -> bool:
	var a_priority: int = _role_priority(a.definition.role)
	var b_priority: int = _role_priority(b.definition.role)
	if a_priority == b_priority:
		return a.network_entity_id < b.network_entity_id
	return a_priority < b_priority


func _role_priority(role: StringName) -> int:
	match role:
		&"tank":
			return 0
		&"frontline":
			return 1
		&"flanker":
			return 2
		&"ranged":
			return 3
		&"worker":
			return 4
		_:
			return 5
