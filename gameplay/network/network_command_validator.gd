class_name NetworkCommandValidator
extends RefCounted

const ALLOWED_COMMANDS: Array[StringName] = [
	&"move",
	&"attack",
	&"gather",
	&"rally",
	&"split",
	&"spread",
	&"merge",
	&"upgrade",
	&"produce",
]


static func validate(
	command: Dictionary, controller: ColonyController, peer_id: int, last_sequence: int
) -> Dictionary:
	if not is_instance_valid(controller) or controller.eliminated:
		return _result(false, "inactive_controller")
	if command.size() > 4:
		return _result(false, "oversized_command")
	if controller.owner_peer_id > 0 and controller.owner_peer_id != peer_id:
		return _result(false, "owner_mismatch")
	var sequence_variant: Variant = command.get("sequence", null)
	if not sequence_variant is int:
		return _result(false, "invalid_sequence")
	var sequence: int = sequence_variant
	if sequence < 0 or sequence > 2_147_483_647:
		return _result(false, "sequence_out_of_range")
	if sequence <= last_sequence:
		return _result(false, "stale_sequence")
	var client_tick_variant: Variant = command.get("client_tick", 0)
	if not client_tick_variant is int or int(client_tick_variant) < 0:
		return _result(false, "invalid_client_tick")
	var command_type_variant: Variant = command.get("type", "")
	if not command_type_variant is String and not command_type_variant is StringName:
		return _result(false, "invalid_command_name")
	var command_type_text: String = String(command_type_variant)
	if command_type_text.length() > 16:
		return _result(false, "invalid_command_name")
	var command_type := StringName(command_type_text)
	if not ALLOWED_COMMANDS.has(command_type):
		return _result(false, "unknown_command")
	var payload_variant: Variant = command.get("payload", {})
	if not payload_variant is Dictionary:
		return _result(false, "invalid_payload")
	var payload: Dictionary = payload_variant
	if payload.size() > 4:
		return _result(false, "oversized_payload")
	match command_type:
		&"move":
			var vector_variant: Variant = payload.get("vector", Vector2.ZERO)
			if not vector_variant is Vector2:
				return _result(false, "invalid_move_vector")
			var movement: Vector2 = vector_variant
			if not movement.is_finite() or movement.length_squared() > 1.21:
				return _result(false, "move_out_of_range")
		&"produce":
			var unit_id_variant: Variant = payload.get("unit_id", "")
			if not unit_id_variant is String and not unit_id_variant is StringName:
				return _result(false, "invalid_unit")
			var unit_id_text: String = String(unit_id_variant)
			if unit_id_text.is_empty() or unit_id_text.length() > 32:
				return _result(false, "invalid_unit")
			var unit_id := StringName(unit_id_text)
			var definition: UnitDefinition = UnitCatalog.get_definition(unit_id)
			if definition == null or definition.role == &"commander":
				return _result(false, "invalid_unit")
	return _result(true, "")


static func _result(valid: bool, reason: String) -> Dictionary:
	return {"valid": valid, "reason": reason}
