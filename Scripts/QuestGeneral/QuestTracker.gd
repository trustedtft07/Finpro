extends Node
class_name QuestTracker

const QUESTRESOURCE = preload("res://Scenes/QuestTemplate.tscn")
var current_quest_step := 0
var quest_length : int
var current_quest : Quest
@export var quest_info : Label
@export var quest_announcement : Label

func _ready():
	quest_announcement.text = ""
	current_quest = QUESTRESOURCE.instantiate()
	add_child(current_quest)

#All three return whether the step actually applied - QuestGiver only consumes its
#trigger on a true
func start_new_quest(new_quest : Quest) -> bool:
	quest_length = new_quest.quest_objective.size()
	if quest_length < 1:
		print("Faulty quest objectives")
		return false

	current_quest_step = 0
	current_quest.quest_id = new_quest.quest_id
	current_quest.quest_name = new_quest.quest_name
	current_quest.quest_objective = new_quest.quest_objective
	current_quest.quest_reward = new_quest.quest_reward

	quest_info.text = new_quest.quest_name + ":\n" + new_quest.quest_objective[current_quest_step]
	announce_quest("New Quest! \n" + new_quest.quest_name, 2)
	return true

func update_quest(source_quest : Quest) -> bool:
	if !source_quest:
		print("recieved quest is null")
		return false

	if !current_quest:
		print("current quest is null")
		return false

	if source_quest.quest_id != current_quest.quest_id:
		print("Quests did not match.." )
		return false

	if current_quest_step+1 >= source_quest.quest_objective.size():
		print("Already at last stage of quest..")
		return false

	current_quest_step += 1
	quest_info.text = current_quest.quest_name + "\n" + source_quest.quest_objective[current_quest_step]
	announce_quest("Quest updated!", 1.5)
	return true

func complete_quest(quest : Quest) -> bool:
	#Only the quest actually being tracked can be completed - a level's quest givers all
	#point at one shared Quest node, so walking into the "finish" trigger first must not
	#pay out (or, worse, free that node out from under the "start" trigger)
	if !quest || !current_quest || quest.quest_id != current_quest.quest_id:
		print("No matching active quest to complete")
		return false

	GameManager.add_money(quest.quest_reward)
	announce_quest("Quest completed!", 3)
	quest_info.text = ""
	current_quest.quest_id = 0
	return true

func announce_quest(text : String, time : float):
	quest_announcement.text = text
	quest_announcement.modulate.a = 0

	var tween = create_tween()
	tween.tween_property(quest_announcement, "modulate:a", 1, time)
	tween.chain().tween_property(quest_announcement, "modulate:a", 0, time)
	await tween.finished
	quest_announcement.text = ""
