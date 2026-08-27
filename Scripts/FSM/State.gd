@icon("res://Art/Icons/StateSprite.png")
extends Node
class_name State

#Base class for all states - avoid changing this directly

@warning_ignore("unused_signal")
signal state_transition

func Enter():
	pass
	
func Exit():
	pass
	
func Update(_delta:float):
	pass
	
