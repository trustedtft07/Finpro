extends CharacterBase
class_name EnemyMain

@onready var fsm = $FSM as FiniteStateMachine
var player_in_range = false

@export var attack_node : Node
@export var chase_node : Node

func finished_attacking():
	if(player_in_range == true):
		fsm.change_state(attack_node, "enemy_chase_state")
	else:
		fsm.change_state(attack_node, "enemy_idle_state")

#region Parry Stagger
#Prevents an instant re-attack right after a parry
@export var parry_stagger_duration : float = 0.6
var _stagger_timer : float = 0.0

func is_staggered() -> bool:
	return _stagger_timer > 0.0

#Physics frame: EnemyChaseState reads is_staggered() from Update()
func _physics_process(delta):
	super(delta)
	if(_stagger_timer > 0.0):
		_stagger_timer -= delta
#endregion

#On parry: stop the hitbox, stagger, then finish normally
func interrupt_attack():
	if attack_node.has_method("cancel"):
		attack_node.cancel()
	_stagger_timer = parry_stagger_duration
	finished_attacking()

func _on_detection_area_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = true
		#Only from idle, not death
		if fsm.current_state.name == "enemy_idle_state":
			fsm.force_change_state("enemy_chase_state")

func _on_detection_area_body_exited(body):
	if body.is_in_group("Player"):
		player_in_range = false
		fsm.change_state(chase_node, "enemy_idle_state")

func _die():
	super()
	fsm.force_change_state("enemy_death_state")
