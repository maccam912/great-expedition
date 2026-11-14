extends SceneTree
## Headless rule tests: the whole game is exercised through ExpeditionSim.tick().

const DT := 1.0 / 30.0
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("TEST FAIL: " + message)

func make(seed_value: int, ids: Array, populate := false) -> ExpeditionSim:
	var sim := ExpeditionSim.new()
	sim.setup(seed_value, ids, populate)
	return sim

func zone(sim: ExpeditionSim, kind: int) -> Dictionary:
	for candidate: Dictionary in sim.terrain.zones:
		if candidate.kind == kind:
			return candidate
	return {}

func run(sim: ExpeditionSim, seconds: float) -> void:
	for step in range(int(seconds / DT)):
		sim.tick(DT)

func find_tile(sim: ExpeditionSim, area: Dictionary, wanted: int, row: int) -> int:
	for x in range(area.x0, area.x1):
		if sim.terrain.tile(x, row) == wanted:
			return x
	return -1

func reachable(terrain: Terrain, strict: bool) -> bool:
	var start := Vector2i(terrain.spawn / Defs.TILE)
	var target := Vector2i(terrain.goal / Defs.TILE)
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if cell == target:
			return true
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + step
			var tile := terrain.tile(next.x, next.y)
			if seen.has(next) or Defs.solid(tile):
				continue
			if strict and (tile == Defs.PIT or tile == Defs.VOID):
				continue
			seen[next] = true
			queue.append(next)
	return false

func _run() -> void:
	test_terrain()
	test_walk_and_items()
	test_river()
	test_raft()
	test_rope()
	test_bog()
	test_wind()
	test_cave()
	test_creatures()
	test_win_and_snapshot()
	test_fuzz()
	if failures == 0:
		print("SIM_PASS %d checks" % checks)
		quit()
	else:
		print("SIM_FAILED %d of %d" % [failures, checks])
		quit(1)

func test_terrain() -> void:
	var a := Terrain.new()
	var b := Terrain.new()
	a.generate(42)
	b.generate(42)
	check(a.tiles == b.tiles and a.w == b.w, "same seed gives same world")
	b.generate(43)
	check(a.tiles != b.tiles, "different seed gives different world")
	var orders := {}
	for seed_value in range(60):
		var terrain := Terrain.new()
		terrain.generate(seed_value)
		check(reachable(terrain, true), "seed %d: goal reachable without pits/void" % seed_value)
		check(terrain.tile_at(terrain.spawn) == Defs.GRASS, "seed %d: spawn on grass" % seed_value)
		check(terrain.tile_at(terrain.goal) == Defs.GOAL, "seed %d: goal tile" % seed_value)
		orders[str(terrain.zones.map(func(z: Dictionary) -> int: return z.kind))] = true
	check(orders.size() > 10, "zone order varies between seeds")

func test_walk_and_items() -> void:
	var sim := make(1, [1, 2], true)
	check(sim.items.size() >= 6, "supplies spawned")
	check(sim.creatures.size() >= 3, "creatures spawned")
	var p: Dictionary = sim.players[1]
	var start: Vector2 = p.pos
	sim.set_axis(1, Vector2(99, 0))
	run(sim, 0.5)
	check(absf(p.pos.x - start.x - 75.0) < 6.0, "walk speed is clamped and applied")
	sim.set_axis(1, Vector2(0, -1))
	run(sim, 12.0)
	check(p.pos.y > 2 * Defs.TILE, "trees stop the player at the north edge")
	sim.set_axis(1, Vector2.ZERO)
	var item: Dictionary = sim.add_item(Defs.LANTERN, p.pos + Vector2(10, 0))
	sim.act(1, "interact")
	check(p.items[0] == Defs.LANTERN and not sim.items.has(item.id), "pick up")
	sim.add_item(Defs.ROPE, p.pos)
	sim.act(1, "interact")
	sim.add_item(Defs.WHISTLE, p.pos)
	sim.act(1, "interact")
	check(p.items.count(Defs.NONE) == 1 and Defs.ROPE not in p.items, "two slots: third pickup swaps the selected item")
	sim.act(1, "drop")
	check(p.items.count(Defs.NONE) == 2, "drop")
	sim.act(1, "slot", 7)
	check(p.sel < 2, "bad slot index ignored")
	sim.act(99, "use")

func test_river() -> void:
	var sim := make(3, [1])
	var river := zone(sim, Defs.Z_RIVER)
	var water := find_tile(sim, river, Defs.WATER, 10)
	var p: Dictionary = sim.players[1]
	p.pos = sim.terrain.center(water - 1, 10)
	p.items[0] = Defs.SNACKS
	sim.set_axis(1, Vector2.RIGHT)
	run(sim, 1.0)
	check(p.st == Defs.SWIM, "walking into water means swimming")
	sim.set_axis(1, Vector2.ZERO)
	run(sim, 9.0)
	check(p.st == Defs.WALK and sim.terrain.tile_at(p.pos) == Defs.SAND and p.items[0] == Defs.SNACKS, "a river bend nudges an edge swimmer back onto the bank")
	p.pos = sim.terrain.center(find_tile(sim, river, Defs.WATER, 20) + 4, 20)
	run(sim, 12.0)
	check(p.st != Defs.SWIM and sim.terrain.tile_at(p.pos) == Defs.SAND, "mid-river swimmer washes up at the bottom")
	check(p.pos.x < sim.terrain.center(water + 4, 0).x, "washed up on the west bank, not across")
	check(p.items[0] == Defs.NONE and sim.items.size() == 1, "items are dropped on wash-up")

func test_raft() -> void:
	var sim := make(3, [1, 2, 3])
	var river := zone(sim, Defs.Z_RIVER)
	var water := find_tile(sim, river, Defs.WATER, 6)
	var bank := sim.terrain.center(water - 1, 6)
	for id in [1, 2, 3]:
		sim.players[id].pos = bank + Vector2(0, (id - 2) * 6)
	var p: Dictionary = sim.players[1]
	p.items[0] = Defs.RAFT
	p.face = Vector2.RIGHT
	sim.act(1, "use")
	check(p.st == Defs.RIDE and sim.rafts.size() == 1, "raft launches and carries its owner")
	run(sim, 1.0)
	var raft: Dictionary = sim.rafts.values()[0]
	check(raft.pos.y < bank.y + 40, "a beached raft does not drift away")
	sim.set_axis(2, Vector2.RIGHT)
	sim.set_axis(3, Vector2.RIGHT)
	run(sim, 1.0)
	check(raft.riders.size() == 2, "the raft holds exactly two")
	check(sim.players[3].st == Defs.SWIM or sim.players[2].st == Defs.SWIM, "the third explorer falls in")
	sim.set_axis(1, Vector2.RIGHT)
	run(sim, 6.0)
	check(raft.pos.x > sim.terrain.center(water + 7, 0).x, "paddling crosses the river")
	sim.act(1, "interact")
	check(p.st == Defs.WALK and p.pos.x > raft.pos.x, "disembark on the east bank")
	check(sim.terrain.tile_at(p.pos) == Defs.SAND, "landed on sand")

func test_rope() -> void:
	var sim := make(5, [1, 2])
	var river := zone(sim, Defs.Z_RIVER)
	var water := find_tile(sim, river, Defs.WATER, 12)
	var thrower: Dictionary = sim.players[1]
	var swimmer: Dictionary = sim.players[2]
	thrower.pos = sim.terrain.center(find_tile(sim, river, Defs.WATER, 14) - 1, 14)
	thrower.items[0] = Defs.ROPE
	thrower.face = Vector2.RIGHT
	swimmer.pos = sim.terrain.center(water + 3, 12)
	run(sim, 0.2)
	check(swimmer.st == Defs.SWIM, "swimmer is swimming")
	sim.act(1, "use")
	check(sim.ropes.has(1) and sim.ropes[1].target == 2, "rope attaches to the swimmer")
	run(sim, 3.0)
	check(swimmer.st == Defs.WALK and Defs.firm(sim.terrain.tile_at(swimmer.pos)), "rope pulls the swimmer ashore")
	check(not sim.ropes.has(1), "rescue rope lets go once they are safe")
	thrower.face = Vector2.LEFT
	sim.act(1, "use")
	check(sim.ropes.has(1) == false or sim.ropes[1].kind == "p", "rope only grabs things in range")

func test_bog() -> void:
	var sim := make(8, [1, 2])
	var bog := zone(sim, Defs.Z_BOG)
	var p: Dictionary = sim.players[1]
	var row := -1
	for y in range(4, 36):
		var clear := true
		for x in range(bog.x0 + 5, bog.x0 + 13):
			if sim.terrain.tile(x, y) != Defs.BOG:
				clear = false
		if clear:
			row = y
			break
	check(row > 0, "found a full-width mire row")
	p.pos = sim.terrain.center(bog.x0 + 4, row)
	sim.set_axis(1, Vector2.RIGHT)
	run(sim, 6.0)
	check(p.st == Defs.STUCK, "deep bog swallows a lone walker")
	var held: Vector2 = p.pos
	run(sim, 1.0)
	check(p.pos == held, "stuck means stuck")
	var friend: Dictionary = sim.players[2]
	friend.pos = p.pos + Vector2(-40, 0)
	friend.sink = 0.0
	sim.act(2, "interact")
	check(p.st == Defs.WALK and p.sink == 0.0, "a friend can tug you free")
	friend.pos = sim.terrain.spawn
	p.pos = sim.terrain.center(bog.x0 + 8, row)
	run(sim, 4.0)
	check(p.st == Defs.STUCK, "stuck again, alone this time")
	run(sim, Defs.STUCK_ESCAPE + 0.5)
	check(p.pos.x < bog.x0 * Defs.TILE, "nobody came: crawls back out to the bog's entrance (no softlock)")
	# Rope can haul an empty raft back across a river.
	var river := zone(sim, Defs.Z_RIVER)
	var west := find_tile(sim, river, Defs.WATER, 10)
	sim.rafts[900] = {"id": 900, "pos": sim.terrain.center(west, 10), "riders": [], "beached": true}
	p.pos = sim.terrain.center(west + 9, 10)
	p.st = Defs.WALK
	p.stun = 0.0
	p.items[0] = Defs.ROPE
	p.sel = 0
	p.face = Vector2.LEFT
	sim.set_axis(1, Vector2.ZERO)
	run(sim, 2.0)
	sim.act(1, "use")
	check(sim.ropes.has(1) and sim.ropes[1].kind == "r", "rope reaches a raft on the far bank")
	run(sim, 4.0)
	check(sim.rafts[900].pos.x > sim.terrain.center(west + 6, 0).x, "and hauls it across")

func test_wind() -> void:
	var sim := make(11, [1, 2])
	var ridge := zone(sim, Defs.Z_RIDGE)
	var exposed := Vector2.INF
	var sheltered := Vector2.INF
	for x in range(ridge.x0 + 1, ridge.x1 - 1):
		for y in range(3, 9):
			var spot := sim.terrain.center(x, y)
			if sim.terrain.tile(x, y) != Defs.RIDGE:
				continue
			if sim.terrain.sheltered(spot):
				sheltered = spot
			elif exposed == Vector2.INF and not Defs.solid(sim.terrain.tile(x, y + 1)) and not Defs.solid(sim.terrain.tile(x, y + 2)):
				exposed = spot
	check(exposed != Vector2.INF and sheltered != Vector2.INF, "ridge has open and sheltered spots")
	sim.players[1].pos = exposed
	sim.players[2].pos = sheltered
	run(sim, Defs.WIND_CALM + Defs.WIND_WARN - 0.1)
	check(sim.players[1].pos == exposed, "no push before the gust")
	run(sim, 0.6)
	check(sim.wind == Defs.GUST and sim.players[1].pos.y > exposed.y + 40, "gust pushes exposed explorers south")
	check(sim.players[2].pos == sheltered, "boulders give shelter")
	run(sim, 8.0)
	check(sim.players[1].pos.x < ridge.x0 * Defs.TILE, "blown off the ridge = back to its entrance")

func test_cave() -> void:
	var sim := make(13, [1])
	var cave := zone(sim, Defs.Z_CAVE)
	var pit := Vector2.INF
	for x in range(cave.x0, cave.x1):
		for y in range(sim.terrain.h):
			if sim.terrain.tile(x, y) == Defs.PIT:
				pit = sim.terrain.center(x, y)
	check(pit != Vector2.INF, "cave has pits")
	var p: Dictionary = sim.players[1]
	p.pos = pit
	p.items[1] = Defs.LANTERN
	sim.tick(DT)
	check(p.st == Defs.STUN and p.pos.x < cave.x0 * Defs.TILE, "falling in a pit sends you to the cave mouth")
	check(sim.items.size() == 1, "and you drop your things")
	sim.set_axis(1, Vector2.RIGHT)
	var held: Vector2 = p.pos
	run(sim, 1.0)
	check(p.pos == held, "stunned explorers cannot move")
	run(sim, 1.0)
	check(p.pos.x > held.x, "stun wears off")

func test_creatures() -> void:
	var sim := make(17, [1, 2], true)
	sim.items.clear()
	var thicket := zone(sim, Defs.Z_THICKET)
	var grumble := {}
	var snuffler := {}
	for c: Dictionary in sim.creatures.values():
		if c.kind == Defs.GRUMBLE:
			grumble = c
		elif snuffler.is_empty() and c.home.x > thicket.x0 * Defs.TILE and c.home.x < thicket.x1 * Defs.TILE:
			snuffler = c
	var p: Dictionary = sim.players[1]
	sim.players[2].pos = grumble.home + Vector2(-300, 0)
	# Grumble plugs the pass.
	p.pos = grumble.home + Vector2(-70, 0)
	sim.set_axis(1, Vector2.RIGHT)
	run(sim, 4.0)
	check(p.pos.x < grumble.home.x, "Grumble blocks the pass")
	# Snack lures it away.
	p.pos = grumble.home + Vector2(-90, 30)
	p.items[0] = Defs.SNACKS
	p.sel = 0
	p.face = Vector2.DOWN
	sim.set_axis(1, Vector2.ZERO)
	sim.act(1, "use")
	check(p.items[0] == Defs.NONE, "snack tossed")
	for other: Dictionary in sim.creatures.values():
		if other.kind == Defs.SNUFFLER:
			other.pos = other.home + Vector2(-600, 0)
			other.home = other.pos
	run(sim, 6.0)
	check(grumble.st == Defs.C_EAT, "Grumble leaves to eat the snack")
	p.pos = grumble.home + Vector2(-70, 0)
	sim.set_axis(1, Vector2.RIGHT)
	run(sim, 2.0)
	check(p.pos.x > grumble.home.x + 40, "the pass is open while it eats")
	run(sim, 60.0)
	check(grumble.st == Defs.C_IDLE and grumble.pos == grumble.home, "Grumble goes back to sleep in the pass")
	# Whistle distracts it.
	var q: Dictionary = sim.players[2]
	q.pos = grumble.home + Vector2(-150, 0)
	q.items[0] = Defs.WHISTLE
	q.sel = 0
	sim.act(2, "use")
	check(grumble.st == Defs.C_STOMP, "whistle wakes the Grumble")
	run(sim, 3.0)
	check(grumble.pos.x < grumble.home.x - 60, "it stomps toward the whistler")
	# Snuffler steals snacks, whistle makes it drop them.
	sim = make(17, [1, 2], true)
	sim.items.clear()
	p = sim.players[1]
	q = sim.players[2]
	q.items[0] = Defs.WHISTLE
	for c: Dictionary in sim.creatures.values():
		if c.kind == Defs.SNUFFLER and c.home.x > thicket.x0 * Defs.TILE:
			snuffler = c
	p.pos = snuffler.home + Vector2(60, 0)
	p.items[0] = Defs.SNACKS
	q.pos = p.pos + Vector2(0, 30)
	run(sim, 3.0)
	check(p.items[0] == Defs.NONE and snuffler.held == Defs.SNACKS, "Snuffler steals snacks from a pocket")
	q.pos = snuffler.pos + Vector2(50, 0)
	q.cd = 0.0
	sim.act(2, "use")
	check(snuffler.held == Defs.NONE and sim.items.size() == 1, "whistle makes it drop the loot")

func test_win_and_snapshot() -> void:
	var sim := make(21, [1, 2, 3], true)
	sim.players[1].pos = sim.terrain.goal + Vector2(-40, 0)
	sim.players[2].pos = sim.terrain.goal + Vector2(40, 10)
	sim.players[2].items[1] = Defs.ROPE
	run(sim, 1.0)
	check(not sim.won, "not won until everyone arrives")
	var mirror := ExpeditionSim.new()
	mirror.setup(21, [], false)
	var wire: Variant = JSON.parse_string(JSON.stringify({"p": sim.player_rows(), "e": sim.entity_rows()}))
	check(mirror.apply_players(wire.p) and mirror.apply_entities(wire.e, 1.0), "snapshot applies")
	check(mirror.players.size() == 3 and mirror.players[2].items[1] == Defs.ROPE, "players mirrored")
	check(mirror.players[2].pos.distance_to(sim.players[2].pos) < 2.0, "positions mirrored")
	check(mirror.items.size() == sim.items.size() and mirror.creatures.size() == sim.creatures.size(), "entities mirrored")
	check(JSON.stringify({"t": "sp", "p": sim.player_rows()}).length() < 500, "player packet is small")
	check(not mirror.apply_players([[1, "x", 2]]) and not mirror.apply_players("junk"), "malformed rows rejected")
	mirror.prune(2.0)
	check(mirror.items.is_empty(), "stale entities pruned")
	sim.players[3].pos = sim.terrain.goal + Vector2(0, 60)
	run(sim, 0.2)
	check(sim.won, "everyone at the landmark wins the run")

func test_fuzz() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for seed_value in [100, 101, 102]:
		var sim := make(seed_value, [1, 2, 3, 4], true)
		for id in [1, 2, 3, 4]:
			var spot := sim.terrain.spawn
			for attempt in range(50):
				spot = sim.terrain.center(rng.randi_range(4, sim.terrain.w - 5), rng.randi_range(4, 30))
				if not sim.terrain.blocked(spot, Defs.PLAYER_R):
					break
			sim.players[id].pos = spot
			sim.players[id].items = [rng.randi_range(0, 5), rng.randi_range(0, 5), 0]
		for step in range(30 * 90):
			if step % 10 == 0:
				for id in [1, 2, 3, 4]:
					sim.set_axis(id, Vector2(rng.randf_range(-0.6, 1.0), rng.randf_range(-1, 1)))
					if rng.randf() < 0.3:
						sim.act(id, ["use", "interact", "drop", "next"][rng.randi_range(0, 3)])
			sim.tick(DT)
			sim.events.clear()
		var size := sim.terrain.size_px()
		for p: Dictionary in sim.players.values():
			check(is_finite(p.pos.x) and p.pos.x > 0 and p.pos.y > 0 and p.pos.x < size.x and p.pos.y < size.y, "fuzz: player stays in the world")
			check(not Defs.solid(sim.terrain.tile_at(p.pos)), "fuzz: player never inside a wall")
		check(sim.entity_rows().size() < 60, "fuzz: entity count bounded")
