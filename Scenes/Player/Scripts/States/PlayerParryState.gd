extends State
class_name PlayerParrying

#Windup before the active window opens
@export var startup_time : float = 0.05
#Window where an incoming hit gets deflected
@export var active_window : float = 0.35
#Endlag on a whiff
@export var fail_recovery : float = 0.35
@export var stamina_cost : float = 10.0

@export var success_hitstop : float = 0.12
@export var success_timescale : float = 0.02
@export var deflect_knockback : float = 1200.0

@export var camera : Camera2D
@export var parry_text : Label
@export var parry_sparks : GPUParticles2D
@export var shield : ParryShield

enum Phase {STARTUP, ACTIVE, RECOVER}
var phase : Phase
var _timer : float
var _active : bool = false
var _attacker : EnemyMain
@onready var player : PlayerMain = $"../.."

func Enter():
	#Claimed here rather than by whichever state sent us, so a parry that can't start
	#doesn't leave the press in the buffer to fire again next frame
	player.claim_input(["Parry"])
	_active = false

	#call_deferred: see PlayerAttackState's stamina bail-out for why
	if(!player.has_stamina(stamina_cost)):
		call_deferred("_abort_to_idle")
		return

	player.use_stamina(stamina_cost)
	player.parried.connect(_on_parried)
	_active = true
	_start_phase(Phase.STARTUP, startup_time, Color(0.55, 0.85, 1.0))

func Exit():
	_active = false
	if player and player.parried.is_connected(_on_parried):
		player.parried.disconnect(_on_parried)
	if is_instance_valid(player):
		player.parry_active = false
		player.sprite.modulate = Color.WHITE
	if shield:
		shield.visible = false

func _abort_to_idle():
	state_transition.emit(self, "Idle")

func Update(delta : float):
	if(!_active):
		return

	#Rolling out of a whiffed parry is the escape the endlag exists to make you earn -
	#it costs the roll's own stamina on top of the parry's
	if(phase == Phase.RECOVER and player.peek_input(["Dash"])):
		state_transition.emit(self, "Rolling")
		return

	_timer -= delta
	if(_timer > 0):
		return

	match phase:
		Phase.STARTUP:
			_start_phase(Phase.ACTIVE, active_window, Color(0.85, 0.97, 1.0))
			player.parry_active = true
		Phase.ACTIVE:
			player.parry_active = false
			_start_phase(Phase.RECOVER, fail_recovery, Color(0.5, 0.5, 0.55))
		Phase.RECOVER:
			state_transition.emit(self, "Idle")

func _start_phase(new_phase : Phase, duration : float, tint : Color):
	phase = new_phase
	_timer = duration
	var tween = create_tween()
	tween.tween_property(player.sprite, "modulate", tint, min(duration * 0.4, 0.08))
	_update_shield(new_phase, duration)

func _update_shield(new_phase : Phase, duration : float):
	if(!shield):
		return

	match new_phase:
		Phase.STARTUP:
			shield.visible = true
			shield.rotation = player.facing_direction.angle()
			shield.line_color = Color(0.55, 0.9, 1.0, 0.0)
			shield.line_width = 2.0
			var tween = create_tween()
			tween.tween_property(shield, "line_color", Color(0.55, 0.9, 1.0, 0.55), duration)
		Phase.ACTIVE:
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(shield, "line_color", Color(0.75, 0.97, 1.0, 0.9), min(duration * 0.3, 0.08))
			tween.tween_property(shield, "line_width", 4.0, min(duration * 0.3, 0.08))
		Phase.RECOVER:
			var tween = create_tween()
			tween.tween_property(shield, "line_color", Color(0.4, 0.4, 0.45, 0.0), duration * 0.6)
			tween.tween_callback(func(): shield.visible = false)

#Fires from PlayerMain.try_parry the instant a hit lands during the active window
func _on_parried(attacker : EnemyMain):
	if(phase != Phase.ACTIVE):
		return

	_active = false
	_attacker = attacker
	player.parry_active = false
	_play_success()

func _play_success():
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_HIT, 0, 4)
	GameManager.hitstop(success_hitstop, success_timescale)
	_shake_camera(6.0, 0.18)
	_show_parry_text()
	_flash_shield()
	_deflect()

	var tween = create_tween()
	tween.tween_property(player.sprite, "modulate", Color(1.4, 1.4, 1.0), 0.06)
	tween.tween_property(player.sprite, "modulate", Color.WHITE, 0.16)
	await tween.finished

	#A landed parry is meant to open a punish, so a swing queued during the freeze-frame
	#comes straight out instead of being thrown away
	if player.peek_input(["Punch", "Kick"]):
		state_transition.emit(self, "Attacking")
		return

	state_transition.emit(self, "Idle")

#Deflect only - no damage dealt
func _deflect():
	if(!is_instance_valid(_attacker)):
		return

	var direction = _attacker.global_position - player.global_position
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	_spark_burst(direction)
	_attacker.apply_knockback(direction, deflect_knockback)
	_attacker.interrupt_attack()

func _spark_burst(direction : Vector2):
	if(!parry_sparks):
		return

	parry_sparks.rotation = direction.angle()
	parry_sparks.restart()

func _flash_shield():
	if(!shield):
		return

	shield.line_color = Color(1, 1, 1, 1)
	shield.line_width = 6.0

	var tween = create_tween()
	tween.tween_property(shield, "line_color", Color(0.75, 0.97, 1.0, 0.0), 0.2)
	tween.parallel().tween_property(shield, "line_width", 1.0, 0.2)
	tween.tween_callback(func(): shield.visible = false)

func _shake_camera(strength : float, duration : float):
	if(!camera):
		return

	var tween = create_tween()
	var steps := 6
	for i in steps:
		var offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(camera, "offset", offset, duration / steps)
	tween.tween_property(camera, "offset", Vector2.ZERO, duration / steps)

func _show_parry_text():
	if(!parry_text):
		return

	parry_text.modulate = Color(1, 1, 1, 1)
	parry_text.scale = Vector2(0.6, 0.6)

	var tween = create_tween()
	tween.tween_property(parry_text, "scale", Vector2(1.15, 1.15), 0.08).set_trans(Tween.TRANS_BACK)
	tween.tween_interval(0.35)
	tween.tween_property(parry_text, "modulate:a", 0.0, 0.25)
