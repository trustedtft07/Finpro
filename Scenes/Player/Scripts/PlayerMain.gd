extends CharacterBase
class_name PlayerMain

@onready var fsm = $FSM as FiniteStateMachine
@export var staminabar : ProgressBar
@export var aim_indicator : Node2D
@export var heal_bar : ProgressBar
@export var manabar : ProgressBar
const DEATH_SCREEN = preload("res://Scenes/Misc/DeathScreen.tscn")
const PROJECTILE = preload("res://Scenes/Interactables/Projectile.tscn")

#region Healing (Gourd)
#Getting hit while channeling interrupts the heal - charge still spent
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
@export var projectile_mana_cost : float = 25.0
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

#region Mana
#Doesn't regenerate on its own - only bonfire rest or a kill restores it
@export var max_mana : float = 100.0
@export var mana_kill_restore : float = 5.0
var mana : float = 100.0

func has_mana(amount : float) -> bool:
	return mana >= amount

func use_mana(amount : float):
	mana = clampf(mana - amount, 0, max_mana)
	_update_manabar()

func restore_mana(amount : float):
	mana = clampf(mana + amount, 0, max_mana)
	_update_manabar()

#Used by PlayerAttackState and Projectile on a kill
func restore_mana_on_kill():
	restore_mana(mana_kill_restore)

func _update_manabar():
	manabar.value = mana
#endregion

#region Parry
#True only during the parry active window; checked by EnemyAttackState
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

	#Spawn at the last bonfire if we're in that scene
	if GameManager.has_checkpoint and get_tree().current_scene.scene_file_path == GameManager.checkpoint_scene:
		global_position = GameManager.checkpoint_position

#Only interrupt on hits that actually land, not ones blocked by an i-frame
func _take_damage(amount):
	if(fsm.current_state.name == "Healing" && !invincible && !dodge_invincible):
		fsm.current_state.interrupt()
	super._take_damage(amount)

func _process(delta):
	super(delta)
	_regen_stamina(delta)

	if(Input.is_action_just_pressed("RangedAttack")):
		try_fire_projectile()

	aim_indicator.position = facing_direction * aim_indicator_offset
	aim_indicator.rotation = facing_direction.angle()
	aim_indicator.visible = !is_dead

func _die():
	super()

	fsm.force_change_state("Die")
	var death_scene = DEATH_SCREEN.instantiate()
	add_child(death_scene)
