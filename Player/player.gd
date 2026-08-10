extends CharacterBody3D

@export var move_speed: float = 5.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 10.0
@export var dash_speed: float = 20.0
@export var dash_duration: float = 0.15
@export var jump_velocity: float = 8.0
@export var gravity: float = 20.0

@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var footstep_player: AudioStreamPlayer3D = $FootstepSound

# --- Pojedyncze źródło prawdy dla łańcucha ataków ---
# Dodanie nowego ataku = jedna nowa linia tutaj. Kolejność w tablicy = kolejność w combo.
# node = nazwa węzła w Combat/StateMachine, anim = nazwa animacji w AnimationPlayer.
const ATTACK_SEQUENCE := [
	{"node": "Attacks_attack1", "anim": "Attacks/attack1"},
	{"node": "Attacks_attack2_strike", "anim": "Attacks/attack2_strike"},
	{"node": "Attacks_attack3", "anim": "Attacks/attack3"},
	{"node": "Attacks_attack4", "anim": "Attacks/attack4"},
]

# Wyliczane w _ready() z ATTACK_SEQUENCE, żeby nie trzymać dwóch osobnych,
# ręcznie synchronizowanych map.
var _next_attack: Dictionary = {}   # node_name -> next_node_name
var _anim_to_node: Dictionary = {}  # anim_name -> node_name

# --- Combo / cancel window jako jeden mały typ zamiast 4 osobnych zmiennych ---
class AttackWindow:
	var open: bool = false
	var attack: String = ""

	func start(current_attack: String) -> void:
		open = true
		attack = current_attack

	func close_if_current(current_attack: String) -> void:
		if attack == current_attack:
			open = false
			attack = ""

	func reset() -> void:
		open = false
		attack = ""

var combo_window := AttackWindow.new()
var cancel_window := AttackWindow.new()

var top_playback: AnimationNodeStateMachinePlayback
var combat_playback: AnimationNodeStateMachinePlayback
var is_jumping: bool = false
var in_combat: bool = false
var queued_attack: bool = false
var queued_attack_direction: Vector2 = Vector2.ZERO
var target_attack_rotation: float = 0.0
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO


func _ready() -> void:

	for i in ATTACK_SEQUENCE.size():

		var entry: Dictionary = ATTACK_SEQUENCE[i]
		var next_entry: Dictionary = ATTACK_SEQUENCE[(i + 1) % ATTACK_SEQUENCE.size()]

		_next_attack[entry.node] = next_entry.node
		_anim_to_node[entry.anim] = entry.node

	top_playback = anim_tree.get(
		"parameters/playback"
	)

	combat_playback = anim_tree.get(
		"parameters/Combat/StateMachine/playback"
	)

	anim_tree.animation_finished.connect(
		_on_animation_finished
	)

func _physics_process(delta: float) -> void:

	_apply_gravity(delta)

	_handle_dash_input()
	_handle_jump_input()


	if is_dashing:

		_handle_dash(delta)

	else:

		_handle_movement(delta)
		_handle_attack_input()

	if in_combat:

		rotation.y = lerp_angle(
			rotation.y,
			target_attack_rotation,
			rotation_speed * delta
		)


	move_and_slide()

	_check_jump_landing()

func _handle_movement(delta: float) -> void:

	var input_vec := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)


	var move_dir := Vector3(
		input_vec.x,
		0.0,
		input_vec.y
	)

	if in_combat:

		move_dir = Vector3.ZERO

	velocity.x = move_toward(
		velocity.x,
		move_dir.x * move_speed,
		acceleration * delta
	)

	velocity.z = move_toward(
		velocity.z,
		move_dir.z * move_speed,
		acceleration * delta
	)

	if move_dir.length() > 0.1 and not in_combat:

		var target_angle := atan2(
			move_dir.x,
			move_dir.z
		)

		rotation.y = lerp_angle(
			rotation.y,
			target_angle,
			rotation_speed * delta
		)

	var speed_ratio := Vector2(
		velocity.x,
		velocity.z
	).length() / move_speed

	anim_tree.set(
		"parameters/Locomotion/Move/blend_amount",
		speed_ratio
	)

	_update_footstep_audio(speed_ratio)

func _update_footstep_audio(speed_ratio: float) -> void:

	var is_moving := (
		speed_ratio > 0.1
		and is_on_floor()
	)


	if is_moving and not footstep_player.playing:

		footstep_player.play()

	elif not is_moving and footstep_player.playing:

		footstep_player.stop()

func _handle_dash_input() -> void:

	if not Input.is_action_just_pressed("dash"):
		return


	if is_dashing:
		return


	_start_dash()

func _handle_dash(delta: float) -> void:

	dash_timer -= delta

	velocity = dash_direction * dash_speed


	if dash_timer <= 0.0:

		is_dashing = false

		velocity.x = 0.0
		velocity.z = 0.0

		top_playback.travel(
			"Locomotion"
		)

func _start_dash() -> void:

	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	if input_dir.length() > 0.1:

		dash_direction = Vector3(
			input_dir.x,
			0.0,
			input_dir.y
		).normalized()

	else:

		dash_direction = Vector3(
			sin(rotation.y),
			0.0,
			cos(rotation.y)
		).normalized()

	in_combat = false

	queued_attack = false
	queued_attack_direction = Vector2.ZERO

	combo_window.reset()
	cancel_window.reset()

	rotation.y = atan2(
		dash_direction.x,
		dash_direction.z
	)

	is_dashing = true
	dash_timer = dash_duration

	top_playback.travel(
		"Moves_dash"
	)

func _apply_gravity(delta: float) -> void:

	if not is_on_floor():

		velocity.y -= gravity * delta

	elif velocity.y < 0.0:

		velocity.y = 0.0

func _handle_jump_input() -> void:

	if not Input.is_action_just_pressed("jump"):
		return


	if not is_on_floor():
		return


	if is_dashing or in_combat or is_jumping:
		return


	_start_jump()

func _start_jump() -> void:

	is_jumping = true

	velocity.y = jump_velocity


	top_playback.travel(
		"Moves_jump"
	)

func _check_jump_landing() -> void:

	if (
		is_jumping
		and is_on_floor()
		and velocity.y <= 0.0
	):

		is_jumping = false

		top_playback.travel(
			"Locomotion"
		)

func _handle_attack_input() -> void:

	if not Input.is_action_just_pressed("attack"):
		return

	if not in_combat:

		_start_combat()

		return

	if not combo_window.open:

		return

	queued_attack = true

	queued_attack_direction = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	if cancel_window.open:

		_transition_to_next_attack()

func _start_combat() -> void:

	in_combat = true

	queued_attack = false
	queued_attack_direction = Vector2.ZERO

	target_attack_rotation = rotation.y

	combo_window.reset()
	cancel_window.reset()

	velocity.x = 0.0
	velocity.z = 0.0


	top_playback.travel(
		"Combat"
	)

func _rotate_to_attack_direction() -> void:

	if queued_attack_direction.length() < 0.1:
		return


	target_attack_rotation = atan2(
		queued_attack_direction.x,
		queued_attack_direction.y
	)


func _open_combo_window() -> void:

	combo_window.start(
		String(combat_playback.get_current_node())
	)

func _close_combo_window() -> void:

	combo_window.close_if_current(
		String(combat_playback.get_current_node())
	)

func _open_cancel_window() -> void:

	if not combo_window.open:
		return


	cancel_window.start(
		String(combat_playback.get_current_node())
	)

	if queued_attack:

		_transition_to_next_attack()

func _close_cancel_window() -> void:

	cancel_window.close_if_current(
		String(combat_playback.get_current_node())
	)

func _transition_to_next_attack() -> void:

	var current_attack := String(
		combat_playback.get_current_node()
	)

	var next_attack: String = _next_attack.get(
		current_attack,
		""
	)

	if next_attack.is_empty():

		return

	_rotate_to_attack_direction()

	queued_attack = false
	queued_attack_direction = Vector2.ZERO

	combo_window.reset()
	cancel_window.reset()

	combat_playback.travel(
		next_attack
	)

func _on_animation_finished(anim_name: StringName) -> void:

	var finished_node: String = _anim_to_node.get(
		String(anim_name),
		""
	)

	var current_node := String(
		combat_playback.get_current_node()
	)

	if finished_node.is_empty():
		return

	if finished_node != current_node:

		return

	combo_window.reset()
	cancel_window.reset()


	if not in_combat:
		return

	_exit_combat()

func _exit_combat() -> void:

	in_combat = false

	queued_attack = false
	queued_attack_direction = Vector2.ZERO

	combo_window.reset()
	cancel_window.reset()


	top_playback.travel(
		"Locomotion"
	)
