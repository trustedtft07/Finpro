extends Node

#Quick-travel shortcuts, usable from any level. Kept as paths and load()ed on demand
#so the big forest scenes aren't pulled into memory at startup.
const QUICK_TRAVEL = {
	"TeleportForest": "res://Scenes/Levels/Forest.tscn",
	"TeleportGreenForest": "res://Scenes/Levels/GreenForest.tscn",
}

var money = 0
var _hitstop_token := 0

func _process(_delta):
	for action in QUICK_TRAVEL:
		if Input.is_action_just_pressed(action):
			var path = QUICK_TRAVEL[action]
			if get_tree().current_scene.scene_file_path != path:
				get_tree().change_scene_to_file(path)
			return

#Brief slow-motion freeze-frame for hit feedback. Safe to call from overlapping hits;
#only the most recent call restores time_scale, so a second hit extends the freeze
#instead of cutting it short.
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

#Everything a run carries between scenes. Starting over from the first level has to
#clear it, or you come back with a spent gourd and a checkpoint in a level you left.
func reset_run():
	reset_money()
	heal_charges = -1
	has_checkpoint = false
	checkpoint_position = Vector2.ZERO
	checkpoint_scene = ""

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
