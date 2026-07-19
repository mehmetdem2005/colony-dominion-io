class_name AudioEventLibrary
extends RefCounted

const EVENT_PATHS: Array[String] = [
	"res://audio/events/ui_press.tres",
	"res://audio/events/ui_invalid.tres",
	"res://audio/events/ui_select.tres",
	"res://audio/events/command_attack.tres",
	"res://audio/events/command_gather.tres",
	"res://audio/events/command_rally.tres",
	"res://audio/events/command_split.tres",
	"res://audio/events/command_spread.tres",
	"res://audio/events/command_merge.tres",
	"res://audio/events/production_start.tres",
	"res://audio/events/production_complete.tres",
	"res://audio/events/nest_upgrade.tres",
	"res://audio/events/unit_melee_attack.tres",
	"res://audio/events/acid_launch.tres",
	"res://audio/events/acid_hit.tres",
	"res://audio/events/unit_hurt.tres",
	"res://audio/events/unit_death.tres",
	"res://audio/events/nest_hurt.tres",
	"res://audio/events/nest_destroyed.tres",
	"res://audio/events/queen_danger.tres",
	"res://audio/events/resource_seed.tres",
	"res://audio/events/resource_nectar.tres",
	"res://audio/events/resource_protein.tres",
	"res://audio/events/resource_leaf.tres",
	"res://audio/events/resource_stone.tres",
	"res://audio/events/match_victory.tres",
	"res://audio/events/match_defeat.tres",
]

var _events: Dictionary = {}


func load_all() -> void:
	_events.clear()
	for path in EVENT_PATHS:
		var definition := load(path) as AudioEventDefinition
		if definition == null or definition.event_id == &"":
			push_warning("Audio event could not be loaded: %s" % path)
			continue
		if _events.has(definition.event_id):
			push_error("Duplicate audio event id rejected: %s" % definition.event_id)
			continue
		_events[definition.event_id] = definition


func get_event(event_id: StringName) -> AudioEventDefinition:
	return _events.get(event_id) as AudioEventDefinition


func has_event(event_id: StringName) -> bool:
	return _events.has(event_id)


func get_event_count() -> int:
	return _events.size()
