extends Area2D
class_name Projectile

@export var speed : float = 500.0
@export var damage : int = 20
@export var lifetime : float = 1.5

#Set by whoever spawns this (see PlayerMain.try_fire_projectile) before it enters the tree
var direction : Vector2 = Vector2.RIGHT

func _ready():
	rotation = direction.angle()
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		queue_free()

func _process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	#Pass through the player who fired it, but stop on walls as well as enemies
	if body.is_in_group("Player"):
		return

	if body.is_in_group("Enemy"):
		var was_dead = body.is_dead
		body._take_damage(damage)
		AudioManager.play_sound(AudioManager.PLAYER_ATTACK_HIT, 0, 1)

		if(!was_dead && body.is_dead):
			var player = get_tree().get_first_node_in_group("Player") as PlayerMain
			if player:
				player.restore_mana_on_kill()

	queue_free()
