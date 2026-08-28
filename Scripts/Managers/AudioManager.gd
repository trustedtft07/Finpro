extends Node

#region Preloaded Sounds
const PLAYER_ATTACK_HIT = preload("res://Art/Audio/Effects/AttackHit.ogg")
const PLAYER_ATTACK_SWING = preload("res://Art/Audio/Effects/AttackSwing.ogg")
const ENEMY_HIT = preload("res://Art/Audio/Effects/Enemy_hit.ogg")
const BLOODY_HIT = preload("res://Art/Audio/Effects/bloody_hit.ogg")
const COIN_PICK = preload("res://Art/Audio/Effects/coin_pick.ogg")
const QUEST_SOUND = preload("res://Art/Audio/Effects/QuestSound.ogg")
#endregion

var audio_players = []
var max_players = 8
var starting_players = 3

func _ready() -> void:
	initiate_audio_stream()

#offset: start partway into the clip (seconds)
func play_sound(audiostream : AudioStreamOggVorbis, offset : float, volume : float):
	var available_player : AudioStreamPlayer = null
	for player in audio_players:
		if not player.is_playing():
			available_player = player
			break

	#Grow the pool on demand, and only cut off a playing sound once it's maxed out
	if available_player == null:
		if audio_players.size() < max_players:
			available_player = AudioStreamPlayer.new()
			audio_players.append(available_player)
			add_child(available_player)
		else:
			available_player = audio_players[0]

	available_player.stream = audiostream
	available_player.pitch_scale = randf_range(0.9, 1.1)
	available_player.volume_db = volume
	available_player.play(offset)

func initiate_audio_stream():
	for i in range(starting_players):
		var player = AudioStreamPlayer.new()
		audio_players.append(player)
		add_child(player)
