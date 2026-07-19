extends Node

const DEFINITION_PATHS := {
	&"commander": "res://data/units/commander.tres",
	&"worker": "res://data/units/worker.tres",
	&"soldier": "res://data/units/soldier.tres",
	&"guard": "res://data/units/guard.tres",
	&"scout": "res://data/units/scout.tres",
	&"acid_ant": "res://data/units/acid_ant.tres",
}

var _definitions: Dictionary = {}


func _ready() -> void:
	for unit_id in DEFINITION_PATHS:
		var definition := load(DEFINITION_PATHS[unit_id]) as UnitDefinition
		if definition != null:
			_definitions[unit_id] = definition


func get_definition(unit_id: StringName) -> UnitDefinition:
	return _definitions.get(unit_id) as UnitDefinition


func get_producible_ids() -> Array[StringName]:
	return [&"worker", &"soldier", &"guard", &"scout", &"acid_ant"]


func get_all() -> Dictionary:
	return _definitions.duplicate()
