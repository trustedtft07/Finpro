extends Node2D
class_name AttackAura

#The swing aura on the player's melee attacks.
#
#Nothing here is keyframed. The aura reads the melee hitboxes themselves and draws the
#area they cover, and it is on screen for exactly as long as the AnimationPlayer keeps
#one of them enabled. So the glow a player reads their spacing off is the reach they
#actually have, and retuning a shape in the inspector retunes the aura with it - there
#is no second copy of the numbers to drift out of sync.
#
#This node sits under AnimatedSprite2D alongside the hitboxes, so the facing flip on the
#sprite mirrors the aura and the hitbox together.

#In the same order as PlayerAttacking.attacks: punch first, then kick
@export var shapes : Array[CollisionShape2D]
#One tint per shape; the last is reused if this list is shorter
@export var tints : Array[Color] = [Color(1.0, 0.84, 0.5), Color(0.6, 0.9, 1.0)]
#Time to sweep out to full reach, and to fade once the hitbox closes again
@export var grow_time : float = 0.07
@export var fade_time : float = 0.16
#A corpse keeps whichever hitbox the death animation interrupted - see
#PlayerAttackState._on_hitbox_body_entered for the same guard on the damage side
@export var character : CharacterBase

var _shape : CollisionShape2D
var _grow : float = 0.0
var _alpha : float = 0.0

func _ready():
	z_index = 1

func _process(delta : float):
	var active = _active_shape()
	if active:
		if active != _shape:
			_shape = active
			_grow = 0.0
		_grow = minf(_grow + delta / maxf(grow_time, 0.001), 1.0)
		_alpha = 1.0
	elif _shape:
		_alpha = maxf(_alpha - delta / maxf(fade_time, 0.001), 0.0)
		if _alpha <= 0.0:
			_shape = null
	else:
		return
	queue_redraw()

func _active_shape() -> CollisionShape2D:
	if character and character.is_dead:
		return null
	for shape in shapes:
		if is_instance_valid(shape) and not shape.disabled:
			return shape
	return null

func _draw():
	if _shape == null or _alpha <= 0.0:
		return
	var shape = _shape.shape
	if shape == null:
		return
	#Both nodes hang off the same mirrored parent, so this lands in the aura's own frame
	var origin = to_local(_shape.global_position)
	var tint = _tint_for(_shape)
	if shape is CircleShape2D:
		_draw_ring(origin, (shape as CircleShape2D).radius, tint)
	elif shape is RectangleShape2D:
		_draw_slash(origin, (shape as RectangleShape2D).size, tint)

#A leaf inscribed in the hitbox rectangle - widest across the middle, tapering to both
#ends. Inscribed rather than circumscribed on purpose: the aura never promises reach the
#box does not have.
func _draw_slash(origin : Vector2, size : Vector2, tint : Color):
	var near = origin.x - size.x * 0.5
	var far = near + size.x * _grow
	var half = size.y * 0.5
	var steps := 16
	var edge := PackedVector2Array()
	for i in steps + 1:
		var t = float(i) / float(steps)
		#sin gives the leaf its belly; the exponent keeps the two tips from going spindly
		var spread = half * pow(sin(t * PI), 0.55)
		edge.append(Vector2(lerpf(near, far, t), origin.y - spread))
	for i in steps + 1:
		var t = 1.0 - float(i) / float(steps)
		var spread = half * pow(sin(t * PI), 0.55)
		edge.append(Vector2(lerpf(near, far, t), origin.y + spread))

	draw_colored_polygon(edge, Color(tint.r, tint.g, tint.b, 0.26 * _alpha))
	edge.append(edge[0])
	draw_polyline(edge, Color(tint.r, tint.g, tint.b, 0.8 * _alpha), 1.5, true)

#The kick reaches the same distance every way, so its aura is the hitbox circle itself,
#opening outwards.
func _draw_ring(origin : Vector2, radius : float, tint : Color):
	var r = radius * _grow
	if r <= 0.5:
		return
	draw_circle(origin, r, Color(tint.r, tint.g, tint.b, 0.15 * _alpha))
	draw_arc(origin, r, 0.0, TAU, 48, Color(tint.r, tint.g, tint.b, 0.85 * _alpha), 2.5, true)

func _tint_for(shape : CollisionShape2D) -> Color:
	if tints.is_empty():
		return Color.WHITE
	return tints[clampi(shapes.find(shape), 0, tints.size() - 1)]
