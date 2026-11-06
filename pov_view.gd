## First-person view of the water, from the angler's eyes, from the cast until the fish is landed.
## The rod is held in front of you (bottom right), the line runs out to the float, and the fish stays
## hidden: you see the float, the line, the rod bending, rings and spray, and the fish only when it
## jumps, thrashes or rolls at the surface. The catch is lifted into view at the end.
##
## Projection: a pinhole camera at eye height `eye_h` (m) above the water. A point `x` m to the right,
## `z` m ahead and `h` m above the water is drawn at
##     screen = (CX + F * x / z,  HY + F * (eye_h - h) / z)
## so the horizon sits at HY and everything shrinks with distance.
##
## Motion follows Nature of Code: the rod tip is a damped spring (Hooke) pulled by the line, the
## float is a spring around its rest depth (set by ShoreFishing), jumps are projectiles under gravity,
## spray and drips are particles, gulls are steering agents (wander + contain), waves are sums of
## oscillators, the far coast and clouds come from Perlin noise.
class_name PovView
extends FightView

const CX := 640.0
const HY := 300.0                 ## horizon height on screen
const F := 900.0                  ## focal length in px
const ROD_BASE := Vector2(1120.0, 735.0)   ## butt of the rod, under your forearm
const ROD_REST := Vector2(690.0, 175.0)    ## tip when nothing pulls on it
const REST_PITCH := 110.0                  ## px the view looks down at rest, so the near water shows
const PITCH_MAX := 430.0
## Distance from your eyes to where the water starts (m), by spot kind. The fish cannot come closer.
const EDGE_M := {"rocky": 5.0, "beach": 6.0, "harbor": 3.0, "bridge": 4.0}

## Sound cues for the shore scene to play: exit, drips, splash, splash_big.
signal sfx(kind: String, volume: float)
const G := 9.8
const WAVE_ROWS := 12

## Set by ShoreFishing every frame.
var eye_h := 3.0
var time_of_day := 0.3
var wind_x := 0.0                 ## px/s, drifts clouds and gulls
var wave_amp := 1.0               ## 1 calm, up to 2 windy
var reeling := false
var tension := 0.0                ## line tension / breaking force, 0..1+
var kind := "rocky"               ## spot kind: rocky, beach, harbor, bridge
var on_pier := false

## What the line ends on. phase: "off", "fly", "float", "fight".
var phase := "off"
var target_x := 0.0               ## m right of the aim line
var target_z := 20.0              ## m ahead
var target_h := 0.0               ## m above the water (flying bait)
var float_dip := 0.0              ## 0 floating, 1 pulled under
var lure := false                 ## a lure has no float: only the line entering the water shows

var _open := false
var _pitch := REST_PITCH          ## camera looks down by this many px (tilts as the fish comes close)
var _fish_id := ""
var _flex_phase := 0.0            ## tail-beat phase of a jumping or lifted fish
var _tired_t := 3.0
var _prev_x := 0.0
var _lat_v := 0.0                 ## m/s sideways speed of the fish, for its wake on the surface
## The sky and the far coast change slowly: they live on their own layers and are redrawn only when
## the light has changed, and the camera tilt just moves them. Clouds and gulls move every frame.
var _sky_layer: Control
var _mid_layer: Control
var _coast_layer: Control
var _bg_time := -1.0
var _bg_light := -1.0
var _tip := ROD_REST
var _tip_v := Vector2.ZERO
var _reel_angle := 0.0
var _ripples: Array[Dictionary] = []      ## {x, z, age, size}
var _spray: Array[Noc.Particle] = []       ## screen-space particles
var _gulls: Array = []
var _clouds: Array[Dictionary] = []
var _stars: PackedVector2Array = PackedVector2Array()
var _houses: Array[Dictionary] = []
var _boats: Array[Dictionary] = []
var _neighbours: Array[Dictionary] = []
var _glints: Array[Vector3] = []
var _coast_far := PackedVector2Array()
var _coast_near := PackedVector2Array()
var _ring_t := 0.0
var _prev_dip := 0.0
## Surfacing event in world metres: {kind, t, x, z, h, vh, vx}
var _jump: Dictionary = {}


func _ready() -> void:
	super._ready()
	_sky_layer = _make_layer(_draw_sky_layer)
	_mid_layer = _make_layer(_draw_mid_layer)
	_coast_layer = _make_layer(_draw_coast_layer)
	move_child(_sky_layer, 0)
	move_child(_mid_layer, 1)
	move_child(_coast_layer, 2)
	var coast_noise := FastNoiseLite.new()
	coast_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	coast_noise.seed = 11
	coast_noise.frequency = 0.004
	# Far coast: hills on both sides of the bay, open sea in the middle.
	_coast_far.append(Vector2(0.0, HY + 1.0))
	_coast_near.append(Vector2(0.0, HY + 1.0))
	var x := 0.0
	while x <= W:
		var side := clampf(absf(x - CX) / 520.0, 0.0, 1.0)
		var rise := smoothstep(0.35, 1.0, side)
		_coast_far.append(Vector2(x, HY - (14.0 + 40.0 * (0.5 + 0.5 * coast_noise.get_noise_1d(x))) * (0.25 + rise)))
		_coast_near.append(Vector2(x, HY - (8.0 + 50.0 * (0.5 + 0.5 * coast_noise.get_noise_1d(x + 900.0))) * rise))
		x += 20.0
	_coast_far.append(Vector2(W, HY + 1.0))
	_coast_near.append(Vector2(W, HY + 1.0))
	# A small town on the far shore: white and ochre houses with terracotta roofs, one mosque.
	for i in 46:
		var hx := _rng.randf_range(20.0, 470.0) if i % 2 == 0 else _rng.randf_range(830.0, 1260.0)
		_houses.append({"x": hx, "w": _rng.randf_range(5.0, 11.0), "h": _rng.randf_range(4.0, 9.0),
			"col": [Color(0.93, 0.91, 0.86), Color(0.90, 0.80, 0.62), Color(0.86, 0.86, 0.84)][i % 3],
			"lit": _rng.randf() < 0.6, "phase": _rng.randf() * TAU})
	for i in 70:
		_stars.append(Vector2(_rng.randf_range(0.0, W), _rng.randf_range(0.0, HY - 40.0)))
	for i in 6:
		var puffs: Array[Vector3] = []
		for j in _rng.randi_range(3, 5):
			puffs.append(Vector3(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-12.0, 10.0), _rng.randf_range(18.0, 34.0)))
		_clouds.append({"pos": Vector2(_rng.randf_range(0.0, W), _rng.randf_range(50.0, 200.0)), "puffs": puffs,
			"speed": _rng.randf_range(4.0, 10.0)})
	for i in 7:
		var gl := Noc.Vehicle.new(Vector2(_rng.randf_range(100.0, 1180.0), _rng.randf_range(60.0, 220.0)), 60.0, 40.0)
		gl.vel = Vector2(_rng.randf_range(-30.0, 30.0), 0.0)
		gl.data = {"phase": _rng.randf() * TAU, "size": _rng.randf_range(0.7, 1.2)}
		_gulls.append(gl)
	# Boats far out: x in m (lateral), z in m (distance), speed in m/s.
	_boats.append({"x": -260.0, "z": 900.0, "v": 4.0, "type": "ferry"})
	_boats.append({"x": 120.0, "z": 420.0, "v": -1.6, "type": "fishing"})
	_boats.append({"x": -60.0, "z": 650.0, "v": 2.2, "type": "sail"})
	for i in 36:
		_glints.append(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(15.0, 400.0), _rng.randf() * TAU))
	# Other anglers along the rail or rocks, to the left: their rods nod on oscillators.
	for i in 3:
		_neighbours.append({"base": Vector2(70.0 + float(i) * 120.0, 735.0 - float(i) * 12.0),
			"tip": Vector2(240.0 + float(i) * 70.0, 330.0 + float(i) * 25.0), "phase": _rng.randf() * TAU,
			"bend": 0.0, "bend_t": _rng.randf_range(8.0, 30.0)})


# ---------------------------------------------------------------- API used by ShoreFishing
## The cast is released: the view opens and the rod whips forward from behind the shoulder.
func begin_cast() -> void:
	_open = true
	_active = true
	_canvas.visible = true
	_catch_t = 0.0
	_jump = {}
	_surf = {}
	_ripples.clear()
	_spray.clear()
	phase = "fly"
	_pitch = REST_PITCH
	_tip = Vector2(980.0, 20.0)
	_tip_v = Vector2(-1700.0, 1000.0)


func is_open() -> bool:
	return _open or _catch_t > 0.0


## Hooked fish: keep the view, load the fish look (sprite, length) for jumps and the catch.
func begin(fish_id: String, weight_kg: float, cast_dist_m: float) -> void:
	super.begin(fish_id, weight_kg, cast_dist_m)
	_fish_id = fish_id
	_tired_t = 3.0
	_prev_x = target_x
	_open = true
	phase = "fight"
	_jump = {}
	_add_ripple(target_x, target_z, 1.6)
	_spray_at(_proj(target_x, target_z, 0.0), 14, 1.0)


func end() -> void:
	super.end()
	_open = false
	phase = "off"
	_jump = {}


## Real length in metres for a fish of this weight (roughly a seabass shape: 1 kg is about 45 cm).
func _fish_len_m() -> float:
	return clampf(0.45 * pow(maxf((_fish_len - 60.0) / 45.0, 0.1), 0.66), 0.08, 2.5)


## The fish shows itself where the line enters the water.
func surface(kind_name: String) -> void:
	if _creature != "" or not _jump.is_empty() or phase != "fight":
		return
	var big := clampf(_fish_len_m() / 1.2, 0.0, 1.0)
	_jump = {"kind": kind_name, "t": 0.0, "x": target_x, "z": target_z, "h": 0.0,
		"vh": _rng.randf_range(3.2, 4.6) * (1.0 - 0.4 * big), "vx": _rng.randf_range(-1.5, 1.5)}
	_spray_at(_proj(target_x, target_z, 0.0), 22, 1.4)
	_add_ripple(target_x, target_z, 1.4)
	var vol := _near_volume(target_z)
	if kind_name == "jump":
		sfx.emit("exit", vol)
		sfx.emit("drips", vol * 0.6)
	else:
		sfx.emit("splash", vol * 0.8)


## Louder when the fish is close.
func _near_volume(z: float) -> float:
	return clampf(1.3 - z / 45.0, 0.25, 1.0)


## Nearest distance (m) where the line can meet the water: the water's edge, or the closest point
## the view can still show when looking down from a pier or bridge.
func _z_min() -> float:
	var edge: float = EDGE_M.get(kind, 4.0)
	if on_pier:
		edge = 2.0
	var view_min := F * eye_h / (PITCH_MAX + 560.0 - HY)
	return maxf(edge + 0.4, view_min)


func _z_edge() -> float:
	return 2.0 if on_pier else float(EDGE_M.get(kind, 4.0))

# ---------------------------------------------------------------- projection helpers
func _proj(x: float, z: float, h: float) -> Vector2:
	var zz := maxf(z, 0.6)
	return Vector2(CX + F * x / zz, HY - _pitch + F * (eye_h - h) / zz)


func _add_ripple(x: float, z: float, size: float) -> void:
	if _ripples.size() < 24:
		_ripples.append({"x": x, "z": z, "age": 0.0, "size": size})


func _spray_at(p: Vector2, n: int, strength: float) -> void:
	for i in n:
		if _spray.size() > 140:
			return
		_spray.append(Noc.Particle.new(p, Vector2(_rng.randf_range(-120.0, 120.0), -_rng.randf_range(80.0, 320.0)) * strength,
			0.0, 0.0, _rng.randf_range(0.5, 0.9), _rng.randf_range(1.5, 3.5), Color(0.92, 0.97, 1.0, 0.9)))


## Where the line ends on screen right now.
func _line_end() -> Vector2:
	if phase == "fight" and not _jump.is_empty():
		return _proj(float(_jump["x"]), float(_jump["z"]), float(_jump["h"]))
	return _proj(target_x, target_z, target_h)


# ---------------------------------------------------------------- simulation
func _process(delta: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if (_open or _catch_t > 0.0) else 0.0, delta * 4.0)
	if _alpha <= 0.0:
		_canvas.visible = false
		_sky_layer.visible = false
		_mid_layer.visible = false
		_coast_layer.visible = false
		return
	_canvas.visible = true
	_canvas.modulate = Color(1.0, 1.0, 1.0, _alpha)
	for layer in [_sky_layer, _mid_layer, _coast_layer]:
		var l: Control = layer
		l.visible = true
		l.modulate = _canvas.modulate
		l.position.y = -_pitch
	if absf(time_of_day - _bg_time) > 0.002 or absf(daylight - _bg_light) > 0.01:
		_bg_time = time_of_day
		_bg_light = daylight
		_sky_layer.queue_redraw()
		_coast_layer.queue_redraw()
	_mid_layer.queue_redraw()
	_time += delta
	_flex_phase += delta * 22.0
	if phase == "fly":
		target_z = maxf(target_z, 2.0)
	elif phase != "off":
		target_z = maxf(target_z, _z_min())
	# Look down as the line end comes close, so it stays in view; back to rest for the catch.
	var want := REST_PITCH
	if phase == "float" or phase == "fight":
		var raw := HY + F * eye_h / target_z
		want = clampf(raw - 520.0, REST_PITCH, PITCH_MAX)
	_pitch = lerpf(_pitch, want, 1.0 - exp(-2.5 * delta))
	if phase == "fight":
		_lat_v = lerpf(_lat_v, (target_x - _prev_x) / maxf(delta, 0.001), 1.0 - exp(-4.0 * delta))
	_prev_x = target_x
	if _catch_t > 0.0:
		_catch_t -= delta
		_animate_catch(delta)
		if _catch_t <= 0.0:
			_active = false
	_step_rod(delta)
	_step_water_life(delta)
	_step_jump(delta)
	_step_particles(delta)
	_canvas.queue_redraw()


## The rod tip is a damped spring: rest pose, pulled down and toward the line by tension.
func _step_rod(delta: float) -> void:
	var to_line := (_line_end() - ROD_REST).normalized()
	var pull := clampf(tension, 0.0, 1.3)
	if phase == "float":
		pull = maxf(pull, 0.06 + 0.25 * clampf(float_dip, 0.0, 1.3))
	var target := ROD_REST + to_line * 70.0 * pull + Vector2(0.0, 150.0 * pull)
	if fishing != null and phase == "fight" and fishing.head_shake > 0.0:
		# head shakes come up the line as a fast knock on the rod tip
		target += Vector2(sin(_time * 50.0) * 10.0, sin(_time * 47.0) * 14.0) * fishing.head_shake
	if _catch_t > 0.0:
		target = ROD_REST + Vector2(-40.0, 40.0)
	var acc := (target - _tip) * 90.0 - _tip_v * 11.0
	_tip_v += acc * delta
	_tip += _tip_v * delta
	if reeling or _catch_t > 0.0:
		_reel_angle += delta * 14.0


func _step_water_life(delta: float) -> void:
	for r in _ripples:
		r["age"] = float(r["age"]) + delta
	_ripples.assign(_ripples.filter(func(r: Dictionary) -> bool: return float(r["age"]) < 2.2))
	# Float: a ring when it bobs, a big ring when it goes under.
	if phase == "float":
		if float_dip - _prev_dip > 0.15:
			_add_ripple(target_x, target_z, 1.0)
		_ring_t -= delta
		if _ring_t <= 0.0:
			_ring_t = 2.5
			_add_ripple(target_x, target_z, 0.5)
	elif phase == "fight":
		_ring_t -= delta
		if _ring_t <= 0.0:
			_ring_t = 0.35 if fishing != null and fishing._burst_mult > 1.0 else 0.9
			_add_ripple(target_x, target_z, 0.7)
			if fishing != null and fishing._burst_mult > 1.0:
				_spray_at(_proj(target_x, target_z, 0.0), 6, 0.6)
		# A tired fish near the edge comes up and thrashes or rolls, as real fish do before landing.
		if fishing != null and fishing.stamina < 0.4 and target_z < _z_min() + 8.0 and _creature == "":
			_tired_t -= delta
			if _tired_t <= 0.0:
				_tired_t = _rng.randf_range(2.0, 4.0)
				surface("thrash" if _rng.randf() < 0.6 else "roll")
	_prev_dip = float_dip
	for c in _clouds:
		var p: Vector2 = c["pos"]
		p.x += (float(c["speed"]) + wind_x * 0.05) * delta
		if p.x > W + 120.0:
			p.x = -120.0
		elif p.x < -120.0:
			p.x = W + 120.0
		c["pos"] = p
	var sky := Rect2(40.0, 40.0, W - 80.0, HY - 110.0)
	for gl in _gulls:
		gl.apply_force(gl.wander(delta, 50.0, 25.0, 2.5) * 0.5)
		gl.apply_force(gl.contain(sky, 60.0))
		gl.apply_force(Vector2(wind_x * 0.05, 0.0))
		gl.update(delta)
	for b in _boats:
		var bx: float = b["x"] + float(b["v"]) * delta
		if bx > 900.0:
			bx = -900.0
		elif bx < -900.0:
			bx = 900.0
		b["x"] = bx
	for n in _neighbours:
		var bt: float = n["bend_t"] - delta
		if bt <= 0.0:
			bt = _rng.randf_range(15.0, 40.0)
			n["bend"] = 1.0
		n["bend_t"] = bt
		n["bend"] = maxf(0.0, float(n["bend"]) - delta * 0.25)


## Surfacing: a jump is a projectile in metres under gravity; a thrash or roll is a short oscillation.
func _step_jump(delta: float) -> void:
	if _jump.is_empty():
		return
	var t: float = float(_jump["t"]) + delta
	_jump["t"] = t
	var k := String(_jump["kind"])
	if k == "jump":
		var vh: float = float(_jump["vh"]) - G * delta
		_jump["vh"] = vh
		_jump["h"] = float(_jump["h"]) + vh * delta
		_jump["x"] = float(_jump["x"]) + float(_jump["vx"]) * delta
		if float(_jump["h"]) <= 0.0 and vh < 0.0:
			var p := _proj(float(_jump["x"]), float(_jump["z"]), 0.0)
			_spray_at(p, 30, 1.6)
			_add_ripple(float(_jump["x"]), float(_jump["z"]), 1.8)
			sfx.emit("splash_big", _near_volume(float(_jump["z"])))
			_jump = {}
		elif _rng.randf() < delta * 30.0:
			# water streaming off the fish in the air
			var pf := _proj(float(_jump["x"]), float(_jump["z"]), float(_jump["h"]))
			_spray.append(Noc.Particle.new(pf, Vector2(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-20.0, 40.0)), 0.0, 0.0, 0.6, _rng.randf_range(1.0, 2.5), Color(0.9, 0.97, 1.0, 0.9)))
	else:
		_jump["h"] = sin(minf(t / 0.8, 1.0) * PI) * (0.18 if k == "thrash" else 0.06)
		if _rng.randf() < delta * 20.0:
			_spray_at(_proj(float(_jump["x"]), float(_jump["z"]), 0.0), 3, 0.7)
		if t >= 0.8:
			_add_ripple(float(_jump["x"]), float(_jump["z"]), 1.2)
			_jump = {}


func _step_particles(delta: float) -> void:
	var keep: Array[Noc.Particle] = []
	for p in _spray:
		p.vel += Vector2(0.0, 900.0) * delta
		p.pos += p.vel * delta
		p.age += delta
		if not p.dead():
			keep.append(p)
	_spray = keep
	var dkeep: Array = []
	for d in _drips:
		d.vel += Vector2(0.0, 900.0) * delta
		d.pos += d.vel * delta
		d.age += delta
		if not d.dead() and d.pos.y < H + 10.0:
			dkeep.append(d)
	_drips = dkeep


## Landed: the fish swings up into view on the line, a pendulum on a spring, dripping water.
func _animate_catch(delta: float) -> void:
	var target := Vector2(540.0, 380.0)
	var acc := (target - _fish_pos) * 26.0 - _lift_v * 6.0
	_lift_v += acc * delta
	_fish_pos += _lift_v * delta
	_facing = -1.0
	_tilt = sin(_time * 9.0) * 0.4 * clampf(_catch_t / 3.4, 0.2, 1.0)
	if _rng.randf() < delta * 20.0:
		_drips.append(Noc.Particle.new(_fish_pos + Vector2(_rng.randf_range(-40.0, 40.0), 10.0),
			Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(0.0, 60.0)), 0.0, 0.0, 1.2, _rng.randf_range(2.0, 4.0), Color(0.8, 0.95, 1.0, 0.9)))


func show_catch(title: String, lines: PackedStringArray) -> void:
	super.show_catch(title, lines)
	_fish_pos = _proj(target_x, target_z, 0.0)
	_lift_v = Vector2(0.0, -600.0)
	_open = false
	phase = "off"


# ---------------------------------------------------------------- drawing
func _draw_view() -> void:
	var c := _canvas
	var day := daylight
	var night := 1.0 - day
	var dusk := clampf(1.0 - absf(day - 0.4) / 0.35, 0.0, 1.0) * 0.8
	var hy := HY - _pitch
	var sky_low := _sky_low(night, dusk)

	# Sea.
	var wcol: Dictionary = spot.get("water", {})
	var shallow: Color = wcol.get("shallow", Color(0.12, 0.70, 0.78))
	var deep: Color = wcol.get("deep", Color(0.02, 0.15, 0.32))
	var far_sea := sky_low.lerp(deep, 0.55).darkened(0.1 * night)
	var near_sea := deep.lerp(shallow, 0.35).darkened(0.55 * night)
	c.draw_polygon(PackedVector2Array([Vector2(0, hy), Vector2(W, hy), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([far_sea, far_sea, near_sea, near_sea]))
	_draw_glitter(day, night, dusk)
	_draw_waves(night)
	_draw_boats(night)
	_draw_ripples()
	_draw_target()
	_draw_line_entry()
	_draw_surfacing()
	_draw_foreground(night)
	_draw_neighbours(night)
	for p in _spray:
		var a := 1.0 - clampf(p.age / p.life, 0.0, 1.0)
		c.draw_circle(p.pos, p.size, Color(0.92, 0.97, 1.0, 0.85 * a))
	_draw_rod_and_line(night)
	if _catch_t > 0.0:
		_draw_caught_fish()
		for d in _drips:
			c.draw_circle(d.pos, float(d.size), Color(0.8, 0.95, 1.0, 0.85))
		_draw_card()


func _make_layer(draw_fn: Callable) -> Control:
	var l := Control.new()
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	l.draw.connect(draw_fn)
	add_child(l)
	return l


func _dusk() -> float:
	return clampf(1.0 - absf(daylight - 0.4) / 0.35, 0.0, 1.0) * 0.8


func _sky_low(night: float, dusk: float) -> Color:
	return Color(0.80, 0.89, 0.97).lerp(Color(0.08, 0.10, 0.22), night).lerp(Color(1.0, 0.62, 0.40), dusk)


## Sky gradient, stars, sun or moon. Redrawn only when the light changes.
func _draw_sky_layer() -> void:
	var c := _sky_layer
	var night := 1.0 - daylight
	var dusk := _dusk()
	var sky_top := Color(0.30, 0.56, 0.88).lerp(Color(0.02, 0.03, 0.10), night).lerp(Color(0.32, 0.30, 0.55), dusk * 0.5)
	var sky_low := _sky_low(night, dusk)
	c.draw_polygon(PackedVector2Array([Vector2(0, -10.0), Vector2(W, -10.0), Vector2(W, HY + 2.0), Vector2(0, HY + 2.0)]),
		PackedColorArray([sky_top, sky_top, sky_low, sky_low]))
	if night > 0.3:
		for i in _stars.size():
			c.draw_rect(Rect2(_stars[i], Vector2(2.0, 2.0)), Color(1.0, 1.0, 0.95, (night - 0.3) * (0.5 + 0.4 * fmod(float(i) * 0.37, 1.0))))
	_draw_sun_moon(c, sky_low)


## Clouds and gulls: they move, so this small layer is redrawn every frame.
func _draw_mid_layer() -> void:
	var night := 1.0 - daylight
	var dusk := _dusk()
	var ccol := Color(1.0, 1.0, 1.0, 0.75).lerp(Color(0.25, 0.28, 0.38, 0.7), night).lerp(Color(1.0, 0.78, 0.65, 0.8), dusk * 0.6)
	for cl in _clouds:
		var cp: Vector2 = cl["pos"]
		for pf: Vector3 in cl["puffs"]:
			_mid_layer.draw_circle(cp + Vector2(pf.x, pf.y), pf.z, ccol)
	_draw_gulls(_mid_layer, night)


## Far coast, town and mosque. Redrawn only when the light changes.
func _draw_coast_layer() -> void:
	var night := 1.0 - daylight
	var haze := _sky_low(night, _dusk()).lerp(Color(0.45, 0.55, 0.62), 0.35)
	_coast_layer.draw_colored_polygon(_coast_far, haze.darkened(0.12))
	_coast_layer.draw_colored_polygon(_coast_near, haze.darkened(0.28).lerp(Color(0.25, 0.33, 0.28), 0.35 * daylight))
	_draw_town(_coast_layer, night)


func _draw_sun_moon(c: CanvasItem, sky_low: Color) -> void:
	var elev := sin((time_of_day - 0.25) * TAU)
	var sx := CX + (time_of_day - 0.5) * 2.0 * 820.0
	if elev > -0.08:
		var sp := Vector2(sx, HY - elev * 250.0)
		var sun_col := Color(1.0, 0.97, 0.85).lerp(Color(1.0, 0.6, 0.3), clampf(1.0 - elev * 3.0, 0.0, 1.0))
		for i in 4:
			c.draw_circle(sp, 26.0 + float(i) * 18.0, Color(sun_col.r, sun_col.g, sun_col.b, 0.10 - 0.02 * float(i)))
		c.draw_circle(sp, 22.0, sun_col)
	var mt := fmod(time_of_day + 0.5, 1.0)
	var melev := sin((mt - 0.25) * TAU)
	if melev > 0.0:
		var mp := Vector2(CX + (mt - 0.5) * 2.0 * 820.0, HY - melev * 230.0)
		c.draw_circle(mp, 30.0, Color(0.9, 0.92, 1.0, 0.12))
		c.draw_circle(mp, 16.0, Color(0.95, 0.95, 0.88))
		c.draw_circle(mp + Vector2(6.0, -3.0), 13.0, sky_low.lerp(Color(0.05, 0.06, 0.14), 0.6))


func _draw_gulls(ci: CanvasItem, night: float) -> void:
	var col := Color(1.0, 1.0, 1.0, 0.95).lerp(Color(0.6, 0.62, 0.7, 0.8), night)
	for gl in _gulls:
		var s: float = gl.data["size"] * 9.0
		var fl := sin(_time * 7.0 + float(gl.data["phase"])) * s * 0.6
		var p: Vector2 = gl.pos
		ci.draw_polyline(PackedVector2Array([p + Vector2(-s * 1.6, -fl), p + Vector2(-s * 0.5, -fl * 0.2 - 2.0), p,
			p + Vector2(s * 0.5, -fl * 0.2 - 2.0), p + Vector2(s * 1.6, -fl)]), col, 2.2, true)


func _draw_town(c: CanvasItem, night: float) -> void:
	for hs in _houses:
		var hx: float = hs["x"]
		var base := _coast_y(hx) + 3.0
		var w: float = hs["w"]
		var h: float = hs["h"]
		var col: Color = hs["col"]
		c.draw_rect(Rect2(hx, base - h, w, h), col.darkened(0.15 + 0.6 * night))
		c.draw_rect(Rect2(hx - 1.0, base - h - 2.0, w + 2.0, 2.5), Color(0.72, 0.33, 0.22).darkened(0.6 * night))
		if bool(hs["lit"]) and night > 0.35:
			var fl := 0.8 + 0.2 * sin(_time * 3.0 + float(hs["phase"]))
			c.draw_rect(Rect2(hx + w * 0.35, base - h * 0.6, 2.0, 2.0), Color(1.0, 0.85, 0.45, (night - 0.35) * 1.4 * fl))
	# Mosque on the left shore: dome and a minaret, a quiet landmark of a Turkish coastal town.
	var mx := 300.0
	var my := _coast_y(mx) + 3.0
	var mcol := Color(0.88, 0.88, 0.86).darkened(0.15 + 0.6 * night)
	c.draw_rect(Rect2(mx - 12.0, my - 12.0, 24.0, 12.0), mcol)
	c.draw_circle(Vector2(mx, my - 12.0), 9.0, mcol)
	c.draw_rect(Rect2(mx + 16.0, my - 40.0, 3.0, 40.0), mcol)
	c.draw_colored_polygon(PackedVector2Array([Vector2(mx + 15.0, my - 40.0), Vector2(mx + 20.0, my - 40.0), Vector2(mx + 17.5, my - 49.0)]), Color(0.45, 0.5, 0.55).darkened(0.5 * night))
	if night > 0.35:
		c.draw_circle(Vector2(mx + 17.5, my - 30.0), 2.0, Color(0.6, 1.0, 0.7, night * 0.8))


## Height of the near coast line at screen x.
func _coast_y(x: float) -> float:
	var i := clampi(int(x / 20.0) + 1, 1, _coast_near.size() - 2)
	return minf(_coast_near[i].y, HY - 2.0)


func _draw_glitter(day: float, night: float, dusk: float) -> void:
	var elev := sin((time_of_day - 0.25) * TAU)
	var sx := CX + (time_of_day - 0.5) * 2.0 * 820.0
	var bright := clampf(elev * 3.0, 0.0, 1.0) * day + dusk * 0.6
	var col := Color(1.0, 0.95, 0.8).lerp(Color(1.0, 0.7, 0.4), dusk)
	if elev <= 0.0:
		var mt := fmod(time_of_day + 0.5, 1.0)
		var melev := sin((mt - 0.25) * TAU)
		if melev <= 0.0 or night < 0.5:
			return
		sx = CX + (mt - 0.5) * 2.0 * 820.0
		bright = 0.5
		col = Color(0.85, 0.9, 1.0)
	if bright < 0.05:
		return
	for g in _glints:
		var z := g.y
		var p := _proj(0.0, z, 0.0)
		p.x = sx + g.x * (40.0 + 2600.0 / z) + sin(_time * 0.7 + g.z) * 6.0
		var tw := sin(_time * 3.0 + g.z)
		if tw > 0.3:
			var k := (tw - 0.3) / 0.7 * bright
			var glen := 3.0 + 400.0 / z
			_canvas.draw_line(p - Vector2(glen, 0.0), p + Vector2(glen, 0.0), Color(col.r, col.g, col.b, 0.9 * k), 1.5 + 30.0 / z)


## Wave crests: rows at growing distance, each a sum of two oscillators travelling toward the shore.
func _draw_waves(night: float) -> void:
	var z := 3.0
	for row in WAVE_ROWS:
		z *= 1.38
		var base := _proj(0.0, z, 0.0).y
		if base < HY - _pitch + 2.0:
			break
		var near := clampf(6.0 / z, 0.0, 1.0)
		var amp := (0.10 + 0.05 * wave_amp) * F / z * 0.12 * wave_amp
		var pts := PackedVector2Array()
		var x := -20.0
		while x <= W + 20.0:
			var wx := (x - CX) * z / F
			var y := base + sin(wx * 0.9 + z * 0.8 - _time * 1.6) * amp + sin(wx * 0.37 - _time * 0.9 + float(row)) * amp * 0.7
			pts.append(Vector2(x, y))
			x += 64.0
		var a := (0.10 + 0.25 * near) * (1.0 - 0.6 * night)
		_canvas.draw_polyline(pts, Color(1.0, 1.0, 1.0, a), 1.0 + 2.5 * near)
		if wave_amp > 1.4 and row > 2 and row % 2 == 0:
			for j in 4:
				var cx := fmod(float(j) * 337.0 + _time * 20.0 + float(row) * 91.0, W)
				_canvas.draw_line(Vector2(cx, base), Vector2(cx + 24.0 * near + 4.0, base), Color(1, 1, 1, 0.45), 2.0)


func _draw_boats(night: float) -> void:
	var c := _canvas
	for b in _boats:
		var z: float = b["z"]
		var p := _proj(float(b["x"]), z, 0.0)
		if p.x < -60.0 or p.x > W + 60.0:
			continue
		var s := F / z
		var t := String(b["type"])
		var hull := Color(0.95, 0.95, 0.93).darkened(0.65 * night)
		if t == "ferry":
			c.draw_rect(Rect2(p.x - 26.0 * s, p.y - 4.0 * s, 52.0 * s, 4.0 * s), hull)
			c.draw_rect(Rect2(p.x - 18.0 * s, p.y - 9.0 * s, 32.0 * s, 5.0 * s), hull.darkened(0.08))
			c.draw_rect(Rect2(p.x + 4.0 * s, p.y - 13.0 * s, 3.0 * s, 4.0 * s), Color(0.8, 0.2, 0.15).darkened(0.5 * night))
		elif t == "sail":
			c.draw_rect(Rect2(p.x - 5.0 * s, p.y - 2.0 * s, 10.0 * s, 2.0 * s), hull)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0.0, -2.0 * s), p + Vector2(0.0, -16.0 * s), p + Vector2(6.0 * s, -3.0 * s)]), hull)
		else:
			c.draw_rect(Rect2(p.x - 7.0 * s, p.y - 3.0 * s, 14.0 * s, 3.0 * s), Color(0.25, 0.45, 0.7).darkened(0.6 * night))
			c.draw_rect(Rect2(p.x - 2.0 * s, p.y - 6.0 * s, 5.0 * s, 3.0 * s), hull)
		if night > 0.4:
			c.draw_circle(p + Vector2(0.0, -6.0 * s), maxf(1.5, s), Color(1.0, 0.9, 0.6, night))


func _draw_ripples() -> void:
	for r in _ripples:
		var age: float = r["age"]
		var k := age / 2.2
		var rad_m: float = (0.15 + age * 0.9) * float(r["size"])
		var z: float = r["z"]
		var ctr := _proj(float(r["x"]), z, 0.0)
		var rx := F * rad_m / z
		var ry := rx * clampf(eye_h / z, 0.06, 0.5)
		_ellipse_line(ctr, Vector2(rx, ry), Color(1.0, 1.0, 1.0, 0.55 * (1.0 - k)), 1.5)


func _ellipse_line(ctr: Vector2, r: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 15:
		var a := TAU * float(i) / 14.0
		pts.append(ctr + Vector2(cos(a) * r.x, sin(a) * r.y))
	_canvas.draw_polyline(pts, col, width)


## The float (red tip, white body) or the flying bait or, in the fight, the jumping fish.
func _draw_target() -> void:
	var c := _canvas
	if phase == "float" and lure:
		var pl := _proj(target_x, target_z, 0.0)
		_ellipse_line(pl, Vector2(5.0, 1.8), Color(1.0, 1.0, 1.0, 0.6), 1.2)
	elif phase == "float":
		var p := _proj(target_x, target_z, 0.0)
		var s := clampf(F * 0.05 / target_z, 2.5, 14.0)
		var dip := clampf(float_dip, 0.0, 1.4)
		var show := clampf(1.0 - dip * 0.8, 0.0, 1.0)
		var bob := sin(_time * 2.2) * s * 0.15
		if show > 0.05:
			var top := p + Vector2(0.0, bob - s * 2.6 * show)
			c.draw_line(p + Vector2(0.0, bob), top, Color(0.95, 0.95, 0.9), s * 0.7)
			c.draw_line(top, top + Vector2(0.0, s * 1.1 * show), Color(1.0, 0.25, 0.15), s * 0.75)
		_ellipse_line(p + Vector2(0.0, bob), Vector2(s * 1.4, s * 0.35), Color(1.0, 1.0, 1.0, 0.5), 1.2)
	elif phase == "fly":
		var p2 := _proj(target_x, target_z, target_h)
		c.draw_circle(p2, clampf(F * 0.04 / target_z, 2.0, 8.0), Color(1.0, 0.3, 0.2))


func _draw_foreground(night: float) -> void:
	var c := _canvas
	var dark := 0.55 * night
	var edge_y := _proj(0.0, _z_edge(), 0.0).y
	if edge_y > H + 40.0:
		return
	c.draw_set_transform(Vector2(0.0, edge_y - 666.0), 0.0, Vector2.ONE)
	match kind:
		"bridge":
			c.draw_rect(Rect2(0.0, 660.0, W, 400.0), Color(0.42, 0.42, 0.44).darkened(dark))
			c.draw_rect(Rect2(0.0, 640.0, W, 10.0), Color(0.30, 0.32, 0.34).darkened(dark))
			var x := 20.0
			while x < W:
				c.draw_rect(Rect2(x, 600.0, 8.0, 60.0), Color(0.28, 0.30, 0.32).darkened(dark))
				x += 90.0
			c.draw_rect(Rect2(0.0, 596.0, W, 7.0), Color(0.35, 0.37, 0.40).darkened(dark))
		"harbor":
			c.draw_rect(Rect2(0.0, 670.0, W, 400.0), Color(0.62, 0.60, 0.56).darkened(dark))
			c.draw_rect(Rect2(0.0, 664.0, W, 8.0), Color(0.75, 0.73, 0.68).darkened(dark))
			c.draw_circle(Vector2(180.0, 668.0), 16.0, Color(0.2, 0.2, 0.22).darkened(dark))
			_draw_foam(662.0, night)
		"beach":
			var sand := Color(0.86, 0.78, 0.60).darkened(dark)
			var pts := PackedVector2Array([Vector2(0.0, H + 400.0)])
			var x2 := 0.0
			while x2 <= W:
				pts.append(Vector2(x2, 668.0 + sin(x2 * 0.01) * 8.0))
				x2 += 40.0
			pts.append(Vector2(W, H + 400.0))
			c.draw_colored_polygon(pts, sand)
			_draw_foam(664.0, night)
		_:
			_draw_rocks(night)
			_draw_foam(670.0, night)
	if on_pier:
		c.draw_rect(Rect2(0.0, 690.0, W, 300.0), Color(0.50, 0.37, 0.24).darkened(dark))
		for i in 12:
			c.draw_line(Vector2(0.0, 694.0 + float(i) * 14.0), Vector2(W, 694.0 + float(i) * 14.0), Color(0.38, 0.27, 0.17).darkened(dark), 2.0)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Foam where the water meets the near edge: a line that washes up and back on an oscillator.
func _draw_foam(y: float, night: float) -> void:
	var wash := sin(_time * 0.9) * 6.0
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= W:
		pts.append(Vector2(x, y + wash + sin(x * 0.03 + _time * 1.4) * 3.0 + _noise.get_noise_2d(x * 0.02, _time) * 5.0))
		x += 24.0
	_canvas.draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.75 - 0.4 * night), 4.0, true)


func _draw_rocks(night: float) -> void:
	var c := _canvas
	var col := Color(0.40, 0.37, 0.34).darkened(0.55 * night)
	c.draw_circle(Vector2(60.0, 740.0), 120.0, col)
	c.draw_circle(Vector2(230.0, 760.0), 95.0, col.lightened(0.06))
	c.draw_circle(Vector2(1220.0, 750.0), 130.0, col.darkened(0.05))
	c.draw_circle(Vector2(640.0, 800.0), 140.0, col.lightened(0.03))
	c.draw_rect(Rect2(0.0, 760.0, W, 400.0), col)
	c.draw_circle(Vector2(40.0, 690.0), 30.0, col.lightened(0.15))


## Other anglers' rods to the left: thin lines that nod in the swell; now and then one bends on a fish.
func _draw_neighbours(night: float) -> void:
	if kind == "beach":
		return
	var col := Color(0.12, 0.12, 0.14).lerp(Color(0.05, 0.05, 0.07), night)
	for n in _neighbours:
		var base: Vector2 = n["base"]
		var tip: Vector2 = n["tip"]
		var bend: float = n["bend"]
		var nod := sin(_time * 1.3 + float(n["phase"])) * 6.0 + bend * 40.0 * absf(sin(_time * 6.0))
		var t2 := tip + Vector2(0.0, nod + bend * 50.0)
		var ctrl := base.lerp(t2, 0.5) + Vector2(-10.0, 0.0) + Vector2(0.0, bend * 30.0)
		_canvas.draw_polyline(_bezier(base, ctrl, t2, 10), col, 3.0, true)
		var entry := Vector2(t2.x + 40.0 + bend * 20.0, HY - _pitch + 70.0 + float(n["phase"]) * 8.0)
		_canvas.draw_line(t2, entry, Color(1.0, 1.0, 1.0, 0.25), 1.0)


func _bezier(a: Vector2, ctrl: Vector2, b: Vector2, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts


## Your rod seen from just behind your hands: tapered blank bending toward the line, guides, a
## spinning reel under it (spool with line, bail arm, handle you turn while reeling), your hands.
func _draw_rod_and_line(night: float) -> void:
	var c := _canvas
	var tip := _tip
	var line_end := _line_end()
	var bend := clampf((tip - ROD_REST).length() / 160.0, 0.0, 1.2)
	var dir := (tip - ROD_BASE).normalized()
	var ctrl := ROD_BASE.lerp(tip, 0.55) + dir.orthogonal() * (-30.0 - 90.0 * bend)
	var pts := _bezier(ROD_BASE, ctrl, tip, 18)
	var dim := lerpf(1.0, 0.45, night)

	# Line: sags when slack, straight when tight; from the tip down to the water.
	if phase != "off" or _catch_t > 0.0:
		var to := line_end if _catch_t <= 0.0 else _fish_pos + Vector2(-30.0, -10.0)
		var sag := (1.0 - clampf(tension * 2.0, 0.0, 1.0)) * 50.0
		if phase == "fly":
			sag = 15.0
		var mid := tip.lerp(to, 0.5) + Vector2(0.0, sag)
		c.draw_polyline(_bezier(tip, mid, to, 16), Color(1.0, 1.0, 1.0, 0.8 - 0.3 * night), 1.5, true)
		# The line also runs back along the rod through the guides to the spool.
		c.draw_polyline(PackedVector2Array([pts[18], pts[15], pts[11], pts[7], pts[4]]), Color(1.0, 1.0, 1.0, 0.45), 1.0, true)

	# Blank: carbon, tapering, with a highlight; cork grip at the butt.
	for i in pts.size() - 1:
		var w := lerpf(16.0, 3.0, float(i) / float(pts.size() - 1))
		var col := Color(0.10, 0.12, 0.16) if i > 3 else Color(0.62, 0.48, 0.32) * Color(dim, dim, dim)
		c.draw_line(pts[i], pts[i + 1], col, w)
		if i > 3:
			c.draw_line(pts[i] + Vector2(-1.5, -1.5), pts[i + 1] + Vector2(-1.5, -1.5), Color(0.55, 0.60, 0.70, 0.5 * dim), w * 0.25)
	for gi in [7, 11, 15, 17]:
		var gp: Vector2 = pts[gi]
		var gr := lerpf(9.0, 3.0, float(gi) / 18.0)
		c.draw_arc(gp + Vector2(0.0, gr * 0.8), gr, 0.0, TAU, 12, Color(0.78, 0.78, 0.82), 2.0)
		c.draw_line(gp, gp + Vector2(0.0, gr * 0.4), Color(0.6, 0.6, 0.65), 2.0)

	# Spinning reel hanging under the reel seat.
	var seat := pts[4]
	var body := seat + Vector2(8.0, 58.0)
	var steel := Color(0.30, 0.32, 0.36) * Color(dim, dim, dim)
	var bright := Color(0.70, 0.72, 0.76) * Color(dim, dim, dim)
	c.draw_line(seat, body + Vector2(0.0, -20.0), steel, 9.0)                      # foot and stem
	c.draw_circle(body, 30.0, steel)                                                # gear housing
	c.draw_circle(body + Vector2(-6.0, -4.0), 22.0, steel.lightened(0.12))
	var spool_c := body + Vector2(-44.0, -18.0)
	c.draw_set_transform(spool_c, dir.angle() + PI, Vector2.ONE)
	c.draw_rect(Rect2(-20.0, -17.0, 40.0, 34.0), bright)                            # spool
	for k in 7:
		var y := -13.0 + float(k) * 4.3
		c.draw_line(Vector2(-18.0, y), Vector2(18.0, y + 1.0), Color(0.92, 0.92, 0.88, 0.8), 1.2)   # line wraps
	c.draw_rect(Rect2(-24.0, -20.0, 6.0, 40.0), steel.lightened(0.2))
	c.draw_arc(Vector2(10.0, 0.0), 24.0, -1.6, 1.6, 12, Color(0.85, 0.85, 0.88), 2.5) # bail arm
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Handle: the arm turns in a circle while you reel; seen at an angle it traces an ellipse.
	var hd := Vector2(cos(_reel_angle) * 34.0, sin(_reel_angle) * 14.0)
	var knob := body + Vector2(26.0, 6.0) + hd
	c.draw_line(body + Vector2(26.0, 6.0), knob, steel.darkened(0.2), 6.0)
	c.draw_circle(knob, 9.0, Color(0.15, 0.15, 0.17))

	# Hands and forearms: right hand round the seat, left hand on the reel knob.
	var skin := Color(0.92, 0.74, 0.58) * Color(dim, dim, dim)
	var sleeve := Color(0.18, 0.32, 0.55) * Color(dim, dim, dim)
	c.draw_line(Vector2(1250.0, H + 60.0), seat + Vector2(26.0, 10.0), sleeve, 54.0)
	c.draw_circle(seat + Vector2(10.0, 4.0), 24.0, skin)
	c.draw_circle(seat + Vector2(-8.0, 10.0), 10.0, skin.darkened(0.08))
	c.draw_line(Vector2(880.0, H + 80.0), knob + Vector2(6.0, 24.0), sleeve.darkened(0.08), 46.0)
	c.draw_circle(knob + Vector2(4.0, 10.0), 19.0, skin)


## In the fight the line cuts the water: a V wake trails the entry point when the fish swims across.
func _draw_line_entry() -> void:
	if phase != "fight" or not _jump.is_empty():
		return
	var p := _proj(target_x, target_z, 0.0)
	var speed := clampf(absf(_lat_v) / 3.0, 0.0, 1.0)
	var back := -signf(_lat_v)
	var arm := (8.0 + 40.0 * speed) * F / 900.0 * clampf(12.0 / target_z, 0.3, 2.0)
	var ry := clampf(eye_h / target_z, 0.08, 0.5)
	var col := Color(1.0, 1.0, 1.0, 0.25 + 0.5 * speed)
	_canvas.draw_line(p, p + Vector2(back * arm, -arm * ry), col, 1.5)
	_canvas.draw_line(p, p + Vector2(back * arm, arm * ry), col, 1.5)
	_ellipse_line(p, Vector2(4.0 + 6.0 * tension, 1.5 + 2.0 * tension), Color(1.0, 1.0, 1.0, 0.6), 1.5)


## The fish when it shows itself: leaping clear, thrashing half out with its head shaking, or
## rolling so only its back and dorsal fin break the surface.
func _draw_surfacing() -> void:
	if phase != "fight" or _jump.is_empty() or _creature != "":
		return
	var z: float = _jump["z"]
	var hgt: float = _jump["h"]
	var p := _proj(float(_jump["x"]), z, hgt)
	var len_px := F * _fish_len_m() / z
	var k := String(_jump["kind"])
	var t: float = _jump["t"]
	var dir := 1.0 if float(_jump["vx"]) >= 0.0 else -1.0
	var water := _proj(float(_jump["x"]), z, 0.0)
	match k:
		"jump":
			var vh: float = _jump["vh"]
			var rot := -atan2(vh, 3.5) * 0.9 + sin(t * 32.0) * 0.18 * clampf(1.0 - absf(vh) / 3.0, 0.0, 1.0)
			RealFish.draw(_canvas, _fish_id, p, len_px, rot * dir, dir, _flex_phase, 0.9, daylight, 1.0)
			# a sheet of water torn up behind it in the first moments
			if t < 0.25:
				_ellipse_line(water, Vector2(len_px * 0.5, len_px * 0.12), Color(1.0, 1.0, 1.0, 0.8 - t * 3.0), 3.0)
		"thrash":
			var rot2 := sin(t * 28.0) * 0.45 - 0.25
			RealFish.draw(_canvas, _fish_id, water + Vector2(0.0, -len_px * 0.08), len_px, rot2 * dir, dir, _flex_phase * 1.3, 1.0, daylight, 1.0)
			_cover_with_water(water, len_px, 0.55)
			for i in 3:
				_ellipse_line(water, Vector2(len_px * (0.5 + 0.15 * float(i)), len_px * (0.10 + 0.03 * float(i))), Color(1.0, 1.0, 1.0, 0.7 - 0.2 * float(i)), 2.5)
		_:
			var arc := sin(clampf(t / 0.8, 0.0, 1.0) * PI)
			var back_c: Color = RealFish.look(_fish_id)["back"]
			var pts := PackedVector2Array()
			for i in 13:
				var u := float(i) / 12.0
				pts.append(water + Vector2((u - 0.5) * len_px * 0.8 * dir, -sin(u * PI) * len_px * 0.12 * arc))
			_canvas.draw_polyline(pts, back_c.darkened(0.2), maxf(3.0, len_px * 0.06), true)
			var fin_at := water + Vector2(len_px * 0.05 * dir, -len_px * 0.12 * arc)
			_canvas.draw_colored_polygon(PackedVector2Array([fin_at + Vector2(-len_px * 0.08 * dir, 0.0), fin_at + Vector2(0.0, -len_px * 0.14 * arc), fin_at + Vector2(len_px * 0.06 * dir, 0.0)]), back_c.darkened(0.35))
			_ellipse_line(water, Vector2(len_px * 0.55, len_px * 0.1), Color(1.0, 1.0, 1.0, 0.5), 2.0)


## Hides the lower part of a fish at the surface under a band of water with a foam edge.
func _cover_with_water(at: Vector2, len_px: float, depth_frac: float) -> void:
	var wcol: Dictionary = spot.get("water", {})
	var deep: Color = wcol.get("deep", Color(0.02, 0.15, 0.32))
	var shallow: Color = wcol.get("shallow", Color(0.12, 0.70, 0.78))
	var sea := deep.lerp(shallow, 0.3).darkened(0.5 * (1.0 - daylight))
	var w := len_px * 0.75
	var top := at.y + len_px * 0.02
	_canvas.draw_rect(Rect2(at.x - w, top, w * 2.0, len_px * depth_frac), Color(sea.r, sea.g, sea.b, 0.92))
	_canvas.draw_line(Vector2(at.x - w, top), Vector2(at.x + w, top), Color(1.0, 1.0, 1.0, 0.8), 3.0)


func _draw_caught_fish() -> void:
	var len_px := clampf(_fish_len_m(), 0.18, 1.3) * 300.0
	if _creature != "":
		_draw_creature(_creature, _fish_pos, _facing, _tilt, len_px / 160.0, Color.WHITE)
	else:
		RealFish.draw(_canvas, _fish_id, _fish_pos, len_px, _tilt - 0.15, _facing, _flex_phase * 0.6, 0.5 + 0.5 * clampf(_catch_t / 3.4, 0.0, 1.0), daylight, 1.0)


## Catch card, with the species drawn as it looks (not a sprite).
func _draw_card() -> void:
	var appear := clampf((3.4 - _catch_t) * 4.0, 0.0, 1.0)
	var rect := Rect2(Vector2(40.0, 120.0 + (1.0 - appear) * 40.0), Vector2(520.0, 300.0))
	_card.draw(_canvas.get_canvas_item(), rect)
	var font := ThemeDB.fallback_font
	_canvas.draw_string(font, rect.position + Vector2(24.0, 50.0), _catch_title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 48.0, 30, Color(1.0, 0.92, 0.6))
	for i in _catch_lines.size():
		_canvas.draw_string(font, rect.position + Vector2(24.0, 94.0 + float(i) * 32.0), _catch_lines[i], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 48.0, 22, Color.WHITE)
