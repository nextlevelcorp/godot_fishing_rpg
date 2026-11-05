## Draws a fish in side view the way the species looks, with no sprite: body outline from a
## profile curve, back-to-belly shading, the species' markings, fins, eye and gill cover, and a body
## that flexes like a swimming fish (a travelling wave whose amplitude grows toward the tail, as in
## Nature of Code's oscillation chapter).
##
## Colours and markings follow common field-guide descriptions of each species (game-design fill
## for exact shades). Unknown species fall back to a plain silver fish.
class_name RealFish
extends RefCounted

## back, belly: colours.  depth: body height / length.  tail: fork, round, square, flat (flatfish).
## pattern: none, bars, wavy, oblique, stripes, spots, blotches, saddle, band.  pcol: pattern colour.
## extra: beak (garfish), barbels (red mullet), brow (gold band between the eyes, gilthead), spot (gill spot).
const LOOKS := {
	"bluefish": {"back": Color(0.22, 0.42, 0.48), "belly": Color(0.86, 0.90, 0.92), "fin": Color(0.35, 0.50, 0.55), "depth": 0.24, "tail": "fork", "pattern": "none", "extra": "spot"},
	"garfish": {"back": Color(0.15, 0.40, 0.42), "belly": Color(0.88, 0.92, 0.95), "fin": Color(0.25, 0.45, 0.48), "depth": 0.08, "tail": "fork", "pattern": "none", "extra": "beak"},
	"european_seabass": {"back": Color(0.40, 0.46, 0.52), "belly": Color(0.93, 0.94, 0.95), "fin": Color(0.45, 0.50, 0.55), "depth": 0.25, "tail": "square", "pattern": "none", "extra": "spot"},
	"gilthead_seabream": {"back": Color(0.50, 0.55, 0.60), "belly": Color(0.90, 0.91, 0.90), "fin": Color(0.48, 0.50, 0.55), "depth": 0.40, "tail": "fork", "pattern": "stripes", "pcol": Color(0.40, 0.44, 0.50, 0.35), "extra": "brow"},
	"atlantic_bonito": {"back": Color(0.12, 0.22, 0.38), "belly": Color(0.85, 0.88, 0.92), "fin": Color(0.20, 0.25, 0.35), "depth": 0.24, "tail": "fork", "pattern": "oblique", "pcol": Color(0.08, 0.12, 0.22, 0.85)},
	"atlantic_mackerel": {"back": Color(0.15, 0.45, 0.42), "belly": Color(0.92, 0.94, 0.95), "fin": Color(0.25, 0.40, 0.40), "depth": 0.18, "tail": "fork", "pattern": "wavy", "pcol": Color(0.05, 0.10, 0.12, 0.9)},
	"mediterranean_horse_mackerel": {"back": Color(0.35, 0.48, 0.50), "belly": Color(0.90, 0.92, 0.93), "fin": Color(0.55, 0.58, 0.55), "depth": 0.21, "tail": "fork", "pattern": "none", "extra": "spot"},
	"european_anchovy": {"back": Color(0.20, 0.38, 0.52), "belly": Color(0.90, 0.93, 0.96), "fin": Color(0.70, 0.75, 0.80), "depth": 0.15, "tail": "fork", "pattern": "band", "pcol": Color(0.78, 0.85, 0.92, 0.8)},
	"red_mullet": {"back": Color(0.82, 0.35, 0.32), "belly": Color(0.98, 0.85, 0.80), "fin": Color(0.90, 0.60, 0.55), "depth": 0.23, "tail": "fork", "pattern": "none", "extra": "barbels"},
	"flathead_grey_mullet": {"back": Color(0.32, 0.38, 0.42), "belly": Color(0.90, 0.91, 0.92), "fin": Color(0.40, 0.44, 0.48), "depth": 0.21, "tail": "fork", "pattern": "stripes", "pcol": Color(0.20, 0.25, 0.30, 0.55)},
	"common_dentex": {"back": Color(0.70, 0.55, 0.58), "belly": Color(0.95, 0.88, 0.86), "fin": Color(0.75, 0.55, 0.58), "depth": 0.34, "tail": "fork", "pattern": "spots", "pcol": Color(0.30, 0.45, 0.80, 0.7)},
	"greater_amberjack": {"back": Color(0.38, 0.45, 0.55), "belly": Color(0.92, 0.92, 0.88), "fin": Color(0.80, 0.70, 0.30), "depth": 0.26, "tail": "fork", "pattern": "band", "pcol": Color(0.92, 0.78, 0.30, 0.7)},
	"leerfish": {"back": Color(0.42, 0.48, 0.50), "belly": Color(0.93, 0.93, 0.92), "fin": Color(0.30, 0.32, 0.34), "depth": 0.30, "tail": "fork", "pattern": "none"},
	"dusky_grouper": {"back": Color(0.38, 0.28, 0.22), "belly": Color(0.62, 0.50, 0.38), "fin": Color(0.35, 0.26, 0.20), "depth": 0.32, "tail": "round", "pattern": "blotches", "pcol": Color(0.85, 0.78, 0.62, 0.55)},
	"black_scorpionfish": {"back": Color(0.40, 0.25, 0.20), "belly": Color(0.70, 0.52, 0.42), "fin": Color(0.45, 0.28, 0.22), "depth": 0.32, "tail": "round", "pattern": "blotches", "pcol": Color(0.20, 0.12, 0.10, 0.6)},
	"saddled_bream": {"back": Color(0.48, 0.55, 0.60), "belly": Color(0.92, 0.93, 0.94), "fin": Color(0.50, 0.55, 0.60), "depth": 0.30, "tail": "fork", "pattern": "saddle", "pcol": Color(0.05, 0.05, 0.06, 0.95)},
	"white_seabream": {"back": Color(0.62, 0.64, 0.62), "belly": Color(0.94, 0.94, 0.92), "fin": Color(0.60, 0.62, 0.60), "depth": 0.38, "tail": "fork", "pattern": "bars", "pcol": Color(0.20, 0.20, 0.22, 0.55)},
	"striped_sea_bream": {"back": Color(0.62, 0.60, 0.50), "belly": Color(0.94, 0.93, 0.88), "fin": Color(0.62, 0.60, 0.55), "depth": 0.34, "tail": "fork", "pattern": "stripes", "pcol": Color(0.85, 0.70, 0.30, 0.6)},
	"whiting": {"back": Color(0.62, 0.60, 0.55), "belly": Color(0.95, 0.94, 0.92), "fin": Color(0.65, 0.63, 0.58), "depth": 0.19, "tail": "square", "pattern": "none"},
	"turbot": {"back": Color(0.48, 0.40, 0.30), "belly": Color(0.62, 0.55, 0.45), "fin": Color(0.45, 0.38, 0.30), "depth": 0.75, "tail": "flat", "pattern": "spots", "pcol": Color(0.25, 0.20, 0.15, 0.7)},
	"greater_weever": {"back": Color(0.70, 0.62, 0.42), "belly": Color(0.92, 0.88, 0.78), "fin": Color(0.15, 0.15, 0.15), "depth": 0.18, "tail": "square", "pattern": "oblique", "pcol": Color(0.35, 0.40, 0.55, 0.6)},
	"ornate_wrasse": {"back": Color(0.20, 0.55, 0.35), "belly": Color(0.95, 0.65, 0.30), "fin": Color(0.30, 0.60, 0.70), "depth": 0.24, "tail": "round", "pattern": "stripes", "pcol": Color(0.95, 0.45, 0.30, 0.7)},
}
const DEFAULT := {"back": Color(0.45, 0.50, 0.55), "belly": Color(0.92, 0.93, 0.94), "fin": Color(0.50, 0.55, 0.60), "depth": 0.25, "tail": "fork", "pattern": "none"}
const SAMPLES := 16


static func look(id: String) -> Dictionary:
	return LOOKS.get(id, DEFAULT)


## Draws the fish. center: screen position of the body middle; length: px from tail tip to snout;
## rot: radians; facing: 1 snout to the right, -1 to the left; phase: tail-beat phase (radians);
## flex: 0 stiff .. 1 full swimming bend; light: 0 night .. 1 day; wet: 0..1 sheen.
static func draw(ci: CanvasItem, id: String, center: Vector2, length: float, rot: float, facing: float,
		phase: float, flex: float, light: float, wet: float = 0.6) -> void:
	var lk := look(id)
	var dim := lerpf(0.35, 1.0, light)
	var shade := Color(dim, dim, dim)
	var back: Color = lk["back"]
	var belly: Color = lk["belly"]
	var fin: Color = lk["fin"]
	back *= shade
	belly *= shade
	fin *= shade
	var depth: float = lk["depth"]
	var tail := String(lk["tail"])
	ci.draw_set_transform(center, rot, Vector2(facing, 1.0))
	var body_len := length * 0.82
	var x0 := -length * 0.5 + length * 0.18           # peduncle (tail root)
	if tail == "flat":
		_draw_flatfish(ci, lk, length, back, belly, fin, phase, flex)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var mid := PackedVector2Array()
	for i in SAMPLES + 1:
		var u := float(i) / float(SAMPLES)          # 0 peduncle .. 1 snout
		var x := x0 + u * body_len
		var h := depth * length * 0.5 * (0.16 + 0.84 * sin(PI * pow(u, 0.8))) * (1.0 - 0.75 * pow(u, 5.0))
		var c := _bend(u, length, phase, flex)
		top.append(Vector2(x, c - h * 1.05))
		bot.append(Vector2(x, c + h * 0.95))
		mid.append(Vector2(x, c))
	# Fins behind the body.
	_draw_tail(ci, tail, Vector2(x0, _bend(0.0, length, phase, flex)), length, depth, fin, phase, flex)
	var dorsal := PackedVector2Array([top[6], top[7] + Vector2(0.0, -depth * length * 0.32), top[11] + Vector2(0.0, -depth * length * 0.18), top[12]])
	ci.draw_colored_polygon(dorsal, Color(fin.r, fin.g, fin.b, 0.9))
	var anal := PackedVector2Array([bot[3], bot[4] + Vector2(0.0, depth * length * 0.18), bot[6]])
	ci.draw_colored_polygon(anal, Color(fin.r, fin.g, fin.b, 0.85))
	# Body: shaded from back to belly through the flank.
	var outline := PackedVector2Array()
	var cols := PackedColorArray()
	for i in top.size():
		outline.append(top[i])
		cols.append(back)
	for i in range(bot.size() - 1, -1, -1):
		outline.append(bot[i])
		cols.append(belly)
	ci.draw_polygon(outline, cols)
	var flank := PackedVector2Array()
	var fcols := PackedColorArray()
	for i in top.size():
		flank.append(top[i].lerp(mid[i], 0.55))
		fcols.append(back.lerp(belly, 0.55))
	for i in range(mid.size() - 1, -1, -1):
		flank.append(mid[i].lerp(bot[i], 0.35))
		fcols.append(belly)
	ci.draw_polygon(flank, fcols)
	_draw_pattern(ci, lk, top, mid, bot, length)
	# Lateral line, gill cover, pectoral fin, eye, mouth.
	var lateral := PackedVector2Array()
	for i in range(1, SAMPLES - 2):
		lateral.append(top[i].lerp(mid[i], 0.75))
	ci.draw_polyline(lateral, Color(back.r, back.g, back.b, 0.55), maxf(1.0, length * 0.008), true)
	var gill := top[SAMPLES - 4].lerp(bot[SAMPLES - 4], 0.5)
	var gh := (bot[SAMPLES - 4].y - top[SAMPLES - 4].y) * 0.45
	ci.draw_arc(gill, gh, -1.2, 1.2, 10, Color(back.r, back.g, back.b, 0.6), maxf(1.0, length * 0.01))
	if String(lk.get("extra", "")) == "spot":
		ci.draw_circle(gill + Vector2(-gh * 0.1, -gh * 0.55), length * 0.018, Color(0.05, 0.05, 0.06, 0.8))
	var pec_root := gill + Vector2(-gh * 0.2, gh * 0.35)
	ci.draw_colored_polygon(PackedVector2Array([pec_root, pec_root + Vector2(-length * 0.13, length * 0.03 + sin(phase * 1.3) * length * 0.02),
		pec_root + Vector2(-length * 0.08, length * 0.07)]), Color(fin.r, fin.g, fin.b, 0.6))
	var eye := top[SAMPLES - 2].lerp(mid[SAMPLES - 2], 0.55)
	var er := maxf(1.5, length * (0.038 if depth > 0.12 else 0.025))
	ci.draw_circle(eye, er, Color(0.95, 0.93, 0.80))
	ci.draw_circle(eye, er * 0.62, Color(0.04, 0.04, 0.05))
	ci.draw_circle(eye + Vector2(er * 0.25, -er * 0.3), er * 0.22, Color(1.0, 1.0, 1.0, 0.9))
	var snout := mid[SAMPLES]
	ci.draw_line(snout + Vector2(0.0, length * 0.006), snout + Vector2(-length * 0.05, length * 0.012), Color(0.1, 0.1, 0.1, 0.6), maxf(1.0, length * 0.006))
	match String(lk.get("extra", "")):
		"beak":
			ci.draw_line(snout + Vector2(0.0, -1.0), snout + Vector2(length * 0.22, 0.0), back.darkened(0.2), maxf(1.5, length * 0.012))
			ci.draw_line(snout + Vector2(0.0, 1.0), snout + Vector2(length * 0.24, 1.5), back.darkened(0.3), maxf(1.0, length * 0.01))
		"barbels":
			ci.draw_line(snout + Vector2(-length * 0.03, length * 0.02), snout + Vector2(-length * 0.02, length * 0.08), Color(0.95, 0.85, 0.75), maxf(1.0, length * 0.006))
		"brow":
			ci.draw_line(eye + Vector2(er * 0.8, -er * 1.4), eye + Vector2(-er * 0.6, -er * 1.6), Color(0.95, 0.78, 0.25, 0.9), maxf(1.5, er * 0.6))
	# Wet sheen along the back.
	if wet > 0.0:
		var sheen := PackedVector2Array()
		for i in range(3, SAMPLES - 3):
			sheen.append(top[i].lerp(mid[i], 0.22))
		ci.draw_polyline(sheen, Color(1.0, 1.0, 1.0, 0.35 * wet * light), maxf(1.0, length * 0.012), true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Centre-line offset at u: a travelling wave, strongest at the tail (Nature of Code: oscillation).
static func _bend(u: float, length: float, phase: float, flex: float) -> float:
	return flex * length * 0.07 * sin(phase - u * 3.2) * pow(1.0 - u, 1.6)


static func _draw_tail(ci: CanvasItem, tail: String, root: Vector2, length: float, depth: float, fin: Color, phase: float, flex: float) -> void:
	var sweep := flex * length * 0.06 * sin(phase + 0.6)
	var tip := -length * 0.18
	var span := maxf(depth, 0.14) * length * 0.55
	var col := Color(fin.r, fin.g, fin.b, 0.95)
	match tail:
		"fork":
			ci.draw_colored_polygon(PackedVector2Array([root + Vector2(4.0, -span * 0.12), root + Vector2(tip, -span + sweep),
				root + Vector2(tip * 0.55, sweep * 0.6), root + Vector2(tip, span + sweep), root + Vector2(4.0, span * 0.12)]), col)
		"round":
			var pts := PackedVector2Array([root + Vector2(4.0, -span * 0.25)])
			for i in 9:
				var a := lerpf(-1.3, 1.3, float(i) / 8.0)
				pts.append(root + Vector2(cos(a) * tip * 0.85, sin(a) * span * 0.75 + sweep))
			pts.append(root + Vector2(4.0, span * 0.25))
			ci.draw_colored_polygon(pts, col)
		_:
			ci.draw_colored_polygon(PackedVector2Array([root + Vector2(4.0, -span * 0.2), root + Vector2(tip, -span * 0.8 + sweep),
				root + Vector2(tip * 0.92, sweep), root + Vector2(tip, span * 0.8 + sweep), root + Vector2(4.0, span * 0.2)]), col)


static func _draw_pattern(ci: CanvasItem, lk: Dictionary, top: PackedVector2Array, mid: PackedVector2Array, bot: PackedVector2Array, length: float) -> void:
	var pat := String(lk.get("pattern", "none"))
	var pc: Color = lk.get("pcol", Color(0, 0, 0, 0.5))
	var w := maxf(1.0, length * 0.012)
	match pat:
		"bars":
			for i in [4, 7, 10, 13]:
				ci.draw_line(top[i].lerp(bot[i], 0.05), top[i].lerp(bot[i], 0.75), pc, w * 2.2)
		"wavy":
			for row in 3:
				var line := PackedVector2Array()
				for i in range(2, SAMPLES - 3):
					var p := top[i].lerp(mid[i], 0.15 + 0.22 * float(row))
					line.append(p + Vector2(0.0, sin(float(i) * 1.9 + float(row)) * length * 0.012))
				ci.draw_polyline(line, pc, w, true)
			for i in range(3, SAMPLES - 3, 2):
				ci.draw_line(top[i].lerp(mid[i], 0.05), top[i].lerp(mid[i], 0.7) + Vector2(length * 0.02, 0.0), pc, w * 0.9)
		"oblique":
			for i in range(3, SAMPLES - 3, 2):
				ci.draw_line(top[i].lerp(mid[i], 0.1), top[i - 2].lerp(mid[i - 2], 0.9), pc, w * 1.2)
		"stripes":
			for row in 4:
				var line2 := PackedVector2Array()
				for i in range(1, SAMPLES - 2):
					line2.append(top[i].lerp(bot[i], 0.15 + 0.17 * float(row)))
				ci.draw_polyline(line2, pc, w * 0.8, true)
		"spots", "blotches":
			var r := length * (0.012 if pat == "spots" else 0.035)
			for i in range(2, SAMPLES - 2):
				for row in 3:
					if (i * 7 + row * 3) % 4 == 0:
						ci.draw_circle(top[i].lerp(bot[i], 0.2 + 0.25 * float(row)), r, pc)
		"saddle":
			ci.draw_circle(mid[1].lerp(top[1], 0.2), length * 0.045, pc)
		"band":
			var line3 := PackedVector2Array()
			for i in range(1, SAMPLES - 1):
				line3.append(top[i].lerp(mid[i], 0.85))
			ci.draw_polyline(line3, pc, w * 2.0, true)


## Turbot and other flatfish: a broad disc seen from above, eyes on top, fringe fins around it.
static func _draw_flatfish(ci: CanvasItem, lk: Dictionary, length: float, back: Color, belly: Color, fin: Color, phase: float, flex: float) -> void:
	var r := Vector2(length * 0.42, length * 0.34)
	var fringe := PackedVector2Array()
	var disc := PackedVector2Array()
	for i in 28:
		var a := TAU * float(i) / 28.0
		var wob := 1.0 + 0.06 * sin(a * 9.0 + phase * 2.0) * flex
		fringe.append(Vector2(cos(a) * r.x * 1.12 * wob, sin(a) * r.y * 1.15 * wob))
		disc.append(Vector2(cos(a) * r.x, sin(a) * r.y))
	ci.draw_colored_polygon(fringe, fin)
	ci.draw_colored_polygon(disc, back)
	var pc: Color = lk.get("pcol", Color(0, 0, 0, 0.5))
	for i in 14:
		var a2 := float(i) * 2.4
		ci.draw_circle(Vector2(cos(a2) * r.x * 0.6 * fmod(float(i) * 0.37, 1.0), sin(a2) * r.y * 0.6), length * 0.02, pc)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-r.x * 0.95, 0.0), Vector2(-r.x * 1.35, -r.y * 0.4), Vector2(-r.x * 1.35, r.y * 0.4)]), fin)
	for e in [Vector2(r.x * 0.55, -r.y * 0.15), Vector2(r.x * 0.62, r.y * 0.05)]:
		ci.draw_circle(e, length * 0.03, Color(0.9, 0.88, 0.7))
		ci.draw_circle(e, length * 0.018, Color(0.05, 0.05, 0.05))
