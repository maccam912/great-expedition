extends Node
## Host-authoritative Great Expedition protocol over Iroh packet channels.
## The host ticks an ExpeditionSim; clients mirror it from snapshots.
## See docs/DESIGN.md (protocol table) and docs/NETWORKING.md (transport).

signal status_changed(message: String)
signal chat_received(message: String)
signal session_closed
signal phase_changed
signal roster_changed
signal sim_event(name: String, pos: Vector2)

const PROTOCOL := 2
const MAX_PLAYERS := Defs.MAX_PLAYERS
const CONNECT_TIMEOUT_MS := 18000
const ACTIONS := ["use", "interact", "drop", "slot", "next"]

var peer: MultiplayerPeer
var role := "offline"
var status := "Solo expedition"
var local_id := 1
var phase := "lobby"            # "lobby" or "playing"
var roster: Array = [1]
var sim := ExpeditionSim.new()
var seed_value := 0
var direction := Vector2.ZERO
var input_times: Dictionary = {}
var pending: Dictionary = {}
var last_chat: Dictionary = {}
var act_budget: Dictionary = {}
var snapshots_received := 0
var _send_clock := 0.0
var _entity_clock := 0.0
var _clock := 0.0
var _started_at := 0
var _welcomed := false

func available() -> bool:
	if not ClassDB.class_exists("IrohServer") or not ClassDB.class_exists("IrohClient"):
		return false
	if OS.has_feature("android"):
		return Engine.has_singleton("IrohAndroid") and bool(Engine.get_singleton("IrohAndroid").call("initializeIroh"))
	return true

func is_authority() -> bool:
	return role == "host" or role == "offline"

func host() -> bool:
	leave()
	if not available():
		_set_status("Build the native extension first: python3 tools/build_native.py")
		return false
	peer = ClassDB.class_call_static("IrohServer", "start_configured", "--relay-only" in OS.get_cmdline_user_args())
	if peer == null:
		_set_status("Could not start Iroh. Check the console and network access.")
		return false
	role = "host"
	peer.peer_connected.connect(_peer_connected)
	peer.peer_disconnected.connect(_peer_disconnected)
	_set_status("Hosting · share your connection ticket")
	roster_changed.emit()
	return true

func join(ticket: String) -> bool:
	leave()
	if not available():
		_set_status("Iroh extension unavailable on this build.")
		return false
	ticket = ticket.strip_edges()
	if (not ticket.begins_with("git1_") and ticket.length() != 43) or ticket.length() > 8192:
		_set_status("Paste a complete git1_ connection ticket.")
		return false
	peer = ClassDB.class_call_static("IrohClient", "connect_configured", ticket, "--relay-only" in OS.get_cmdline_user_args())
	role = "joining"
	roster.clear()
	local_id = 0
	_started_at = Time.get_ticks_msec()
	_set_status("Connecting…")
	roster_changed.emit()
	return true

func ticket() -> String:
	return str(peer.call("connection_string")) if role == "host" and peer != null else ""

func leave() -> void:
	session_closed.emit()
	if peer != null:
		peer.close()
		peer = null
	var was_playing := phase == "playing"
	role = "offline"
	local_id = 1
	phase = "lobby"
	roster = [1]
	sim = ExpeditionSim.new()
	input_times.clear()
	pending.clear()
	last_chat.clear()
	act_budget.clear()
	direction = Vector2.ZERO
	_welcomed = false
	_send_clock = 0.0
	snapshots_received = 0
	_set_status("Solo expedition")
	roster_changed.emit()
	if was_playing:
		phase_changed.emit()

## Host (or solo player) begins a run. A negative seed picks a random one.
func start_game(new_seed := -1) -> bool:
	if not is_authority():
		return false
	seed_value = new_seed if new_seed >= 0 else randi() % 1000000
	sim = ExpeditionSim.new()
	sim.setup(seed_value, roster)
	phase = "playing"
	_send(0, {"type": "start", "seed": seed_value}, true)
	phase_changed.emit()
	return true

func end_game() -> void:
	if is_authority() and phase == "playing":
		phase = "lobby"
		_send(0, {"type": "lobby", "ids": roster}, true)
		phase_changed.emit()

## Local player's discrete actions: use / interact / drop / slot / next.
func act(kind: String, value := 0) -> void:
	if phase != "playing":
		return
	if is_authority():
		sim.act(local_id, kind, value)
	elif role == "client" and _welcomed:
		_send(1, {"type": "act", "a": kind, "v": value}, true)

func local_player() -> Dictionary:
	return sim.players.get(local_id, {})

func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)

func _peer_connected(id: int) -> void:
	pending[id] = Time.get_ticks_msec()

func _peer_disconnected(id: int) -> void:
	pending.erase(id)
	input_times.erase(id)
	last_chat.erase(id)
	act_budget.erase(id)
	if id in roster:
		roster.erase(id)
		sim.remove_player(id)
		chat_received.emit("Explorer %d left" % id)
		_send(0, {"type": "lobby", "ids": roster}, true)
		roster_changed.emit()

func _physics_process(delta: float) -> void:
	_clock += delta
	if peer != null:
		peer.poll()
		var connection := peer.get_connection_status()
		if connection == MultiplayerPeer.CONNECTION_DISCONNECTED:
			var reason := str(peer.call("connection_error")) if peer.has_method("connection_error") else ""
			leave()
			_set_status("Disconnected. " + reason)
			return
		if role == "joining" and connection == MultiplayerPeer.CONNECTION_CONNECTED:
			local_id = peer.get_unique_id()
			role = "client"
			_send(1, {"type": "hello", "version": PROTOCOL}, true)
		if role in ["joining", "client"] and not _welcomed and Time.get_ticks_msec() - _started_at > CONNECT_TIMEOUT_MS:
			leave()
			_set_status("Connection timed out. Ask the host for a fresh code.")
			return
		for _index in range(mini(peer.get_available_packet_count(), 256)):
			var sender := peer.get_packet_peer()
			var packet := peer.get_packet()
			if packet.size() > 1024:
				continue
			var parser := JSON.new()
			if parser.parse(packet.get_string_from_utf8()) == OK and parser.data is Dictionary:
				_receive(sender, parser.data)
	if phase == "playing":
		if is_authority():
			sim.set_axis(local_id, direction)
			for id: int in input_times.keys():
				if Time.get_ticks_msec() - int(input_times[id]) > 500:
					sim.set_axis(id, Vector2.ZERO)
			sim.tick(delta)
			_flush_events()
		else:
			sim.prune(_clock - 0.6)
	_send_clock += delta
	if _send_clock >= 0.05:
		_send_clock = 0.0
		_entity_clock += 1.0
		if role == "host":
			if phase == "playing":
				_send(0, {"type": "sp", "tm": snappedf(sim.time, 0.01), "w": sim.wind, "wt": snappedf(sim.wind_t, 0.01),
					"won": sim.won, "sl": sim.slots, "p": sim.player_rows()}, false)
				if int(_entity_clock) % 2 == 0:
					var rows := sim.entity_rows()
					for start in range(0, rows.size(), 20):
						_send(0, {"type": "se", "e": rows.slice(start, start + 20)}, false)
			for id: int in pending.keys():
				if Time.get_ticks_msec() - int(pending[id]) > 5000:
					peer.disconnect_peer(id, true)
					_peer_disconnected(id)
			for id: int in act_budget.keys():
				act_budget[id] = minf(float(act_budget[id]) + 1.0, 20.0)
		elif role == "client" and _welcomed and phase == "playing":
			_send(1, {"type": "in", "ax": [snappedf(direction.x, 0.01), snappedf(direction.y, 0.01)]}, false)

func _flush_events() -> void:
	if sim.events.is_empty():
		return
	var batch: Array = sim.events.duplicate()
	sim.events.clear()
	for event: Array in batch:
		sim_event.emit(str(event[0]), Vector2(event[1], event[2]))
	if role == "host":
		for start in range(0, batch.size(), 16):
			_send(0, {"type": "ev", "e": batch.slice(start, start + 16)}, true)

func _receive(sender: int, message: Dictionary) -> void:
	var kind = message.get("type")
	if role == "host":
		if kind == "hello" and pending.has(sender):
			if message.get("version") != PROTOCOL or roster.size() >= MAX_PLAYERS:
				peer.disconnect_peer(sender, true)
				_peer_disconnected(sender)
				return
			pending.erase(sender)
			roster.append(sender)
			act_budget[sender] = 20.0
			if phase == "playing":
				sim.add_player(sender)
			_send(sender, {"type": "welcome", "version": PROTOCOL, "phase": phase, "seed": seed_value}, true)
			_send(0, {"type": "lobby", "ids": roster, "keep": phase == "playing"}, true)
			chat_received.emit("Explorer %d joined" % sender)
			roster_changed.emit()
		elif sender in roster:
			if kind == "in" and phase == "playing":
				var axis = message.get("ax")
				if _valid_vector(axis):
					sim.set_axis(sender, Vector2(float(axis[0]), float(axis[1])))
					input_times[sender] = Time.get_ticks_msec()
			elif kind == "act" and phase == "playing":
				var action = message.get("a")
				var value = message.get("v", 0)
				if action is String and action in ACTIONS and _number(value) and float(act_budget.get(sender, 0.0)) >= 1.0:
					act_budget[sender] = float(act_budget[sender]) - 1.0
					sim.act(sender, action, clampi(int(value), 0, 2))
			elif kind == "chat":
				_accept_chat(sender, message.get("text"))
	elif role == "client" and sender == 1:
		if kind == "welcome" and message.get("version") == PROTOCOL:
			_welcomed = true
			_set_status("Connected · explorer %d" % local_id)
			if message.get("phase") == "playing" and _number(message.get("seed")):
				_begin_mirror(int(message.seed))
		elif not _welcomed:
			return
		elif kind == "lobby":
			var ids = message.get("ids")
			if not ids is Array or ids.size() > MAX_PLAYERS:
				return
			var next: Array = []
			for id in ids:
				if not _number(id) or float(id) < 1 or float(id) > 2147483647:
					return
				next.append(int(id))
			roster = next
			roster_changed.emit()
			if phase == "playing" and not message.get("keep", false):
				phase = "lobby"
				phase_changed.emit()
		elif kind == "start" and _number(message.get("seed")):
			_begin_mirror(int(message.seed))
		elif kind == "sp" and phase == "playing":
			if sim.apply_players(message.get("p")):
				snapshots_received += 1
				if _number(message.get("tm")):
					sim.time = float(message.tm)
				if _number(message.get("w")) and _number(message.get("wt")):
					sim.wind = clampi(int(message.w), 0, 2)
					sim.wind_t = float(message.wt)
				if _number(message.get("sl")):
					sim.slots = clampi(int(message.sl), 2, 3)
				if message.get("won") == true and not sim.won:
					sim.won = true
					sim.win_time = sim.time
		elif kind == "se" and phase == "playing":
			sim.apply_entities(message.get("e"), _clock)
		elif kind == "ev" and message.get("e") is Array and message.e.size() <= 16:
			for event in message.e:
				if event is Array and event.size() == 3 and event[0] is String and _valid_vector([event[1], event[2]]):
					sim_event.emit(str(event[0]).left(16), Vector2(float(event[1]), float(event[2])))
		elif kind == "chat" and message.get("text") is String:
			chat_received.emit(str(message.text).left(200))

func _begin_mirror(new_seed: int) -> void:
	seed_value = new_seed
	sim = ExpeditionSim.new()
	sim.setup(seed_value, [], false)
	phase = "playing"
	phase_changed.emit()

func send_chat(text: String) -> void:
	text = text.strip_edges().left(160)
	if text.is_empty():
		return
	if is_authority():
		_accept_chat(1, text)
	elif role == "client" and _welcomed:
		_send(1, {"type": "chat", "text": text}, true)

func _accept_chat(sender: int, value: Variant) -> void:
	if not value is String or value.length() > 160 or value.strip_edges().is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(last_chat.get(sender, -1000)) < 750:
		return
	last_chat[sender] = now
	var text := "Explorer %d: %s" % [sender, value.strip_edges()]
	chat_received.emit(text)
	if role == "host":
		_send(0, {"type": "chat", "text": text}, true)

func _send(target: int, message: Dictionary, reliable: bool) -> void:
	if peer == null:
		return
	var packet := JSON.stringify(message).to_utf8_buffer()
	if packet.size() > 1024:
		push_warning("Dropped oversized %s packet (%d bytes)" % [message.get("type"), packet.size()])
		return
	peer.set_target_peer(target)
	peer.transfer_channel = 0 if reliable else 1
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	var error := peer.put_packet(packet)
	if reliable and error != OK:
		_set_status("Network send failed (%d). Reconnect if it persists." % error)

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _valid_vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

func _exit_tree() -> void:
	if peer != null:
		peer.close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and OS.has_feature("mobile") and role != "offline":
		leave()
		_set_status("Session closed while app was in the background. Host or join again.")
