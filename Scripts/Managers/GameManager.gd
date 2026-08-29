extends Node

#Quick-travel shortcuts, usable from any level. Kept as paths and load()ed on demand
#so the big forest scenes aren't pulled into memory at startup.
const QUICK_TRAVEL = {
	"TeleportForest": "res://Scenes/Levels/Forest.tscn",
	"TeleportGreenForest": "res://Scenes/Levels/GreenForest.tscn",
	"TeleportUndeadForest": "res://Scenes/Levels/UndeadForest.tscn",
	"TeleportBossPlace": "res://Scenes/Levels/BossPlace.tscn",
}

var money = 0
var _hitstop_token := 0

func _process(_delta):
	if Input.is_action_just_pressed("GodMode"):
		toggle_god_mode()

	for action in QUICK_TRAVEL:
		if Input.is_action_just_pressed(action):
			var path = QUICK_TRAVEL[action]
			if get_tree().current_scene.scene_file_path != path:
				get_tree().change_scene_to_file(path)
			return

#region Debug god mode
#Toggled with '\'. PlayerMain checks this flag in the four places that spend a
#resource or take a hit, so nothing has to be reset when it is switched back off.
var god_mode : bool = false
var _god_banner : Label

func toggle_god_mode():
	god_mode = !god_mode
	_show_god_banner()
	if not god_mode:
		return
	#Top everything up, so a run that was already drained is usable straight away
	var player = get_tree().get_first_node_in_group("Player")
	if is_instance_valid(player) and player.has_method("full_restore"):
		player.full_restore()

#Lives on the autoload, so it survives scene changes like the flag it reports
func _show_god_banner():
	if not is_instance_valid(_god_banner):
		var layer = CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_god_banner = Label.new()
		_god_banner.label_settings = load("res://Art/Fonts/pixelized_label.tres")
		_god_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_god_banner.offset_top = 8.0
		_god_banner.offset_bottom = 28.0
		_god_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_god_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_god_banner.modulate = Color(1.0, 0.85, 0.35)
		layer.add_child(_god_banner)
	_god_banner.text = "GOD MODE ON" if god_mode else "GOD MODE OFF"
	_god_banner.visible = true
	if god_mode:
		return
	#The "off" message is only worth a moment
	var tween = create_tween()
	tween.tween_interval(1.2)
	tween.tween_callback(func(): if is_instance_valid(_god_banner): _god_banner.visible = false)
#endregion

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
