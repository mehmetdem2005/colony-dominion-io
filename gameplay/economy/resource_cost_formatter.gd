class_name ResourceCostFormatter
extends RefCounted

const RESOURCE_NAMES: Dictionary = {
	&"seed": "tohum",
	&"nectar": "nektar",
	&"protein": "protein",
	&"leaf": "yaprak",
	&"stone": "taş",
}


static func format(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for resource_id in ColonyInventory.RESOURCE_IDS:
		var amount: int = int(cost.get(resource_id, 0))
		if amount > 0:
			parts.append("%d %s" % [amount, String(RESOURCE_NAMES.get(resource_id, resource_id))])
	return ", ".join(parts)
