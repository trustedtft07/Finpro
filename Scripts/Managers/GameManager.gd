extends Node

var money = 0
var _hitstop_token := 0

#NOTE This class is our game manager and handles the players money and loading scenes
#These functions can be called globally from anywhere

#Brief slow-motion freeze-frame for hit feedback. Safe to call from overlapping hits;
#only the most recent call restores time_scale, so a second hit while one is still
#resolving extends the freeze instead of cutting it short.
func hitstop(duration : float = 0.06, time_scale : float = 0.05):
	if duration <= 0.0:
		return
	_hitstop_token += 1
	var token = _hitstop_token
	Engine.time_scale = time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0

func reset_money():
	money = 0

func add_money(addmoney : int):
	money += addmoney

func load_next_level(next_scene : PackedScene):
	get_tree().change_scene_to_packed(next_scene)

func load_same_level():
	get_tree().reload_current_scene()

#region Checkpoint (Bonfire)
var has_checkpoint : bool = false
var checkpoint_position : Vector2 = Vector2.ZERO
var checkpoint_scene : String = ""

func set_checkpoint(world_position : Vector2, scene_path : String):
	has_checkpoint = true
	checkpoint_position = world_position
	checkpoint_scene = scene_path

#PlayerMain._ready() positions the player once it detects it's in this scene
func respawn_at_checkpoint():
	if !has_checkpoint:
		load_same_level()
		return

	if get_tree().current_scene.scene_file_path == checkpoint_scene:
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(checkpoint_scene)
#endregion

#region Healing (Gourd)
#Tracked here (not on PlayerMain) so it survives the fresh Player instance a scene reload creates.
#-1 = not set yet, dying does not refill this - only a bonfire rest does
var heal_charges : int = -1
#endregion
