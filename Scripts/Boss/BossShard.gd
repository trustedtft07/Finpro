extends Area2D
class_name BossShard

#Small crystal shard fired in fans during phase 2. A parry deflects it instead of
#taking the hit, so the parry window stays useful at range.

@export var speed : float = 235.0
@export var lifetime : float = 3.5
@export var spin_sprite : AnimatedSprite2D

var direction : Vector2 = Vector2.RIGHT
var damage : int = 16

var _age : float = 0.0

func _ready():
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	if spin_sprite:
		spin_sprite.play("star")
		spin_sprite.rotation = randf() * TAU

func _physics_process(delta):
	position += direction * speed * delta
	if spin_sprite:
		spin_sprite.rotation += delta * 7.0
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_body_entered(body):
	if body.is_in_group("Player"):
		var player = body as PlayerMain
		if player.parry_active:
			#Deflected - no damage, and the shard is gone
			AudioManager.play_sound(AudioManager.PLAYER_ATTACK_HIT, 0, -4)
			queue_free()
			return
		player._take_damage(damage)
		player.apply_knockback(direction, 180.0, 0.12)
		queue_free()
		return
	if body.is_in_group("Enemy"):
		return
	#Anything else is scenery
	queue_free()
