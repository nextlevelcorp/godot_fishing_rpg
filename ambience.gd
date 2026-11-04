## Procedural sound for the shore: no audio files, everything is synthesised.
##   surf     brown noise whose loudness swells and ebbs on Perlin noise (Nature of Code ch. 0)
##   gulls    random cries: a falling pitch glide with a harmonic and vibrato
##   one-shots splash (filtered noise burst), plop (falling sine), click (reel tick), snap (crack)
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


## kind: "splash", "plop", "click", "snap", "gull". volume 0..1.
func play(kind: String, volume: float = 1.0) -> void:
	var e := {"kind": kind, "age": 0.0, "ph": 0.0, "lp": 0.0, "amp": volume}
	match kind:
		"splash":
			e["dur"] = 0.45
		"plop":
			e["dur"] = 0.14
		"click":
			e["dur"] = 0.012
		"snap":
			e["dur"] = 0.08
		"gull":
			e["dur"] = randf_range(0.35, 0.55)
			e["f0"] = randf_range(1700.0, 2100.0)
			e["f1"] = randf_range(1000.0, 1250.0)
		_:
			return
	if _events.size() < 12:
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
		s = clampf(s, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_playback.push_buffer(buf)


func _synth(dt: float) -> float:
	var out := 0.0
	var i := _events.size() - 1
	while i >= 0:
		var e: Dictionary = _events[i]
		var age: float = e["age"]
		var dur: float = e["dur"]
		var k := age / dur
		var amp: float = e["amp"]
		var v := 0.0
		match String(e["kind"]):
			"splash":
				var lp: float = e["lp"]
				lp += (randf_range(-1.0, 1.0) - lp) * lerpf(0.5, 0.08, k)
				e["lp"] = lp
				v = lp * exp(-age * 9.0) * 0.9
			"plop":
				var f := lerpf(320.0, 110.0, k)
				e["ph"] = float(e["ph"]) + TAU * f * dt
				v = sin(float(e["ph"])) * (1.0 - k) * 0.6
			"click":
				v = randf_range(-1.0, 1.0) * (1.0 - k) * 0.35
			"snap":
				v = randf_range(-1.0, 1.0) * exp(-age * 60.0)
			"gull":
				var f2 := lerpf(float(e["f0"]), float(e["f1"]), k) * (1.0 + 0.03 * sin(age * 40.0))
				e["ph"] = float(e["ph"]) + TAU * f2 * dt
				var ph: float = e["ph"]
				v = (sin(ph) + 0.35 * sin(ph * 2.0)) * sin(PI * k) * 0.18
		out += v * amp
		e["age"] = age + dt
		if age + dt >= dur:
			_events.remove_at(i)
		i -= 1
	return out
