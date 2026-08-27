extends Area2D
class_name Projectile

@export var speed : float = 500.0
@export var damage : int = 20
@export var lifetime : float = 1.5

#Must be set by whoever spawns this (see PlayerMain.try_fire_projectile) before it enters the tree,
#since _ready() uses it to orient the sprite towards its travel direction
var direction : Vector2 = Vector2.RIGHT

func _ready():
	rotation = direction.angle()
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func _process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	if body.is_in_group("Enemy"):
		body._take_damage(damage)
		AudioManager.play_sound(AudioManager.PLAYER_ATTACK_HIT, 0, 1)
		queue_free()
