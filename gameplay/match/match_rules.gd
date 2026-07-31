class_name MatchRules
extends Resource

@export_category("Match")
@export_range(60.0, 7200.0, 1.0) var match_duration_seconds: float = 1200.0
@export_range(8, 256, 1) var unit_cap_per_colony: int = 72

@export_category("Simulation")
@export_range(5.0, 60.0, 1.0) var server_tick_rate: float = 20.0
@export_range(10.0, 120.0, 1.0) var projectile_tick_rate: float = 30.0
@export_range(1, 16, 1) var max_server_steps_per_frame: int = 6
@export_range(1, 16, 1) var max_projectile_steps_per_frame: int = 5
@export_range(0.02, 1.0, 0.01) var spatial_rebuild_interval: float = 0.12
@export_range(0.10, 3.0, 0.05) var leaderboard_interval: float = 0.75
@export_range(0.10, 3.0, 0.05) var simulation_tier_interval: float = 0.75
@export_range(0.05, 2.0, 0.05) var audio_context_interval: float = 0.25
@export_range(256.0, 6000.0, 1.0) var audio_context_radius: float = 1700.0

@export_category("Pools")
@export_range(0, 1024, 1) var unit_pool_limit: int = 128
@export_range(0, 1024, 1) var projectile_pool_limit: int = 96
@export_range(0, 1024, 1) var max_visual_projectiles: int = 120
@export_range(32, 8192, 1) var max_logical_projectiles: int = 2048

@export_category("Network")
## Per-peer command budget. Anything past it is dropped without telling the
## client, so it has to clear the honest traffic pattern with room to spare:
## movement alone can reach 45/s when a stick is being swept, and an order the
## player actually pressed must never be the thing that gets thrown away.
@export_range(1, 240, 1) var max_commands_per_second: int = 90
@export_range(10, 600, 1) var command_journal_capacity: int = 240


func sanitize() -> void:
	match_duration_seconds = clampf(match_duration_seconds, 60.0, 7200.0)
	unit_cap_per_colony = clampi(unit_cap_per_colony, 8, 256)
	server_tick_rate = clampf(server_tick_rate, 5.0, 60.0)
	projectile_tick_rate = clampf(projectile_tick_rate, 10.0, 120.0)
	max_server_steps_per_frame = clampi(max_server_steps_per_frame, 1, 16)
	max_projectile_steps_per_frame = clampi(max_projectile_steps_per_frame, 1, 16)
	spatial_rebuild_interval = clampf(spatial_rebuild_interval, 0.02, 1.0)
	leaderboard_interval = clampf(leaderboard_interval, 0.10, 3.0)
	simulation_tier_interval = clampf(simulation_tier_interval, 0.10, 3.0)
	audio_context_interval = clampf(audio_context_interval, 0.05, 2.0)
	audio_context_radius = clampf(audio_context_radius, 256.0, 6000.0)
	unit_pool_limit = clampi(unit_pool_limit, 0, 1024)
	projectile_pool_limit = clampi(projectile_pool_limit, 0, 1024)
	max_visual_projectiles = clampi(max_visual_projectiles, 0, 1024)
	max_logical_projectiles = clampi(max_logical_projectiles, 32, 8192)
	max_commands_per_second = clampi(max_commands_per_second, 1, 240)
	command_journal_capacity = clampi(command_journal_capacity, 10, 600)
	_apply_device_profile()


## Phones run the same match as desktop — same unit counts, same world, same
## content. Only two invisible scheduling knobs change, and neither removes
## anything from the game.
func _apply_device_profile() -> void:
	if not OS.has_feature("mobile") or OS.has_feature("dedicated_server"):
		return
	# Catch-up stepping is a stutter amplifier: once a phone misses the frame
	# budget it runs even more simulation steps next frame, which makes it miss
	# again. Three steps still cover 3x real time, so the match never runs slow;
	# it just stops the spiral.
	max_server_steps_per_frame = mini(max_server_steps_per_frame, 3)
	max_projectile_steps_per_frame = mini(max_projectile_steps_per_frame, 3)
	# Rebuilding the spatial index ~8x a second is redundant at a 30 Hz tick.
	spatial_rebuild_interval = maxf(spatial_rebuild_interval, 0.2)


func get_server_tick_interval() -> float:
	return 1.0 / server_tick_rate


func get_projectile_tick_interval() -> float:
	return 1.0 / projectile_tick_rate
