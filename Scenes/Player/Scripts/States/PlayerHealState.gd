extends State
class_name PlayerHealing

@onready var sprite : AnimatedSprite2D = $"../../AnimatedSprite2D"

#Rises for the whole channel
@export var heal_particles : GPUParticles2D
#One-shot pop when the heal lands
@export var heal_burst : GPUParticles2D

@onready var player : PlayerMain = $"../.."
var interrupted := false
var _glow_tween : Tween

func Enter():
	#Claimed here rather than by whichever state sent us, so a heal that can't start
	#doesn't leave the press in the buffer to fire again next frame
	player.claim_input(["Heal"])

	#call_deferred: see PlayerAttackState's stamina bail-out for why
	if(!player.has_heal_charge()):
		call_deferred("_abort_to_idle")
		return

	player.use_heal_charge()
	interrupted = false
	AudioManager.play_sound(AudioManager.QUEST_SOUND, 0, -4)

	if(heal_particles):
		heal_particles.emitting = true

	_start_glow_pulse(player.heal_channel_time)

	await get_tree().create_timer(player.heal_channel_time).timeout

	_stop_glow_pulse()
	if(heal_particles):
		heal_particles.emitting = false

	if(!interrupted && is_instance_valid(player) && !player.is_dead):
		player.apply_heal()
		if(heal_burst):
			heal_burst.restart()

	state_transition.emit(self, "Idle")

func _abort_to_idle():
	state_transition.emit(self, "Idle")

#Called by PlayerMain on a landed hit
func interrupt():
	interrupted = true
	_stop_glow_pulse()
	if(heal_particles):
		heal_particles.emitting = false

#Breathing pulse instead of one flash
func _start_glow_pulse(total_duration : float):
	var pulse_time = 0.3
	var loops = max(int(total_duration / (pulse_time * 2.0)), 1)

	_glow_tween = create_tween()
	_glow_tween.set_loops(loops)
	_glow_tween.tween_property(sprite, "modulate", Color(0.4, 1.0, 0.55), pulse_time)
	_glow_tween.tween_property(sprite, "modulate", Color(0.75, 1.0, 0.85), pulse_time)

func _stop_glow_pulse():
	if(_glow_tween and _glow_tween.is_valid()):
		_glow_tween.kill()
	if(is_instance_valid(sprite)):
		sprite.modulate = Color.WHITE
