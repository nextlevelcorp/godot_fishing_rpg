## Keeps the game well-behaved on phones.
##   - Held upright (portrait): the game is built for landscape, so it pauses and asks the player to
##     turn the phone, instead of shrinking everything to a third of its size.
##   - App sent to the background, tab hidden or window focus lost: pauses, mutes, and waits for a tap
##     (a tap is also the user gesture browsers need before audio may play again).
## Add one to every scene a player can sit in. It keeps running while the tree is paused.
class_name DeviceGuard
extends CanvasLayer

var _panel: ColorRect
var _title: Label
var _sub: Label
var _portrait := false
var _away := false
var _check_t := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	_panel.color = Color(0.01, 0.05, 0.10, 0.96)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)
	_title = _make_label(44)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_title.offset_left = -520.0
	_title.offset_right = 520.0
	_title.offset_top = -90.0
	_title.offset_bottom = -20.0
	_sub = _make_label(24)
	_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_sub.offset_left = -520.0
	_sub.offset_right = 520.0
	_sub.offset_top = 10.0
	_sub.offset_bottom = 120.0
	_panel.visible = false
	get_viewport().size_changed.connect(_check_orientation)
	_check_orientation()


func _make_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(l)
	return l


func _process(delta: float) -> void:
	_check_t += delta
	if _check_t >= 0.5:            # some browsers rotate without a resize signal
		_check_t = 0.0
		_check_orientation()


func _check_orientation() -> void:
	var win := get_window().size
	var portrait := win.y > int(float(win.x) * 1.05)
	if portrait != _portrait:
		_portrait = portrait
		_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if not _away:
			_away = true
			_apply()


func _on_panel_input(event: InputEvent) -> void:
	if not _away or _portrait:
		return
	var tapped := (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed)
	if tapped:
		_away = false
		_apply()


func _apply() -> void:
	var stop := _portrait or _away
	get_tree().paused = stop
	AudioServer.set_bus_mute(0, stop)
	_panel.visible = stop
	if _portrait:
		_title.text = "Telefonu yatay çevir\nRotate your phone"
		_sub.text = "The game is played in landscape."
	elif _away:
		_title.text = "Paused"
		_sub.text = "Tap to continue"
