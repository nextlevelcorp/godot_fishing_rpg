## Procedural sound for the shore: no audio files, everything is synthesised.
##   surf     brown noise whose loudness swells and ebbs on Perlin noise (Nature of Code ch. 0)
##   gulls    random cries: a falling pitch glide with a harmonic and vibrato
##   one-shots splash (band-passed noise with falling pitch, then bubble drops), plop and drop (rising
##             bubble bloop), cast and strike (rod swish), click (reel tick), drag (clutch ratchet),
##             snap (crack and twang)
## Browsers only start audio after the first touch or click; Godot resumes it on its own.
class_name Ambience
extends Node

const RATE := 22050.0

## 0..1 loudness of the surf bed. The shore scene sets it from the spot and the weather.
var surf_level := 0.6
## Gull cries per second on average. Lower at night.
var gull_rate := 0.07

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _swell := FastNoiseLite.new()
var _t := 0.0
var _brown := 0.0
var _events: Array[Dictionary] = []


func _ready() -> void:
	_swell.noise_type = FastNoiseLite.TYPE_PERLIN
	_swell.frequency = 0.12
	_swell.seed = randi()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.2
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = -4.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## kind: "splash", "plop", "drop", "cast", "strike", "click", "drag", "snap", "gull". volume 0..1.
## A splash also schedules a few bubble drops just after it, as real water does.
func play(kind: String, volume: float = 1.0, delay: float = 0.0) -> void:
	var e := {"kind": kind, "age": -delay, "ph": 0.0, "lp": 0.0, "bp": 0.0, "amp": volume}
	match kind:
		"splash":
			e["dur"] = 0.7
			for i in randi_range(2, 4):
				play("drop", volume * randf_range(0.25, 0.5), delay + randf_range(0.06, 0.45))
		"plop":
			e["dur"] = 0.18
			e["f0"] = randf_range(260.0, 360.0)
		"drop":
			e["dur"] = 0.09
			e["f0"] = randf_range(500.0, 950.0)
		"cast":
			e["dur"] = 0.5
		"strike":
			e["dur"] = 0.22
		"click":
			e["dur"] = 0.02
		"drag":
			e["dur"] = 0.45
		"snap":
			e["dur"] = 0.35
		"gull":
			e["dur"] = randf_range(0.35, 0.55)
			e["f0"] = randf_range(1700.0, 2100.0)
			e["f1"] = randf_range(1000.0, 1250.0)
		_:
			return
	if _events.size() < 16:
		_events.append(e)


func _process(delta: float) -> void:
	if randf() < gull_rate * delta:
		play("gull", randf_range(0.25, 0.6))
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	var dt := 1.0 / RATE
	for i in frames:
		_t += dt
		# Brown noise: a random walk, leaked back toward zero so it never drifts off.
		_brown = clampf(_brown + randf_range(-0.04, 0.04), -1.0, 1.0) * 0.996
		var swell := 0.5 + 0.5 * _swell.get_noise_1d(_t)
		var s := _brown * (0.10 + 0.45 * swell * swell) * surf_level
		if not _events.is_empty():
			s += _synth(dt)
		s = s / (1.0 + absf(s))           # soft limit: loud splashes round off instead of clipping
		buf[i] = Vector2(s, s)
	_playback.push_buffer(buf)


## One state-variable band-pass step on the event's own filter state: returns the band output.
func _bandpass(e: Dictionary, x: float, fc: float, q: float) -> float:
	var f := 2.0 * sin(PI * minf(fc, RATE * 0.2) / RATE)
	var lp: float = e["lp"]
	var bp: float = e["bp"]
	lp += f * bp
	var hp := x - lp - q * bp
	bp += f * hp
	e["lp"] = lp
	e["bp"] = bp
	return bp


func _synth(dt: float) -> float:
	var out := 0.0
	var i := _events.size() - 1
	while i >= 0:
		var e: Dictionary = _events[i]
		var age: float = e["age"]
		var dur: float = e["dur"]
		e["age"] = age + dt
		if age < 0.0:                       # scheduled for later
			i -= 1
			continue
		var k := age / dur
		var amp: float = e["amp"]
		var v := 0.0
		match String(e["kind"]):
			"splash":
				# Bright crack, then a body of water noise whose pitch falls as the splash settles.
				var n := randf_range(-1.0, 1.0)
				var body := _bandpass(e, n, lerpf(2600.0, 500.0, sqrt(k)), 0.9)
				var crack := n * exp(-age * 120.0) * 0.5
				var env := minf(age / 0.004, 1.0) * exp(-age * 6.5)
				v = (body * 1.6 + crack) * env * 0.8
			"plop":
				# Float pulled under: a low bloop (pitch rises, as a bubble does) over a soft thud.
				var f := float(e["f0"]) * (1.0 + 1.2 * k)
				e["ph"] = float(e["ph"]) + TAU * f * dt
				v = sin(float(e["ph"])) * exp(-age * 22.0) * 0.6 + _bandpass(e, randf_range(-1.0, 1.0), 300.0, 1.2) * exp(-age * 30.0) * 0.5
			"drop":
				var f2 := float(e["f0"]) * (1.0 + 1.8 * k)
				e["ph"] = float(e["ph"]) + TAU * f2 * dt
				v = sin(float(e["ph"])) * exp(-age * 45.0) * 0.5
			"cast":
				# Rod swish and line leaving the spool: band-passed air noise sweeping up and down.
				var sw := sin(PI * k)
				v = _bandpass(e, randf_range(-1.0, 1.0), 350.0 + 1700.0 * sw, 0.6) * sw * sw * 0.9
			"strike":
				var sw2 := sin(PI * k)
				v = _bandpass(e, randf_range(-1.0, 1.0), 600.0 + 2200.0 * k, 0.5) * sw2 * 0.8
			"click":
				v = _bandpass(e, randf_range(-1.0, 1.0), 4000.0, 0.5) * exp(-age * 400.0) * 0.5
			"drag":
				# The clutch giving line: a fast ratchet, each tick a short decaying burst.
				var tick := fmod(age, 1.0 / 38.0)
				v = _bandpass(e, randf_range(-1.0, 1.0), 3200.0, 0.4) * exp(-tick * 500.0) * (1.0 - k) * 0.7
			"snap":
				# The line parting: a crack and a short falling twang.
				var tw := 330.0 * (1.0 - 0.4 * k)
				e["ph"] = float(e["ph"]) + TAU * tw * dt
				v = randf_range(-1.0, 1.0) * exp(-age * 70.0) + sin(float(e["ph"])) * exp(-age * 9.0) * 0.4
			"gull":
				var f3 := lerpf(float(e["f0"]), float(e["f1"]), k) * (1.0 + 0.03 * sin(age * 40.0))
				e["ph"] = float(e["ph"]) + TAU * f3 * dt
				var ph: float = e["ph"]
				v = (sin(ph) + 0.35 * sin(ph * 2.0)) * sin(PI * k) * 0.18
		out += v * amp
		if age + dt >= dur:
			_events.remove_at(i)
		i -= 1
	return out
