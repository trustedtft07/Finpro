extends Node

enum QuestFunction {GIVE=1, UPDATE=2, COMPLETE=3}
@export var quest : Quest
@export var type : QuestFunction = QuestFunction.GIVE
var player_quest_tracker : QuestTracker

func _on_body_entered(body):
	if !can_update_quest(body):
		return

	match type:
		1: give_quest()
		2: update_quest()
		3: complete_quest()

	AudioManager.play_sound(AudioManager.QUEST_SOUND, 0, -10)
	queue_free()

func give_quest():
	print("Giving Player a quest!")
	player_quest_tracker.start_new_quest(quest)

func update_quest():
	print("Updating a quest")
	player_quest_tracker.update_quest(quest)
	pass

func complete_quest():
	print("Completing a quest!")
	player_quest_tracker.complete_quest(quest)
	pass

func can_update_quest(body):
	player_quest_tracker = body.find_child("QuestTracker") as QuestTracker

	#!quest means quest is unset (null)
	if !body.is_in_group("Player") || !quest || !player_quest_tracker:
		return false
	else:
		return true
