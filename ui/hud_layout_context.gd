class_name HudLayoutContext
extends RefCounted

var viewport: Viewport
var root_control: Control
var resources_panel: PanelContainer
var minimap_panel: PanelContainer
var leaderboard_panel: PanelContainer
var production_panel: PanelContainer
var timer_label: Label
var audio_settings_button: Button
var audio_settings_panel: PanelContainer
var stick: ColonyVirtualStick
var gather_button: TouchActionButton
var rally_button: TouchActionButton
var attack_button: TouchActionButton
var split_button: TouchActionButton
var spread_button: TouchActionButton
var merge_button: TouchActionButton
var toast_label: Label
var game_over_panel: PanelContainer


func is_ready() -> bool:
	return (
		is_instance_valid(viewport)
		and is_instance_valid(root_control)
		and is_instance_valid(resources_panel)
		and is_instance_valid(minimap_panel)
		and is_instance_valid(leaderboard_panel)
		and is_instance_valid(production_panel)
		and is_instance_valid(timer_label)
		and is_instance_valid(audio_settings_button)
		and is_instance_valid(audio_settings_panel)
		and is_instance_valid(stick)
		and is_instance_valid(gather_button)
		and is_instance_valid(rally_button)
		and is_instance_valid(attack_button)
		and is_instance_valid(split_button)
		and is_instance_valid(spread_button)
		and is_instance_valid(merge_button)
		and is_instance_valid(toast_label)
		and is_instance_valid(game_over_panel)
	)
