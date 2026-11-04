// Nightshoal-style top-down water + procedural boat wake. Godot 4 CanvasItem shader.
// Put it on a Sprite2D that covers the camera view (see water_surface.gd).
// Output goes through Godot's normal 2D pipeline, so CanvasModulate / Light2D day-night works.
shader_type canvas_item;

// ---------------- palette ----------------
uniform vec4 shallow_color : source_color = vec4(0.12, 0.78, 0.82, 1.0);
uniform vec4 mid_color : source_color = vec4(0.02, 0.40, 0.62, 1.0);
uniform vec4 deep_color : source_color = vec4(0.01, 0.08, 0.26, 1.0);
uniform vec4 foam_color : source_color = vec4(0.94, 0.99, 1.0, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);

// ---------------- water ----------------
uniform float time_scale = 1.0;
uniform float depth_frequency = 0.0007;            // lower = bigger shallows/deeps
uniform float depth_bias : hint_range(-0.5, 0.5) = 0.0;   // per-biome: Aegean shallower, fjord deeper
uniform float depth_contrast = 1.6;
uniform float wave_frequency = 0.018;
uniform float wave_speed = 0.35;
uniform float normal_strength = 40.0;
uniform float shininess = 70.0;
uniform vec2 sun_direction = vec2(0.6, -0.5);
uniform float sun_elevation : hint_range(0.05, 1.0) = 0.55;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;     // driven by DayNightCycle
uniform float caustic_strength : hint_range(0.0, 1.5) = 0.55;
uniform float caustic_scale = 0.012;
uniform float storm : hint_range(0.0, 1.0) = 0.0;         // sea roughness, driven by WeatherManager
uniform vec2 wind_dir = vec2(1.0, 0.0);                   // the way the wind blows, waves travel with it

// ---------------- boat and wake ----------------
uniform vec2 boat_pos = vec2(0.0);
uniform vec2 boat_dir = vec2(1.0, 0.0);
uniform float boat_speed01 : hint_range(0.0, 1.0) = 0.0;
uniform int trail_count = 0;
uniform vec2 trail_points[32];     // newest first, index 0 = live boat position
uniform float trail_ages[32];      // seconds
uniform float trail_power[32];     // 0..1 boat speed when the point was recorded
uniform float trail_lifetime = 6.0;
uniform float wake_width_start = 5.0;
uniform float wake_width_end = 26.0;
uniform float arm_tan = 0.3535;    // tan(19.47 deg), the Kelvin wake half-angle
uniform float arm_length = 260.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// ---------------- noise ----------------
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
			   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}

// ---------------- caustics: two warped ridged-noise layers, bright where they cross ----------------
float ridge(vec2 p) {
	return 1.0 - abs(vnoise(p) * 2.0 - 1.0);
}

float caustics(vec2 p, float t) {
	vec2 w = vec2(vnoise(p * 0.7 + t * 0.35), vnoise(p.yx * 0.7 - t * 0.30)) * 2.0 - 1.0;
	float a = ridge(p + w * 0.9 + vec2(t * 0.25, 0.0));
	float b = ridge(p * 1.6 - w * 0.7 + vec2(0.0, t * 0.20));
	return min(pow(a * b, 3.0) * 2.5, 1.0);
}

// ---------------- wake: analytic V-shaped Kelvin arms (follows the boat heading) ----------------
float wake_ripple(vec2 p, float t) {
	vec2 f = normalize(boat_dir);
	vec2 rel = p - boat_pos;
	float along = -dot(rel, f);              // distance behind the boat
	float across = dot(rel, vec2(-f.y, f.x));
	if (along < 0.0) {
		return 0.0;
	}
	float edge = abs(abs(across) - along * arm_tan);
	float width = 6.0 + along * 0.05;
	float env = exp(-along / arm_length) * (1.0 - smoothstep(0.0, width * 2.0, edge)) * boat_speed01;
	return env * sin(along * 0.22 - t * 6.0);
}

float surface(vec2 p, float t) {
	vec2 q = p * wave_frequency;
	float run = 0.6 + 1.4 * storm;                       // storm waves run faster
	float h = fbm(q - wind_dir * t * run * 1.2) + 0.5 * fbm(q * 2.1 - wind_dir * t * run * 1.9 + vec2(t * 0.1, 0.0));
	return h + wake_ripple(p, t) * 0.6;
}

// ---------------- wake: foam along the recorded path (handles turns), thickens and fades with age ----------------
float trail_foam(vec2 p) {
	float foam = 0.0;
	for (int i = 0; i < 31; i++) {
		if (i >= trail_count - 1) {
			break;
		}
		vec2 a = trail_points[i];
		vec2 b = trail_points[i + 1];
		vec2 pa = p - a;
		vec2 ba = b - a;
		float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
		float d = length(pa - ba * h);
		float age = mix(trail_ages[i], trail_ages[i + 1], h);
		float power = mix(trail_power[i], trail_power[i + 1], h);
		float life = clamp(age / trail_lifetime, 0.0, 1.0);
		float width = mix(wake_width_start, wake_width_end, life) * (0.5 + power);
		float f = (1.0 - smoothstep(0.0, width, d)) * (1.0 - life) * (1.0 - life) * power;
		foam = max(foam, f);
	}
	return foam;
}

void fragment() {
	float t = TIME * time_scale;
	vec2 p = world_pos;

	// depth tint: procedural depth map, shallow turquoise to deep navy
	float depth = clamp(fbm(p * depth_frequency + vec2(31.7, 12.4)) * depth_contrast + depth_bias, 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.0, 0.5, depth));
	col = mix(col, deep_color.rgb, smoothstep(0.35, 1.0, depth));

	// surface normal from finite differences of the height field
	float e = 2.0;
	float h0 = surface(p, t * wave_speed);
	float hx = surface(p + vec2(e, 0.0), t * wave_speed);
	float hy = surface(p + vec2(0.0, e), t * wave_speed);
	float ns = normal_strength * (1.0 + 1.3 * storm);
	vec3 n = normalize(vec3((h0 - hx) / e * ns, (h0 - hy) / e * ns, 1.0));

	// sun glints and sky fresnel (fade out at night via daylight)
	vec3 L = normalize(vec3(normalize(sun_direction) * (1.0 - sun_elevation), sun_elevation));
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	float spec = pow(max(dot(n, H), 0.0), shininess);
	col += sun_color.rgb * spec * daylight * 1.6;
	float fres = pow(1.0 - max(n.z, 0.0), 2.0);
	col += vec3(0.50, 0.70, 0.90) * fres * 0.8 * daylight;

	// caustics only on the shallows
	float shallow_mask = 1.0 - smoothstep(0.05, 0.55, depth);
	col += sun_color.rgb * caustics(p * caustic_scale, t * 0.8) * caustic_strength * shallow_mask * daylight;

	// wake: foam trail + crest highlights on the V arms
	float trail = trail_foam(p);
	float breakup = fbm(p * 0.08 + vec2(t * 0.20, -t * 0.15));
	float foam = smoothstep(0.30, 0.65, trail * (0.5 + breakup)) * 0.95;
	col = mix(col, shallow_color.rgb, trail * 0.35);        // turbulent aerated water around the foam
	col = mix(col, foam_color.rgb, foam);
	float crest = max(wake_ripple(p, t), 0.0);
	col = mix(col, foam_color.rgb, smoothstep(0.55, 0.95, crest) * 0.5);

	// storm: whitecaps on the crests, greyer and darker water
	float caps = smoothstep(1.05 - 0.25 * storm, 1.30 - 0.25 * storm, h0) * smoothstep(0.25, 0.6, storm);
	col = mix(col, foam_color.rgb, caps * 0.8);
	col = mix(col, vec3(dot(col, vec3(0.33))) * 0.55, storm * 0.5);

	COLOR = vec4(col, 1.0);
}
