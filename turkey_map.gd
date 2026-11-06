## Stylised map of Turkey. Tap a pin to choose a real fishing spot, then go fishing there.
## The coastline is a hand-simplified outline in (lat, lon): it looks right at game scale but is not
## survey data. Pins use the town-level coordinates in fishing_spots.gd.
class_name TurkeyMap
extends Control

const LIVE_BAIT_PRICE := 30

const LAT_MIN := 35.6
const LAT_MAX := 42.4
const LON_MIN := 25.5
const LON_MAX := 45.0
const REF_LAT_DEG := 39.0       ## longitude is squeezed by cos(this) so the shape is not stretched

const PIN_SIZE := 44.0
const TOP_BAR := 64.0
const PANEL_HEIGHT := 250.0

const SEA_TOP := Color(0.02, 0.26, 0.42)
const SEA_BOTTOM := Color(0.02, 0.52, 0.68)
const SEA_LABEL := Color(1, 1, 1, 0.35)
const LAND := Color(0.88, 0.80, 0.58)
const LAND_SHADOW := Color(0.0, 0.1, 0.2, 0.35)
const LAND_EDGE := Color(1.0, 0.97, 0.85, 0.95)
const PIN_COLOR := Color(1.0, 0.45, 0.20)
const PIN_SELECTED := Color(1.0, 0.85, 0.20)

## Turkey, clockwise from the north-west corner (lat, lon). Stylised.
const OUTLINE: Array[Vector2] = [
	Vector2(41.74, 26.36), Vector2(41.90, 26.60), Vector2(42.00, 27.20), Vector2(41.98, 28.02),
	Vector2(41.60, 28.10), Vector2(41.35, 28.70), Vector2(41.22, 29.12), Vector2(41.17, 29.61),
	Vector2(41.12, 30.15), Vector2(41.10, 30.70), Vector2(41.09, 31.12), Vector2(41.28, 31.42),
	Vector2(41.45, 31.79), Vector2(41.75, 32.38), Vector2(41.88, 32.95), Vector2(41.98, 33.77),
	Vector2(42.10, 34.95), Vector2(41.80, 35.25), Vector2(41.72, 35.95), Vector2(41.29, 36.33),
	Vector2(41.15, 37.00), Vector2(40.98, 37.88), Vector2(40.92, 38.39), Vector2(41.02, 39.72),
	Vector2(41.03, 40.52), Vector2(41.40, 41.43), Vector2(41.52, 41.53), Vector2(41.55, 42.50),
	Vector2(41.50, 43.20), Vector2(40.95, 43.65), Vector2(40.45, 43.60), Vector2(40.05, 44.10),
	Vector2(39.70, 44.50), Vector2(39.40, 44.80), Vector2(38.40, 44.35), Vector2(37.60, 44.75),
	Vector2(37.30, 44.60), Vector2(37.10, 43.80), Vector2(37.15, 42.35), Vector2(37.05, 41.20),
	Vector2(36.85, 40.05), Vector2(36.70, 38.95), Vector2(36.83, 38.00), Vector2(36.60, 37.10),
	Vector2(36.20, 36.65), Vector2(35.85, 36.15), Vector2(36.10, 35.90), Vector2(36.60, 36.20),
	Vector2(36.85, 36.00), Vector2(36.75, 35.80), Vector2(36.55, 35.40), Vector2(36.80, 34.64),
	Vector2(36.38, 33.93), Vector2(36.07, 32.83), Vector2(36.54, 32.00), Vector2(36.78, 31.45),
	Vector2(36.88, 30.70), Vector2(36.40, 30.40), Vector2(36.30, 30.15), Vector2(36.20, 29.64),
	Vector2(36.27, 29.42), Vector2(36.62, 29.10), Vector2(36.76, 28.80), Vector2(36.85, 28.27),
	Vector2(36.70, 27.55), Vector2(37.03, 27.43), Vector2(37.40, 27.25), Vector2(37.86, 27.26),
	Vector2(38.15, 26.80), Vector2(38.30, 26.25), Vector2(38.67, 26.50), Vector2(39.07, 26.85),
	Vector2(39.31, 26.69), Vector2(39.48, 26.08), Vector2(39.90, 26.18), Vector2(40.04, 26.20),
	Vector2(40.45, 26.15), Vector2(40.75, 26.05), Vector2(41.25, 26.40),
]

## The Sea of Marmara, drawn in sea colour on top of the land.
const MARMARA: Array[Vector2] = [
	Vector2(40.40, 26.72), Vector2(40.60, 27.00), Vector2(40.90, 27.45), Vector2(40.97, 28.00),
	Vector2(41.00, 28.65), Vector2(41.02, 29.00), Vector2(40.80, 29.15), Vector2(40.78, 29.60),
	Vector2(40.73, 29.95), Vector2(40.72, 29.40), Vector2(40.55, 29.20), Vector2(40.38, 28.90),
	Vector2(40.40, 28.30), Vector2(40.38, 27.80), Vector2(40.40, 27.30),
]

const SEA_LABELS := [
	["BLACK SEA", 43.0, 34.0],
	["AEGEAN", 38.7, 25.9],
	["MEDITERRANEAN", 35.9, 31.0],
]

var _map_rect := Rect2()
var _land_pts := PackedVector2Array()
var _marmara_pts := PackedVector2Array()
var _pins: Dictionary = {}              # spot id -> Button
var _selected := ""
var _time := 0.0

var _panel: PanelContainer
var _title: Label
var _sub: Label
var _fish_label: Label
var _note_label: Label
var _go_button: Button
var _coins_label: Label
var _overlay: PanelContainer
var _overlay_title: Label
var _overlay_list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GameSession.load_once()
	add_child(DeviceGuard.new())
	_build_header()
	_build_pins()
	_build_panel()
	_build_overlay()
	_update_coins()
	resized.connect(_layout)
	_layout()
	if GameSession.spot_id != "" and _pins.has(GameSession.spot_id):
		_select(GameSession.spot_id)


func _process(delta: float) -> void:
	_time += delta
	if _selected != "":
		queue_redraw()


# ---------------------------------------------------------------- building the UI
func _build_header() -> void:
	var header := Label.new()
	header.name = "Header"
	header.text = "Choose your fishing spot  -  Türkiye      [%s]" % GameSession.BUILD
	header.position = Vector2(20, 14)
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", Color.WHITE)
	header.add_theme_color_override("font_outline_color", Color(0, 0.1, 0.2, 0.9))
	header.add_theme_constant_override("outline_size", 6)
	add_child(header)

	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bar.offset_left = -560.0
	bar.offset_right = -16.0
	bar.offset_top = 6.0
	bar.offset_bottom = 60.0
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	_coins_label = _make_label(bar, 22, Color(1.0, 0.9, 0.5))
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_make_button("TACKLE", 150.0, _open_tackle))
	bar.add_child(_make_button("JOURNAL", 160.0, _open_journal))
	_update_coins()


func _build_pins() -> void:
	for id: String in FishingSpots.ids():
		var b := Button.new()
		b.name = "Pin_" + id
		b.custom_minimum_size = Vector2(PIN_SIZE, PIN_SIZE)
		b.size = Vector2(PIN_SIZE, PIN_SIZE)
		b.focus_mode = Control.FOCUS_NONE
		_style_pin(b, false)
		b.pressed.connect(_select.bind(id))
		add_child(b)
		_pins[id] = b


func _style_pin(b: Button, selected: bool, locked: bool = false) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.47, 0.5) if locked else (PIN_SELECTED if selected else PIN_COLOR)
	sb.set_corner_radius_all(int(PIN_SIZE * 0.5))
	sb.set_border_width_all(4)
	sb.border_color = Color.WHITE
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "InfoPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 12.0
	_panel.offset_right = -12.0
	_panel.offset_top = -PANEL_HEIGHT
	_panel.offset_bottom = -12.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.88)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	_title = _make_label(box, 26, Color.WHITE)
	_sub = _make_label(box, 17, Color(0.8, 0.9, 1.0))
	_fish_label = _make_label(box, 18, Color(1.0, 0.9, 0.6))
	_note_label = _make_label(box, 14, Color(0.7, 0.8, 0.9))
	_title.text = "Tap a pin to pick a spot"
	_sub.text = "Each pin is a real place where people fish in Türkiye."

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	_go_button = Button.new()
	_go_button.text = "FISH HERE"
	_go_button.custom_minimum_size = Vector2(240, 60)
	_go_button.add_theme_font_size_override("font_size", 24)
	_go_button.disabled = true
	_go_button.pressed.connect(_on_go_pressed)
	row.add_child(_go_button)

	var sandbox := Button.new()
	sandbox.text = "Boat sandbox"
	sandbox.custom_minimum_size = Vector2(200, 60)
	sandbox.add_theme_font_size_override("font_size", 20)
	sandbox.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://main_sandbox.tscn"))
	row.add_child(sandbox)


func _make_label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


# ---------------------------------------------------------------- layout and projection
func _layout() -> void:
	_map_rect = Rect2(Vector2(16, TOP_BAR), size - Vector2(32, TOP_BAR + PANEL_HEIGHT + 20.0))
	_land_pts = _project_all(OUTLINE)
	_marmara_pts = _project_all(MARMARA)
	for id: String in _pins:
		var b: Button = _pins[id]
		b.position = _project(FishingSpots.get_spot(id)["lat_lon"]) - b.size * 0.5
	queue_redraw()


func _project_all(points: Array[Vector2]) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_project(p))
	return out


## (lat, lon) -> local pixel position inside the map rect, keeping the shape proportions.
func _project(lat_lon: Vector2) -> Vector2:
	var kx := cos(deg_to_rad(REF_LAT_DEG))
	var w := (LON_MAX - LON_MIN) * kx
	var h := LAT_MAX - LAT_MIN
	var s := minf(_map_rect.size.x / w, _map_rect.size.y / h)
	var origin := _map_rect.position + (_map_rect.size - Vector2(w, h) * s) * 0.5
	return origin + Vector2((lat_lon.y - LON_MIN) * kx, LAT_MAX - lat_lon.x) * s


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var corners := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(corners, PackedColorArray([SEA_TOP, SEA_TOP, SEA_BOTTOM, SEA_BOTTOM]))

	if _land_pts.size() >= 3:
		var shadow := PackedVector2Array()
		for p in _land_pts:
			shadow.append(p + Vector2(0, 7))
		draw_colored_polygon(shadow, LAND_SHADOW)
		draw_colored_polygon(_land_pts, LAND)
	if _marmara_pts.size() >= 3:
		draw_colored_polygon(_marmara_pts, SEA_BOTTOM.lerp(SEA_TOP, 0.35))
	if _land_pts.size() >= 3:
		var edge := _land_pts.duplicate()
		edge.append(_land_pts[0])
		draw_polyline(edge, LAND_EDGE, 3.0, true)

	var font := ThemeDB.fallback_font
	for entry in SEA_LABELS:
		var pos := _project(Vector2(entry[1], entry[2]))
		draw_string(font, pos, entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, SEA_LABEL)

	if _selected != "" and _pins.has(_selected):
		var b: Button = _pins[_selected]
		var c := b.position + b.size * 0.5
		var pulse := 0.5 + 0.5 * sin(_time * 3.0)
		draw_arc(c, PIN_SIZE * 0.5 + 8.0 + pulse * 8.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8 - pulse * 0.5), 3.0)
		var name_text: String = FishingSpots.get_spot(_selected)["name"]
		var tw := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, c + Vector2(-tw * 0.5, -PIN_SIZE * 0.5 - 14.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)


# ---------------------------------------------------------------- selecting
func _select(id: String) -> void:
	_selected = id
	for pid: String in _pins:
		_style_pin(_pins[pid], pid == id, not GameSession.is_unlocked(FishingSpots.get_spot(pid)))
	var s := FishingSpots.get_spot(id)
	_title.text = "%s  (%s)" % [s["name"], s["local_name"]]
	_sub.text = "%s  -  %s" % [s["region"], s["blurb"]]
	var names: Array[String] = []
	for sid: String in s["species"]:
		names.append(String(BiomeDB.get_species(sid).get("name", sid)))
	var ids: Array = s["species"]
	_fish_label.text = "Fish here (%d/%d caught): %s" % [_caught_count(ids), ids.size(), ", ".join(names)]
	_note_label.text = "Evidence: %s (%d sources). %s Pin is town-level, not the exact mark." % [s["evidence"], s["sources"].size(), s["species_note"]]
	var need := int(s.get("unlock_level", 1))
	if GameSession.is_unlocked(s):
		_go_button.disabled = false
		_go_button.text = "FISH HERE"
	else:
		_go_button.disabled = true
		_go_button.text = "LOCKED - LEVEL %d" % need
		_note_label.text = "Reach level %d to fish here (you are level %d). Catch fish at other spots to earn XP. %s" % [need, GameSession.level(), _note_label.text]
	queue_redraw()


func _caught_count(ids: Array) -> int:
	var n := 0
	for fid: String in ids:
		if GameSession.counts.has(fid):
			n += 1
	return n


func _update_coins() -> void:
	var prog := GameSession.level_progress()
	_coins_label.text = "Level %d  (%d/%d XP)   Coins: %d" % [GameSession.level(), int(prog.x), int(prog.y), GameSession.coins]
	for pid: String in _pins:
		_style_pin(_pins[pid], pid == _selected, not GameSession.is_unlocked(FishingSpots.get_spot(pid)))


func _make_button(text: String, width: float, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 54.0)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


# ---------------------------------------------------------------- tackle shop and journal
func _build_overlay() -> void:
	_overlay = PanelContainer.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay.offset_left = -420.0
	_overlay.offset_right = 420.0
	_overlay.offset_top = -300.0
	_overlay.offset_bottom = 300.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.10, 0.18, 0.96)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(18)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.25)
	_overlay.add_theme_stylebox_override("panel", style)
	add_child(_overlay)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_overlay.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_overlay_title = _make_label(top, 28, Color.WHITE)
	top.add_child(_make_button("CLOSE", 140.0, func() -> void: _overlay.visible = false))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_overlay_list = VBoxContainer.new()
	_overlay_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlay_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_overlay_list)
	_overlay.visible = false


func _clear_list() -> void:
	for c in _overlay_list.get_children():
		c.queue_free()


func _open_tackle() -> void:
	_clear_list()
	_overlay_title.text = "Tackle  -  Coins: %d" % GameSession.coins
	for rid: String in GameSession.SHORE_RIGS:
		var rig := BiomeDB.get_rig(rid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_overlay_list.add_child(row)
		var info := _make_label(row, 18, Color.WHITE)
		info.text = "%s\nLine breaks at %.0f N, clutch up to %.0f N, %.0f m of line" % [rig["name"], rig["line_break_force_n"], rig["drag_max_n"], rig["spool_m"]]
		var price := int(rig.get("price", 0))
		var b: Button
		if GameSession.rig_id == rid:
			b = _make_button("EQUIPPED", 190.0, func() -> void: pass)
			b.disabled = true
		elif GameSession.owned_rigs.has(rid):
			b = _make_button("EQUIP", 190.0, func() -> void:
				GameSession.equip(rid)
				_open_tackle())
		else:
			b = _make_button("BUY  %d" % price, 190.0, func() -> void:
				GameSession.buy_rig(rid, price)
				_update_coins()
				_open_tackle())
			b.disabled = GameSession.coins < price
		row.add_child(b)
	var bait_row := HBoxContainer.new()
	bait_row.add_theme_constant_override("separation", 12)
	_overlay_list.add_child(bait_row)
	var bait_info := _make_label(bait_row, 18, Color.WHITE)
	bait_info.text = "Live baitfish (canli yem), 5 in a bucket\nIn the bucket: %d / %d. Bluefish, seabass, dentex and amberjack love it." % [GameSession.live_bait, GameSession.LIVE_BAIT_MAX]
	var bb := _make_button("BUY 5  %d" % LIVE_BAIT_PRICE, 190.0, func() -> void:
		GameSession.buy_live_bait(5, LIVE_BAIT_PRICE)
		_update_coins()
		_open_tackle())
	bb.disabled = GameSession.coins < LIVE_BAIT_PRICE or GameSession.live_bait >= GameSession.LIVE_BAIT_MAX
	bait_row.add_child(bb)
	var net_row := HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 12)
	_overlay_list.add_child(net_row)
	var net_info := _make_label(net_row, 18, Color.WHITE)
	net_info.text = "Landing net (kepce)\nLands heavy fish from piers, quays and bridges, where lifting on the line can part it."
	var nb: Button
	if GameSession.has_net:
		nb = _make_button("OWNED", 190.0, func() -> void: pass)
		nb.disabled = true
	else:
		nb = _make_button("BUY  %d" % GameSession.NET_PRICE, 190.0, func() -> void:
			GameSession.buy_net()
			_update_coins()
			_open_tackle())
		nb.disabled = GameSession.coins < GameSession.NET_PRICE
	net_row.add_child(nb)
	var tip := _make_label(_overlay_list, 15, Color(0.7, 0.8, 0.9))
	tip.text = "A stronger rig lets you hold big fish without snapping the line. The biggest fish here can still out-pull it: use the clutch."
	_overlay.visible = true


func _open_journal() -> void:
	_clear_list()
	_overlay_title.text = "Journal  -  %d species landed" % GameSession.counts.size()
	for spot_key: String in FishingSpots.ids():
		var s := FishingSpots.get_spot(spot_key)
		var ids: Array = s["species"]
		var head := _make_label(_overlay_list, 20, Color(1.0, 0.9, 0.6))
		head.text = "%s  -  %d / %d species" % [s["name"], _caught_count(ids), ids.size()]
		for fid: String in ids:
			var known := GameSession.counts.has(fid)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			_overlay_list.add_child(row)
			row.add_child(FishIcon.new(fid, known))
			var info := _make_label(row, 15, Color(0.85, 0.9, 1.0))
			var sp := BiomeDB.get_species(fid)
			var season := Season.label(fid)
			var season_txt := ("  [%s in %s]" % [season, Season.month_name()]) if season != "" else ""
			if Regulations.min_cm(fid) > 0.0:
				season_txt += "  [legal size %.0f cm]" % Regulations.min_cm(fid)
			var baits := ", ".join(Tackle.best_baits(fid))
			if known:
				var dr: Vector2 = sp["depth_m"]
				info.text = "%s  (%s)%s\nBest %.2f kg, landed %d.  %.0f-%.0f m deep, feeds %s.\nBait: %s.  Hook %s." % [sp["name"], sp["scientific"], season_txt,
					float(GameSession.best_kg[fid]), int(GameSession.counts[fid]), dr.x, dr.y, _feeds_text(fid), baits, Tackle.hook_range(fid)]
			else:
				info.text = "???  Not caught yet.%s\nLocals say: try %s, %s." % [season_txt, baits if baits != "" else "different baits", _feeds_text(fid)]
	_overlay.visible = true


## When a species feeds, in words (see BiomeDB.ACTIVITY).
func _feeds_text(fid: String) -> String:
	match BiomeDB.activity_kind(fid):
		"night":
			return "at night"
		"day":
			return "by day"
	return "at dawn and dusk"


func _on_go_pressed() -> void:
	if _selected == "" or not GameSession.is_unlocked(FishingSpots.get_spot(_selected)):
		return
	GameSession.spot_id = _selected
	get_tree().change_scene_to_file("res://shore_fishing.tscn")
