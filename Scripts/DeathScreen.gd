extends "res://Scripts/Reset.gd"

#The death screen no longer waits on a keypress - "YOU DIED" fades in, holds, then
#respawn_at_checkpoint() fires on its own, the way a soulslike's death screen does.
#restart() (and therefore GameManager.reset_money()) already leaves the checkpoint,
#heal_charges and everything else on the GameManager autoload untouched - only the
#level itself reloads, so enemies and the boss come back fresh while the bonfire
#progress does not.
#
#Escape (quit) and Enter (back to the first level) are inherited from Reset.gd and
#still work at any point during the wait, for a player who doesn't want to watch it out.

@export var label : Label
@export var fade_in_time : float = 0.9
@export var hold_time : float = 1.6

var _respawned := false

func _ready():
	if label:
		label.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(label, "modulate:a", 1.0, fade_in_time)

	await get_tree().create_timer(fade_in_time + hold_time).timeout
	if not _respawned and is_instance_valid(self):
		_auto_respawn()

func _auto_respawn():
	_respawned = true
	restart()

#Overridden so a manual Restart press (still wired via Reset.gd's _process) also marks
#the flag - otherwise the awaited timer above would fire a second, redundant respawn
func restart():
	_respawned = true
	super.restart()
