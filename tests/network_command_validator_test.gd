extends Node

# Runs as a scene, not via --script.
#
# A --script run compiles this file, and everything it preloads, before the
# autoloads exist. MatchController's own preload of colony_controller.gd
# therefore resolved to a script that could not compile — UnitCatalog was not a
# known identifier yet — and the broken result was baked into the class
# constant, so `new()` failed and the test sat there forever with no way to
# recover. Loading the scene again does not help: the poisoned constant lives
# inside the already-compiled class. Booting this as the main scene registers
# the autoloads first, which is the only ordering that makes the gameplay stack
# loadable at all.

const CONTROLLER_SCRIPT := preload("res://gameplay/colony/colony_controller.gd")
const VALIDATOR_SCRIPT := preload("res://gameplay/network/network_command_validator.gd")


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	var controller := CONTROLLER_SCRIPT.new() as ColonyController
	controller.owner_peer_id = 7
	get_tree().root.add_child(controller)
	var valid_move := {
		"sequence": 1,
		"client_tick": 10,
		"type": &"move",
		"payload": {"vector": Vector2(0.5, -0.25)},
	}
	if not _is_valid(VALIDATOR_SCRIPT.validate(valid_move, controller, 7, 0)):
		_fail("A valid owned movement command was rejected")
		return
	if _is_valid(VALIDATOR_SCRIPT.validate(valid_move, controller, 7, 1)):
		_fail("A stale sequence was accepted")
		return
	if _is_valid(VALIDATOR_SCRIPT.validate(valid_move, controller, 8, 0)):
		_fail("A command from the wrong peer was accepted")
		return
	var invalid_move: Dictionary = valid_move.duplicate(true)
	invalid_move["sequence"] = 2
	invalid_move["payload"] = {"vector": Vector2(2.0, 0.0)}
	if _is_valid(VALIDATOR_SCRIPT.validate(invalid_move, controller, 7, 1)):
		_fail("An out-of-range movement vector was accepted")
		return
	var non_finite_move: Dictionary = valid_move.duplicate(true)
	non_finite_move["sequence"] = 3
	non_finite_move["payload"] = {"vector": Vector2(NAN, 0.0)}
	if _is_valid(VALIDATOR_SCRIPT.validate(non_finite_move, controller, 7, 2)):
		_fail("A non-finite movement vector was accepted")
		return
	var float_sequence: Dictionary = valid_move.duplicate(true)
	float_sequence["sequence"] = 4.0
	if _is_valid(VALIDATOR_SCRIPT.validate(float_sequence, controller, 7, 2)):
		_fail("A floating-point sequence number was accepted")
		return
	var negative_tick: Dictionary = valid_move.duplicate(true)
	negative_tick["sequence"] = 4
	negative_tick["client_tick"] = -1
	if _is_valid(VALIDATOR_SCRIPT.validate(negative_tick, controller, 7, 2)):
		_fail("A negative client tick was accepted")
		return
	var invalid_produce := {
		"sequence": 5,
		"client_tick": 10,
		"type": &"produce",
		"payload": {"unit_id": 42},
	}
	if _is_valid(VALIDATOR_SCRIPT.validate(invalid_produce, controller, 7, 2)):
		_fail("A non-string production unit id was accepted")
		return
	var valid_produce := {
		"sequence": 6,
		"client_tick": 10,
		"type": &"produce",
		"payload": {"unit_id": &"worker"},
	}
	if not _is_valid(VALIDATOR_SCRIPT.validate(valid_produce, controller, 7, 2)):
		_fail("A valid production command was rejected")
		return
	print("PASS network_command_validator_test")
	get_tree().quit(0)


func _is_valid(result: Dictionary) -> bool:
	return bool(result.get("valid", false))


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
