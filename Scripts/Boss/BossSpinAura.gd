extends Node2D
class_name BossSpinAura

#The whirl drawn by the boss's spin. BossMain hands it the same radius and sweep angle
#its hitbox is using that frame, so what the player reads the danger off is exactly the
#shape that hits them - the same contract AttackAura keeps on the player's side.
#The windup borrows BossLightning's ground-marker language so it reads the same way.

@export var ring_color : Color = Color(1.0, 0.33, 0.36)
@export var edge_color : Color = Color(1.0, 0.66, 0.5)
#Degrees of fading trail left behind the leading edge
@export var trail_span : float = 80.0

var radius : float = 0.0
#Half-width of the wedge that actually damages, in degrees
var arc : float = 34.0
var angle : float = 0.0
#0..1 through the windup
var charge : float = 0.0
var sweeping : bool = false

func _ready():
	visible = false
	z_index = -1        # on the ground, under the boss drawing it

#Called once as the move starts, with the numbers the hitbox will use
func begin(hit_radius : float, hit_arc : float, aim : float):
	radius = hit_radius
	arc = hit_arc
	angle = aim
	charge = 0.0
	sweeping = false
	visible = true
	queue_redraw()

func telegraph(progress : float):
	charge = clampf(progress, 0.0, 1.0)
	sweeping = false
	queue_redraw()

func sweep(new_angle : float):
	angle = new_angle
	charge = 1.0
	sweeping = true
	queue_redraw()

func finish():
	visible = false
	sweeping = false
	queue_redraw()

func _draw():
	if radius <= 0.0:
		return

	#The reach - standing outside it is the whole answer to the move
	draw_circle(Vector2.ZERO, radius, Color(ring_color.r, ring_color.g, ring_color.b, 0.11 * charge))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48,
			Color(ring_color.r, ring_color.g, ring_color.b, 0.28 + 0.5 * charge), 2.0, true)

	if not sweeping:
		#A ring closing in while it winds up, so the pause reads as a threat
		draw_arc(Vector2.ZERO, maxf(radius * (1.0 - charge), 1.0), 0.0, TAU, 40,
				Color(edge_color.r, edge_color.g, edge_color.b, 0.55 + 0.4 * charge), 3.0, true)
		return

	_draw_trail()
	_draw_wedge()

#Fades quadratically so the leading edge - the part about to hit - stays brightest
func _draw_trail():
	var half = deg_to_rad(arc)
	var span = deg_to_rad(trail_span)
	var steps := 6
	for i in steps:
		var to = angle - half - span * float(i) / steps
		var from = angle - half - span * float(i + 1) / steps
		var fade = 1.0 - float(i) / float(steps)
		draw_arc(Vector2.ZERO, radius * 0.93, from, to, 8,
				Color(edge_color.r, edge_color.g, edge_color.b, 0.5 * fade * fade), 5.0, true)

#The exact shape BossMain._hit_player_wedge() is testing
func _draw_wedge():
	var half = deg_to_rad(arc)
	var segments := 14
	var fan := PackedVector2Array([Vector2.ZERO])
	for i in segments + 1:
		var step = angle - half + 2.0 * half * float(i) / float(segments)
		fan.append(Vector2.RIGHT.rotated(step) * radius)

	draw_colored_polygon(fan, Color(edge_color.r, edge_color.g, edge_color.b, 0.22))
	draw_arc(Vector2.ZERO, radius, angle - half, angle + half, 20,
			Color(edge_color.r, edge_color.g, edge_color.b, 0.95), 4.0, true)
