extends CharacterBase
class_name PlayerMain

@onready var fsm = $FSM as FiniteStateMachine
@export var staminabar : ProgressBar
@export var aim_indicator : Node2D
@export var heal_bar : ProgressBar
@export var manabar : ProgressBar
const DEATH_SCREEN = preload("res://Scenes/Misc/DeathScreen.tscn")
const PROJECTILE = preload("res://Scenes/Interactables/Projectile.tscn")

#region Input buffer
#A press made while the character is committed to something is remembered instead of
#dropped, so a swing queued mid-roll or mid-swing still comes out. The window has to
#outlast the recovery it carries a press through - the punch opens its cancel window at
#0.30s, so anything shorter silently drops the input again.
const BUFFERED_ACTIONS : Array[String] = ["Punch", "Kick", "Dash", "Parry", "Heal", "RangedAttack"]
@export var input_buffer_window : float = 0.3

var _buffered : String = ""
var _buffer_timer : float = 0.0

#Only the newest press is kept - a queue makes the character play out inputs the player
#has already stopped meaning
func _read_input_buffer(delta : float):
	if(_buffer_timer > 0.0):
		_buffer_timer -= delta
		if(_buffer_timer <= 0.0):
			_buffered = ""

	for action in BUFFERED_ACTIONS:
		if Input.is_action_just_pressed(action):
			_buffered = action
			_buffer_timer = input_buffer_window

#States peek to decide a transition and the state handed to claims the press, so it
#survives the change_state() in between
func peek_input(actions : Array) -> bool:
	return _buffered != "" and actions.has(_buffered)

func claim_input(actions : Array) -> String:
	if(!peek_input(actions)):
		return ""

	var action = _buffered
	clear_input_buffer()
	return action

func clear_input_buffer():
	_buffered = ""
	_buffer_timer = 0.0

func is_free_to_act() -> bool:
	if(fsm == null or fsm.current_state == null):
		return false
	var state_name = fsm.current_state.name
	return state_name == "Idle" or state_name == "Moving"
#endregion

#region Healing (Gourd)
#Getting hit while channeling interrupts the heal - the charge is still spent
@export var max_heal_charges : int = 3
@export var heal_amount : int = 80
@export var heal_channel_time : float = 0.9
var heal_charges : int = 3

func has_heal_charge() -> bool:
	return heal_charges > 0

func use_heal_charge():
	if GameManager.god_mode:
		return
	heal_charges -= 1
	GameManager.heal_charges = heal_charges
	_update_heal_bar()

func apply_heal():
	health = min(health + heal_amount, max_health)
	healthbar.value = health

func refill_heal_charges():
	heal_charges = max_heal_charges
	GameManager.heal_charges = heal_charges
	_update_heal_bar()

func _update_heal_bar():
	heal_bar.value = heal_charges
#endregion

#region Ranged Attack
#Only updated on movement, so it keeps pointing the same way while standing still
var facing_direction : Vector2 = Vector2.DOWN
@export var projectile_mana_cost : float = 25.0
@export var projectile_spawn_offset : float = 20.0
@export var aim_indicator_offset : float = 16.0

func set_facing_direction(dir : Vector2):
	if(dir != Vector2.ZERO):
		facing_direction = dir.normalized()

#region Wading through foliage
#Bushes carry a polygon on physics layer 8 ("Foliage"), which no body masks - they never
#block, they are only there to be read, and pushing through one costs speed the way
#branches would. The roll is deliberately left at full speed: a dodge that scenery can
#slow is a dodge the player cannot rely on.
#
#Asked as a shape query rather than through an Area2D on purpose - an Area2D reports no
#overlap at all against TileMapLayer's own static bodies here, and a query also answers
#on the frame it is asked instead of one frame late.
const FOLIAGE_MASK := 128
@export var bush_slow : float = 0.4
@onready var _body_shape : CollisionShape2D = $BodyCollisionShape
var _bush_query : PhysicsShapeQueryParameters2D

func is_in_bush() -> bool:
	if(_body_shape == null or _body_shape.shape == null):
		return false
	if(_bush_query == null):
		_bush_query = PhysicsShapeQueryParameters2D.new()
		_bush_query.shape = _body_shape.shape
		_bush_query.collision_mask = FOLIAGE_MASK
	_bush_query.transform = Transform2D(0.0, _body_shape.global_position)
	return not get_world_2d().direct_space_state.intersect_shape(_bush_query, 1).is_empty()

func move_speed_scale() -> float:
	return 1.0 - bush_slow if is_in_bush() else 1.0
#endregion

func try_fire_projectile():
	if(!has_mana(projectile_mana_cost)):
		return

	use_mana(projectile_mana_cost)
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.3, 0)

	var projectile = PROJECTILE.instantiate()
	projectile.direction = facing_direction
	projectile.global_position = global_position + facing_direction * projectile_spawn_offset
	get_tree().current_scene.add_child(projectile)
#endregion

#region Stamina
@export var max_stamina : float = 100.0
@export var stamina_regen_rate : float = 32.0
@export var stamina_regen_delay : float = 0.55
var stamina : float = 100.0
var _stamina_regen_timer : float = 0.0

func has_stamina(amount : float) -> bool:
	return stamina >= amount

func use_stamina(amount : float):
	if GameManager.god_mode:
		return
	stamina = clampf(stamina - amount, 0, max_stamina)
	_stamina_regen_timer = stamina_regen_delay
	_update_staminabar()

func _regen_stamina(delta : float):
	if(_stamina_regen_timer > 0):
		_stamina_regen_timer -= delta
		return

	if(stamina < max_stamina):
		stamina = clampf(stamina + stamina_regen_rate * delta, 0, max_stamina)
		_update_staminabar()

func _update_staminabar():
	staminabar.value = stamina
#endregion

#region Mana
#Only a bonfire rest or a kill restores it
@export var max_mana : float = 100.0
@export var mana_kill_restore : float = 5.0
var mana : float = 100.0

func has_mana(amount : float) -> bool:
	return mana >= amount

func use_mana(amount : float):
	if GameManager.god_mode:
		return
	mana = clampf(mana - amount, 0, max_mana)
	_update_manabar()

func restore_mana(amount : float):
	mana = clampf(mana + amount, 0, max_mana)
	_update_manabar()

func restore_mana_on_kill():
	restore_mana(mana_kill_restore)

func _update_manabar():
	manabar.value = mana
#endregion

#region Parry
signal parried(attacker)
var parry_active : bool = false

func try_parry(attacker) -> bool:
	if(!parry_active):
		return false

	parry_active = false #only the first hit within the window counts
	parried.emit(attacker)
	return true
#endregion

#region Checkpoint (Bonfire)
func full_restore():
	heal_to_full()
	stamina = max_stamina
	_update_staminabar()
	refill_heal_charges()
	mana = max_mana
	_update_manabar()
#endregion

func _ready():
	super()
	staminabar.max_value = max_stamina
	staminabar.value = stamina
	heal_bar.max_value = max_heal_charges
	heal_charges = GameManager.heal_charges if GameManager.heal_charges >= 0 else max_heal_charges
	_update_heal_bar()
	manabar.max_value = max_mana
	manabar.value = mana

	if GameManager.has_checkpoint and get_tree().current_scene.scene_file_path == GameManager.checkpoint_scene:
		global_position = GameManager.checkpoint_position

#Only hits that actually land interrupt a heal, not ones an i-frame blocked
func _take_damage(amount):
	if GameManager.god_mode:
		return
	if(fsm.current_state.name == "Healing" && !invincible && !dodge_invincible):
		fsm.current_state.interrupt()
	super._take_damage(amount)

func apply_knockback(direction : Vector2, force : float, duration : float = 0.15):
	if GameManager.god_mode:
		return
	super.apply_knockback(direction, force, duration)

#Turning on intent rather than the base class's velocity.x, which would flip the
#character to face wherever a knockback shoved them and leave a swing pointing wrong
func Turn():
	var direction = -1 if flipped_horizontal == true else 1

	if(facing_direction.x < -0.05):
		sprite.scale.x = -direction
	elif(facing_direction.x > 0.05):
		sprite.scale.x = direction

func _process(delta):
	super(delta)

	aim_indicator.position = facing_direction * aim_indicator_offset
	aim_indicator.rotation = facing_direction.angle()
	aim_indicator.visible = !is_dead

#This node is the state machine's parent, so the buffer is always filled before any
#state reads it
func _physics_process(delta):
	super(delta)
	_read_input_buffer(delta)
	_regen_stamina(delta)

	if(is_free_to_act() and claim_input(["RangedAttack"]) != ""):
		try_fire_projectile()

func _die():
	super()

	clear_input_buffer()
	fsm.force_change_state("Die")
	var death_scene = DEATH_SCREEN.instantiate()
	add_child(death_scene)
