class_name HudResponsiveLayout
extends RefCounted

## Floor for the extra shrink the production bar may take on narrow screens,
## relative to the rest of the HUD. Below this the unit cards stop being
## readable, so the bar keeps its size and the layout accepts a tighter gap.
const MIN_PRODUCTION_SHRINK: float = 0.7


func get_world_safe_frame_insets(context: HudLayoutContext) -> Vector4:
	if context == null or not is_instance_valid(context.viewport):
		return Vector4(24.0, 72.0, 24.0, 190.0)
	var viewport_size: Vector2 = context.viewport.get_visible_rect().size
	var bottom_inset: float = 190.0
	if is_instance_valid(context.production_panel):
		var production_rect: Rect2 = context.production_panel.get_global_rect()
		if production_rect.size.y > 0.0:
			bottom_inset = maxf(viewport_size.y - production_rect.position.y + 24.0, 176.0)
	return Vector4(24.0, 72.0, 24.0, bottom_inset)


func apply(context: HudLayoutContext) -> Vector4:
	if context == null or not context.is_ready():
		return get_world_safe_frame_insets(context)
	var safe_rect: Rect2 = _get_logical_safe_rect(context.viewport)
	if safe_rect.size.x <= 1.0 or safe_rect.size.y <= 1.0:
		return get_world_safe_frame_insets(context)
	var ui_scale: float = clampf(
		minf(safe_rect.size.x / 1188.0, safe_rect.size.y / 720.0), 0.64, 1.0
	)
	var scale_vector := Vector2.ONE * ui_scale
	var margin: float = 14.0 * ui_scale

	# Resource strip runs horizontally along the top-left, with the minimap
	# directly beneath it — the layout the framed HUD art is drawn for.
	context.resources_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.resources_panel.scale = scale_vector
	context.resources_panel.position = safe_rect.position + Vector2.ONE * margin
	context.resources_panel.size = Vector2(452.0, 66.0)

	context.minimap_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.minimap_panel.scale = scale_vector
	context.minimap_panel.position = Vector2(
		context.resources_panel.position.x,
		(
			context.resources_panel.position.y
			+ context.resources_panel.size.y * ui_scale
			+ 8.0 * ui_scale
		)
	)
	context.minimap_panel.size = Vector2(224.0, 224.0)

	context.leaderboard_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.leaderboard_panel.scale = scale_vector
	context.leaderboard_panel.size = Vector2(246.0, 260.0)
	context.leaderboard_panel.position = Vector2(
		safe_rect.end.x - margin - context.leaderboard_panel.size.x * ui_scale,
		safe_rect.position.y + 16.0 * ui_scale
	)

	context.timer_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.timer_label.scale = scale_vector
	context.timer_label.size = Vector2(152.0, 44.0)
	context.timer_label.position = Vector2(
		safe_rect.get_center().x - context.timer_label.size.x * ui_scale * 0.5,
		safe_rect.position.y + 16.0 * ui_scale
	)

	# The top row is fully taken by the resource strip and the centred clock, so
	# the two settings buttons sit in the gap beside the minimap instead — that
	# is the only place they clear both.
	var settings_column_x: float = (
		context.minimap_panel.position.x + context.minimap_panel.size.x * ui_scale + 12.0 * ui_scale
	)
	context.audio_settings_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.audio_settings_button.scale = scale_vector
	context.audio_settings_button.size = Vector2(84.0, 44.0)
	context.audio_settings_button.position = Vector2(
		settings_column_x, context.minimap_panel.position.y
	)

	context.settings_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.settings_button.scale = scale_vector
	context.settings_button.size = Vector2(84.0, 44.0)
	context.settings_button.position = Vector2(
		settings_column_x,
		(
			context.audio_settings_button.position.y
			+ context.audio_settings_button.size.y * ui_scale
			+ 8.0 * ui_scale
		)
	)

	context.audio_settings_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.audio_settings_panel.scale = scale_vector
	context.audio_settings_panel.size = Vector2(348.0, 370.0)
	var audio_panel_position := Vector2(
		context.audio_settings_button.position.x,
		(
			context.audio_settings_button.position.y
			+ context.audio_settings_button.size.y * ui_scale
			+ 8.0 * ui_scale
		)
	)
	var audio_panel_visual_size: Vector2 = context.audio_settings_panel.size * ui_scale
	audio_panel_position.x = clampf(
		audio_panel_position.x,
		safe_rect.position.x + margin,
		maxf(safe_rect.end.x - margin - audio_panel_visual_size.x, safe_rect.position.x + margin)
	)
	audio_panel_position.y = clampf(
		audio_panel_position.y,
		safe_rect.position.y + margin,
		maxf(safe_rect.end.y - margin - audio_panel_visual_size.y, safe_rect.position.y + margin)
	)
	context.audio_settings_panel.position = audio_panel_position

	# The controls go down first: the production bar is sized from the gap they
	# leave, so it cannot be placed before they are.
	_layout_mobile_controls(context, safe_rect, ui_scale)
	_layout_production_bar(context, safe_rect, ui_scale)
	_layout_overlay_panels(context, safe_rect, ui_scale)
	return get_world_safe_frame_insets(context)


func _layout_production_bar(context: HudLayoutContext, safe_rect: Rect2, ui_scale: float) -> void:
	context.production_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Matches the framed production art in hud.gd: the card row plus the status
	# line underneath only clear the frame's inner border at this size.
	# 766 is what the card row plus the upgrade slot actually measure. A
	# PanelContainer never shrinks below its content, so assigning less than
	# this was simply ignored — and the layout then placed the panel using the
	# number it had asked for rather than the one it got.
	context.production_panel.size = Vector2(766.0, 178.0)
	# Measure from the size the panel will really occupy, not the one just
	# assigned, for the same reason.
	var production_minimum: Vector2 = context.production_panel.get_combined_minimum_size()
	var production_size := Vector2(
		maxf(context.production_panel.size.x, production_minimum.x),
		maxf(context.production_panel.size.y, production_minimum.y)
	)

	# The bar shares the bottom band with the joystick on its left and the
	# command cluster on its right, so the width it may take is whatever those
	# two leave — never a fixed reserve. A fixed one held on 16:9 and broke on
	# 4:3: at 960x720 the left clamp, the bar and a 322 px reserve wanted 1032 px
	# of a 960 px screen, the clamp won, and the bar slid under HASAT and
	# GERİ ÇAĞIR.
	var gap: float = 8.0 * ui_scale
	var left_bound: float = maxf(
		safe_rect.position.x + 14.0 * ui_scale,
		context.stick.position.x + context.stick.size.x * ui_scale + gap
	)
	var right_bound: float = _command_cluster_left_edge(context, safe_rect) - gap
	var available_width: float = maxf(right_bound - left_bound, 1.0)
	var production_scale: float = ui_scale
	if production_size.x * production_scale > available_width:
		production_scale = maxf(
			available_width / production_size.x, ui_scale * MIN_PRODUCTION_SHRINK
		)
	context.production_panel.scale = Vector2.ONE * production_scale

	var production_visual_size: Vector2 = production_size * production_scale
	var production_x: float = maxf(right_bound - production_visual_size.x, left_bound)
	context.production_panel.position = Vector2(
		production_x, safe_rect.end.y - 10.0 * ui_scale - production_visual_size.y
	)


## Left edge of the buttons that sit at the production bar's own height. The
## BÖL/DAĞIT/BİRLEŞ row is above the bar, so it never constrains its width.
func _command_cluster_left_edge(context: HudLayoutContext, safe_rect: Rect2) -> float:
	var edge: float = safe_rect.end.x
	for button: Control in [context.gather_button, context.rally_button, context.attack_button]:
		if is_instance_valid(button):
			edge = minf(edge, button.position.x)
	return edge


func _layout_mobile_controls(context: HudLayoutContext, safe_rect: Rect2, ui_scale: float) -> void:
	var scale_vector := Vector2.ONE * ui_scale
	var margin: float = 18.0 * ui_scale
	context.stick.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.stick.scale = scale_vector
	context.stick.position = Vector2(
		safe_rect.position.x + 20.0 * ui_scale,
		safe_rect.end.y - 34.0 * ui_scale - context.stick.size.y * ui_scale
	)

	context.attack_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.attack_button.scale = scale_vector
	context.attack_button.position = Vector2(
		safe_rect.end.x - margin - context.attack_button.size.x * ui_scale,
		safe_rect.end.y - 22.0 * ui_scale - context.attack_button.size.y * ui_scale
	)

	context.gather_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.gather_button.scale = scale_vector
	context.gather_button.position = Vector2(
		context.attack_button.position.x - 130.0 * ui_scale,
		safe_rect.end.y - 122.0 * ui_scale - context.gather_button.size.y * ui_scale
	)
	context.rally_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.rally_button.scale = scale_vector
	context.rally_button.position = Vector2(
		context.attack_button.position.x - 130.0 * ui_scale,
		safe_rect.end.y - 56.0 * ui_scale - context.rally_button.size.y * ui_scale
	)

	var upper_y: float = safe_rect.end.y - 194.0 * ui_scale - context.split_button.size.y * ui_scale
	var right_edge: float = safe_rect.end.x - 10.0 * ui_scale
	context.merge_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.merge_button.scale = scale_vector
	context.merge_button.position = Vector2(
		right_edge - context.merge_button.size.x * ui_scale, upper_y
	)
	context.spread_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.spread_button.scale = scale_vector
	context.spread_button.position = Vector2(
		context.merge_button.position.x - 6.0 * ui_scale - context.spread_button.size.x * ui_scale,
		upper_y
	)
	context.split_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.split_button.scale = scale_vector
	context.split_button.position = Vector2(
		context.spread_button.position.x - 6.0 * ui_scale - context.split_button.size.x * ui_scale,
		upper_y
	)


func _layout_overlay_panels(context: HudLayoutContext, safe_rect: Rect2, ui_scale: float) -> void:
	var scale_vector := Vector2.ONE * ui_scale
	context.toast_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.toast_label.scale = scale_vector
	context.toast_label.size = Vector2(500.0, 56.0)
	context.toast_label.position = Vector2(
		safe_rect.get_center().x - context.toast_label.size.x * ui_scale * 0.5,
		safe_rect.get_center().y - 128.0 * ui_scale
	)
	context.game_over_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	context.game_over_panel.scale = scale_vector
	context.game_over_panel.size = Vector2(520.0, 320.0)
	context.game_over_panel.position = Vector2(
		safe_rect.get_center().x - context.game_over_panel.size.x * ui_scale * 0.5,
		safe_rect.get_center().y - context.game_over_panel.size.y * ui_scale * 0.5
	)


func _get_logical_safe_rect(viewport: Viewport) -> Rect2:
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var full_rect := Rect2(Vector2.ZERO, viewport_size)
	if not OS.has_feature("mobile"):
		return full_rect
	var screen_size_i: Vector2i = DisplayServer.screen_get_size()
	var safe_area_i: Rect2i = DisplayServer.get_display_safe_area()
	if screen_size_i.x <= 0 or screen_size_i.y <= 0 or safe_area_i.size == Vector2i.ZERO:
		return full_rect
	var scale_to_viewport := Vector2(
		viewport_size.x / float(screen_size_i.x), viewport_size.y / float(screen_size_i.y)
	)
	var logical_safe := Rect2(
		Vector2(safe_area_i.position) * scale_to_viewport,
		Vector2(safe_area_i.size) * scale_to_viewport
	)
	return logical_safe.intersection(full_rect)
