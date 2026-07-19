class_name AudioSnapshotController
extends Node

signal ducking_changed(music_db: float, ambient_db: float)

var _music_duck_db: float = 0.0
var _ambient_duck_db: float = 0.0
var _target_music_db: float = 0.0
var _target_ambient_db: float = 0.0
var _hold_left: float = 0.0
var _last_emitted_music_db: float = INF
var _last_emitted_ambient_db: float = INF


func trigger(ducking_db: float, duration: float) -> void:
	if not is_finite(ducking_db) or not is_finite(duration) or ducking_db <= 0.0 or duration <= 0.0:
		return
	_target_music_db = minf(_target_music_db, -ducking_db)
	_target_ambient_db = minf(_target_ambient_db, -ducking_db * 0.55)
	_hold_left = maxf(_hold_left, duration)
	set_process(true)


func reset() -> void:
	_hold_left = 0.0
	_target_music_db = 0.0
	_target_ambient_db = 0.0
	_music_duck_db = 0.0
	_ambient_duck_db = 0.0
	_emit_if_changed(true)
	set_process(false)


func _process(delta: float) -> void:
	if _hold_left > 0.0:
		_hold_left = maxf(0.0, _hold_left - delta)
	else:
		_target_music_db = 0.0
		_target_ambient_db = 0.0
	var attack_speed: float = 28.0
	var release_speed: float = 8.0
	var music_speed: float = attack_speed if _target_music_db < _music_duck_db else release_speed
	var ambient_speed: float = (
		attack_speed if _target_ambient_db < _ambient_duck_db else release_speed
	)
	_music_duck_db = move_toward(_music_duck_db, _target_music_db, music_speed * delta)
	_ambient_duck_db = move_toward(_ambient_duck_db, _target_ambient_db, ambient_speed * delta)
	_emit_if_changed()
	if _hold_left <= 0.0 and is_zero_approx(_music_duck_db) and is_zero_approx(_ambient_duck_db):
		set_process(false)


func _emit_if_changed(force: bool = false) -> void:
	if (
		not force
		and absf(_music_duck_db - _last_emitted_music_db) < 0.02
		and absf(_ambient_duck_db - _last_emitted_ambient_db) < 0.02
	):
		return
	_last_emitted_music_db = _music_duck_db
	_last_emitted_ambient_db = _ambient_duck_db
	ducking_changed.emit(_music_duck_db, _ambient_duck_db)
