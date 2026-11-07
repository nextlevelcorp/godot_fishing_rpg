## Sound for the shore and the fishing view. The sounds are rendered offline from physical models
## by tools/audio/render_sfx.py (water = impact + Minnaert bubbles, reel and clutch = metallic click
## trains, gulls = formant-shaped glides, surf = pink noise under wave envelopes) and played here
## from assets/audio/*.wav. No synthesis runs on the phone.
##   surf     a seamless loop whose loudness follows `surf_level`
##   gulls    random calls, `gull_rate` per second
##   loops    reel (while cranking) and drag (while the clutch gives line), see set_loop()
##   one-shots play(kind, volume): splash, splash_big, exit, drips, plop, nibble, cast, strike, snap, gull
## Browsers only start audio after the first touch or click; Godot resumes it on its own.
class_name Ambience
extends Node

const DIR := "res://assets/audio/"
const VOICES := 8

## 0..1 loudness of the surf bed. The shore scene sets it from the spot and the weather.
var surf_level := 0.6
## Gull calls per second on average. Lower at night.
var gull_rate := 0.07

var _streams: Dictionary = {}          ## name -> AudioStreamWAV
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _surf: AudioStreamPlayer
var _loops: Dictionary = {}            ## name -> AudioStreamPlayer
var _loop_hold: Dictionary = {}        ## name -> seconds left (for timed loops such as drag)
var _beds: Dictionary = {}             ## always-running background loops faded by set_bed: engine, cicada, cricket
var _bed_target: Dictionary = {}


func _ready() -> void:
	for n in ["splash_small", "splash_big", "splash_exit", "drips", "bloop", "nibble", "cast", "strike",
			"reel_loop", "drag_loop", "snap", "bell", "engine_loop", "cicada_loop", "cricket_loop", "lap", "horn", "gull_0", "gull_1", "gull_2", "surf_loop"]:
		var s := load(DIR + n + ".wav") as AudioStreamWAV
		if s != null:
			_streams[n] = s
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_surf = _make_loop("surf_loop")
	if _surf != null:
		_surf.volume_db = linear_to_db(maxf(surf_level, 0.01)) - 8.0
		_surf.play()
	_loops["reel"] = _make_loop("reel_loop")
	_loops["drag"] = _make_loop("drag_loop")
	for id: String in ["engine", "cicada", "cricket"]:
		var p: AudioStreamPlayer = _make_loop(id + "_loop")
		if p != null:
			p.volume_db = -60.0
			p.play()
			_beds[id] = p


func _make_loop(id: String) -> AudioStreamPlayer:
	if not _streams.has(id):
		return null
	var s := (_streams[id] as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * float(s.mix_rate))
	var p := AudioStreamPlayer.new()
	p.stream = s
	add_child(p)
	return p


## kind: "splash" (small, or big when volume > 0.9), "splash_big", "exit", "drips", "plop", "nibble",
## "cast", "strike", "click" (ignored: the reel loop covers it), "drag", "snap", "gull". volume 0..1.
func play(kind: String, volume: float = 1.0) -> void:
	var snd := ""
	match kind:
		"splash":
			snd = "splash_big" if volume > 0.9 else "splash_small"
		"splash_big":
			snd = "splash_big"
		"exit":
			snd = "splash_exit"
		"drips", "drop":
			snd = "drips"
		"plop":
			snd = "bloop" if volume > 0.6 else "nibble"
		"nibble":
			snd = "nibble"
		"cast":
			snd = "cast"
		"strike":
			snd = "strike"
		"snap":
			snd = "snap"
		"bell":
			snd = "bell"
		"lap":
			snd = "lap"
		"horn":
			snd = "horn"
		"gull":
			snd = "gull_%d" % randi_range(0, 2)
		"drag":
			hold_loop("drag", 0.5, volume)
			return
		_:
			return
	if not _streams.has(snd):
		return
	var p := _voices[_next]
	_next = (_next + 1) % _voices.size()
	p.stream = _streams[snd]
	p.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()


## Sets how loud a background bed is, 0..1 ("engine", "cicada", "cricket"); it fades there.
func set_bed(id: String, level: float) -> void:
	_bed_target[id] = clampf(level, 0.0, 1.0)


## Starts or stops a looping sound ("reel" or "drag").
func set_loop(id: String, on: bool, volume: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loops.get(id, null)
	if p == null:
		return
	p.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	if on and not p.playing:
		p.play()
	elif not on and p.playing and float(_loop_hold.get(id, 0.0)) <= 0.0:
		p.stop()


## Plays a loop for at least `seconds` (the drag ratchet during a run).
func hold_loop(id: String, seconds: float, volume: float = 1.0) -> void:
	_loop_hold[id] = maxf(float(_loop_hold.get(id, 0.0)), seconds)
	set_loop(id, true, volume)


func _process(delta: float) -> void:
	if randf() < gull_rate * delta:
		play("gull", randf_range(0.25, 0.6))
	for id: String in _beds:
		var bp: AudioStreamPlayer = _beds[id]
		var want := linear_to_db(maxf(float(_bed_target.get(id, 0.0)), 0.001))
		bp.volume_db = lerpf(bp.volume_db, want, delta * 1.5)
	if _surf != null:
		_surf.volume_db = lerpf(_surf.volume_db, linear_to_db(maxf(surf_level, 0.01)) - 8.0, delta * 2.0)
	for id: String in _loop_hold.keys():
		var left := float(_loop_hold[id]) - delta
		_loop_hold[id] = left
		if left <= 0.0:
			_loop_hold.erase(id)
			var p: AudioStreamPlayer = _loops.get(id, null)
			if p != null:
				p.stop()
