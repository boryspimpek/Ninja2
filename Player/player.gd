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

var top_playback: AnimationNodeStateMachinePlayback
var combat_playback: AnimationNodeStateMachinePlayback
var is_jumping: bool = false
var in_combat: bool = false
var combo_window_open: bool = false
var cancel_window_open: bool = false
var combo_window_attack: String = ""
var cancel_window_attack: String = ""
var queued_attack: bool = false
var queued_attack_direction: Vector2 = Vector2.ZERO
var target_attack_rotation: float = 0.0
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
func _ready() -> void:

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
		"parameters/Locomotion/blend_position",
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

	combo_window_open = false
	cancel_window_open = false

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

	print("========== ATTACK INPUT ==========")
	print("in_combat: ", in_combat)
	print("combo_window_open: ", combo_window_open)
	print("cancel_window_open: ", cancel_window_open)
	print("queued_attack: ", queued_attack)

	if in_combat:
		print("CURRENT COMBAT NODE: ", combat_playback.get_current_node())

	if not in_combat:

		print("STARTING COMBAT")

		_start_combat()

		return

	if not combo_window_open:

		print("IGNORED - COMBO WINDOW CLOSED")

		return

	queued_attack = true

	queued_attack_direction = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	print("QUEUED ATTACK")
	print("DIRECTION: ", queued_attack_direction)

	if cancel_window_open:

		print("CANCEL WINDOW ACTIVE - TRANSITION NOW")

		_transition_to_next_attack()

func _start_combat() -> void:

	in_combat = true

	queued_attack = false
	queued_attack_direction = Vector2.ZERO

	target_attack_rotation = rotation.y

	combo_window_open = false
	cancel_window_open = false

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

	combo_window_open = true

	combo_window_attack = String(
		combat_playback.get_current_node()
	)

	print(
		">>> COMBO WINDOW OPEN | ATTACK: ",
		combo_window_attack
	)

func _close_combo_window() -> void:

	var current_attack := String(
		combat_playback.get_current_node()
	)

	if current_attack != combo_window_attack:

		print(
			"!!! IGNORING OLD COMBO CLOSE | CURRENT: ",
			current_attack,
			" | WINDOW OWNER: ",
			combo_window_attack
		)

		return


	combo_window_open = false
	combo_window_attack = ""

	print(
		"<<< COMBO WINDOW CLOSE | ATTACK: ",
		current_attack
	)

func _open_cancel_window() -> void:

	if not combo_window_open:
		return


	cancel_window_open = true

	cancel_window_attack = String(
		combat_playback.get_current_node()
	)

	print(
		">>> CANCEL WINDOW OPEN | ATTACK: ",
		cancel_window_attack,
		" | QUEUED: ",
		queued_attack
	)

	if queued_attack:

		_transition_to_next_attack()

func _close_cancel_window() -> void:

	var current_attack := String(
		combat_playback.get_current_node()
	)

	if current_attack != cancel_window_attack:

		print(
			"!!! IGNORING OLD CANCEL CLOSE | CURRENT: ",
			current_attack,
			" | WINDOW OWNER: ",
			cancel_window_attack
		)

		return

	cancel_window_open = false
	cancel_window_attack = ""

	print(
		"<<< CANCEL WINDOW CLOSE | ATTACK: ",
		current_attack
	)

func _get_next_attack(current_attack: String) -> String:

	print("GET NEXT ATTACK FOR: [", current_attack, "]")

	match current_attack:

		"Attacks_attack1":
			print("MATCH: ATTACK 1")
			return "Attacks_attack2_strike"

		"Attacks_attack2_strike":
			print("MATCH: ATTACK 2")
			return "Attacks_attack3"

		"Attacks_attack3":
			print("MATCH: ATTACK 3")
			return "Attacks_attack4"

		"Attacks_attack4":
			print("MATCH: ATTACK 4")
			return "Attacks_attack1"

		_:
			print("NO MATCH!")

	return ""

func _transition_to_next_attack() -> void:

	var current_attack := String(
		combat_playback.get_current_node()
	)

	var next_attack := _get_next_attack(
		current_attack
	)

	print("CURRENT ATTACK: ", current_attack)
	print("NEXT ATTACK: ", next_attack)


	if next_attack.is_empty():

		print(
			"!!! NO NEXT ATTACK MAPPING FOR: ",
			current_attack
		)

		return

	_rotate_to_attack_direction()

	queued_attack = false
	queued_attack_direction = Vector2.ZERO

	combo_window_open = false
	cancel_window_open = false

	combo_window_attack = ""
	cancel_window_attack = ""

	print(
		">>> TRAVEL TO: ",
		next_attack
	)


	combat_playback.travel(
		next_attack
	)

func _animation_to_combat_node(anim_name: String) -> String:

	match anim_name:

		"Attacks/attack1":
			return "Attacks_attack1"

		"Attacks/attack2_strike":
			return "Attacks_attack2_strike"

		"Attacks/attack3":
			return "Attacks_attack3"

		"Attacks/attack4":
			return "Attacks_attack4"

	return ""

	
func _on_animation_finished(anim_name: StringName) -> void:

	var finished_animation := String(anim_name)

	var finished_node := _animation_to_combat_node(
		finished_animation
	)

	var current_node := String(
		combat_playback.get_current_node()
	)

	print(
		"ANIMATION FINISHED: ",
		finished_animation,
		" | FINISHED NODE: ",
		finished_node,
		" | CURRENT NODE: ",
		current_node
	)

	if finished_node.is_empty():
		return

	if finished_node != current_node:

		print(
			"!!! IGNORING FINISHED OLD ATTACK: ",
			finished_animation
		)

		return

	combo_window_open = false
	cancel_window_open = false

	combo_window_attack = ""
	cancel_window_attack = ""


	if not in_combat:
		return

	_exit_combat()

func _exit_combat() -> void:

	in_combat = false

	queued_attack = false
	queued_attack_direction = Vector2.ZERO

	combo_window_open = false
	cancel_window_open = false


	top_playback.travel(
		"Locomotion"
	)
