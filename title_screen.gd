## Start screen: Play, Settings (sound, vibration), Credits. Opens the Türkiye map.
## Motion follows Nature of Code: wave layers are sums of oscillators drifting with Perlin noise,
## and a few fish are steering agents that wander and stay inside the water (noc.gd Vehicle).
extends Control

const SEA_TOP := Color(0.02, 0.20, 0.36)
const SEA_BOTTOM := Color(0.03, 0.55, 0.70)
const WAVE_LAYERS := 5
const FISH_COUNT := 9
const MAP_SCENE := "res://turkey_map.tscn"
const CREDITS := "Shore Fishing Türkiye\n\nArt: Kenney (kenney.nl), CC0 - Fish Pack, Game Icons, Mobile Controls.\nFish, spot and tackle facts: see the sources listed for each spot on the map.\nMotion ideas: The Nature of Code, Daniel Shiffman (natureofcode.com).\nMade with Godot 4.4.\n\nEvery spot is a real place where people fish in Türkiye. Game-design fill is labelled in the data."

var _time := 0.0
var _noise := FastNoiseLite.new()
var _fish: Array[Dictionary] = []   ## {pos, vel, wander, size, hue}
## The painted species that swim under the title (assets/art/fish), so the first screen shows the
## game's real fish instead of flat silhouettes.
const TITLE_FISH: Array[String] = ["bluefish", "saddled_bream", "white_seabream", "striped_sea_bream",
	"garfish", "whiting", "common_dentex", "greater_amberjack"]
var _overlay: PanelContainer
var _overlay_title: Label
var _overlay_body: VBoxContainer
var _sound_btn: Button
var _vibrate_btn: Button
var _test_btn: Button
var _diag: Label
var _menu: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameSession.load_once()
	theme = UiTheme.get_theme()
	add_child(DeviceGuard.new())
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.4
	_noise.seed = 7
	for i in FISH_COUNT:
		_fish.append({
			"pos": Vector2(randf_range(100.0, maxf(size.x, 1280.0) - 100.0), randf_range(300.0, 660.0)),
			"vel": Vector2(randf_range(-30.0, 30.0), 0.0),
			"wander": randf() * TAU,
			"size": randf_range(14.0, 30.0),
			"hue": randf_range(0.5, 0.62),
			"sp": TITLE_FISH[i % TITLE_FISH.size()],
		})
	_build_menu()
	_build_overlay()


func _build_menu() -> void:
	var title := Label.new()
	title.text = "SHORE FISHING\nTÜRKİYE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.1, 0.2, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -400.0
	title.offset_right = 400.0
	title.offset_top = 40.0
	title.offset_bottom = 210.0
	add_child(title)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 14)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.offset_left = -170.0
	_menu.offset_right = 170.0
	_menu.offset_top = -10.0
	_menu.offset_bottom = 200.0
	add_child(_menu)
	_menu.add_child(_button("PLAY", 34, _on_play))
	_menu.add_child(_button("SETTINGS", 26, _open_settings))
	_menu.add_child(_button("CREDITS", 26, _open_credits))

	var ver := Label.new()
	ver.text = GameSession.BUILD
	ver.add_theme_font_size_override("font_size", 16)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	ver.position = Vector2(14, 690)
	add_child(ver)


func _button(text: String, font: int, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340.0, 70.0)
	b.add_theme_font_size_override("font_size", font)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _build_overlay() -> void:
	_overlay = PanelContainer.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay.offset_left = -400.0
	_overlay.offset_right = 400.0
	_overlay.offset_top = -290.0
	_overlay.offset_bottom = 290.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.96)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(20)
	_overlay.add_theme_stylebox_override("panel", style)
	_overlay.visible = false
	add_child(_overlay)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_overlay.add_child(box)
	_overlay_title = Label.new()
	_overlay_title.add_theme_font_size_override("font_size", 32)
	box.add_child(_overlay_title)
	_overlay_body = VBoxContainer.new()
	_overlay_body.add_theme_constant_override("separation", 12)
	_overlay_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body_scroll := ScrollContainer.new()
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(body_scroll)
	body_scroll.add_child(_overlay_body)
	box.add_child(_button("BACK", 24, _close_overlay))


func _clear_body() -> void:
	for c in _overlay_body.get_children():
		c.queue_free()


func _open_settings() -> void:
	_clear_body()
	_overlay_title.text = "Settings"
	_sound_btn = _button("", 24, _toggle_sound)
	_vibrate_btn = _button("", 24, _toggle_vibration)
	_overlay_body.add_child(_sound_btn)
	_overlay_body.add_child(_vibrate_btn)
	_test_btn = _button("", 24, _toggle_test_tools)
	_overlay_body.add_child(_test_btn)
	_overlay_body.add_child(_button("SOUND TEST", 24, _sound_test))
	_diag = Label.new()
	_diag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diag.add_theme_font_size_override("font_size", 15)
	_diag.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_overlay_body.add_child(_diag)
	var note := Label.new()
	note.text = "Vibration works on Android browsers. iPhone Safari does not allow it.\nTEST TOOLS adds a TEST button on the shore: hook any species at once and trigger jumps, to check the pictures. Test catches give no coins or XP.\nYour progress is saved in this browser; clearing site data erases it."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_overlay_body.add_child(note)
	_refresh_settings()
	_show_overlay()


func _open_credits() -> void:
	_clear_body()
	_overlay_title.text = "Credits"
	var l := Label.new()
	l.text = CREDITS
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_overlay_body.add_child(l)
	_show_overlay()


func _show_overlay() -> void:
	_overlay.visible = true
	_menu.visible = false


func _close_overlay() -> void:
	_overlay.visible = false
	_menu.visible = true


func _toggle_sound() -> void:
	GameSession.set_sound(not GameSession.sound_on)
	_refresh_settings()


func _toggle_vibration() -> void:
	GameSession.set_vibration(not GameSession.vibration_on)
	if GameSession.vibration_on:
		Input.vibrate_handheld(60)
	_refresh_settings()


## Plays a splash on a fresh player and reports what the phone sees, so a missing sound can be traced
## without a console: is the file there, is the setting on, is the master bus muted.
func _sound_test() -> void:
	var s := load("res://assets/audio/splash_small.wav") as AudioStreamWAV
	var lines: Array[String] = []
	lines.append("sound file: %s" % ("found" if s != null else "MISSING"))
	lines.append("setting: %s   master bus muted: %s   buses: %d   mix rate: %d Hz" % [
		"ON" if GameSession.sound_on else "OFF", "YES" if AudioServer.is_bus_mute(0) else "no", AudioServer.bus_count, int(AudioServer.get_mix_rate())])
	if s != null:
		var p := AudioStreamPlayer.new()
		p.stream = s
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
		lines.append("playing a splash now. If you hear nothing: check the phone's silent switch and volume.")
	_diag.text = "\n".join(lines)


func _toggle_test_tools() -> void:
	GameSession.set_test_tools(not GameSession.test_tools)
	_refresh_settings()


func _refresh_settings() -> void:
	_test_btn.text = "TEST TOOLS: %s" % ("ON" if GameSession.test_tools else "OFF")
	_sound_btn.text = "SOUND: %s" % ("ON" if GameSession.sound_on else "OFF")
	_vibrate_btn.text = "VIBRATION: %s" % ("ON" if GameSession.vibration_on else "OFF")


func _on_play() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


# ---------------------------------------------------------------- motion and drawing
func _process(delta: float) -> void:
	_time += delta
	for f in _fish:
		# wander steering: a target point on a circle ahead, nudged by a Perlin-driven angle
		var pos: Vector2 = f["pos"]
		var vel: Vector2 = f["vel"]
		var w: float = f["wander"] + (_noise.get_noise_2d(pos.x * 0.01, _time) * 2.0) * delta * 3.0
		f["wander"] = w
		var heading := vel.normalized() if vel.length() > 1.0 else Vector2.RIGHT
		var target := heading * 40.0 + Vector2.from_angle(w) * 22.0
		var steer := (target.normalized() * 55.0 - vel).limit_length(90.0)
		# contain: push back from the edges of the water band
		if pos.x < 80.0:
			steer.x += 140.0
		elif pos.x > size.x - 80.0:              # the whole screen width (aspect "expand")
			steer.x -= 140.0
		if pos.y < 280.0:
			steer.y += 120.0
		elif pos.y > 680.0:
			steer.y -= 120.0
		vel = (vel + steer * delta).limit_length(70.0)
		f["vel"] = vel
		f["pos"] = pos + vel * delta
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var corners := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(corners, PackedColorArray([SEA_TOP, SEA_TOP, SEA_BOTTOM, SEA_BOTTOM]))
	for f in _fish:
		_draw_fish(f)
	for layer in WAVE_LAYERS:
		_draw_wave(layer)


func _draw_wave(layer: int) -> void:
	var base := 250.0 + float(layer) * 95.0
	var amp := 8.0 + float(layer) * 3.0
	var pts := PackedVector2Array()
	var step := 20.0
	var x := 0.0
	while x <= size.x + step:
		var y := base + sin(x * 0.012 + _time * (0.6 + 0.15 * layer) + layer) * amp
		y += _noise.get_noise_2d(x * 0.004 + layer * 10.0, _time * 0.3) * amp * 1.5
		pts.append(Vector2(x, y))
		x += step
	var poly := pts.duplicate()
	poly.append(Vector2(size.x, size.y))
	poly.append(Vector2(0.0, size.y))
	var a := 0.08 + 0.02 * float(layer)
	draw_colored_polygon(poly, Color(0.55, 0.85, 0.95, a))
	draw_polyline(pts, Color(1, 1, 1, 0.18), 2.0, true)


func _draw_fish(f: Dictionary) -> void:
	var pos: Vector2 = f["pos"]
	var vel: Vector2 = f["vel"]
	var s: float = f["size"]
	var dir := 1.0 if vel.x >= 0.0 else -1.0
	var sp := String(f.get("sp", ""))
	if sp != "" and RealFish.sprite(sp) != null:
		# a painted fish a little below the surface: slightly dim, swimming with a gentle bend
		var tilt := clampf(vel.y / maxf(absf(vel.x), 20.0), -0.4, 0.4) * dir
		RealFish.draw(self, sp, pos, s * 4.4, tilt, dir, _time * 6.0 + pos.y * 0.05, 0.7, 0.82, 0.3)
		return
	var col := Color.from_hsv(float(f["hue"]), 0.35, 0.95, 0.55)
	var wag := sin(_time * 6.0 + pos.x * 0.05) * s * 0.25
	var body := PackedVector2Array([
		pos + Vector2(dir * s * 1.2, 0.0), pos + Vector2(dir * s * 0.2, -s * 0.5),
		pos + Vector2(-dir * s * 0.8, wag * 0.3), pos + Vector2(dir * s * 0.2, s * 0.5)])
	draw_colored_polygon(body, col)
	var tail := PackedVector2Array([
		pos + Vector2(-dir * s * 0.7, wag * 0.3),
		pos + Vector2(-dir * s * 1.3, -s * 0.45 + wag), pos + Vector2(-dir * s * 1.3, s * 0.45 + wag)])
	draw_colored_polygon(tail, col)
