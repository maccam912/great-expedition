extends SceneTree
## Authority and validation rules of Session._receive, with no real network.

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("TEST FAIL: " + message)

func _run() -> void:
	var session = root.get_node("Session")
	session.set_physics_process(false)
	# Host side.
	session.role = "host"
	session.roster = [1, 2]
	check(session.start_game(5), "host can start")
	check(session.phase == "playing" and session.sim.players.size() == 2, "both explorers spawned")
	session._receive(2, {"type": "in", "ax": [99999, 99999]})
	check(session.sim.players[2].axis.length() <= 1.0001, "host clamps movement input")
	session._receive(2, {"type": "in", "ax": ["bad", 0]})
	session._receive(2, {"type": "in", "ax": [NAN, 0]})
	check(session.sim.players[2].axis.length() <= 1.0001, "malformed input ignored")
	session._receive(3, {"type": "in", "ax": [1, 0]})
	session._receive(3, {"type": "act", "a": "use"})
	check(not session.sim.players.has(3), "unknown peer cannot act")
	session.act_budget[2] = 20.0
	var item: Dictionary = session.sim.add_item(Defs.ROPE, session.sim.players[2].pos)
	session._receive(2, {"type": "act", "a": "explode", "v": 0})
	session._receive(2, {"type": "act", "a": 7})
	check(session.sim.items.has(item.id), "unknown actions rejected")
	session._receive(2, {"type": "act", "a": "interact", "v": 0})
	check(session.sim.players[2].items[0] == Defs.ROPE, "valid action applied for the sender only")
	check(session.sim.players[1].items[0] == Defs.NONE, "other explorers untouched")
	for burst in range(100):
		session._receive(2, {"type": "act", "a": "next"})
	check(session.act_budget[2] < 1.0, "action spam is rate limited")
	session._receive(2, {"type": "start", "seed": 9})
	check(session.seed_value == 5, "clients cannot restart the run")
	var before: int = session.sim.items.size()
	session._peer_disconnected(2)
	check(session.roster == [1] and not session.sim.players.has(2), "leaver removed")
	check(session.sim.items.size() == before + 1, "leaver's items stay in the world")
	# Client side.
	session.leave()
	session.role = "client"
	session.local_id = 2
	session._receive(1, {"type": "start", "seed": 5})
	check(session.phase == "lobby", "nothing accepted before welcome")
	session._welcomed = true
	session._receive(2, {"type": "start", "seed": 5})
	check(session.phase == "lobby", "only the host can start")
	session._receive(1, {"type": "start", "seed": 5})
	check(session.phase == "playing" and session.sim.terrain.w > 0, "client mirrors the world from the seed")
	session._receive(2, {"type": "sp", "p": [[2, 500, 500, 0, 0, 0, 0, 0, 0, 0]]})
	check(session.sim.players.is_empty(), "only the host can publish state")
	session._receive(1, {"type": "sp", "p": [[2, "bad", 500, 0, 0, 0, 0, 0, 0, 0]]})
	session._receive(1, {"type": "sp", "p": "junk"})
	session._receive(1, {"type": "sp"})
	check(session.sim.players.is_empty() and session.snapshots_received == 0, "malformed snapshot ignored")
	session._receive(1, {"type": "sp", "tm": 3.5, "w": 2, "wt": 0.5, "won": false, "sl": 2, "p": [[1, 50, 60, 0, 0, 0, 1, 0, 0, 0], [2, 90, 100, 1, 90, 1, 0, 99, 0, 0]]})
	check(session.sim.players[1].pos == Vector2(50, 60) and session.snapshots_received == 1, "snapshot applied")
	check(session.sim.players[2].items[1] == Defs.SNACKS and session.sim.wind == Defs.GUST, "values clamped to known ranges")
	session._receive(1, {"type": "se", "e": [["i", 4, 2, 10, 20], ["zz", 1, 1, 1, 1], ["c", 5, 1, 30, 40, 0, 0], "junk", ["i", 6, "x", 1, 1]]})
	check(session.sim.items.size() == 1 and session.sim.creatures.size() == 1, "entity rows validated one by one")
	session._receive(1, {"type": "lobby", "ids": [1, 2]})
	check(session.phase == "lobby" and session.roster == [1, 2], "host can call everyone back to camp")
	session.leave()
	check(session.role == "offline" and session.roster == [1] and session.phase == "lobby", "leave resets")
	if failures == 0:
		print("PROTOCOL_PASS")
		quit()
	else:
		quit(1)
