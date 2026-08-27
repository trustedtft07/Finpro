extends Area2D

var talking = false
@export var speech : Label
@export var line1 = []

@export var show_text_duration : float = 1.0
@export var silence_duration : float = 1.0

func _ready():
	speech.text = ""

#region Signal Entering & Exiting

func _on_body_entered(body):
		if body.is_in_group("Player") and not talking:
			talk_tween()
			speech.text = line1[randi() % line1.size()]

func _on_body_exited(body):
	if body.is_in_group("Player") and talking:
		await get_tree().create_timer(show_text_duration).timeout
		speech.text = "*murmur*"
		await get_tree().create_timer(silence_duration).timeout
		speech.text = ""
		talking = false

#endregion

func talk_tween():
	talking = true
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.2)
	tween.tween_property(self, "scale", Vector2(0.9, 0.9), 0.2)
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.2)
	tween.tween_property(self, "scale", Vector2.ONE, 0.2)
