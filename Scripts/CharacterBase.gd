extends CharacterBody2D
class_name CharacterBase

@export var sprite : AnimatedSprite2D
@export var healthbar : ProgressBar
@export var health : int
@export var flipped_horizontal : bool
@export var hit_particles : GPUParticles2D
var invincible : bool = false
#Separate from 'invincible' so a dodge roll's i-frames aren't cut short by the damage-flash tween
var dodge_invincible : bool = false
var is_dead : bool = false
var max_health : int

var knockback_velocity : Vector2 = Vector2.ZERO
var is_knockbacked : bool = false
var _knockback_timer : float = 0.0

func _ready():
	init_character()

func _process(delta):
	Turn()
	_process_knockback(delta)

func init_character():
	max_health = health
	healthbar.max_value = health
	healthbar.value = health

func heal_to_full():
	health = max_health
	healthbar.value = health

func Turn():
	#Some sprites are drawn facing the other way
	var direction = -1 if flipped_horizontal == true else 1

	if(velocity.x < 0):
		sprite.scale.x = -direction
	elif(velocity.x > 0):
		sprite.scale.x = direction

#region Knockback

#Movement states must check is_knockbacked and skip setting velocity while this is active
func apply_knockback(direction : Vector2, force : float, duration : float = 0.15):
	if force <= 0.0:
		return
	knockback_velocity = direction.normalized() * force
	is_knockbacked = true
	_knockback_timer = duration

func _process_knockback(delta : float):
	if not is_knockbacked:
		return
	velocity = knockback_velocity
	move_and_slide()
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
	_knockback_timer -= delta
	if _knockback_timer <= 0.0 or knockback_velocity.length() <= 1.0:
		is_knockbacked = false
		knockback_velocity = Vector2.ZERO

#endregion

#region Taking Damage

func damage_effects():
	AudioManager.play_sound(AudioManager.BLOODY_HIT, 0, -3)
	after_damage_iframes()
	if(hit_particles):
		hit_particles.emitting = true

func after_damage_iframes():
	invincible = true
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.DARK_RED, 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	tween.tween_property(self, "modulate", Color.RED, 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	await tween.finished
	invincible = false

func _take_damage(amount):
	if(invincible == true || dodge_invincible == true || is_dead == true):
		return

	health -= amount
	healthbar.value = health;
	damage_effects()

	if(health <= 0):
		_die()

func _die():
	if(is_dead):
		return

	is_dead = true
	#Not the player - PlayerMain handles its own removal
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self) and not is_in_group("Player"):
		queue_free()

#endregion
