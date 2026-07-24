class_name MainMenuArtLibrary
extends RefCounted

const ENCODED_ROOT: String = "res://assets/ui/main_menu/encoded/"
const SKIN_CHUNK_COUNT: int = 11

static var _skin_cache: Texture2D


static func skin_texture() -> Texture2D:
	if is_instance_valid(_skin_cache):
		return _skin_cache
	var encoded := ""
	for index in range(SKIN_CHUNK_COUNT):
		var path := ENCODED_ROOT + "skin_%03d.b64" % index
		if not FileAccess.file_exists(path):
			push_error("Main menu skin chunk is missing: %s" % path)
			return null
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("Main menu skin chunk could not be opened: %s" % path)
			return null
		encoded += file.get_as_text().strip_edges()
		file.close()
	var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if bytes.is_empty():
		push_error("Main menu skin could not be decoded")
		return null
	var image := Image.new()
	var error: Error = image.load_webp_from_buffer(bytes)
	if error != OK:
		push_error("Main menu skin WebP decode failed: %s" % error_string(error))
		return null
	_skin_cache = ImageTexture.create_from_image(image)
	return _skin_cache


static func clear_cache() -> void:
	_skin_cache = null
