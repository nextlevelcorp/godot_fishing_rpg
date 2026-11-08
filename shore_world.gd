## The living world behind the angler: a small coastal town styled per sea, a day-night cycle,
## and Nature of Code agents (people strolling, cats, a flock of gulls).
##
## Layers:
##   _static  ground, promenade, houses, benches (drawn once)
##   _dyn     trees swaying (oscillation), walkers and cats (steering agents), redrawn each frame
##   _sky     gull flock and its shadows, above everything else in the world
##   _glow    lamps and lit windows in an additive CanvasLayer that the night tint does not darken
##
## The parent reads `daylight` and tint() to grade the whole scene and the water.
class_name ShoreWorld
extends Node2D

const WALKERS := 34
const CATS := 7
const GULLS := 12
## Half the width of the town in px; matches ShoreFishing.HALF_WIDTH.
const HALF := 4000.0
const PANTS := [Color(0.20, 0.22, 0.30), Color(0.35, 0.30, 0.25), Color(0.15, 0.15, 0.17), Color(0.45, 0.42, 0.38)]
const HAIR := [Color(0.15, 0.10, 0.08), Color(0.35, 0.22, 0.12), Color(0.55, 0.50, 0.45), Color(0.08, 0.07, 0.07)]
const SKIN := [Color(0.92, 0.74, 0.58), Color(0.80, 0.60, 0.45), Color(0.65, 0.47, 0.33)]
const NIGHT := Color(0.30, 0.36, 0.60)
const DUSK := Color(1.0, 0.70, 0.52)
const CLOTHES := [
	Color(0.85, 0.25, 0.22), Color(0.20, 0.45, 0.80), Color(0.95, 0.75, 0.20), Color(0.25, 0.65, 0.40),
	Color(0.55, 0.30, 0.60), Color(0.92, 0.92, 0.90), Color(0.15, 0.15, 0.20), Color(0.95, 0.50, 0.30),
]

@export var day_length_s := 480.0
## 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
@export_range(0.0, 1.0) var time_of_day := 0.30

var daylight := 1.0
var spot: Dictionary = {}
## Set by the shore scene each frame: cloud shadows drift with it.
var wind := Vector2(20.0, 0.0)
## Camera x, set by the parent every frame. Things farther than CULL_RADIUS from it are not drawn
## (the world is 8000 px wide, the screen shows at most about 1900 px).
var view_x := 0.0
const CULL_RADIUS := 1300.0
## Half the world width the camera shows, plus a margin; set by the shore scene each frame (it follows
## the zoom and the screen shape). Used instead of CULL_RADIUS when set.
var view_half := CULL_RADIUS
var _frame := 0

var _kind := ""
var _clouds: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _pal: Dictionary = {}
var _town_y0 := 215.0
var _time := 0.0
var _buildings: Array[Dictionary] = []
var _trees: Array[Dictionary] = []
var _lamps: Array[Vector2] = []
var _benches: Array[Vector2] = []
var _domes: Array[Dictionary] = []
var _walkers: Array = []
var _cats: Array = []
var _gulls: Array = []
var _glow_level := -1.0

var _static: Node2D
var _dyn: Node2D
var _sky: Node2D
var _glow: Node2D
var _glow_layer: CanvasLayer
var _glow_x := INF                     ## view_x at the last glow redraw


## Call before adding the node to the tree.
func setup(p_spot: Dictionary, seed_value: int) -> void:
	spot = p_spot
	_rng.seed = seed_value
	_pal = _palette()
	var kind: String = spot.get("kind", "rocky")
	_kind = kind
	_town_y0 = {"bridge": 430.0, "harbor": 150.0, "beach": 240.0}.get(kind, 215.0)
	for i in 12:
		var puffs: Array[Vector3] = []
		for j in 5:
			puffs.append(Vector3(_rng.randf_range(-160.0, 160.0), _rng.randf_range(-70.0, 70.0), _rng.randf_range(90.0, 170.0)))
		_clouds.append({"pos": Vector2(_rng.randf_range(-HALF, HALF), _rng.randf_range(-1100.0, 700.0)), "puffs": puffs})
	_build_town()
	_spawn_life()


func _ready() -> void:
	_static = Node2D.new()
	_static.draw.connect(_draw_static)
	add_child(_static)
	_dyn = Node2D.new()
	_dyn.draw.connect(_draw_dyn)
	add_child(_dyn)
	_sky = Node2D.new()
	_sky.z_index = 10
	_sky.draw.connect(_draw_sky)
	add_child(_sky)

	var glow_layer := CanvasLayer.new()
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	_glow_layer = glow_layer
	_glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	glow_layer.add_child(_glow)


## Colour grade for the whole scene: night blue, a warm dusk band, the sea's own tint by day.
func tint(day_color: Color) -> Color:
	var sun := sin((time_of_day - 0.25) * TAU)
	var dusk := clampf(1.0 - absf(sun) * 3.0, 0.0, 1.0)
	return NIGHT.lerp(day_color, daylight).lerp(DUSK, dusk * 0.35)


## "HH:MM" for the HUD.
func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


# ---------------------------------------------------------------- per-sea look
func _palette() -> Dictionary:
	var region: String = spot.get("region", "")
	if region.contains("Black Sea"):
		return {"walls": [Color(0.62, 0.45, 0.30), Color(0.70, 0.55, 0.38), Color(0.92, 0.90, 0.85)],
			"roofs": [Color(0.34, 0.37, 0.44), Color(0.45, 0.30, 0.25)], "trim": Color(0.25, 0.35, 0.30),
			"ground": Color(0.34, 0.50, 0.28), "path": Color(0.55, 0.55, 0.52), "tree": Color(0.16, 0.40, 0.20), "tree_kind": "round"}
	if region.contains("Mediterranean"):
		return {"walls": [Color(0.98, 0.95, 0.88), Color(0.96, 0.88, 0.74)],
			"roofs": [Color(0.82, 0.45, 0.30), Color(0.76, 0.40, 0.28)], "trim": Color(0.85, 0.30, 0.55),
			"ground": Color(0.80, 0.72, 0.54), "path": Color(0.88, 0.84, 0.74), "tree": Color(0.30, 0.55, 0.30), "tree_kind": "palm"}
	if region.contains("Istanbul"):
		return {"walls": [Color(0.86, 0.62, 0.58), Color(0.90, 0.78, 0.52), Color(0.55, 0.70, 0.72), Color(0.92, 0.90, 0.86)],
			"roofs": [Color(0.45, 0.42, 0.42), Color(0.70, 0.38, 0.28)], "trim": Color(0.30, 0.30, 0.35),
			"ground": Color(0.52, 0.52, 0.50), "path": Color(0.66, 0.64, 0.60), "tree": Color(0.26, 0.46, 0.24), "tree_kind": "round", "skyline": true}
	return {"walls": [Color(0.97, 0.97, 0.95), Color(0.95, 0.93, 0.86)],
		"roofs": [Color(0.80, 0.42, 0.30), Color(0.93, 0.93, 0.90)], "trim": Color(0.15, 0.40, 0.75),
		"ground": Color(0.78, 0.72, 0.56), "path": Color(0.90, 0.88, 0.82), "tree": Color(0.48, 0.56, 0.40), "tree_kind": "olive"}


func _build_town() -> void:
	var walls: Array = _pal["walls"]
	var roofs: Array = _pal["roofs"]
	var lx := -HALF + 150.0
	while lx <= HALF - 150.0:
		_lamps.append(Vector2(lx, _town_y0 + 10.0))
		if _rng.randf() < 0.5:
			_benches.append(Vector2(lx + 90.0, _town_y0 + 30.0))
		lx += 220.0
	for row in 3:
		var y := _town_y0 + 80.0 + float(row) * 150.0
		var x := -HALF + 50.0 + _rng.randf_range(0.0, 60.0)
		var since_street := 0
		while x < HALF - 50.0:
			if since_street >= 4 and _rng.randf() < 0.5:
				_trees.append({"pos": Vector2(x + 30.0, y + 50.0), "r": _rng.randf_range(22.0, 34.0), "phase": _rng.randf() * TAU})
				x += 70.0
				since_street = 0
				continue
			var w := _rng.randf_range(90.0, 150.0)
			var h := _rng.randf_range(80.0, 115.0)
			var wins: Array[bool] = []
			for i in int(w / 34.0):
				wins.append(_rng.randf() < 0.6)
			_buildings.append({
				"rect": Rect2(x, y, w, h),
				"wall": walls[_rng.randi() % walls.size()],
				"roof": roofs[_rng.randi() % roofs.size()],
				"lit": wins,
			})
			x += w + _rng.randf_range(10.0, 28.0)
			since_street += 1
	for i in 64:
		_trees.append({"pos": Vector2(_rng.randf_range(-HALF + 100.0, HALF - 100.0), _town_y0 + _rng.randf_range(62.0, 72.0)),
			"r": _rng.randf_range(18.0, 28.0), "phase": _rng.randf() * TAU})
	if _pal.get("skyline", false):
		for i in 3:
			_domes.append({"pos": Vector2(-2200.0 + float(i) * 2200.0 + _rng.randf_range(-200.0, 200.0), _town_y0 + 560.0), "r": _rng.randf_range(55.0, 80.0)})


func _spawn_life() -> void:
	var band := _walk_band()
	for i in WALKERS:
		var v := Noc.Vehicle.new(Vector2(_rng.randf_range(band.position.x, band.end.x), _rng.randf_range(band.position.y, band.end.y)), _rng.randf_range(20.0, 36.0), 30.0)
		v.data = {"color": CLOTHES[_rng.randi() % CLOTHES.size()], "pause": 0.0, "step": _rng.randf() * TAU, "k": _rng.randi() % 24}
		_walkers.append(v)
	for i in CATS:
		var c := Noc.Vehicle.new(Vector2(_rng.randf_range(-HALF + 300.0, HALF - 300.0), _town_y0 + _rng.randf_range(20.0, 60.0)), 45.0, 70.0)
		c.data = {"color": [Color(0.95, 0.60, 0.25), Color(0.30, 0.30, 0.32), Color(0.92, 0.90, 0.86)][i % 3], "phase": _rng.randf() * TAU}
		_cats.append(c)
	for i in GULLS:
		var g := Noc.Vehicle.new(Vector2(_rng.randf_range(-HALF + 500.0, HALF - 500.0), _rng.randf_range(-700.0, -300.0)), 95.0, 60.0)
		g.data = {"phase": _rng.randf() * TAU}
		_gulls.append(g)


## Where people stroll: the bridge deck on Galata (it is busy with pedestrians), else the promenade.
func _walk_band() -> Rect2:
	if _kind == "bridge":
		return Rect2(-HALF + 200.0, 50.0, HALF * 2.0 - 400.0, 48.0)
	return Rect2(-HALF + 200.0, _town_y0 + 4.0, HALF * 2.0 - 400.0, 48.0)


# ---------------------------------------------------------------- simulation
func _process(delta: float) -> void:
	_time += delta
	time_of_day = fmod(time_of_day + delta / day_length_s, 1.0)
	daylight = clampf(sin((time_of_day - 0.25) * TAU) * 1.6 + 0.45, 0.0, 1.0)

	# A CanvasLayer does not hide with its parent: hide the night glow with the world.
	if _glow_layer.visible != visible:
		_glow_layer.visible = visible
	if not visible:
		return                      # hidden behind the first-person view: only the clock runs
	var band := _walk_band()
	_frame += 1
	if _frame % 2 == 0:
		Noc.flock(_walkers, 20.0, 1.0, 1.4, 0.0, 0.0)     # O(n^2): every other frame is enough for strolling
	for v in _walkers:
		v.data["pause"] = float(v.data["pause"]) - delta
		if float(v.data["pause"]) > 0.0:
			v.apply_force(-v.vel * 2.0)               # standing still: brake
		else:
			v.apply_force(v.wander(delta, 30.0, 12.0, 2.5))
			if _rng.randf() < delta * 0.08:
				v.data["pause"] = _rng.randf_range(1.5, 5.0)
		v.apply_force(v.contain(band, 8.0))
		v.update(delta)
		v.data["step"] = float(v.data["step"]) + v.vel.length() * delta * 0.25

	var cat_area := Rect2(-HALF + 300.0, _town_y0, HALF * 2.0 - 600.0, 70.0)
	for c in _cats:
		c.apply_force(c.wander(delta, 24.0, 14.0, 4.0) * 0.7)
		for v in _walkers:
			c.apply_force(c.flee(v.pos, 55.0) * 2.0)
		c.apply_force(c.contain(cat_area, 10.0))
		c.update(delta)

	var sky := Rect2(-HALF + 300.0, -1200.0, HALF * 2.0 - 600.0, 1300.0)
	Noc.flock(_gulls, 45.0, 180.0, 1.6, 0.9, 0.6)
	for g in _gulls:
		g.apply_force(g.wander(delta, 60.0, 30.0, 2.0) * 0.6)
		g.apply_force(g.contain(sky, 160.0))
		g.update(delta)

	for cl in _clouds:
		var p: Vector2 = cl["pos"]
		p += (wind * 0.6 + Vector2(14.0, 0.0)) * delta
		if p.x > HALF + 300.0:
			p.x = -HALF - 300.0
		elif p.x < -HALF - 300.0:
			p.x = HALF + 300.0
		cl["pos"] = p

	_dyn.queue_redraw()
	_sky.queue_redraw()
	var glow := 1.0 - daylight
	if absf(glow - _glow_level) > 0.02 or (glow > 0.01 and absf(view_x - _glow_x) > 200.0):
		_glow_level = glow
		_glow_x = view_x
		_glow.queue_redraw()


# ---------------------------------------------------------------- drawing
func _draw_static() -> void:
	var ground: Color = _pal["ground"]
	var path: Color = _pal["path"]
	_static.draw_rect(Rect2(-HALF - 200.0, _town_y0, HALF * 2.0 + 400.0, 1100.0), ground)
	_static.draw_rect(Rect2(-HALF - 200.0, _town_y0, HALF * 2.0 + 400.0, 56.0), path)
	var tx := -HALF - 200.0
	while tx < HALF + 200.0:
		_static.draw_line(Vector2(tx, _town_y0), Vector2(tx, _town_y0 + 56.0), path.darkened(0.08), 1.0)
		tx += 40.0
	_static.draw_line(Vector2(-HALF - 200.0, _town_y0 + 56.0), Vector2(HALF + 200.0, _town_y0 + 56.0), path.darkened(0.2), 3.0)
	for b in _benches:
		_static.draw_rect(Rect2(b + Vector2(3.0, 4.0), Vector2(46.0, 12.0)), Color(0.0, 0.0, 0.0, 0.2))
		_static.draw_rect(Rect2(b, Vector2(46.0, 12.0)), Color(0.50, 0.32, 0.18))
		_static.draw_line(b + Vector2(0.0, 4.0), b + Vector2(46.0, 4.0), Color(0.62, 0.42, 0.24), 2.0)
	for d in _domes:
		_draw_dome(d["pos"], d["r"])
	for bd in _buildings:
		_draw_building(bd)
	var trim: Color = _pal["trim"]
	for l in _lamps:
		# Street lamp standing up: shadow, post, lantern.
		_static.draw_line(l + Vector2(2.0, 0.0), l + Vector2(16.0, 6.0), Color(0.0, 0.0, 0.0, 0.2), 4.0)
		_static.draw_line(l, l + Vector2(0.0, -38.0), trim.darkened(0.4), 3.0)
		_static.draw_rect(Rect2(l + Vector2(-5.0, -48.0), Vector2(10.0, 11.0)), trim.darkened(0.3))
		_static.draw_rect(Rect2(l + Vector2(-3.0, -46.0), Vector2(6.0, 7.0)), Color(1.0, 0.95, 0.75))


func _draw_building(bd: Dictionary) -> void:
	var r: Rect2 = bd["rect"]
	var wall: Color = bd["wall"]
	var roof: Color = bd["roof"]
	var trim: Color = _pal["trim"]
	_static.draw_rect(Rect2(r.position + Vector2(9.0, 11.0), r.size), Color(0.0, 0.0, 0.0, 0.22))
	var roof_h := r.size.y * 0.62
	var front := Rect2(r.position.x, r.position.y + roof_h, r.size.x, r.size.y - roof_h)
	_static.draw_rect(front, wall.darkened(0.06))
	_static.draw_rect(Rect2(r.position, Vector2(r.size.x, roof_h)), roof)
	_static.draw_rect(Rect2(r.position, Vector2(r.size.x, roof_h * 0.5)), roof.lightened(0.10))
	_static.draw_line(Vector2(r.position.x, r.position.y + roof_h), Vector2(r.end.x, r.position.y + roof_h), roof.darkened(0.35), 3.0)
	var wins: Array = bd["lit"]
	var n := wins.size()
	for i in n:
		var wx := r.position.x + (float(i) + 0.5) * r.size.x / float(n) - 7.0
		var wr := Rect2(wx, front.position.y + 7.0, 14.0, 14.0)
		_static.draw_rect(wr, Color(0.12, 0.16, 0.24))
		_static.draw_rect(wr, trim, false, 2.0)
	var door := Rect2(r.position.x + r.size.x * 0.5 - 9.0, r.end.y - 22.0, 18.0, 22.0)
	_static.draw_rect(door, trim.darkened(0.2))


func _draw_dome(p: Vector2, radius: float) -> void:
	_static.draw_circle(p + Vector2(12.0, 14.0), radius, Color(0.0, 0.0, 0.0, 0.2))
	_static.draw_circle(p, radius, Color(0.55, 0.58, 0.62))
	_static.draw_circle(p + Vector2(-radius * 0.25, -radius * 0.25), radius * 0.55, Color(0.66, 0.69, 0.73))
	_static.draw_circle(p, 6.0, Color(0.85, 0.75, 0.40))
	for side in [-1.0, 1.0]:
		var base: Vector2 = p + Vector2(side * (radius + 60.0), 20.0)
		_static.draw_rect(Rect2(base + Vector2(-5.0, -150.0), Vector2(10.0, 150.0)), Color(0.86, 0.85, 0.82))
		_static.draw_colored_polygon(PackedVector2Array([base + Vector2(-7.0, -150.0), base + Vector2(7.0, -150.0), base + Vector2(0.0, -185.0)]), Color(0.55, 0.58, 0.62))


func _draw_dyn() -> void:
	var tree_col: Color = _pal["tree"]
	var kind: String = _pal["tree_kind"]
	for t in _trees:
		var p: Vector2 = t["pos"]
		var rad: float = t["r"]
		if absf(p.x - view_x) > view_half + rad * 2.0:
			continue
		var sway := Vector2(sin(_time * 1.3 + float(t["phase"])) * rad * 0.10, 0.0)
		# Three-quarter view: a shadow on the ground, a trunk standing up, the crown above it.
		_dyn.draw_circle(p + Vector2(rad * 0.4, rad * 0.25), rad * 0.9, Color(0.0, 0.0, 0.0, 0.16))
		_dyn.draw_line(p, p + Vector2(0.0, -rad * 1.1), Color(0.40, 0.27, 0.16), maxf(4.0, rad * 0.22))
		p = p + Vector2(0.0, -rad * 1.3)
		if kind == "palm":
			for i in 7:
				var a := TAU * float(i) / 7.0 + float(t["phase"])
				var tip := p + sway + Vector2.from_angle(a) * rad * 1.3
				_dyn.draw_line(p + sway * 0.3, tip, tree_col, 5.0)
				_dyn.draw_line(p + sway * 0.3, tip, tree_col.lightened(0.2), 2.0)
		elif kind == "olive":
			for i in 3:
				var off := Vector2.from_angle(TAU * float(i) / 3.0 + float(t["phase"])) * rad * 0.35
				_dyn.draw_circle(p + sway + off, rad * 0.62, tree_col.darkened(0.05 * float(i)))
			_dyn.draw_circle(p + sway + Vector2(-rad * 0.2, -rad * 0.25), rad * 0.3, tree_col.lightened(0.18))
		else:
			_dyn.draw_circle(p + sway, rad, tree_col)
			_dyn.draw_circle(p + sway + Vector2(-rad * 0.25, -rad * 0.3), rad * 0.55, tree_col.lightened(0.15))

	for c in _cats:
		if absf(c.pos.x - view_x) > view_half:
			continue
		var col: Color = c.data["color"]
		Figure.draw_cat(_dyn, c.pos, 1.0 if c.vel.x >= 0.0 else -1.0, _time + float(c.data["phase"]), col)

	for v in _walkers:
		if absf(v.pos.x - view_x) > view_half:
			continue
		var col2: Color = v.data["color"]
		var k := int(v.data.get("k", 0))
		var look := {"shirt": col2, "pants": PANTS[k % PANTS.size()], "hair": HAIR[k % HAIR.size()],
			"skin": SKIN[k % SKIN.size()]}
		if k % 4 == 0:
			look["hat"] = Color(0.85, 0.80, 0.65)
		Figure.draw_person(_dyn, v.pos, v.vel.normalized() if v.vel.length() > 1.0 else Vector2.DOWN, float(v.data["step"]), v.vel.length() > 4.0, look, 1.15)


func _draw_sky() -> void:
	var shade := 0.07 * daylight
	if shade > 0.005:
		for cl in _clouds:
			var cp: Vector2 = cl["pos"]
			if absf(cp.x - view_x) > view_half + 600.0:
				continue
			for pf: Vector3 in cl["puffs"]:
				_sky.draw_circle(cp + Vector2(pf.x, pf.y), pf.z, Color(0.0, 0.05, 0.12, shade))
	for g in _gulls:
		if absf(g.pos.x - view_x) > view_half:
			continue
		var fl := sin(_time * 7.0 + float(g.data["phase"])) * 7.0
		var h: Vector2 = g.heading()
		var s := h.orthogonal()
		var p: Vector2 = g.pos
		var sh := p + Vector2(40.0, 90.0)
		_sky.draw_polyline(PackedVector2Array([sh - s * 14.0 - h * fl * 0.4, sh, sh + s * 14.0 - h * fl * 0.4]), Color(0.0, 0.0, 0.0, 0.15), 3.0)
		_sky.draw_polyline(PackedVector2Array([p - s * 16.0 - h * fl, p + h * 3.0, p + s * 16.0 - h * fl]), Color(1.0, 1.0, 1.0, 0.95), 3.0)


func _draw_glow() -> void:
	var n := _glow_level
	if n <= 0.01:
		return
	# Only lamps and windows near the camera; redrawn when the camera has moved 200 px (see _process).
	var reach := view_half + 300.0
	for l in _lamps:
		if absf(l.x - view_x) > reach:
			continue
		_glow.draw_circle(l, 90.0, Color(1.0, 0.75, 0.40, 0.10 * n))
		_glow.draw_circle(l + Vector2(0.0, -42.0), 26.0, Color(1.0, 0.85, 0.55, 0.30 * n))
	for bd in _buildings:
		var r: Rect2 = bd["rect"]
		if r.end.x < view_x - reach or r.position.x > view_x + reach:
			continue
		var wins: Array = bd["lit"]
		var cnt := wins.size()
		var front_y := r.position.y + r.size.y * 0.62
		for i in cnt:
			if wins[i]:
				var wx := r.position.x + (float(i) + 0.5) * r.size.x / float(cnt) - 7.0
				_glow.draw_rect(Rect2(wx, front_y + 7.0, 14.0, 14.0), Color(1.0, 0.80, 0.42, 0.75 * n))
				_glow.draw_circle(Vector2(wx + 7.0, front_y + 14.0), 22.0, Color(1.0, 0.75, 0.40, 0.08 * n))
