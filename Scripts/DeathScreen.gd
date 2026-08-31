extends "res://Scripts/Reset.gd"

#"YOU DIED" fades in, holds, then respawn_at_checkpoint() fires on its own. restart()
#leaves the checkpoint and heal_charges on the GameManager autoload untouched - only the
#level reloads, so enemies and the boss come back fresh while bonfire progress does not.
#Escape and Enter are inherited from Reset.gd and still work during the wait.

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

#So a manual Restart press marks the flag too and the timer above doesn't fire a second
#redundant respawn
func restart():
	_respawned = true
	super.restart()
