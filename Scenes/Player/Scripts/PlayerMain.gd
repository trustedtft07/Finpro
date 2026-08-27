extends CharacterBase
class_name PlayerMain

@onready var fsm = $FSM as FiniteStateMachine
@export var staminabar : ProgressBar
@export var aim_indicator : Node2D
@export var heal_bar : ProgressBar
const DEATH_SCREEN = preload("res://Scenes/Misc/DeathScreen.tscn")
const PROJECTILE = preload("res://Scenes/Interactables/Projectile.tscn")

#region Healing (Gourd)
#Getting hit while channeling interrupts the heal (see _take_damage override) - the charge is still spent either way
@export var max_heal_charges : int = 3
@export var heal_amount : int = 80
@export var heal_channel_time : float = 0.9
var heal_charges : int = 3

func has_heal_charge() -> bool:
	return heal_charges > 0

func use_heal_charge():
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
@export var projectile_stamina_cost : float = 20.0
@export var projectile_spawn_offset : float = 20.0
@export var aim_indicator_offset : float = 16.0

func set_facing_direction(dir : Vector2):
	if(dir != Vector2.ZERO):
		facing_direction = dir.normalized()

func try_fire_projectile():
	#Only allow firing while free to act, not mid melee-swing/roll/dying
	var state_name = fsm.current_state.name
	if(state_name != "Idle" && state_name != "Moving"):
		return

	if(!has_stamina(projectile_stamina_cost)):
		return

	use_stamina(projectile_stamina_cost)
	AudioManager.play_sound(AudioManager.PLAYER_ATTACK_SWING, 0.3, 0)

	var projectile = PROJECTILE.instantiate()
	projectile.direction = facing_direction
	projectile.global_position = global_position + facing_direction * projectile_spawn_offset
	get_tree().current_scene.add_child(projectile)
#endregion

#region Stamina
@export var max_stamina : float = 100.0
@export var stamina_regen_rate : float = 30.0
@export var stamina_regen_delay : float = 0.7
var stamina : float = 100.0
var _stamina_regen_timer : float = 0.0

func has_stamina(amount : float) -> bool:
	return stamina >= amount

func use_stamina(amount : float):
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

#region Checkpoint (Bonfire)
func full_restore():
	heal_to_full()
	stamina = max_stamina
	_update_staminabar()
	refill_heal_charges()
#endregion

func _ready():
	super() #calls init_character() on base-class CharacterBase
	staminabar.max_value = max_stamina
	staminabar.value = stamina
	heal_bar.max_value = max_heal_charges
	heal_charges = GameManager.heal_charges if GameManager.heal_charges >= 0 else max_heal_charges
	_update_heal_bar()

	#If we're loading into the scene our last bonfire was lit in, spawn there instead of the level's default start position
	if GameManager.has_checkpoint and get_tree().current_scene.scene_file_path == GameManager.checkpoint_scene:
		global_position = GameManager.checkpoint_position

#Only interrupt on hits that actually land, not ones blocked by an i-frame
func _take_damage(amount):
	if(fsm.current_state.name == "Healing" && !invincible && !dodge_invincible):
		fsm.current_state.interrupt()
	super._take_damage(amount)

func _process(delta):
	super(delta) #calls Turn() on base-class CharacterBase
	_regen_stamina(delta)

	if(Input.is_action_just_pressed("RangedAttack")):
		try_fire_projectile()

	aim_indicator.position = facing_direction * aim_indicator_offset
	aim_indicator.rotation = facing_direction.angle()
	aim_indicator.visible = !is_dead

#All of our logic is either in the CharacterBase class
#or spread out over our states in the finite-state-manager, this class is almost empty

func _die():
	super() #calls _die() on base-class CharacterBase

	fsm.force_change_state("Die")
	var death_scene = DEATH_SCREEN.instantiate()
	add_child(death_scene)
