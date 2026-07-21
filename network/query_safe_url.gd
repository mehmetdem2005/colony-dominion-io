class_name QuerySafeUrl
extends RefCounted


static func append_path(base_url: String, path_suffix: String) -> String:
	var base: String = base_url.strip_edges()
	if base.is_empty():
		return ""
	var fragment_index: int = base.find("#")
	if fragment_index >= 0:
		base = base.substr(0, fragment_index)
	var query: String = ""
	var query_index: int = base.find("?")
	if query_index >= 0:
		query = base.substr(query_index)
		base = base.substr(0, query_index)
	var suffix: String = path_suffix.strip_edges()
	if suffix.is_empty():
		return base.trim_suffix("/") + query
	if not suffix.begins_with("/"):
		suffix = "/" + suffix
	return base.trim_suffix("/") + suffix + query
