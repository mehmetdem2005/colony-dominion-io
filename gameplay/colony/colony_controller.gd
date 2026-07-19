class_name ColonyController
extends Node

enum SimulationTier { FULL, REDUCED, DORMANT }

const NEST_SCENE := preload("res://scenes/structures/nest.tscn")
const PROGRESSION_SCRIPT := preload("res://gameplay/colony/colony_progression.gd")
const SQUAD_MANAGER_SCRIPT := preload("res://gameplay/colony/squad_manager.gd")
const SWARM_FORMATION_SCRIPT := preload("res://gameplay/colony/swarm_formation_manager.gd")
const BOT_BRAIN_SCRIPT := preload("res://gameplay/colony/colony_bot_brain.gd")
const SWARM_SCHEDULER_SCRIPT := preload("res://gameplay/colony/swarm_simulation_scheduler.gd")
const GATHER_SERVICE_SCRIPT := preload("res://gameplay/colony/colony_gather_service.gd")
const COST_FORMATTER_SCRIPT := preload("res://gameplay/economy/resource_cost_formatter.gd")

const GATHER_COMMAND_RADIUS: float = 310.0
const GATHER_CANCEL_RADIUS: float = 360.0
const GATHER_COMMAND_DURATION: float = 7.0
const COMBAT_LEASH_RADIUS: float = 520.0
const HARD_RECALL_RADIUS: float = 760.0
const REINFORCEMENT_JOIN_RADIUS: float = 440.0
const SWARM_BUCKET_COUNT: int = 3
const SWARM_TICK_INTERVAL: float = 1.0 / 20.0
const SWARM_MAX_BUCKET_STEPS_PER_FRAME: int = 6
const RESOURCE_FLUSH_INTERVAL: float = 0.20
const COMMANDER_RESPAWN_RETRY_DELAY: float = 1.0
const DORMANT_NAVIGATION_INTERVAL: float = 0.25

var match_controller
var team_id: int = -1
var display_name: String = "Colony"
var team_color := Color.WHITE
var is_player: bool = false
var is_human: bool = false
var is_local_player: bool = false
var owner_peer_id: int = 0
var eliminated: bool = false

var inventory: ColonyInventory
var progression: ColonyProgression
var squad_manager: ColonySquadManager
var swarm_formation: SwarmFormationManager
var nest: ColonyNest
var commander: ColonyUnit
var units: Array[ColonyUnit] = []
var kills: int = 0
var deaths: int = 0
var simulation_tier: int = SimulationTier.FULL

var _joystick_input := Vector2.ZERO
var _forced_target: Node2D = null
var _forced_target_left: float = 0.0
var _commander_respawn_left: float = 0.0
var _rng := RandomNumberGenerator.new()
var _macro_simulation_left: float = 0.0
var _dormant_navigation_left: float = 0.0
var _cleanup_left: float = 0.0
var _swarm_scheduler: SwarmSimulationScheduler
var _gather_service: ColonyGatherService
var _pending_resource_deltas: Dictionary = {}
var _resource_flush_left: float = RESOURCE_FLUSH_INTERVAL
var _forced_target_entity_id: int = 0
var _bot_brain: ColonyBotBrain


func configure(
	match_node,
	id: int,
	colony_name: String,
	color: Color,
	human_player: bool,
	spawn_position: Vector2,
	local_player: bool = true,
	peer_id: int = 0
) -> void:
	match_controller = match_node
	team_id = id
	display_name = colony_name
	team_color = color
	is_human = human_player
	is_local_player = human_player and local_player
	is_player = is_local_player
	owner_peer_id = peer_id
	var match_seed: int = 738291
	if is_instance_valid(match_controller) and match_controller.has_method("get_match_seed"):
		match_seed = int(match_controller.get_match_seed())
	_rng.seed = match_seed + team_id * 104729
	_bot_brain = BOT_BRAIN_SCRIPT.new() as ColonyBotBrain
	_bot_brain.configure(self, _rng)
	_dormant_navigation_left = 0.0
	_swarm_scheduler = SWARM_SCHEDULER_SCRIPT.new() as SwarmSimulationScheduler
	_swarm_scheduler.configure(team_id)
	_gather_service = GATHER_SERVICE_SCRIPT.new() as ColonyGatherService
	_gather_service.configure(self)
	_pending_resource_deltas.clear()
	progression = PROGRESSION_SCRIPT.new() as ColonyProgression
	squad_manager = SQUAD_MANAGER_SCRIPT.new() as ColonySquadManager
	swarm_formation = SWARM_FORMATION_SCRIPT.new() as SwarmFormationManager
	progression.changed.connect(_on_progression_changed)
	inventory = (
		ColonyInventory
		. new(
			{
				&"seed": 78 if is_human else 66,
				&"nectar": 34,
				&"protein": 24,
				&"leaf": 32,
				&"stone": 18,
			}
		)
	)
	inventory.changed.connect(_on_inventory_changed)
	_create_nest(spawn_position)
	var initial_commander: ColonyUnit = spawn_unit(
		&"commander", spawn_position + Vector2(0.0, 112.0)
	)
	if not is_instance_valid(initial_commander) and is_instance_valid(nest) and nest.is_alive():
		_commander_respawn_left = COMMANDER_RESPAWN_RETRY_DELAY
	for index in 3:
		spawn_unit(&"worker", spawn_position + Vector2(-56.0 + float(index) * 56.0, 155.0))
	spawn_unit(&"soldier", spawn_position + Vector2(0.0, 196.0))
	_emit_inventory()
	_emit_counts()
	_emit_progress()
	if is_player:
		match_controller.events.squad_state_changed.emit(team_id, false)
		match_controller.events.formation_spread_changed.emit(team_id, false)
		match_controller.events.gather_state_changed.emit(team_id, false, 0, &"")


func _physics_process(delta: float) -> void:
	if eliminated:
		return
	_cleanup_left -= delta
	if _cleanup_left <= 0.0:
		_cleanup_left = 0.75
		_cleanup_units()
	_forced_target_left = maxf(0.0, _forced_target_left - delta)
	if _forced_target_left <= 0.0:
		_set_forced_target(null)

	if _gather_service != null:
		_gather_service.advance(delta)
	_resource_flush_left -= delta
	if _resource_flush_left <= 0.0:
		_flush_pending_resources()

	if _commander_respawn_left > 0.0:
		_commander_respawn_left -= delta
		if _commander_respawn_left <= 0.0 and is_instance_valid(nest) and nest.is_alive():
			var respawned_commander: ColonyUnit = spawn_unit(
				&"commander", nest.global_position + Vector2(0.0, 120.0)
			)
			if not is_instance_valid(respawned_commander):
				_commander_respawn_left = COMMANDER_RESPAWN_RETRY_DELAY

	if simulation_tier == SimulationTier.DORMANT and not is_human:
		_dormant_navigation_left -= delta
		if _dormant_navigation_left <= 0.0:
			_dormant_navigation_left = DORMANT_NAVIGATION_INTERVAL
			if _bot_brain != null:
				_bot_brain.advance_dormant_navigation(DORMANT_NAVIGATION_INTERVAL)
		_macro_simulation_left -= delta
		if _macro_simulation_left <= 0.0:
			_macro_simulation_left = 1.5
			if _bot_brain != null:
				_bot_brain.run_dormant_economy()
		return

	_advance_swarm_scheduler(delta)
	_advance_swarm_visuals(delta)

	if not is_human and _bot_brain != null:
		_bot_brain.advance_active(delta)


func _create_nest(spawn_position: Vector2) -> void:
	nest = NEST_SCENE.instantiate() as ColonyNest
	match_controller.structures_root.add_child(nest)
	nest.global_position = spawn_position
	nest.refresh_world_depth()
	var texture_path: String = (
		"res://assets/structures/nest_blue.png"
		if is_player
		else "res://assets/structures/nest_red.png"
	)
	var nest_texture: Texture2D = null
	if is_presentation_enabled():
		nest_texture = load(texture_path) as Texture2D
	var nest_entity_id: int = match_controller.register_network_entity(nest)
	if nest_entity_id <= 0:
		push_error("Failed to register colony nest network entity for team %d" % team_id)
		nest.queue_free()
		nest = null
		eliminated = true
		return
	nest.configure(self, team_id, team_color, nest_texture, nest_entity_id)
	nest.apply_level(progression.level)
	nest.destroyed.connect(_on_nest_destroyed)


func spawn_unit(unit_id: StringName, spawn_position: Vector2) -> ColonyUnit:
	if eliminated:
		return null
	if (
		unit_id != &"commander"
		and is_instance_valid(commander)
		and spawn_position.distance_to(commander.global_position) > REINFORCEMENT_JOIN_RADIUS
	):
		var join_angle: float = _rng.randf_range(0.0, TAU)
		spawn_position = commander.global_position + Vector2.from_angle(join_angle) * 128.0
	if unit_id != &"commander" and get_army_size() >= get_unit_capacity():
		if is_player:
			match_controller.events.toast_requested.emit("Ordu kapasitesi dolu; yuvayı geliştir")
		return null
	var definition := UnitCatalog.get_definition(unit_id)
	if definition == null:
		return null
	var unit: ColonyUnit = match_controller.acquire_unit()
	if not is_instance_valid(unit):
		return null
	var entity_id: int = match_controller.register_network_entity(unit)
	if entity_id <= 0:
		push_error("Failed to register unit network entity for team %d" % team_id)
		match_controller.release_unit(unit)
		return null
	unit.global_position = spawn_position
	unit.configure(definition, self, team_id, team_color, display_name, entity_id)
	unit.set_simulation_tier(simulation_tier)
	units.append(unit)
	if unit_id == &"commander":
		commander = unit
		unit.set_squad_id(0)
		if match_controller.has_method("on_controller_commander_changed"):
			match_controller.on_controller_commander_changed(self)
		if is_player:
			match_controller.events.player_commander_changed.emit(commander)
	else:
		squad_manager.assign_new_unit(unit, units)
		_register_swarm_unit(unit)
	_rebuild_formation_cache()
	match_controller.mark_spatial_index_dirty()
	_emit_counts()
	return unit


func set_simulation_tier(value: int) -> void:
	if is_human and (is_local_player or bool(match_controller.get("is_headless_server"))):
		simulation_tier = SimulationTier.FULL
		for unit in units:
			if is_instance_valid(unit):
				unit.set_simulation_tier(SimulationTier.FULL)
		return
	var new_tier: int = clampi(value, SimulationTier.FULL, SimulationTier.DORMANT)
	if simulation_tier == new_tier:
		return
	simulation_tier = new_tier
	_macro_simulation_left = 0.0
	_dormant_navigation_left = 0.0
	for unit in units:
		if is_instance_valid(unit):
			unit.set_simulation_tier(new_tier)
	if simulation_tier == SimulationTier.DORMANT:
		_set_forced_target(null)
		_forced_target_left = 0.0
	if _bot_brain != null:
		_bot_brain.on_simulation_tier_changed(simulation_tier == SimulationTier.DORMANT)


func get_simulation_tier() -> int:
	return simulation_tier


func request_production(unit_id: StringName) -> bool:
	_flush_pending_resources(true)
	if eliminated or not is_instance_valid(nest) or not nest.is_alive():
		if is_player:
			match_controller.events.toast_requested.emit("Üretim için aktif yuva gerekli")
		return false
	var definition := UnitCatalog.get_definition(unit_id)
	if definition == null:
		return false
	if get_army_size() + nest.production_queue.size() >= get_unit_capacity():
		if is_player:
			match_controller.events.toast_requested.emit(
				"Ordu kapasitesi dolu; YÜKSELT düğmesini kullan"
			)
		return false
	if not inventory.can_afford(definition):
		if is_player:
			match_controller.events.toast_requested.emit("Kaynak yetersiz")
		return false
	if not nest.enqueue(unit_id):
		if is_player:
			match_controller.events.toast_requested.emit("Üretim kuyruğu dolu")
		return false
	inventory.spend(definition)
	return true


func request_nest_upgrade() -> bool:
	_flush_pending_resources(true)
	if eliminated or not is_instance_valid(nest) or not nest.is_alive():
		if is_player:
			match_controller.events.toast_requested.emit("Yükseltme için aktif yuva gerekli")
		return false
	if progression.is_max_level():
		if is_player:
			match_controller.events.toast_requested.emit("Yuva en yüksek seviyede")
		return false
	var next_cost: Dictionary = progression.get_next_upgrade_cost()
	if not progression.can_upgrade(inventory):
		if is_player:
			match_controller.events.toast_requested.emit(
				"Yuva yükseltme maliyeti: %s" % COST_FORMATTER_SCRIPT.format(next_cost)
			)
		return false
	if not progression.try_upgrade(inventory):
		return false
	if is_player:
		match_controller.events.toast_requested.emit(
			"Yuva seviye %d • kapasite %d" % [progression.level, get_unit_capacity()]
		)
	return true


func add_resource(resource_id: StringName, amount: int) -> void:
	if amount <= 0:
		return
	_pending_resource_deltas[resource_id] = (
		int(_pending_resource_deltas.get(resource_id, 0)) + amount
	)


func set_joystick_input(value: Vector2) -> void:
	_joystick_input = value.limit_length(1.0) if value.is_finite() else Vector2.ZERO


func get_movement_input() -> Vector2:
	return _joystick_input


func command_attack() -> bool:
	if not is_instance_valid(commander):
		return false
	_stop_active_gather(false)
	var enemy: Node2D = find_nearest_enemy(commander.global_position, COMBAT_LEASH_RADIUS)
	if enemy == null:
		if is_player:
			match_controller.events.toast_requested.emit("Yakında saldırılacak hedef yok")
		return false
	_set_forced_target(enemy)
	_forced_target_left = 6.0
	if is_player:
		match_controller.events.toast_requested.emit("Ordu saldırıya geçti")
	return true


func command_rally() -> bool:
	if not is_instance_valid(commander):
		return false
	_set_forced_target(null)
	_forced_target_left = 0.0
	_stop_active_gather(false)
	for unit in units:
		if is_instance_valid(unit):
			unit.clear_combat_target()
			if unit.definition != null and unit.definition.role == &"worker":
				unit.resource_target = null
	if is_player:
		match_controller.events.toast_requested.emit(
			"Bütün karıncalar kraliçenin çevresine dönüyor"
		)
	return true


func command_gather() -> bool:
	return _gather_service.command_gather() if _gather_service != null else false


func should_workers_gather() -> bool:
	return _gather_service.should_gather() if _gather_service != null else false


func get_active_resource_target() -> WorldResourceNode:
	return _gather_service.get_active_target() if _gather_service != null else null


func can_worker_reach_resource(worker: ColonyUnit, resource: WorldResourceNode) -> bool:
	return _gather_service.can_worker_reach(worker, resource) if _gather_service != null else false


func _update_active_gather(delta: float) -> void:
	if _gather_service != null:
		_gather_service.advance(delta)


func _stop_active_gather(show_message: bool) -> void:
	if _gather_service != null:
		_gather_service.stop(show_message)


func _emit_gather_state() -> void:
	if _gather_service != null:
		_gather_service.emit_current_state()


func clear_forced_target() -> void:
	_set_forced_target(null)
	_forced_target_left = 0.0


func request_player_toast(message: String) -> void:
	if is_player and not message.is_empty():
		match_controller.events.toast_requested.emit(message)


func emit_gather_state(active: bool, seconds_left: int, resource_id: StringName) -> void:
	if is_player:
		match_controller.events.gather_state_changed.emit(
			team_id, active, seconds_left, resource_id
		)


func emit_production_queue_state(queue: Array, progress: float) -> void:
	if is_player:
		match_controller.events.production_queue_changed.emit(team_id, queue, progress)


func command_split() -> bool:
	if not is_instance_valid(commander):
		return false
	if squad_manager.split_mode:
		if is_player:
			match_controller.events.toast_requested.emit("Ordu zaten iki kola ayrılmış")
		return false
	if not squad_manager.split_units(units, commander):
		if is_player:
			match_controller.events.toast_requested.emit("Bölünmek için en az 4 minyon gerekli")
		return false
	_rebuild_formation_cache()
	if is_player:
		match_controller.events.squad_state_changed.emit(team_id, true)
	if is_player:
		match_controller.events.toast_requested.emit("Ordu iki savaş koluna bölündü")
	return true


func command_spread() -> bool:
	var spread_enabled: bool = squad_manager.toggle_spread()
	_rebuild_formation_cache()
	if is_player:
		match_controller.events.formation_spread_changed.emit(team_id, spread_enabled)
	if is_player:
		match_controller.events.toast_requested.emit(
			"Birlikler geniş düzene dağıldı" if spread_enabled else "Birlikler sıkı düzene geçti"
		)
	return true


func command_merge() -> bool:
	if not squad_manager.split_mode:
		if is_player:
			match_controller.events.toast_requested.emit("Ordu zaten tek grup")
		return false
	squad_manager.merge_units(units)
	_rebuild_formation_cache()
	if is_player:
		match_controller.events.squad_state_changed.emit(team_id, false)
	if is_player:
		match_controller.events.toast_requested.emit("İki savaş kolu yeniden birleşiyor")
	return true


func get_forced_target() -> Node2D:
	if (
		_forced_target_left <= 0.0
		or not is_instance_valid(_forced_target)
		or _get_entity_id(_forced_target) != _forced_target_entity_id
	):
		return null
	return _forced_target


func find_nearest_enemy(origin: Vector2, max_range: float) -> Node2D:
	return match_controller.find_nearest_enemy(team_id, origin, max_range)


func find_resource_for_worker(_origin: Vector2) -> WorldResourceNode:
	return get_active_resource_target()


func can_unit_pursue_target(unit: ColonyUnit, candidate: Node2D) -> bool:
	if (
		not is_instance_valid(unit)
		or not is_instance_valid(candidate)
		or not is_instance_valid(commander)
	):
		return false
	var leash_radius: float = COMBAT_LEASH_RADIUS
	if unit.definition != null and unit.definition.role == &"commander":
		leash_radius = COMBAT_LEASH_RADIUS + 120.0
	return commander.global_position.distance_to(candidate.global_position) <= leash_radius


func find_enemy_for_unit(unit: ColonyUnit, max_range: float) -> Node2D:
	if not is_instance_valid(unit) or not is_instance_valid(commander):
		return null
	var enemy: Node2D = match_controller.find_nearest_enemy(
		team_id, unit.global_position, minf(max_range, COMBAT_LEASH_RADIUS)
	)
	if is_instance_valid(enemy) and can_unit_pursue_target(unit, enemy):
		return enemy
	return null


func get_commander_distance(unit: ColonyUnit) -> float:
	if not is_instance_valid(unit) or not is_instance_valid(commander):
		return INF
	return unit.global_position.distance_to(commander.global_position)


func get_hard_recall_radius() -> float:
	return HARD_RECALL_RADIUS


func get_minimum_follow_speed_multiplier(unit: ColonyUnit) -> float:
	if (
		not is_instance_valid(unit)
		or unit.definition == null
		or not is_instance_valid(commander)
		or commander.definition == null
	):
		return 1.0
	return maxf(1.0, commander.definition.move_speed / maxf(unit.definition.move_speed, 1.0) * 1.08)


func spawn_projectile(attacker: ColonyUnit, victim: Node2D, damage: float, speed: float) -> void:
	match_controller.spawn_projectile(attacker, victim, damage, speed, team_color)


func get_separation_vector(requester: ColonyUnit, radius: float) -> Vector2:
	if not is_instance_valid(match_controller):
		return Vector2.ZERO
	return match_controller.calculate_ally_separation(
		team_id, requester.global_position, radius, requester
	)


func get_formation_position(unit: ColonyUnit) -> Vector2:
	if not is_instance_valid(commander) or unit == commander:
		return unit.global_position
	if not swarm_formation.has_unit(unit):
		_rebuild_formation_cache()
	var direction: Vector2 = commander.facing_direction.normalized()
	if direction.length_squared() < 0.1:
		direction = Vector2.UP
	var right := Vector2(-direction.y, direction.x)
	var anchor: Vector2 = squad_manager.get_anchor(commander, unit.squad_id)
	var local_offset: Vector2 = swarm_formation.get_local_offset(unit)
	return anchor + right * local_offset.x + direction * local_offset.y


func _rebuild_formation_cache() -> void:
	if swarm_formation == null or squad_manager == null:
		return
	swarm_formation.rebuild(units, commander, squad_manager)


func get_bot_move_direction(origin: Vector2) -> Vector2:
	return _bot_brain.get_move_direction(origin) if _bot_brain != null else Vector2.ZERO


func set_bot_forced_target(candidate: Node2D, duration: float) -> void:
	_set_forced_target(candidate)
	_forced_target_left = maxf(duration, 0.0) if is_finite(duration) else 0.0


func get_lowest_resource_type_for_bot() -> StringName:
	return _get_lowest_resource_type()


func on_unit_died(unit: ColonyUnit, killer: Node, killer_team_id: int = -1) -> void:
	deaths += 1
	units.erase(unit)
	_unregister_swarm_unit(unit)
	_rebuild_formation_cache()
	match_controller.mark_spatial_index_dirty()
	var killer_controller: ColonyController = null
	if is_instance_valid(killer):
		var killer_controller_variant: Variant = killer.get("controller")
		if (
			is_instance_valid(killer_controller_variant)
			and killer_controller_variant is ColonyController
		):
			killer_controller = killer_controller_variant as ColonyController
	if killer_controller == null and killer_team_id >= 0:
		killer_controller = match_controller.get_controller_by_team_id(killer_team_id)
	if is_instance_valid(killer_controller) and killer_controller != self:
		killer_controller.kills += 1
	if unit == commander:
		commander = null
		if match_controller.has_method("on_controller_commander_changed"):
			match_controller.on_controller_commander_changed(self)
		if is_instance_valid(nest) and nest.is_alive():
			_commander_respawn_left = 5.0
			if is_player:
				match_controller.events.toast_requested.emit(
					"Komutan 5 saniye içinde yuvada doğacak"
				)
		else:
			eliminated = true
			match_controller.on_colony_eliminated(self)
	_emit_counts()
	match_controller.unregister_network_entity(unit.network_entity_id, unit)
	match_controller.release_unit(unit)


func _on_nest_destroyed(_destroyed_nest: ColonyNest, _attacker: Node) -> void:
	match_controller.unregister_network_entity(_destroyed_nest.network_entity_id, _destroyed_nest)
	_emit_progress()
	if is_player:
		match_controller.events.toast_requested.emit("Yuvan yok edildi; komutan son canın")
	if not is_instance_valid(commander):
		eliminated = true
		match_controller.on_colony_eliminated(self)


func is_active() -> bool:
	return (
		not eliminated
		and (is_instance_valid(commander) or (is_instance_valid(nest) and nest.is_alive()))
	)


func get_score() -> int:
	var score: int = kills * 70 + progression.level * 90
	for unit in units:
		if is_instance_valid(unit) and unit.definition != null:
			score += unit.definition.score_value
	var snapshot: Dictionary = inventory.snapshot()
	for resource_id in ColonyInventory.RESOURCE_IDS:
		score += floori(float(int(snapshot.get(resource_id, 0))) / 3.0)
	if is_instance_valid(nest) and nest.is_alive():
		score += floori(nest.health * 0.12)
	return score


func get_unit_counts() -> Dictionary:
	var counts := {
		&"commander": 0,
		&"worker": 0,
		&"soldier": 0,
		&"guard": 0,
		&"scout": 0,
		&"acid_ant": 0,
	}
	for unit in units:
		if is_instance_valid(unit) and unit.definition != null:
			counts[unit.definition.unit_id] = int(counts.get(unit.definition.unit_id, 0)) + 1
	return counts


func get_army_size() -> int:
	var count: int = 0
	for unit in units:
		if (
			is_instance_valid(unit)
			and unit.definition != null
			and unit.definition.role != &"commander"
			and unit.is_alive()
		):
			count += 1
	return count


func get_scheduled_swarm_count() -> int:
	return _swarm_scheduler.get_scheduled_count() if _swarm_scheduler != null else 0


func get_swarm_scheduler_stats() -> Dictionary:
	if _swarm_scheduler == null:
		return {
			"tick_hz": roundi(1.0 / SWARM_TICK_INTERVAL),
			"simulation_steps": 0,
			"maximum_backlog": 0.0,
			"dropped_time": 0.0,
		}
	return _swarm_scheduler.get_stats()


func get_unit_capacity() -> int:
	return mini(progression.get_capacity(), match_controller.unit_cap_per_colony)


func get_gather_amount(base_amount: int) -> int:
	return maxi(1, roundi(float(base_amount) * progression.get_gather_multiplier()))


func get_production_time_multiplier() -> float:
	return progression.get_production_time_multiplier()


func get_world_bounds() -> Rect2:
	return match_controller.world_bounds


func is_presentation_enabled() -> bool:
	return (
		is_instance_valid(match_controller) and not bool(match_controller.get("is_headless_server"))
	)


func _get_lowest_resource_type() -> StringName:
	var lowest: StringName = &"seed"
	var lowest_value: int = 1_000_000
	for resource_id in ColonyInventory.RESOURCE_IDS:
		var value: int = inventory.get_amount(resource_id)
		if value < lowest_value:
			lowest_value = value
			lowest = resource_id
	return lowest


func _cleanup_units() -> void:
	var removed_any: bool = false
	for index in range(units.size() - 1, -1, -1):
		var unit: ColonyUnit = units[index]
		if is_instance_valid(unit) and unit.definition != null and unit.is_alive():
			continue
		units.remove_at(index)
		removed_any = true
		if not is_instance_valid(unit):
			continue
		_unregister_swarm_unit(unit)
		var stale_entity_id: int = unit.network_entity_id
		var was_commander: bool = unit == commander
		if stale_entity_id > 0 and is_instance_valid(match_controller):
			match_controller.unregister_network_entity(stale_entity_id, unit)
		if was_commander:
			commander = null
			if is_instance_valid(match_controller):
				match_controller.on_controller_commander_changed(self)
			if is_instance_valid(nest) and nest.is_alive():
				_commander_respawn_left = maxf(_commander_respawn_left, 5.0)
			else:
				eliminated = true
				if is_instance_valid(match_controller):
					match_controller.on_colony_eliminated(self)
		if is_instance_valid(match_controller):
			match_controller.release_unit(unit)
	if removed_any:
		_compact_swarm_buckets()
		_rebuild_formation_cache()
		match_controller.mark_spatial_index_dirty()


func _on_inventory_changed(_snapshot: Dictionary) -> void:
	_emit_inventory()
	_emit_progress()


func _on_progression_changed(level: int, _capacity: int, _next_cost: Dictionary) -> void:
	if is_instance_valid(nest):
		nest.apply_level(level)
	_emit_progress()


func _emit_inventory() -> void:
	if not is_player:
		return
	match_controller.events.inventory_changed.emit(team_id, inventory.snapshot())


func _emit_counts() -> void:
	if not is_player:
		return
	match_controller.events.unit_count_changed.emit(team_id, get_unit_counts())
	_emit_progress()


func _emit_progress() -> void:
	if not is_player or progression == null:
		return
	match_controller.events.colony_progress_changed.emit(
		team_id,
		progression.level,
		get_unit_capacity(),
		get_army_size(),
		progression.get_next_upgrade_cost()
	)


func execute_authoritative_command(command_type: StringName, payload: Dictionary) -> bool:
	match command_type:
		&"move":
			var input_value: Vector2 = payload.get("vector", Vector2.ZERO)
			set_joystick_input(input_value)
		&"attack":
			return command_attack()
		&"gather":
			return command_gather()
		&"rally":
			return command_rally()
		&"split":
			return command_split()
		&"spread":
			return command_spread()
		&"merge":
			return command_merge()
		&"upgrade":
			return request_nest_upgrade()
		&"produce":
			return request_production(StringName(payload.get("unit_id", "")))
		_:
			return false
	return true


func _advance_swarm_scheduler(delta: float) -> void:
	if _swarm_scheduler != null:
		_swarm_scheduler.advance(delta)


func _advance_swarm_visuals(delta: float) -> void:
	if _swarm_scheduler != null:
		_swarm_scheduler.advance_visuals(delta, is_presentation_enabled())


func _register_swarm_unit(unit: ColonyUnit) -> void:
	if _swarm_scheduler != null:
		_swarm_scheduler.register_unit(unit)


func _unregister_swarm_unit(unit: ColonyUnit) -> void:
	if _swarm_scheduler != null:
		_swarm_scheduler.unregister_unit(unit)


func _compact_swarm_buckets() -> void:
	if _swarm_scheduler != null:
		_swarm_scheduler.compact(units)


func _flush_pending_resources(force: bool = false) -> void:
	if not force and _resource_flush_left > 0.0:
		return
	_resource_flush_left = RESOURCE_FLUSH_INTERVAL
	if _pending_resource_deltas.is_empty():
		return
	var deltas: Dictionary = _pending_resource_deltas.duplicate()
	_pending_resource_deltas.clear()
	inventory.add_batch(deltas)


func _set_forced_target(candidate: Node2D) -> void:
	_forced_target = candidate
	_forced_target_entity_id = _get_entity_id(candidate)


func _get_entity_id(candidate: Object) -> int:
	if not is_instance_valid(candidate):
		return 0
	var value: Variant = candidate.get("network_entity_id")
	return int(value) if value is int and int(value) > 0 else 0
