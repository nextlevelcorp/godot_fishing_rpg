## Side-on view of the fight: the angler on the shore at the left, the line running down into the
## water, and the hooked fish under the surface. Shown while a fish is on, over the top-down scene.
##
## Nature of Code throughout:
##   - distance out comes from FishingController (spring-mass line); the fish's depth is a damped
##     spring pulled toward a target depth that drifts on Perlin noise, dives on runs and rises as
##     the fish tires;
##   - the line is a Verlet rope that sags under gravity when slack and straightens when tight;
##   - bubbles are particles with buoyancy; seaweed sways on oscillators; background fish are
##     steering agents that wander and flee the hooked fish.
##
## Sprites: Kenney Fish Pack (CC0), assets/kenney_fish_pack/. The pack's fish are generic cartoon
## fish, so each species gets the closest shape and a tint, not a true likeness.
class_name FightView
extends CanvasLayer

const TEX_DIR := "res://assets/kenney_fish_pack/"
const W := 1280.0
const H := 720.0
const SURFACE_Y := 190.0
const BED_Y := 640.0
const MAX_DEPTH_M := 20.0
const HAND := Vector2(96.0, 132.0)
const ROD_TIP := Vector2(205.0, 98.0)
const ROPE_POINTS := 18

## species id -> [sprite name, tint]
const FISH_SPRITES := {
	"mediterranean_horse_mackerel": ["fish_grey", Color(0.85, 0.95, 1.0)],
	"atlantic_bonito": ["fish_blue", Color(0.80, 0.85, 1.0)],
	"bluefish": ["fish_blue", Color(1.0, 1.0, 1.0)],
	"black_scorpionfish": ["fish_brown", Color(1.0, 1.0, 1.0)],
	"european_anchovy": ["fish_grey", Color(0.95, 1.0, 1.0)],
	"european_seabass": ["fish_grey", Color(0.90, 0.95, 1.0)],
	"gilthead_seabream": ["fish_grey", Color(1.0, 0.95, 0.80)],
	"red_mullet": ["fish_red", Color(1.0, 1.0, 1.0)],
	"striped_sea_bream": ["fish_grey", Color(1.0, 1.0, 0.90)],
	"dusky_grouper": ["fish_brown", Color(0.90, 0.85, 0.80)],
	"common_dentex": ["fish_pink", Color(1.0, 1.0, 1.0)],
	"greater_amberjack": ["fish_orange", Color(1.0, 0.95, 0.80)],
	"leerfish": ["fish_grey", Color(0.95, 1.0, 0.90)],
	"saddled_bream": ["fish_grey", Color(0.80, 0.85, 0.90)],
	"garfish": ["fish_green", Color(1.0, 1.0, 1.0)],
}

## Set by the shore scene before begin().
var fishing: FishingController
var spot: Dictionary = {}
var tint := Color.WHITE
var daylight := 1.0

var _canvas: Control
var _tex: Dictionary = {}
var _active := false
var _alpha := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()

var _fish_tex: Texture2D
var _fish_tint := Color.WHITE
var _fish_len := 100.0
var _depth_range := Vector2(1.0, 10.0)
var _view_m := 30.0
var _fish_pos := Vector2(900.0, 400.0)
var _depth_m := 3.0
var _depth_v := 0.0
var _facing := 1.0
var _tilt := 0.0
var _rod_bend := 0.0
var _rope: Noc.Rope
var _bubbles: Array = []
var _small_fish: Array = []
var _bed_items: Array[Dictionary] = []
# catch presentation: the fish is lifted from the water on a spring, flapping, dripping water
var _catch_t := 0.0
var _catch_title := ""
var _catch_lines := PackedStringArray()
var _lift_v := Vector2.ZERO
var _drips: Array = []
var _card := StyleBoxFlat.new()


func _ready() -> void:
	layer = 3
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.25
	_rng.randomize()
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_view)
	_canvas.visible = false
	add_child(_canvas)
	for n in ["fish_blue", "fish_brown", "fish_green", "fish_grey", "fish_orange", "fish_pink", "fish_red",
			"bubble_a", "bubble_b", "bubble_c", "rock_a", "rock_b", "seaweed_green_a", "seaweed_green_b",
			"seaweed_green_c", "seaweed_green_d", "seaweed_grass_a", "seaweed_grass_b", "seaweed_orange_a",
			"seaweed_orange_b", "seaweed_pink_a", "seaweed_pink_b", "background_rock_a", "background_rock_b",
			"background_seaweed_a", "background_seaweed_b", "background_seaweed_c", "background_seaweed_d",
			"terrain_sand_top_a", "terrain_sand_top_b", "terrain_sand_a"]:
		var t := load(TEX_DIR + n + ".png") as Texture2D
		if t != null:
			_tex[n] = t
	_rope = Noc.Rope.new(ROPE_POINTS, ROD_TIP, ROD_TIP)
	_build_bed()


## Lays out the seabed once: sand tiles, rocks, seaweed and background props, with sway phases.
func _build_bed() -> void:
	var weeds := ["seaweed_green_a", "seaweed_green_b", "seaweed_green_c", "seaweed_green_d", "seaweed_grass_a",
		"seaweed_grass_b", "seaweed_orange_a", "seaweed_orange_b", "seaweed_pink_a", "seaweed_pink_b", "rock_a", "rock_b"]
	var backs := ["background_rock_a", "background_rock_b", "background_seaweed_a", "background_seaweed_b",
		"background_seaweed_c", "background_seaweed_d"]
	var x := 330.0
	while x < W + 60.0:
		_bed_items.append({"name": backs[_rng.randi() % backs.size()], "x": x + _rng.randf_range(-20.0, 20.0),
			"scale": _rng.randf_range(0.8, 1.3), "back": true, "phase": _rng.randf() * TAU})
		x += _rng.randf_range(70.0, 130.0)
	x = 360.0
	while x < W + 60.0:
		_bed_items.append({"name": weeds[_rng.randi() % weeds.size()], "x": x, "scale": _rng.randf_range(0.6, 1.0),
			"back": false, "phase": _rng.randf() * TAU})
		x += _rng.randf_range(60.0, 140.0)


## Starts the side view for a freshly hooked fish.
func begin(fish_id: String, weight_kg: float, cast_dist_m: float) -> void:
	var sp: Dictionary = BiomeDB.get_species(fish_id)
	var look: Array = FISH_SPRITES.get(fish_id, ["fish_blue", Color.WHITE])
	_fish_tex = _tex.get(look[0], null)
	_fish_tint = look[1]
	_fish_len = 60.0 + sqrt(maxf(weight_kg, 0.01)) * 45.0
	var dr: Vector2 = sp.get("depth_m", Vector2(1.0, 10.0))
	_depth_range = Vector2(clampf(dr.x, 0.5, MAX_DEPTH_M - 2.0), clampf(dr.y, 2.0, MAX_DEPTH_M - 1.0))
	_depth_m = clampf(lerpf(_depth_range.x, _depth_range.y, 0.3), 1.0, MAX_DEPTH_M - 1.0)
	_depth_v = 0.0
	_view_m = maxf(25.0, cast_dist_m * 1.25)
	_fish_pos = Vector2(_x_for(cast_dist_m), _y_for(_depth_m))
	_rope.reset(ROPE_POINTS, ROD_TIP, _fish_pos)
	_bubbles.clear()
	_small_fish.clear()
	for i in 5:
		var v := Noc.Vehicle.new(Vector2(_rng.randf_range(450.0, 1200.0), _rng.randf_range(260.0, 580.0)), 50.0, 60.0)
		var names := ["fish_grey", "fish_blue", "fish_green", "fish_pink"]
		v.data = {"tex": names[i % names.size()], "scale": _rng.randf_range(0.28, 0.42)}
		_small_fish.append(v)
	_active = true
	_canvas.visible = true


## Fades the side view out (the top-down scene shows the result).
func end() -> void:
	_active = false
	_catch_t = 0.0


## Landed: lift the fish out of the water and show a catch card, then fade out on its own.
func show_catch(title: String, lines: PackedStringArray) -> void:
	_catch_title = title
	_catch_lines = lines
	_catch_t = 3.4
	_lift_v = Vector2.ZERO
	_active = true
	_card.bg_color = Color(0.02, 0.10, 0.18, 0.92)
	_card.set_corner_radius_all(18)
	_card.set_border_width_all(3)
	_card.border_color = Color(1.0, 0.85, 0.4, 0.9)


func _x_for(dist_m: float) -> float:
	return ROD_TIP.x + 40.0 + dist_m * (W - ROD_TIP.x - 120.0) / _view_m


func _y_for(depth_m: float) -> float:
	return SURFACE_Y + 12.0 + depth_m / MAX_DEPTH_M * (BED_Y - SURFACE_Y - 40.0)


func _process(delta: float) -> void:
	_alpha = move_toward(_alpha, 1.0 if _active else 0.0, delta * 3.0)
	if _alpha <= 0.0:
		_canvas.visible = false
		return
	_canvas.visible = true
	_time += delta
	_canvas.modulate = Color(tint.r, tint.g, tint.b, _alpha)
	if _catch_t > 0.0:
		_catch_t -= delta
		_animate_catch(delta)
		if _catch_t <= 0.0:
			_active = false
	elif fishing != null and _active:
		_simulate(delta)
	_update_bubbles(delta)
	_canvas.queue_redraw()


func _simulate(delta: float) -> void:
	var dist := fishing.fish_pos_m
	_view_m = lerpf(_view_m, maxf(25.0, dist * 1.25), delta * 1.5)

	# Target depth: Perlin drift inside the species' range, deeper on runs, rising as it tires
	# and as it nears the bank.
	var drift := 0.5 + 0.5 * _noise.get_noise_1d(_time * 4.0)
	var target := lerpf(_depth_range.x, _depth_range.y, drift)
	var running := fishing._burst_mult > 1.0
	if running:
		target += 4.0
	target = lerpf(1.0, target, clampf(fishing.stamina * 1.4, 0.0, 1.0))
	if dist < 4.0:
		target = lerpf(0.3, target, dist / 4.0)
	target = clampf(target, 0.3, MAX_DEPTH_M - 1.0)
	var r := Noc.spring_step(_depth_m, _depth_v, target, 6.0 if running else 2.5, 2.2, delta)
	_depth_m = r.x
	_depth_v = r.y

	var new_pos := Vector2(_x_for(dist), _y_for(_depth_m))
	var vel := (new_pos - _fish_pos) / maxf(delta, 0.0001)
	if absf(vel.x) > 8.0:
		_facing = signf(vel.x)
	_tilt = lerpf(_tilt, clampf(atan2(vel.y, maxf(absf(vel.x), 30.0)), -0.6, 0.6), delta * 5.0)
	_fish_pos = new_pos
	if running and _rng.randf() < delta * 14.0:
		_spawn_bubble(_fish_pos + Vector2(-_facing * _fish_len * 0.3, 0.0), 1.0)
	elif _rng.randf() < delta * 2.0:
		_spawn_bubble(_fish_pos, 0.6)

	var ratio := fishing.tension_n / maxf(fishing.line_break_force_n, 0.001)
	_rod_bend = lerpf(_rod_bend, clampf(ratio, 0.0, 1.2), delta * 8.0)
	var mouth := _fish_pos + Vector2(_facing * _fish_len * 0.42, 0.0)
	var slack := (1.0 - clampf(ratio * 2.5, 0.0, 1.0)) * 0.12
	var length := _rod_tip_now().distance_to(mouth) * (1.0 + slack)
	_rope.step(_rod_tip_now(), mouth, length, Vector2(0.0, 380.0) * (0.2 + slack * 6.0), delta)

	var area := Rect2(380.0, SURFACE_Y + 40.0, W - 400.0, BED_Y - SURFACE_Y - 80.0)
	for f in _small_fish:
		f.apply_force(f.wander(delta, 30.0, 12.0, 3.0) * 0.6)
		f.apply_force(f.flee(_fish_pos, 220.0) * 2.0)
		f.apply_force(f.contain(area, 60.0))
		f.update(delta)


## Spring pull toward the angler's hand (Hooke), a flapping oscillation, and water dripping off
## the fish as particles under gravity.
func _animate_catch(delta: float) -> void:
	var target := HAND + Vector2(80.0, -36.0)
	var acc := (target - _fish_pos) * 30.0 - _lift_v * 8.0
	_lift_v += acc * delta
	_fish_pos += _lift_v * delta
	_facing = -1.0
	_tilt = sin(_time * 14.0) * 0.35 * clampf(_catch_t / 3.4, 0.2, 1.0)
	_rod_bend = lerpf(_rod_bend, 0.5, delta * 4.0)
	if _rng.randf() < delta * 18.0 and _fish_pos.y < SURFACE_Y:
		_drips.append(Noc.Particle.new(_fish_pos + Vector2(_rng.randf_range(-_fish_len * 0.3, _fish_len * 0.3), 6.0),
			Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(0.0, 40.0)), 0.0, 0.0, 1.2, _rng.randf_range(2.0, 4.0), Color(0.8, 0.95, 1.0, 0.9)))
	var keep: Array = []
	for d in _drips:
		d.vel += Vector2(0.0, 700.0) * delta
		d.pos += d.vel * delta
		d.age += delta
		if not d.dead() and d.pos.y < SURFACE_Y + 4.0:
			keep.append(d)
	_drips = keep
	var mouth := _fish_pos + Vector2(_facing * _fish_len * 0.42, 0.0)
	_rope.step(_rod_tip_now(), mouth, _rod_tip_now().distance_to(mouth), Vector2(0.0, 200.0), delta)


func _rod_tip_now() -> Vector2:
	return ROD_TIP + Vector2(_rod_bend * 18.0, _rod_bend * 42.0)


## Bubbles rise: a particle whose "gravity" is negative (buoyancy), wobbling as it goes.
func _spawn_bubble(pos: Vector2, size: float) -> void:
	if _bubbles.size() > 60:
		return
	var b := Noc.Particle.new(pos, Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-40.0, -20.0)), 0.0, 0.0,
		_rng.randf_range(1.5, 3.0), _rng.randf_range(10.0, 22.0) * size, Color(1.0, 1.0, 1.0, 0.8))
	_bubbles.append(b)


func _update_bubbles(delta: float) -> void:
	var alive: Array = []
	for b in _bubbles:
		b.vel += Vector2(sin(_time * 6.0 + b.size) * 20.0, -60.0) * delta
		b.vel *= 1.0 - 1.2 * delta
		b.pos += b.vel * delta
		b.age += delta
		if not b.dead() and b.pos.y > SURFACE_Y:
			alive.append(b)
	_bubbles = alive


# ---------------------------------------------------------------- drawing
func _draw_view() -> void:
	var c := _canvas
	var night := 1.0 - daylight
	var sky_top := Color(0.45, 0.70, 0.92).lerp(Color(0.03, 0.05, 0.14), night)
	var sky_low := Color(0.86, 0.93, 1.0).lerp(Color(0.10, 0.12, 0.26), night)
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, SURFACE_Y), Vector2(0, SURFACE_Y)]),
		PackedColorArray([sky_top, sky_top, sky_low, sky_low]))
	var hills := Color(0.35, 0.45, 0.42).lerp(Color(0.08, 0.10, 0.16), night)
	var hp := PackedVector2Array([Vector2(W, SURFACE_Y), Vector2(500, SURFACE_Y)])
	var hx := 500.0
	while hx <= W:
		hp.append(Vector2(hx, SURFACE_Y - 22.0 - 16.0 * sin(hx * 0.011) - 10.0 * sin(hx * 0.031)))
		hx += 40.0
	c.draw_colored_polygon(hp, hills)

	var w: Dictionary = spot.get("water", {})
	var shallow: Color = w.get("shallow", Color(0.12, 0.78, 0.82))
	var deep: Color = w.get("deep", Color(0.01, 0.08, 0.26))
	c.draw_polygon(PackedVector2Array([Vector2(0, SURFACE_Y), Vector2(W, SURFACE_Y), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([shallow, shallow, deep, deep]))

	# Light shafts from the surface, swaying slowly.
	for i in 4:
		var sx := 420.0 + float(i) * 230.0 + sin(_time * 0.4 + float(i)) * 40.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(sx, SURFACE_Y), Vector2(sx + 60.0, SURFACE_Y),
			Vector2(sx + 160.0, BED_Y), Vector2(sx + 40.0, BED_Y)]), Color(1.0, 1.0, 0.9, 0.06 * daylight))

	for item in _bed_items:
		if bool(item["back"]):
			_draw_prop(item, Color(0.55, 0.75, 0.85, 0.55))
	for f in _small_fish:
		var tx: Texture2D = _tex.get(f.data["tex"], null)
		if tx != null:
			var s: float = f.data["scale"]
			_draw_sprite(tx, f.pos, Vector2(s * signf(f.vel.x if absf(f.vel.x) > 1.0 else 1.0), s), 0.0, Color(0.6, 0.8, 0.9, 0.5))

	var top: Texture2D = _tex.get("terrain_sand_top_a", null)
	var fill: Texture2D = _tex.get("terrain_sand_a", null)
	var tx2 := 330.0
	while tx2 < W:
		if top != null:
			c.draw_texture_rect(top, Rect2(tx2, BED_Y - 20.0, 64.0, 64.0), false)
		if fill != null:
			c.draw_texture_rect(fill, Rect2(tx2, BED_Y + 44.0, 64.0, 64.0), false)
		tx2 += 64.0
	for item in _bed_items:
		if not bool(item["back"]):
			_draw_prop(item, Color.WHITE)

	_draw_shore()
	c.draw_polyline(_rope.pts, Color(1.0, 1.0, 1.0, 0.9), 2.0, true)
	if _fish_tex != null:
		var sc := _fish_len / 110.0
		_draw_sprite(_fish_tex, _fish_pos, Vector2(sc * _facing, sc), _tilt * _facing, _fish_tint)
	for b in _bubbles:
		var bt: Texture2D = _tex.get("bubble_a", null)
		if bt != null:
			var k := 1.0 - clampf(float(b.age) / float(b.life), 0.0, 1.0)
			var bs: float = b.size / 64.0
			_draw_sprite(bt, b.pos, Vector2(bs, bs), 0.0, Color(1.0, 1.0, 1.0, 0.85 * k))

	for d in _drips:
		_canvas.draw_circle(d.pos, float(d.size), Color(0.8, 0.95, 1.0, 0.85))
	var surf := PackedVector2Array()
	var x := 0.0
	while x <= W:
		surf.append(Vector2(x, SURFACE_Y + sin(x * 0.03 + _time * 2.0) * 3.0 + sin(x * 0.011 - _time) * 2.0))
		x += 16.0
	c.draw_polyline(surf, Color(1.0, 1.0, 1.0, 0.7), 3.0, true)
	_draw_angler()
	if _catch_t > 0.0:
		_draw_card()


func _draw_card() -> void:
	var appear := clampf((3.4 - _catch_t) * 4.0, 0.0, 1.0)
	var rect := Rect2(Vector2(660.0, 230.0 + (1.0 - appear) * 40.0), Vector2(520.0, 230.0))
	_card.draw(_canvas.get_canvas_item(), rect)
	var font := ThemeDB.fallback_font
	_canvas.draw_string(font, rect.position + Vector2(24.0, 50.0), _catch_title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 48.0, 30, Color(1.0, 0.92, 0.6))
	for i in _catch_lines.size():
		_canvas.draw_string(font, rect.position + Vector2(24.0, 96.0 + float(i) * 34.0), _catch_lines[i], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 200.0, 22, Color.WHITE)
	if _fish_tex != null:
		var big := minf(1.6, 150.0 / 110.0)
		_draw_sprite(_fish_tex, rect.position + Vector2(rect.size.x - 100.0, 130.0), Vector2(big, big), sin(_time * 3.0) * 0.08, _fish_tint)


## Seaweed and rocks stand on the bed; seaweed sways on a sine oscillator around its base.
func _draw_prop(item: Dictionary, col: Color) -> void:
	var tx: Texture2D = _tex.get(item["name"], null)
	if tx == null:
		return
	var s: float = item["scale"]
	var prop_name: String = item["name"]
	var sway := 0.0 if prop_name.contains("rock") else sin(_time * 1.2 + float(item["phase"])) * 0.12
	var base := Vector2(float(item["x"]), BED_Y + 4.0)
	_canvas.draw_set_transform(base, sway, Vector2(s, s))
	_canvas.draw_texture(tx, Vector2(-tx.get_width() * 0.5, -tx.get_height()), col)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_sprite(tx: Texture2D, center: Vector2, scl: Vector2, rot: float, col: Color) -> void:
	_canvas.draw_set_transform(center, rot, scl)
	_canvas.draw_texture(tx, -tx.get_size() * 0.5, col)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_shore() -> void:
	var land: Color = spot.get("shore_color", Color(0.6, 0.55, 0.45))
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 150), Vector2(130, 158), Vector2(185, SURFACE_Y + 4.0),
		Vector2(250, 330), Vector2(330, 520), Vector2(380, H), Vector2(0, H)]), land.darkened(0.15))
	_canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, 150), Vector2(130, 158), Vector2(185, SURFACE_Y + 4.0),
		Vector2(0, SURFACE_Y + 4.0)]), land)
	_canvas.draw_line(Vector2(0, 150), Vector2(130, 158), land.lightened(0.2), 4.0)


func _draw_angler() -> void:
	var c := _canvas
	c.draw_circle(HAND + Vector2(-14.0, 6.0), 17.0, Color(0.15, 0.30, 0.55))
	c.draw_rect(Rect2(HAND + Vector2(-26.0, 10.0), Vector2(24.0, 22.0)), Color(0.20, 0.22, 0.30))
	c.draw_circle(HAND + Vector2(-14.0, -22.0), 11.0, Color(0.93, 0.75, 0.6))
	c.draw_circle(HAND + Vector2(-14.0, -28.0), 10.0, Color(0.9, 0.3, 0.2))
	var tip := _rod_tip_now()
	var ctrl := HAND.lerp(ROD_TIP, 0.55) + Vector2(0.0, _rod_bend * 14.0)
	var rod := PackedVector2Array()
	for i in 11:
		var t := float(i) / 10.0
		rod.append(HAND.lerp(ctrl, t).lerp(ctrl.lerp(tip, t), t))
	c.draw_polyline(rod, Color(0.20, 0.13, 0.08), 6.0, true)
	c.draw_polyline(rod, Color(0.55, 0.40, 0.25), 2.5, true)
