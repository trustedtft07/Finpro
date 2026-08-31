extends Node
class_name Attack_Data

@export var anim : String
@export var damage : int
@export var stamina_cost : float = 20.0
@export var knockback_force : float = 520.0
@export var hitstop_duration : float = 0.05
#Seconds into the animation from which the next buffered press is honoured. Keep it past
#the frame the hitbox closes on, or a swing can be cancelled before it can connect.
@export var cancel_time : float = 0.3
#A short shove behind the swing. lunge_speed / lunge_decel is how long it lasts.
@export var lunge_speed : float = 260.0
@export var lunge_decel : float = 1600.0
