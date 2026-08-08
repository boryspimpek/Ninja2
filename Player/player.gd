extends CharacterBody3D

@export var move_speed: float = 5.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 10.0
@export var attack_buffer_time: float = 0.3


@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_player: AnimationPlayer = $AnimationPlayer


var top_playback: AnimationNodeStateMachinePlayback
var combat_playback: AnimationNodeStateMachinePlayback


# Czy aktualnie jesteśmy w systemie ataku.
var in_combat: bool = false


# Input buffer.
#
# false = nie kliknięto następnego ataku
# true  = kliknięto i po zakończeniu aktualnej animacji
#         należy przejść do kolejnego ataku.
var queued_attack: bool = false


func _ready() -> void:
	top_playback = anim_tree.get("parameters/playback")
	combat_playback = anim_tree.get("parameters/Combat/playback")

	anim_tree.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_attack_input()

	move_and_slide()


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


	# Kolejne kliknięcie jest akceptowane
	# tylko w ostatnich 0.3 sekundy animacji.
	if _is_attack_buffer_window_open():
		queued_attack = true


# ============================================================
# START COMBAT
# ============================================================

func _start_combat() -> void:

	in_combat = true
	queued_attack = false

	# Natychmiast zatrzymujemy ruch.
	velocity.x = 0.0
	velocity.z = 0.0

	top_playback.travel("Combat")


func _is_attack_buffer_window_open() -> bool:
	var current_position := combat_playback.get_current_play_position()
	var animation_length := combat_playback.get_current_length()

	var remaining_time := animation_length - current_position

	return remaining_time <= attack_buffer_time
	

# ============================================================
# ANIMATION FINISHED
# ============================================================

func _on_animation_finished(anim_name: StringName) -> void:

	var animation := String(anim_name)

	print(
		"DEBUG anim_finished: '",
		animation,
		"' | current_node: '",
		combat_playback.get_current_node(),
		"' | queued: ",
		queued_attack
	)


	match animation:

		# --------------------------------------------------------
		# ATTACK 1 STRIKE
		# --------------------------------------------------------

		"Attacks/attack1_strike":

			if queued_attack:

				# Kliknięto podczas Attack1.
				#
				# Attack1 -> Attack2
				combat_playback.travel(
					"Attacks_attack2_strike"
				)

			else:

				# Nie kliknięto.
				#
				# Attack1 -> Recovery
				combat_playback.travel(
					"Attacks_attack1_recovery"
				)


			# Klik został właśnie wykorzystany.
			queued_attack = false


		# --------------------------------------------------------
		# ATTACK 1 RECOVERY
		# --------------------------------------------------------

		"Attacks/attack1_recovery":

			if queued_attack:

				# Kliknięto podczas Recovery.
				#
				# Recovery -> Attack1
				combat_playback.travel(
					"Attacks_attack1_strike"
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

	top_playback.travel("Locomotion")
