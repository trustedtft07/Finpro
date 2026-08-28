extends Area2D

@export var label : Label
@export var glow : PointLight2D
@export var ember : Sprite2D

var player_in_range := false
var is_lit := false

func _ready():
	label.visible = false

func _process(_delta):
	if(player_in_range && Input.is_action_just_pressed("Enter") && _player_is_alive()):
		rest()

#Same reason as AreaExit: the death screen also binds 'E', and a corpse shouldn't rest
func _player_is_alive() -> bool:
	var player = get_tree().get_first_node_in_group("Player") as CharacterBase
	return is_instance_valid(player) and not player.is_dead

func _on_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = true
		label.visible = true

func _on_body_exited(body):
	if body.is_in_group("Player"):
		player_in_range = false
		label.visible = false

func rest():
	var player = get_tree().get_first_node_in_group("Player") as PlayerMain
	player.full_restore()
	GameManager.set_checkpoint(global_position, get_tree().current_scene.scene_file_path)
	AudioManager.play_sound(AudioManager.QUEST_SOUND, 0, -8)
	light_bonfire()

func light_bonfire():
	if is_lit:
		return
	is_lit = true

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(glow, "energy", 1.3, 0.6)
	tween.tween_property(ember, "modulate", Color(1.0, 0.55, 0.15, 1.0), 0.6)
