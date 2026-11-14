extends SceneTree
## One real Iroh peer. tools/check.py runs a host and two clients of this.

var session: Node
var chat_seen := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("Session")
	session.chat_received.connect(func(message: String) -> void:
		if "smoke hello" in message:
			chat_seen = true)
	var args := OS.get_cmdline_user_args()
	var path := args[1]
	var use_codes := "--codes" in args
	var rooms := root.get_node("Rooms")
	if args[0] == "host":
		if use_codes:
			assert(await rooms.host(), "TEST FAIL: could not create join code")
		else:
			assert(session.host())
		await create_timer(2).timeout
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(rooms.code if use_codes else session.ticket())
		file.close()
		var joined := false
		for index in range(600):
			await create_timer(0.1).timeout
			if session.roster.size() >= 3 and not joined:
				joined = true
				assert(session.start_game(5), "TEST FAIL: host could not start")
			if joined and session.roster.size() == 1 and chat_seen:
				var old_code: String = rooms.code
				assert(session.sim.items.size() >= 6, "TEST FAIL: leavers' items should be back in the world")
				session.leave()
				await create_timer(1.0).timeout
				if use_codes:
					var reply: Dictionary = await rooms.service.resolve(old_code)
					assert(not reply.ok and "expired or not found" in str(reply.get("message", "")), "TEST FAIL: code not revoked")
				print("HOST_PASS")
				quit()
				return
		push_error("TEST FAIL: host did not see two peers, chat, and disconnect cleanup")
		quit(1)
	else:
		if use_codes:
			assert(await rooms.join(FileAccess.get_file_as_string(path)))
		else:
			assert(session.join(FileAccess.get_file_as_string(path)))
		for index in range(400):
			await create_timer(0.1).timeout
			if session.phase == "playing" and session.sim.players.size() >= 3 and session.sim.players.has(session.local_id) and session.sim.items.size() >= 6:
				break
		assert(session.sim.players.size() >= 3, "TEST FAIL: two clients must join and the run must start")
		assert(session.sim.terrain.w > 100 and session.sim.creatures.size() >= 3, "TEST FAIL: world not mirrored")
		var me: Dictionary = session.local_player()
		var start: Vector2 = me.pos
		session.send_chat("smoke hello")
		# Walk to the nearest supply and pick it up: movement + a reliable action.
		for index in range(40):
			me = session.local_player()
			var nearest := Vector2.INF
			for item: Dictionary in session.sim.items.values():
				if item.pos.distance_to(me.pos) < nearest.distance_to(me.pos):
					nearest = item.pos
			if nearest.distance_to(me.pos) < 20.0:
				break
			session.direction = (nearest - me.pos).normalized()
			await create_timer(0.1).timeout
		session.direction = Vector2.ZERO
		session.act("interact")
		await create_timer(0.6).timeout
		me = session.local_player()
		assert(session.snapshots_received > 10, "TEST FAIL: missing snapshots")
		assert(me.pos.distance_to(start) > 40, "TEST FAIL: movement not replicated")
		assert(me.items[0] != 0, "TEST FAIL: pickup action not applied by host")
		assert(chat_seen, "TEST FAIL: reliable room chat not received")
		session.leave()
		await create_timer(0.5).timeout
		print("CLIENT_PASS")
		quit()
