class_name ColonyMainMenuArtController
extends ColonyMainMenu


func _open_ranking_panel() -> void:
	if not OnlineServices.auth.has_session():
		_open_auth_panel()
		return
	_set_modal_visible(true)
	_profile_panel.open_ranking()


func _open_profile_panel() -> void:
	if not OnlineServices.auth.has_session():
		_open_auth_panel()
		return
	_set_modal_visible(true)
	_profile_panel.open_profile()
