class_name UnitDefinition
extends Resource

@export var unit_id: StringName
@export var display_name: String
@export var role: StringName
@export var texture: Texture2D
@export var max_health: float = 100.0
@export var move_speed: float = 180.0
@export var acceleration: float = 900.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 42.0
@export var attack_interval: float = 0.8
@export var aggro_range: float = 220.0
@export var body_radius: float = 16.0
@export var sprite_world_size: float = 56.0
@export var formation_spacing: float = 42.0
@export var gather_rate: int = 0
@export var ranged: bool = false
@export var projectile_speed: float = 420.0
@export var spawn_time: float = 1.5
@export var score_value: int = 10
@export var cost_seed: int = 0
@export var cost_nectar: int = 0
@export var cost_protein: int = 0
@export var cost_leaf: int = 0
@export var cost_stone: int = 0


func get_cost() -> Dictionary:
	return {
		&"seed": cost_seed,
		&"nectar": cost_nectar,
		&"protein": cost_protein,
		&"leaf": cost_leaf,
		&"stone": cost_stone,
	}
