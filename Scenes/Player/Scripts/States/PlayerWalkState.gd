extends State
class_name PlayerWalking

@export var movespeed := int(350)
@export var dash_max := int(500)
@export var dash_stamina_cost := float(25.0)
@export var dodge_iframe_duration := float(0.25)
var dashspeed := float(100)
var can_dash := bool(false)
var dash_direction := Vector2(0,0)

var player : PlayerMain
@export var animator : AnimationPlayer

func Enter():
	player = get_tree().get_first_node_in_group("Player") as PlayerMain
	animator.play("Walk")

func Update(delta : float):
	var input_dir = Input.get_vector("MoveLeft", "MoveRight", "MoveUp", "MoveDown").normalized()
	Move(input_dir)
	LessenDash(delta)

	if(Input.is_action_just_pressed("Dash") && can_dash && player.has_stamina(dash_stamina_cost)):
		start_dash(input_dir)

	if Input.is_action_just_pressed("Punch") or Input.is_action_just_pressed("Kick"):
		Transition("Attacking")

	if Input.is_action_just_pressed("Heal"):
		Transition("Healing")

	if Input.is_action_just_pressed("Parry"):
		Transition("Parrying")

func Move(input_dir : Vector2):
	if(dash_direction != Vector2.ZERO and dash_direction != input_dir):
		dash_direction = Vector2.ZERO
		dashspeed = 0

	player.velocity = input_dir * movespeed + dash_direction * dashspeed
	player.move_and_slide()
	player.set_facing_direction(input_dir)

	if(input_dir.length() <= 0):
		Transition("Idle")

func start_dash(input_dir : Vector2):
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.3, -1)
	player.use_stamina(dash_stamina_cost)
	dash_direction = input_dir.normalized()
	dashspeed = dash_max
	animator.play("Dash")
	can_dash = false
	roll_iframes()

#Timed independently of the roll animation
func roll_iframes():
	player.dodge_invincible = true
	await get_tree().create_timer(dodge_iframe_duration).timeout
	player.dodge_invincible = false

func LessenDash(delta : float):
	var multiplier : float = 4.0
	var timemultiplier : float = 4.1

	#Decays both proportionally and linearly, clamped to [0, dash_max]
	dashspeed -= (dashspeed * multiplier * delta) + (delta * timemultiplier)
	dashspeed = clamp(dashspeed, 0, dash_max)

	if(dashspeed <= 0):
		can_dash = true
		dash_direction = Vector2.ZERO

	if(animator.current_animation == "Dash"):
		await animator.animation_finished
		animator.play("Walk")

#Blocks transitions until the dash finishes
func Transition(newstate : String):
	if(dashspeed <= 0):
		state_transition.emit(self, newstate)
