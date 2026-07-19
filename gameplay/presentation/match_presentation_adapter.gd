class_name MatchPresentationAdapter
extends CanvasLayer

signal safe_frame_insets_changed(insets: Vector4)


func bind_match(_match_node: Node, _controller: Node) -> void:
	push_error("MatchPresentationAdapter.bind_match() must be implemented by the client HUD")


func get_world_safe_frame_insets() -> Vector4:
	return Vector4.ZERO
