extends Node
## Glue: menu/lobby UI, input capture, sound, and switching the world view
## between the lobby backdrop and the live expedition.

const SOUNDS := {
	"splash": "splash", "washed": "thud", "fell": "thud", "stuck": "squelch", "pickup": "pickup", "drop": "drop",
	"rope": "woosh", "miss": "woosh", "snap": "woosh", "whistle": "whistle", "steal": "steal", "grumble": "grumble",
	"munch": "munch", "raft": "wood", "board": "wood", "land": "wood", "tug": "tug", "nope": "nope", "gust": "woosh", "win": "win",
}

var view: Node2D
var hud: Control
var menu: Control
var backdrop := ExpeditionSim.new()
var status_label: Label
var code_label: Label
var roster_label: Label
var start_button: Button
var join_input: LineEdit
var seed_input: LineEdit
var chat_log: RichTextLabel
var streams: Dictionary = {}
var voices: Array = []
var _escape_time := 0.0

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_quit)
	view = preload("res://game/world_view.gd").new()
	add_child(view)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hud = preload("res://game/hud.gd").new()
	layer.add_child(hud)
	_build_menu(layer)
	_load_audio()
	backdrop.setup(randi() % 100000, [])
	view.show_sim(backdrop, 0)
	Session.phase_changed.connect(_phase_changed)
	Session.roster_changed.connect(_refresh)
	Rooms.changed.connect(_refresh)
	Session.status_changed.connect(func(message: String) -> void: status_label.text = message)
	Session.sim_event.connect(_sim_event)
	Session.chat_received.connect(func(message: String) -> void:
		chat_log.add_text(message + "\n")
		hud.show_toast(message))
	_refresh()
	var args := OS.get_cmdline_user_args()
	if "--native-smoke" in args:
		_native_smoke()
		return
	if "--host" in args or OS.has_feature("dedicated_server"):
		_host_from_cli()
	for arg in args:
		if arg.begins_with("--join="):
			Rooms.join(arg.trim_prefix("--join="))
		if arg.begins_with("--ticket-file="):
			_write_ticket_later(arg.trim_prefix("--ticket-file="))
		if arg.begins_with("--seed="):
			seed_input.text = arg.trim_prefix("--seed=")
	if "--solo" in args:
		_start()

# --- menu -------------------------------------------------------------------

func _build_menu(layer: CanvasLayer) -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 17
	for type in ["Button", "LineEdit"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = {"hover": Color("3d5a45"), "pressed": Color("24382b"), "disabled": Color(0.2, 0.2, 0.2, 0.6)}.get(state, Color("2e4636"))
			if type == "LineEdit":
				box.bg_color = Color(0.08, 0.1, 0.09, 0.9)
			box.set_corner_radius_all(8)
			box.set_content_margin_all(10)
			box.content_margin_left = 16
			box.content_margin_right = 16
			if state == "focus":
				box.draw_center = false
				box.set_border_width_all(2)
				box.border_color = Color("ffe08a")
			theme_resource.set_stylebox(state, type, box)
		theme_resource.set_color("font_color", type, Color("f4f1de"))
	menu = Control.new()
	menu.theme = theme_resource
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(menu)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.08, 0.06, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var panel := PanelContainer.new()
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.09, 0.12, 0.1, 0.92)
	panel_box.set_corner_radius_all(16)
	panel_box.set_content_margin_all(28)
	panel_box.set_border_width_all(2)
	panel_box.border_color = Color("ffe08a")
	panel.add_theme_stylebox_override("panel", panel_box)
	panel.custom_minimum_size.x = 560
	center.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	panel.add_child(stack)
	var title := Label.new()
	title.text = "THE GREAT EXPEDITION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("ffe08a"))
	stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Tiny explorers. Big wilderness. Get everyone to the egg."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.8, 0.88, 0.8)
	stack.add_child(subtitle)
	stack.add_child(HSeparator.new())
	start_button = _button(stack, "Start solo expedition", _start)
	start_button.add_theme_font_size_override("font_size", 22)
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "Route number (blank = surprise me)"
	seed_input.max_length = 6
	stack.add_child(seed_input)
	stack.add_child(HSeparator.new())
	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 10)
	stack.add_child(host_row)
	_button(host_row, "Host a party", func() -> void: Rooms.host())
	_button(host_row, "Copy code", func() -> void:
		if not Rooms.code.is_empty():
			DisplayServer.clipboard_set(Rooms.code))
	_button(host_row, "Copy ticket", func() -> void:
		if not Session.ticket().is_empty():
			DisplayServer.clipboard_set(Session.ticket())
			status_label.text = "Ticket copied · paste it on another device")
	_button(host_row, "Leave", func() -> void: Session.leave())
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	stack.add_child(join_row)
	join_input = LineEdit.new()
	join_input.placeholder_text = "Join code (or full ticket)"
	join_input.max_length = 8192
	join_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_input.text_submitted.connect(func(_text: String) -> void: Rooms.join(join_input.text))
	join_row.add_child(join_input)
	_button(join_row, "Join", func() -> void: Rooms.join(join_input.text))
	code_label = Label.new()
	code_label.add_theme_font_size_override("font_size", 24)
	code_label.add_theme_color_override("font_color", Color("9be3d3"))
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(code_label)
	roster_label = Label.new()
	roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(roster_label)
	status_label = Label.new()
	status_label.text = Session.status
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(0.55, 0.92, 0.78)
	stack.add_child(status_label)
	chat_log = RichTextLabel.new()
	chat_log.custom_minimum_size.y = 56
	chat_log.scroll_following = true
	stack.add_child(chat_log)
	var chat_input := LineEdit.new()
	chat_input.placeholder_text = "Message the party…"
	chat_input.max_length = 160
	chat_input.text_submitted.connect(func(text: String) -> void:
		Session.send_chat(text)
		chat_input.clear())
	stack.add_child(chat_input)
	if not Session.available():
		status_label.text = "Solo only · run python3 tools/build_native.py to enable multiplayer"

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void:
		_play("click", 0.0)
		action.call())
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button

func _refresh() -> void:
	var count := Session.roster.size()
	start_button.disabled = not Session.is_authority()
	if Session.role == "offline":
		start_button.text = "Start solo expedition"
	elif Session.role == "host":
		start_button.text = "Start expedition  ·  %d explorer%s" % [count, "" if count == 1 else "s"]
	else:
		start_button.text = "Waiting for the host to start…"
	seed_input.visible = Session.is_authority()
	roster_label.visible = Session.role != "offline"
	roster_label.text = "%d / %d explorers in the party" % [count, Session.MAX_PLAYERS]

func _start() -> void:
	Session.start_game(int(seed_input.text) if seed_input.text.is_valid_int() else -1)

func _phase_changed() -> void:
	var playing := Session.phase == "playing"
	menu.visible = not playing
	if playing:
		view.show_sim(Session.sim, Session.local_id)
		if menu.get_viewport().gui_get_focus_owner() != null:
			menu.get_viewport().gui_get_focus_owner().release_focus()
	else:
		view.show_sim(backdrop, 0)
	_refresh()

# --- per-frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	_escape_time -= delta
	var seconds := maxi(0, int(Rooms.expires_at - Time.get_unix_time_from_system()))
	code_label.visible = not Rooms.code.is_empty()
	code_label.text = "JOIN CODE  %s   ·   %d:%02d" % [Rooms.code, seconds / 60, seconds % 60] if seconds > 0 else "Code expired (the party stays connected)"
	if Session.phase == "playing":
		var axis := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): axis.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): axis.x += 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): axis.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): axis.y += 1
		Session.direction = axis.normalized()
		if view.sim != Session.sim:
			view.show_sim(Session.sim, Session.local_id)
	else:
		Session.direction = Vector2.ZERO
		backdrop.tick(delta)
		backdrop.events.clear()

func _unhandled_key_input(event: InputEvent) -> void:
	if Session.phase != "playing" or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE: Session.act("use")
		KEY_E: Session.act("interact")
		KEY_Q: Session.act("drop")
		KEY_TAB: Session.act("next")
		KEY_1: Session.act("slot", 0)
		KEY_2: Session.act("slot", 1)
		KEY_3: Session.act("slot", 2)
		KEY_ENTER, KEY_KP_ENTER:
			if Session.sim.won and Session.is_authority():
				Session.start_game()
		KEY_ESCAPE:
			if _escape_time > 0.0 or Session.sim.won:
				if Session.is_authority():
					Session.end_game()
				else:
					Session.leave()
			else:
				_escape_time = 2.5
				hud.show_toast("Press Esc again to leave the expedition")
		_: return
	get_viewport().set_input_as_handled()

# --- sound ------------------------------------------------------------------

func _load_audio() -> void:
	for sound_name: String in ["splash", "thud", "squelch", "pickup", "drop", "woosh", "whistle", "steal", "grumble", "munch", "wood", "tug", "nope", "click", "win"]:
		var path := "res://assets/sfx/%s.ogg" % sound_name
		if ResourceLoader.exists(path):
			streams[sound_name] = load(path)
	for index in range(8):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	# Headless runs (smoke tests, dedicated server) skip music: nobody hears it, and a
	# looping playback still active at quit leaks and fails the export check.
	var headless := DisplayServer.get_name() == "headless"
	if ResourceLoader.exists("res://assets/music/stroll.ogg") and not headless and not "--quiet" in OS.get_cmdline_user_args():
		var music := AudioStreamPlayer.new()
		var stream: AudioStream = load("res://assets/music/stroll.ogg")
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		music.stream = stream
		music.volume_db = -22.0
		add_child(music)
		music.play()

func _play(sound_name: String, volume_db: float) -> void:
	if not streams.has(sound_name):
		return
	for voice: AudioStreamPlayer in voices:
		if not voice.playing:
			voice.stream = streams[sound_name]
			voice.volume_db = volume_db
			voice.pitch_scale = randf_range(0.92, 1.08)
			voice.play()
			return

func _sim_event(event_name: String, pos: Vector2) -> void:
	view.on_event(event_name, pos)
	var player: Dictionary = Session.local_player()
	var distance := 0.0 if player.is_empty() or event_name in ["gust", "win"] else float(player.pos.distance_to(pos))
	if event_name == "gust" and (player.is_empty() or Session.sim.terrain.zone_at(player.pos.x).kind != Defs.Z_RIDGE):
		return
	if distance < 800.0 and SOUNDS.has(event_name):
		_play(SOUNDS[event_name], -6.0 - distance / 40.0)

# --- command line / lifecycle -----------------------------------------------

func _write_ticket_later(path: String) -> void:
	await get_tree().create_timer(2.0).timeout
	if Session.role == "host":
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(Session.ticket())

func _quit() -> void:
	Session.leave()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

func _host_from_cli() -> void:
	if await Rooms.host():
		print("ROOM_READY code=" + Rooms.code)
	elif Session.role != "host":
		push_error("Host startup failed")
		get_tree().quit(1)
	else:
		print("Host is running by ticket; code service unavailable.")

func _native_smoke() -> void:
	if not Session.host():
		push_error("Native extension did not start an Iroh host")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.25).timeout
	Session.leave()
	await get_tree().create_timer(0.25).timeout
	print("NATIVE_RUNTIME_PASS")
	get_tree().quit()
