shader_type particles;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float scale_initial = 0.05; // initial scale
uniform float scale_add = 0.75; // scale amount added (or substracted)
uniform vec3 grav = vec3(0.0, -9.8, 0.0);
uniform float initial_velocity = 5.0;
uniform float vel_damping = 1.0;
uniform float spread = 0.1; // XY random rotation

// function taken from default particle process shader
uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

// function taken from default particle process shader
float rand_from_seed(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

void start() {	
	uint base_number = NUMBER;
	uint alt_seed = hash(base_number + uint(1) + RANDOM_SEED);

	if (RESTART_ROT_SCALE) {
		TRANSFORM[0].xyz = vec3(1.0, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, 1.0, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, 1.0);

		// random angle in Z axis
		float angle_z = rand_from_seed(alt_seed) * TAU;

		// random angle in XY axis
		float angle_x = rand_from_seed(alt_seed) * spread;
		float angle_y = rand_from_seed(alt_seed) * spread;

		// compute x rotation matrix
		float cx = cos(angle_x);
		float sx = sin(angle_x);

		mat3 rot_x = mat3(
			vec3(1.0, 0.0, 0.0),
			vec3(0.0, cx, -sx),
			vec3(0.0, sx,  cx)
		);

		// compute Y rotation matrix
		float cy = cos(angle_y);
		float sy = sin(angle_y);

		mat3 rot_y = mat3(
			vec3( cy, 0.0, sy),
			vec3(0.0, 1.0, 0.0),
			vec3(-sy, 0.0, cy)
		);

		// compute z rotation matrix
		float cz = cos(angle_z);
		float sz = sin(angle_z);

		mat3 rot_z = mat3(
			vec3(cz, -sz, 0.0),
			vec3(sz,  cz, 0.0),
			vec3(0.0, 0.0, 1.0)
		);

		// combine rotations
		mat3 rot = rot_y * rot_x * rot_z;

		// apply rotations
		TRANSFORM[0].xyz = rot * TRANSFORM[0].xyz;
		TRANSFORM[1].xyz = rot * TRANSFORM[1].xyz;
		TRANSFORM[2].xyz = rot * TRANSFORM[2].xyz;
		
		// save some data
		USERDATA1 = vec4(0.0);
		USERDATA1.x = 0.0; // particle time
		USERDATA1.y = angle_z; // desired z rotation		
	}

	// reset position (and appy emissor transform)
	if (RESTART_POSITION) {
		TRANSFORM[3].xyz = vec3(0.0);
		TRANSFORM = EMISSION_TRANSFORM * TRANSFORM; // apply emitter (node) transform 	
	}
	
	// reset color
	if (RESTART_COLOR) {
		COLOR = color;	
	}	
	
	// reset velocity (forward is -Z in Godot)
	if (RESTART_VELOCITY) {
		VELOCITY = normalize(-TRANSFORM[2].xyz) * initial_velocity;	
	}	
}

void process() {
	// increase particle time
	USERDATA1.x += DELTA;
	
	// compute particle time (value from 0 to 1)
	float particle_time = clamp(USERDATA1.x / LIFETIME, 0.0, 1.0);
		
	// apply gravity (and damping)
	VELOCITY += grav * DELTA;
	VELOCITY *= 1.0 - vel_damping * DELTA;
	
	// build rotation matrix along velocity ("forward")
	vec3 dir = normalize(-VELOCITY);

	vec3 up = vec3(0.0, 1.0, 0.0);

	vec3 right = normalize(cross(up, dir));
	vec3 real_up = cross(dir, right);
	
	mat3 desired_rotation = mat3(
		right,
		real_up,
		dir
	);
	
	// rebuild z rotation matrix
	float cz = cos(USERDATA1.y);
	float sz = sin(USERDATA1.y);

	mat3 rot_z = mat3(
		vec3(cz, -sz, 0.0),
		vec3(sz,  cz, 0.0),
		vec3(0.0, 0.0, 1.0)
	);	
	
	// build scale matrix
	float scl = scale_initial + (particle_time * scale_add);
	mat3 desired_scale = mat3(
		vec3(scl, 0.0, 0.0),
		vec3(0.0, scl, 0.0),
		vec3(0.0, 0.0, scl)		
	);

	// combine matrices
	mat3 final = desired_scale * desired_rotation * rot_z;
	TRANSFORM[0].xyz = final[0];
	TRANSFORM[1].xyz = final[1];
	TRANSFORM[2].xyz = final[2];	

	// adjust alpha
	COLOR.a = 1.0 - particle_time;
}
