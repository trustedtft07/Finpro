extends CanvasLayer

@export var panel : Control

func _ready():
	panel.visible = false

func _process(_delta):
	if Input.is_action_just_pressed("MechanicsInfo"):
		panel.visible = !panel.visible
