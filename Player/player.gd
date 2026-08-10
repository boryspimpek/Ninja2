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


# Czy aktualnie jesteśmy w systemie ataku.
var in_combat: bool = false

# Czy combo window aktualnie otwarte (sterowane przez Call Method Track
# w AnimationPlayer, klucze _open_combo_window / _close_combo_window).
var combo_window_open: bool = false

# Input buffer.
#
# false = nie kliknięto następnego ataku
# true  = kliknięto podczas otwartego combo window i po zakończeniu
#         aktualnej animacji należy przejść do kolejnego ataku.
var queued_attack: bool = false
var queued_attack_direction: Vector2 = Vector2.ZERO
var target_attack_rotation: float = 0.0

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	top_playback = anim_tree.get("parameters/playback")
	combat_playback = anim_tree.get("parameters/Combat/StateMachine/playback")

	anim_tree.animation_finished.connect(_on_animation_finished)


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


# ============================================================
# MOVEMENT
# ============================================================

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


	# Podczas ataku postać jest całkowicie "committed"
	# do animacji i nie może się poruszać.
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


	# Obracamy postać tylko podczas normalnego poruszania.
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


	# Aktualizacja BlendSpace locomotion.
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
	var is_moving := speed_ratio > 0.1 and is_on_floor()

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

		top_playback.travel("Locomotion")


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

	# Dash przerywa combat "na twardo" - musimy więc też
	# jawnie zresetować stan combo window, bo animacja ataku
	# nie zdąży odpalić własnego klucza _close_combo_window().
	in_combat = false
	queued_attack = false
	queued_attack_direction = Vector2.ZERO
	combo_window_open = false

	rotation.y = atan2(
		dash_direction.x,
		dash_direction.z
	)

	is_dashing = true
	dash_timer = dash_duration

	top_playback.travel("Moves_dash")


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

	top_playback.travel("Moves_jump")


func _check_jump_landing() -> void:
	if is_jumping and is_on_floor() and velocity.y <= 0.0:
		is_jumping = false
		top_playback.travel("Locomotion")


# ============================================================
# ATTACK INPUT
# ============================================================

func _handle_attack_input() -> void:

	if not Input.is_action_just_pressed("attack"):
		return

	# Pierwsze kliknięcie rozpoczyna combat.
	if not in_combat:
		_start_combat()
		return


	# Kolejne kliknięcie jest akceptowane tylko wtedy, gdy combo
	# window aktualnie odtwarzanej animacji jest otwarte (sterowane
	# przez Call Method Track w AnimationPlayer).
	if combo_window_open:
		queued_attack = true
		queued_attack_direction = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back"
		)

		print("QUEUED ATTACK DIRECTION: ", queued_attack_direction)


# ============================================================
# START COMBAT
# ============================================================

func _start_combat() -> void:

	in_combat = true
	queued_attack = false

	queued_attack_direction = Vector2.ZERO
	target_attack_rotation = rotation.y
	combo_window_open = false

	# Natychmiast zatrzymujemy ruch.
	velocity.x = 0.0
	velocity.z = 0.0

	top_playback.travel("Combat")


func _rotate_to_attack_direction() -> void:
	if queued_attack_direction.length() < 0.1:
		return

	target_attack_rotation = atan2(
		queued_attack_direction.x,
		queued_attack_direction.y
	)


# ============================================================
# COMBO WINDOW - wywoływane z Call Method Track w AnimationPlayer,
# osobno dla każdej animacji ataku (attack1_strike, attack1_recovery,
# attack2_strike, attack3, attack4).
# ============================================================

func _open_combo_window() -> void:
	combo_window_open = true


func _close_combo_window() -> void:
	combo_window_open = false


# ============================================================
# ANIMATION FINISHED
# ============================================================

func _on_animation_finished(anim_name: StringName) -> void:

	var animation := String(anim_name)

	# Niezależnie od tego, co się stanie dalej, animacja się skończyła,
	# więc jej combo window na pewno powinno być już zamknięte.
	combo_window_open = false

	match animation:

		# --------------------------------------------------------
		# ATTACK 1 STRIKE
		# --------------------------------------------------------

		"Attacks/attack1":

			if queued_attack:

				# Kliknięto podczas Attack1.
				#
				# Attack1 -> Attack2

				_rotate_to_attack_direction()

				combat_playback.travel(
					"Attacks_attack2_strike"
				)
				
				queued_attack = false

			else:

				# Nic nie kliknięto.
				#
				# Recovery -> Idle
				_exit_combat()


		# --------------------------------------------------------
		# ATTACK 2 STRIKE
		# --------------------------------------------------------

		"Attacks/attack2_strike":

			if queued_attack:

				# Kliknięto podczas Attack2.
				#
				# Attack2 -> Attack3

				_rotate_to_attack_direction()

				combat_playback.travel(
					"Attacks_attack3"
				)

				queued_attack = false

			else:

				# Nic nie kliknięto.
				#
				# Attack2 -> Idle
				_exit_combat()


		# --------------------------------------------------------
		# ATTACK 3 STRIKE
		# --------------------------------------------------------

		"Attacks/attack3":

			if queued_attack:

				# Kliknięto podczas Attack3.
				#
				# Attack3 -> Attack4

				_rotate_to_attack_direction()

				combat_playback.travel(
					"Attacks_attack4"
				)

				queued_attack = false

			else:

				# Nic nie kliknięto.
				#
				# Attack3 -> Idle
				_exit_combat()


		# --------------------------------------------------------
		# ATTACK 4 STRIKE
		# --------------------------------------------------------

		"Attacks/attack4":

			if queued_attack:

				# Kliknięto podczas Attack4.
				#
				# Attack4 -> Attack1

				_rotate_to_attack_direction()

				combat_playback.travel(
					"Attacks_attack1_strike"
				)

				queued_attack = false

			else:

				# Nic nie kliknięto.
				#
				# Attack4 -> Idle
				_exit_combat()


# ============================================================
# EXIT COMBAT
# ============================================================

func _exit_combat() -> void:

	in_combat = false
	queued_attack = false
	queued_attack_direction = Vector2.ZERO
	combo_window_open = false

	top_playback.travel("Locomotion")
