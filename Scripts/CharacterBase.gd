extends CharacterBody2D
class_name CharacterBase

@export var sprite : AnimatedSprite2D
@export var healthbar : ProgressBar
@export var health : int
@export var flipped_horizontal : bool
@export var hit_particles : GPUParticles2D
#Independent of the damage flash below - tying the two together gave enemies 0.4s of
#immunity and ate every follow-up combo hit
@export var iframe_duration : float = 0.4
var invincible : bool = false
#Separate from 'invincible' so a dodge roll's i-frames aren't cut short by the damage-flash tween
var dodge_invincible : bool = false
var _flash_tween : Tween
var is_dead : bool = false
var max_health : int

var knockback_velocity : Vector2 = Vector2.ZERO
var is_knockbacked : bool = false
var _knockback_timer : float = 0.0
#Fast enough that the shove has bled off before its timer cuts it, or it stops dead
#mid-slide
@export var knockback_decay : float = 2600.0

func _ready():
	init_character()

func _process(_delta):
	Turn()

#move_and_slide() always steps by the physics delta, so driving it from _process() would
#scale distance travelled with the monitor's refresh rate
func _physics_process(delta):
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

#Movement states must skip setting velocity while is_knockbacked
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
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
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
	_play_damage_flash()
	await get_tree().create_timer(iframe_duration).timeout
	invincible = false

#Restarted, not stacked, so two tweens never fight over modulate and leave it stuck red
func _play_damage_flash():
	if(_flash_tween and _flash_tween.is_valid()):
		_flash_tween.kill()

	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.DARK_RED, 0.1)
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.1)
	_flash_tween.tween_property(self, "modulate", Color.RED, 0.1)
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.1)

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
	#PlayerMain handles its own removal
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self) and not is_in_group("Player"):
		queue_free()

#endregion
