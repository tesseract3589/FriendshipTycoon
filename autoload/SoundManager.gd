extends Node

const PURCHASE_SOUND: AudioStream = preload("res://assets/SE/Ding.wav")
const SILENT_VOLUME_DB: float = -80.0

@export_range(0.0, 1.0, 0.01) var bgm_volume: float = 1.0
@export_range(0.0, 1.0, 0.01) var se_volume: float = 0.3

var _bgm_player: AudioStreamPlayer
var _active_se_players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	add_child(_bgm_player)
	_apply_bgm_volume()


func play_bgm(stream: AudioStream, restart: bool = false) -> void:
	if stream == null:
		ErrorManager.report_error("INVALID_AUDIO", "재생할 배경음 리소스가 없습니다.", "SoundManager.play_bgm")
		return
	if not restart and _bgm_player.stream == stream and _bgm_player.playing:
		return
	_bgm_player.stream = stream
	_bgm_player.play()


func stop_bgm() -> void:
	_bgm_player.stop()


func set_bgm_volume(volume: float) -> void:
	if not ErrorManager.validate_number(volume, "SoundManager.bgm_volume"):
		return
	bgm_volume = clampf(volume, 0.0, 1.0)
	_apply_bgm_volume()


func play_se(stream: AudioStream, volume_scale: float = 1.0) -> void:
	if stream == null:
		ErrorManager.report_error("INVALID_AUDIO", "재생할 효과음 리소스가 없습니다.", "SoundManager.play_se")
		return
	if not ErrorManager.validate_number(volume_scale, "SoundManager.se_volume_scale"):
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	var clamped_volume_scale := clampf(volume_scale, 0.0, 1.0)
	player.set_meta("volume_scale", clamped_volume_scale)
	player.volume_db = _volume_to_db(se_volume * clamped_volume_scale)
	player.finished.connect(_on_se_finished.bind(player))
	_active_se_players.append(player)
	add_child(player)
	player.play()


func play_purchase_sound() -> void:
	play_se(PURCHASE_SOUND)


func set_se_volume(volume: float) -> void:
	if not ErrorManager.validate_number(volume, "SoundManager.se_volume"):
		return
	se_volume = clampf(volume, 0.0, 1.0)
	for player in _active_se_players:
		if is_instance_valid(player):
			var volume_scale: float = player.get_meta("volume_scale", 1.0)
			player.volume_db = _volume_to_db(se_volume * volume_scale)


func _apply_bgm_volume() -> void:
	if is_instance_valid(_bgm_player):
		_bgm_player.volume_db = _volume_to_db(bgm_volume)


func _volume_to_db(volume: float) -> float:
	if volume <= 0.0:
		return SILENT_VOLUME_DB
	return linear_to_db(volume)


func _on_se_finished(player: AudioStreamPlayer) -> void:
	_active_se_players.erase(player)
	player.queue_free()
