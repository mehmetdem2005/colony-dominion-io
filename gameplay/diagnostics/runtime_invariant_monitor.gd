class_name RuntimeInvariantMonitor
extends Node

const AUDIT_INTERVAL: float = 1.5
const MAX_REPORTED_KEYS: int = 128

var _match: Node = null
var _time_left: float = AUDIT_INTERVAL
var _violation_counts: Dictionary = {}
var _last_report_msec: Dictionary = {}


func configure(match_node: Node) -> void:
	_match = match_node
	set_process(OS.is_debug_build() or "--runtime-audit" in OS.get_cmdline_user_args())


func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	_time_left = AUDIT_INTERVAL
	_run_audit()


func get_violation_counts() -> Dictionary:
	return _violation_counts.duplicate(true)


func _run_audit() -> void:
	if not is_instance_valid(_match):
		_record(&"invalid_match", "Runtime invariant monitor lost its MatchController")
		return
	var controllers_variant: Variant = _match.get("controllers")
	if not controllers_variant is Array:
		_record(&"invalid_controllers", "Match controllers collection is unavailable")
		return
	var controllers: Array = controllers_variant
	var entity_ids: Dictionary = {}
	var unit_instances: Dictionary = {}
	var team_ids: Dictionary = {}
	for index in controllers.size():
		var controller: Variant = controllers[index]
		if not is_instance_valid(controller):
			_record(&"invalid_controller", "Controller %d is invalid" % index)
			continue
		var team_id: int = int(controller.get("team_id"))
		if team_ids.has(team_id):
			_record(&"duplicate_team", "Duplicate team id %d" % team_id)
		team_ids[team_id] = true
		if team_id != index:
			_record(&"team_index_mismatch", "Team id %d is stored at index %d" % [team_id, index])
		var units_variant: Variant = controller.get("units")
		if not units_variant is Array:
			_record(&"invalid_unit_collection", "Team %d has an invalid units collection" % team_id)
			continue
		for unit_variant in units_variant:
			if not is_instance_valid(unit_variant):
				_record(&"stale_unit", "Team %d contains a freed unit reference" % team_id)
				continue
			var unit: Node = unit_variant as Node
			var instance_id: int = unit.get_instance_id()
			if unit_instances.has(instance_id):
				_record(
					&"duplicate_unit_reference",
					"Unit instance %d exists in multiple slots" % instance_id
				)
			unit_instances[instance_id] = true
			var unit_team: int = int(unit.get("team_id"))
			if unit_team != team_id:
				_record(
					&"unit_team_mismatch",
					(
						"Unit %d belongs to team %d but is stored by %d"
						% [instance_id, unit_team, team_id]
					)
				)
			var position_variant: Variant = unit.get("global_position")
			if position_variant is Vector2:
				var unit_position: Vector2 = position_variant
				if not unit_position.is_finite():
					_record(
						&"non_finite_unit_position",
						"Unit %d has a non-finite position" % instance_id
					)
			_register_entity_id(entity_ids, unit, "unit")
		var nest: Variant = controller.get("nest")
		if is_instance_valid(nest):
			_register_entity_id(entity_ids, nest, "nest")
		var commander: Variant = controller.get("commander")
		if is_instance_valid(commander) and not units_variant.has(commander):
			_record(
				&"commander_not_owned",
				"Team %d commander is not present in its units collection" % team_id
			)
	if _match.has_method("get_stream_stats"):
		var stats: Dictionary = _match.get_stream_stats()
		var chunks: int = int(stats.get("chunks", 0))
		var limit: int = int(stats.get("resident_chunk_limit", 0))
		if limit > 0 and chunks > limit:
			_record(&"chunk_budget_overrun", "Resident chunks %d exceed limit %d" % [chunks, limit])
		if float(stats.get("dropped_server_time", 0.0)) > 0.5:
			_record(&"server_time_drop", "Fixed server clock has dropped more than 0.5 seconds")
		if float(stats.get("dropped_projectile_time", 0.0)) > 0.5:
			_record(&"projectile_time_drop", "Projectile clock has dropped more than 0.5 seconds")


func _register_entity_id(registry: Dictionary, node: Object, kind: String) -> void:
	var entity_id: int = int(node.get("network_entity_id"))
	if entity_id <= 0:
		_record(
			&"missing_entity_id",
			"%s instance %d has no network entity id" % [kind, node.get_instance_id()]
		)
		return
	if registry.has(entity_id):
		_record(&"duplicate_entity_id", "Entity id %d is assigned more than once" % entity_id)
	registry[entity_id] = true


func _record(key: StringName, message: String) -> void:
	_violation_counts[key] = int(_violation_counts.get(key, 0)) + 1
	if _violation_counts.size() > MAX_REPORTED_KEYS:
		return
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = int(_last_report_msec.get(key, -100000))
	if now_msec - last_msec < 5000:
		return
	_last_report_msec[key] = now_msec
	push_warning("[RuntimeInvariant] %s" % message)
