class_name WorldContentCatalog
extends RefCounted

const PROP_VARIANTS: Array[Dictionary] = [
	{
		"key": &"tall_grass",
		"path": "res://assets/props/tall_grass.png",
		"size": 185.0,
		"radius": 42.0,
		"solid": false,
		"ground": false,
	},
	{
		"key": &"medium_grass",
		"path": "res://assets/props/medium_grass.png",
		"size": 145.0,
		"radius": 34.0,
		"solid": false,
		"ground": false,
	},
	{
		"key": &"low_bush",
		"path": "res://assets/props/low_bush.png",
		"size": 130.0,
		"radius": 32.0,
		"solid": false,
		"ground": false,
	},
	{
		"key": &"broad_leaf",
		"path": "res://assets/props/broad_leaf.png",
		"size": 210.0,
		"radius": 56.0,
		"solid": true,
		"ground": false,
	},
	{
		"key": &"large_rock",
		"path": "res://assets/props/large_rock.png",
		"size": 155.0,
		"radius": 54.0,
		"solid": true,
		"ground": false,
	},
	{
		"key": &"medium_rock",
		"path": "res://assets/props/medium_rock.png",
		"size": 105.0,
		"radius": 37.0,
		"solid": true,
		"ground": false,
	},
	{
		"key": &"small_rock",
		"path": "res://assets/props/small_rock.png",
		"size": 72.0,
		"radius": 24.0,
		"solid": true,
		"ground": false,
	},
	{
		"key": &"mushroom_large",
		"path": "res://assets/props/mushroom_large.png",
		"size": 132.0,
		"radius": 35.0,
		"solid": true,
		"ground": false,
	},
	{
		"key": &"mushroom_pair",
		"path": "res://assets/props/mushroom_pair.png",
		"size": 116.0,
		"radius": 31.0,
		"solid": true,
		"ground": false,
	},
	{
		"key": &"stump",
		"path": "res://assets/props/stump.png",
		"size": 245.0,
		"radius": 72.0,
		"solid": true,
		"ground": false,
	},
	{
		"key": &"mud_puddle",
		"path": "res://assets/props/mud_puddle.png",
		"size": 250.0,
		"radius": 80.0,
		"solid": false,
		"ground": true,
	},
]

const RESOURCE_VARIANTS: Array[Dictionary] = [
	{
		"type": &"seed",
		"path": "res://assets/resources/seeds.png",
		"amount": 72,
		"size": 82.0,
	},
	{
		"type": &"nectar",
		"path": "res://assets/resources/nectar.png",
		"amount": 60,
		"size": 86.0,
	},
	{
		"type": &"protein",
		"path": "res://assets/resources/protein.png",
		"amount": 68,
		"size": 144.0,
	},
	{
		"type": &"leaf",
		"path": "res://assets/resources/leaves.png",
		"amount": 68,
		"size": 82.0,
	},
	{
		"type": &"leaf",
		"path": "res://assets/resources/pod.png",
		"amount": 82,
		"size": 88.0,
	},
	{
		"type": &"stone",
		"path": "res://assets/resources/stone.png",
		"amount": 62,
		"size": 92.0,
	},
]

const BIOME_PROP_INDICES: Dictionary = {
	&"meadow": [0, 0, 1, 1, 2, 2, 3, 6, 7, 8, 10],
	&"forest": [0, 1, 2, 3, 3, 4, 5, 7, 8, 9, 9, 10],
	&"rocky": [1, 2, 4, 4, 5, 5, 6, 6, 9, 10],
	&"dry": [1, 2, 4, 5, 6, 6, 8, 10],
}

const BIOME_RESOURCE_INDICES: Dictionary = {
	&"meadow": [0, 0, 1, 3, 3, 4, 5],
	&"forest": [0, 1, 1, 2, 2, 3, 4, 5],
	&"rocky": [0, 2, 2, 5, 5, 5],
	&"dry": [0, 0, 2, 5, 5],
}
