class_name MatchEventHub
extends Node

signal inventory_changed(team_id: int, inventory: Dictionary)
signal production_queue_changed(team_id: int, queue: Array, progress: float)
signal leaderboard_changed(entries: Array)
signal player_commander_changed(commander: Node2D)
signal match_time_changed(seconds_left: int)
signal match_ended(winner_name: String, player_won: bool)
signal toast_requested(message: String)
signal unit_count_changed(team_id: int, counts: Dictionary)
signal colony_progress_changed(
	team_id: int, level: int, capacity: int, army_size: int, next_cost: Dictionary
)
signal squad_state_changed(team_id: int, split_mode: bool)
signal formation_spread_changed(team_id: int, spread_mode: bool)
signal gather_state_changed(team_id: int, active: bool, seconds_left: int, resource_id: StringName)
