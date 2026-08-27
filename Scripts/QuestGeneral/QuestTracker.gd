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

func start_new_quest(new_quest : Quest):
	quest_length = new_quest.quest_objective.size()
	if quest_length < 1:
		print("Faulty quest objectives")
		return

	current_quest_step = 0
	current_quest.quest_id = new_quest.quest_id
	current_quest.quest_name = new_quest.quest_name
	current_quest.quest_objective = new_quest.quest_objective
	current_quest.quest_reward = new_quest.quest_reward

	quest_info.text = new_quest.quest_name + ":\n" + new_quest.quest_objective[current_quest_step]
	announce_quest("New Quest! \n" + new_quest.quest_name, 2)
	pass

#Unused currently
func update_quest(source_quest : Quest):
	if !source_quest:
		print("recieved quest is null")
		return

	if !current_quest:
		print("current quest is null")
		return

	if source_quest.quest_id != current_quest.quest_id:
		print("Quests did not match.." )
		return

	if current_quest_step+1 >= source_quest.quest_objective.size():
		print("Already at last stage of quest..")
		return

	current_quest_step += 1
	quest_info.text = current_quest.quest_name + "\n" + source_quest.quest_objective[current_quest_step]
	announce_quest("Quest updated!", 1.5)

func complete_quest(quest : Quest):
	GameManager.add_money(quest.quest_reward)
	announce_quest("Quest completed!", 3)
	quest_info.text = ""
	quest.free() #may be redundant

func announce_quest(text : String, time : float):
	quest_announcement.text = text
	quest_announcement.modulate.a = 0

	var tween = create_tween()
	tween.tween_property(quest_announcement, "modulate:a", 1, time)
	tween.chain().tween_property(quest_announcement, "modulate:a", 0, time)
	await tween.finished
	quest_announcement.text = ""
