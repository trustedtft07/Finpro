extends Node2D
class_name ParryShield

#Drawn procedurally, no sprite needed
@export var radius : float = 22.0
@export var arc_span_degrees : float = 130.0
@export var segments : int = 24

#Setter triggers a redraw, so Tween can animate these directly
var line_color : Color = Color(0.55, 0.9, 1.0, 0.0):
	set(value):
		line_color = value
		queue_redraw()

var line_width : float = 3.0:
	set(value):
		line_width = value
		queue_redraw()

func _ready():
	visible = false

func _draw():
	var half = deg_to_rad(arc_span_degrees) * 0.5
	draw_arc(Vector2.ZERO, radius, -half, half, segments, line_color, line_width, true)
