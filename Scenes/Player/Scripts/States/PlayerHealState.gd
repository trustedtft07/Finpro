extends State
class_name PlayerHealing

@onready var sprite : AnimatedSprite2D = $"../../AnimatedSprite2D"
var player : PlayerMain
var interrupted := false

func Enter():
	player = get_tree().get_first_node_in_group("Player") as PlayerMain

	#call_deferred: see PlayerAttackState's stamina bail-out for why
	if(!player.has_heal_charge()):
		call_deferred("_abort_to_idle")
		return

	player.use_heal_charge()
	interrupted = false
	AudioManager.play_sound(AudioManager.QUEST_SOUND, 0, -4)

	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(0.4, 1.0, 0.55), player.heal_channel_time * 0.5)
	tween.tween_property(sprite, "modulate", Color.WHITE, player.heal_channel_time * 0.5)

	await get_tree().create_timer(player.heal_channel_time).timeout

	if(!interrupted && is_instance_valid(player) && !player.is_dead):
		player.apply_heal()

	state_transition.emit(self, "Idle")

func _abort_to_idle():
	state_transition.emit(self, "Idle")

#Called by PlayerMain when the player takes real damage while this state is active
func interrupt():
	interrupted = true
