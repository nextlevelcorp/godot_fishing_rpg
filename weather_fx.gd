## Weather for one outing: picks a kind, changes how active the fish are and how hard the wind blows,
## and draws rain and a grey tint over the scene. Sits under the HUD.
## Effects are game-design fill, loosely based on common angling lore (low light and light rain often
## make fish feed; strong wind and downpours make bites harder to read). Tune them in KINDS.
## Motion follows Nature of Code: each raindrop is a particle under gravity plus wind, and gusts come
## from Perlin noise.
class_name WeatherFx
extends Control

## weight: chance to roll. activity: multiplier on fish activity. wind: multiplier on the wind force.
## rain: drops per second. dark: alpha of the grey tint.
const KINDS := {
	"clear": {"label": "Clear", "weight": 45.0, "activity": 1.0, "wind": 1.0, "rain": 0.0, "dark": 0.0},
	"overcast": {"label": "Overcast", "weight": 25.0, "activity": 1.15, "wind": 1.0, "rain": 0.0, "dark": 0.14},
	"drizzle": {"label": "Light rain", "weight": 15.0, "activity": 1.25, "wind": 1.1, "rain": 70.0, "dark": 0.20},
	"windy": {"label": "Windy", "weight": 15.0, "activity": 0.9, "wind": 2.2, "rain": 0.0, "dark": 0.06},
}
const MAX_DROPS := 160
const GRAVITY := 900.0

var kind := "clear"
var _drops: Array[Noc.Particle] = []
var _noise := FastNoiseLite.new()
var _time := 0.0
var _spawn_acc := 0.0
var _gust := 0.0


## Rolls a kind with the given random generator and returns its id.
static func roll(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in KINDS:
		total += float(KINDS[k]["weight"])
	var pick := rng.randf() * total
	for k: String in KINDS:
		pick -= float(KINDS[k]["weight"])
		if pick <= 0.0:
			return k
	return "clear"


func setup(kind_id: String) -> void:
	kind = kind_id if KINDS.has(kind_id) else "clear"


func label() -> String:
	return String(KINDS[kind]["label"])


func activity_factor() -> float:
	return float(KINDS[kind]["activity"])


func wind_factor() -> float:
	return float(KINDS[kind]["wind"])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.25
	_noise.seed = randi()


func _process(delta: float) -> void:
	_time += delta
	_gust = _noise.get_noise_1d(_time) * 140.0 * wind_factor()
	var rate := float(KINDS[kind]["rain"])
	if rate > 0.0:
		_spawn_acc += rate * delta
		while _spawn_acc >= 1.0 and _drops.size() < MAX_DROPS:
			_spawn_acc -= 1.0
			var p := Noc.Particle.new(Vector2(randf_range(-100.0, size.x + 100.0), -10.0), Vector2(_gust * 0.5, 520.0), 0.0, 0.0, 3.0, 1.0, Color(0.8, 0.9, 1.0, 0.45))
			_drops.append(p)
		_spawn_acc = minf(_spawn_acc, 1.0)
	for i in range(_drops.size() - 1, -1, -1):
		var d := _drops[i]
		d.vel += Vector2(_gust * 0.8, GRAVITY * 0.4) * delta
		d.vel = d.vel.limit_length(900.0)
		d.pos += d.vel * delta
		d.age += delta
		if d.pos.y > size.y + 10.0 or d.age > d.life:
			_drops.remove_at(i)
	if rate > 0.0 or float(KINDS[kind]["dark"]) > 0.0:
		queue_redraw()


func _draw() -> void:
	var dark := float(KINDS[kind]["dark"])
	if dark > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.13, 0.18, dark))
	for d in _drops:
		var dir := d.vel.normalized()
		draw_line(d.pos, d.pos - dir * 16.0, d.color, 1.5)
