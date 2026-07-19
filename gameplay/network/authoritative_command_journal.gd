class_name AuthoritativeCommandJournal
extends RefCounted

var _capacity: int = 240
var _entries: Array[Dictionary] = []
var _write_cursor: int = 0
var _total_recorded: int = 0


func configure(capacity: int) -> void:
	_capacity = clampi(capacity, 10, 600)
	_entries.clear()
	_write_cursor = 0
	_total_recorded = 0


func record(
	server_tick: int,
	peer_id: int,
	team_id: int,
	command_type: StringName,
	payload: Dictionary,
	succeeded: bool
) -> void:
	var entry := {
		"server_tick": maxi(server_tick, 0),
		"peer_id": peer_id,
		"team_id": team_id,
		"type": command_type,
		"payload": payload.duplicate(true),
		"succeeded": succeeded,
	}
	if _entries.size() < _capacity:
		_entries.append(entry)
	else:
		_entries[_write_cursor] = entry
		_write_cursor = (_write_cursor + 1) % _capacity
	_total_recorded += 1


func snapshot() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	if _entries.size() < _capacity or _write_cursor == 0:
		for entry in _entries:
			ordered.append(entry.duplicate(true))
		return ordered
	for offset in _entries.size():
		var index: int = (_write_cursor + offset) % _entries.size()
		ordered.append(_entries[index].duplicate(true))
	return ordered


func get_total_recorded() -> int:
	return _total_recorded


func clear() -> void:
	_entries.clear()
	_write_cursor = 0
	_total_recorded = 0
