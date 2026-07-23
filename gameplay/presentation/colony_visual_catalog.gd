class_name ColonyVisualCatalog
extends RefCounted

const NEST_BLUE_PATH: String = "res://assets/structures/nest_blue.png"
const NEST_RED_PATH: String = "res://assets/structures/nest_red.png"

const TEAM_COLORS: Array[Color] = [
	Color("2a9cff"),
	Color("ff3d49"),
	Color("35e06f"),
	Color("c252ff"),
	Color("ff9f1a"),
	Color("18d9e8"),
	Color("ffd23f"),
	Color("f15bb5"),
	Color("8ac926"),
	Color("b08968"),
]

static var _nest_blue: Texture2D = null
static var _nest_red: Texture2D = null


static func team_color(team_id: int) -> Color:
	return TEAM_COLORS[posmod(team_id, TEAM_COLORS.size())]


static func nest_texture(team_id: int) -> Texture2D:
	if team_id == 0:
		if _nest_blue == null:
			_nest_blue = load(NEST_BLUE_PATH) as Texture2D
		return _nest_blue
	if _nest_red == null:
		_nest_red = load(NEST_RED_PATH) as Texture2D
	return _nest_red


static func configure_unit_sprite(sprite: Sprite2D, definition: UnitDefinition) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.texture = definition.texture if definition != null else null
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE
	sprite.modulate = Color.WHITE
	if definition == null or definition.texture == null:
		return
	var longest: float = float(max(definition.texture.get_width(), definition.texture.get_height()))
	sprite.scale = Vector2.ONE * (definition.sprite_world_size / maxf(longest, 1.0))


static func configure_nest_sprite(sprite: Sprite2D, team_id: int) -> void:
	if not is_instance_valid(sprite):
		return
	var texture: Texture2D = nest_texture(team_id)
	sprite.texture = texture
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.modulate = Color.WHITE
	if texture == null:
		return
	var longest: float = float(max(texture.get_width(), texture.get_height()))
	sprite.scale = Vector2.ONE * (205.0 / maxf(longest, 1.0))
