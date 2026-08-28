extends Node

enum QuestFunction {GIVE=1, UPDATE=2, COMPLETE=3}
@export var quest : Quest
@export var type : QuestFunction = QuestFunction.GIVE
var player_quest_tracker : QuestTracker

func _on_body_entered(body):
	if !can_update_quest(body):
		return

	#Only consume the trigger if the step actually applied - reaching the "complete"
	#trigger before the quest was ever given must leave it there for the way back
	var applied := false
	match type:
		1: applied = give_quest()
		2: applied = update_quest()
		3: applied = complete_quest()

	if !applied:
		return

	AudioManager.play_sound(AudioManager.QUEST_SOUND, 0, -10)
	queue_free()

func give_quest() -> bool:
	print("Giving Player a quest!")
	return player_quest_tracker.start_new_quest(quest)

func update_quest() -> bool:
	print("Updating a quest")
	return player_quest_tracker.update_quest(quest)

func complete_quest() -> bool:
	print("Completing a quest!")
	return player_quest_tracker.complete_quest(quest)

func can_update_quest(body):
	player_quest_tracker = body.find_child("QuestTracker") as QuestTracker

	#!quest means quest is unset (null)
	if !body.is_in_group("Player") || !quest || !player_quest_tracker:
		return false
	else:
		return true
