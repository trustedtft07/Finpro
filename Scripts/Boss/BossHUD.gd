extends CanvasLayer
class_name BossHUD

#Boss bar in the Elden Ring shape: a wide, thin bar pinned to the bottom of the screen
#with the boss name under it. A slower "lag" bar drains behind the real one so the
#size of a hit is readable.

@export var root : Control
@export var bar : ProgressBar
@export var lag_bar : ProgressBar
@export var name_label : Label
@export var lag_delay : float = 0.35
@export var lag_time : float = 0.55

var _lag_tween : Tween

func _ready():
	if root:
		root.visible = false

func show_bar(boss_name : String, max_value : float, value : float):
	if bar:
		bar.max_value = max_value
		bar.value = value
	if lag_bar:
		lag_bar.max_value = max_value
		lag_bar.value = value
	set_name_text(boss_name)
	if not root:
		return
	root.visible = true
	root.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(root, "modulate:a", 1.0, 0.4)

func hide_bar():
	if root:
		root.visible = false

func set_name_text(boss_name : String):
	if name_label:
		name_label.text = boss_name

func on_damaged(value : float):
	if not lag_bar:
		return
	if _lag_tween and _lag_tween.is_valid():
		_lag_tween.kill()
	_lag_tween = create_tween()
	_lag_tween.tween_interval(lag_delay)
	_lag_tween.tween_property(lag_bar, "value", value, lag_time).set_trans(Tween.TRANS_CUBIC)

func flash():
	if not root:
		return
	var tween = create_tween()
	tween.tween_property(root, "modulate", Color(2.2, 1.6, 1.6, 1.0), 0.12)
	tween.tween_property(root, "modulate", Color.WHITE, 0.45)

func on_defeated():
	if bar:
		bar.value = 0
	if not root:
		return
	var tween = create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(root, "modulate:a", 0.0, 0.8)
	tween.tween_callback(hide_bar)
