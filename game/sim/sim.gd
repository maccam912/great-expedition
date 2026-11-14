class_name ExpeditionSim
extends RefCounted
## The whole game as plain data + tick(dt). No nodes, no network, no rendering.
## The host ticks it; clients fill the same dictionaries from snapshots.

var terrain := Terrain.new()
var players: Dictionary = {}    # id -> {id,pos,axis,face,st,stun,sink,items,sel,raft,cd,board_cd}
var items: Dictionary = {}      # id -> {id,type,pos}
var rafts: Dictionary = {}      # id -> {id,pos,riders,beached}
var ropes: Dictionary = {}      # thrower id -> {from,kind,target,t,rescue}
var creatures: Dictionary = {}  # id -> {id,kind,pos,home,st,t,held,shy,dir,target,munch,flee}
var events: Array = []          # [name, x, y] drained by the session for sound/juice
var time := 0.0
var wind := Defs.CALM
var wind_t := 0.0
var won := false
var win_time := 0.0
var slots := 2
var _next_id := 1
var _rng := RandomNumberGenerator.new()

# --- setup -----------------------------------------------------------------

func setup(seed_value: int, ids: Array, populate := true) -> void:
	terrain.generate(seed_value)
	_rng.seed = seed_value + 7919
	players.clear()
	items.clear()
	rafts.clear()
	ropes.clear()
	creatures.clear()
	events.clear()
	time = 0.0
	wind = Defs.CALM
	wind_t = 0.0
	won = false
	_next_id = 1
	for id: int in ids:
		add_player(id)
	slots = 3 if ids.size() <= 1 else 2
	if populate:
		_spawn_supplies(maxi(ids.size(), 1))
		for home: Vector2 in terrain.snuffler_homes:
			_add_creature(Defs.SNUFFLER, home)
		if terrain.grumble_home != Vector2.ZERO:
			_add_creature(Defs.GRUMBLE, terrain.grumble_home)

func add_player(id: int) -> Dictionary:
	var angle := players.size() * TAU / 8.0
	var player := {
		"id": id, "pos": terrain.spawn + Vector2(cos(angle), sin(angle)) * 34.0,
		"axis": Vector2.ZERO, "face": Vector2.RIGHT, "st": Defs.WALK, "stun": 0.0,
		"sink": 0.0, "items": [0, 0, 0], "sel": 0, "raft": 0, "cd": 0.0, "board_cd": 0.0,
	}
	players[id] = player
	return player

func remove_player(id: int) -> void:
	if not players.has(id):
		return
	var player: Dictionary = players[id]
	_leave_raft(player)
	_drop_all(player, player.pos)
	ropes.erase(id)
	players.erase(id)

func _spawn_supplies(count: int) -> void:
	var list: Array = []
	for index in range(1 + int(count >= 5)): list.append(Defs.RAFT)
	for index in range(1 + count / 3): list.append(Defs.ROPE)
	for index in range(1 + int(count >= 4)): list.append(Defs.LANTERN)
	for index in range(1 + int(count >= 4)): list.append(Defs.WHISTLE)
	for index in range(2 + count / 3): list.append(Defs.SNACKS)
	for index in range(list.size()):
		var offset := Vector2((index % 4) - 1.5, (index / 4) - 1.0) * 30.0
		add_item(int(list[index]), terrain.supplies + offset)

func add_item(type: int, pos: Vector2) -> Dictionary:
	var item := {"id": _next_id, "type": type, "pos": pos}
	items[_next_id] = item
	_next_id += 1
	return item

func _add_creature(kind: int, pos: Vector2) -> Dictionary:
	var creature := {
		"id": _next_id, "kind": kind, "pos": pos, "home": pos, "st": Defs.C_IDLE, "t": 0.0,
		"held": 0, "shy": 0.0, "dir": Vector2.ZERO, "target": 0, "target_kind": "", "munch": 0.0,
		"flee": pos,
	}
	creatures[_next_id] = creature
	_next_id += 1
	return creature

# --- input -----------------------------------------------------------------

func set_axis(id: int, axis: Vector2) -> void:
	if players.has(id) and is_finite(axis.x) and is_finite(axis.y):
		players[id].axis = axis.limit_length(1.0)

func act(id: int, kind: String, value := 0) -> void:
	if not players.has(id) or won:
		return
	var player: Dictionary = players[id]
	if player.st == Defs.STUN:
		return
	match kind:
		"slot":
			if value >= 0 and value < slots:
				player.sel = value
		"next":
			player.sel = (int(player.sel) + 1) % slots
		"drop":
			_drop_selected(player, 18.0)
		"use":
			_use(player)
		"interact":
			_interact(player)

func has_item(player: Dictionary, type: int) -> bool:
	return type in player.items

func _free_slot(player: Dictionary) -> int:
	for index in range(slots):
		if player.items[index] == Defs.NONE:
			return index
	return -1

func _event(name: String, pos: Vector2) -> void:
	if events.size() < 64:
		events.append([name, int(pos.x), int(pos.y)])

# --- actions ---------------------------------------------------------------

func _drop_selected(player: Dictionary, reach: float) -> void:
	var type: int = player.items[player.sel]
	if type == Defs.NONE or player.st == Defs.STUCK:
		return
	player.items[player.sel] = Defs.NONE
	var target: Vector2 = player.pos + player.face * reach
	if Defs.solid(terrain.tile_at(target)):
		target = player.pos
	add_item(type, target)
	_event("drop", target)

func _drop_all(player: Dictionary, around: Vector2) -> void:
	for index in range(3):
		var type: int = player.items[index]
		if type != Defs.NONE:
			player.items[index] = Defs.NONE
			add_item(type, around + Vector2.from_angle(index * 2.1 + 0.5) * 26.0)

func _use(player: Dictionary) -> void:
	if player.cd > 0.0:
		return
	match int(player.items[player.sel]):
		Defs.RAFT:
			if player.st != Defs.WALK:
				return
			var spot := _water_near(player.pos + player.face * 30.0)
			if spot == Vector2.INF:
				_event("nope", player.pos)
				return
			player.items[player.sel] = Defs.NONE
			var raft := {"id": _next_id, "pos": spot, "riders": [], "beached": true}
			rafts[_next_id] = raft
			_next_id += 1
			_board(player, raft)
			_event("raft", spot)
		Defs.ROPE:
			_use_rope(player)
		Defs.WHISTLE:
			player.cd = 1.2
			_event("whistle", player.pos)
			for creature: Dictionary in creatures.values():
				if creature.pos.distance_to(player.pos) > Defs.WHISTLE_RANGE:
					continue
				if creature.kind == Defs.SNUFFLER:
					if creature.held != Defs.NONE:
						add_item(creature.held, creature.pos)
						creature.held = Defs.NONE
					creature.st = Defs.C_FLEE
					creature.t = 3.0
					creature.shy = 8.0
					creature.flee = player.pos
				elif creature.st == Defs.C_IDLE or creature.st == Defs.C_RETURN:
					creature.st = Defs.C_STOMP
					creature.t = 7.0
					creature.target = player.id
					_event("grumble", creature.pos)
		Defs.SNACKS:
			if player.st != Defs.STUCK:
				_drop_selected(player, 70.0)

func _use_rope(player: Dictionary) -> void:
	if ropes.has(player.id):
		ropes.erase(player.id)
		return
	if player.st != Defs.WALK and player.st != Defs.RIDE:
		return
	var best := {}
	var best_score := INF
	for other: Dictionary in players.values():
		if other.id == player.id or other.st == Defs.RIDE:
			continue
		var needy: bool = other.st == Defs.SWIM or other.st == Defs.STUCK
		var score := _rope_score(player, other.pos, 0 if needy else 2)
		if score < best_score:
			best_score = score
			best = {"from": player.id, "kind": "p", "target": other.id, "t": 12.0, "rescue": needy}
	for raft: Dictionary in rafts.values():
		if raft.id == player.raft:
			continue
		var score := _rope_score(player, raft.pos, 1)
		if score < best_score:
			best_score = score
			best = {"from": player.id, "kind": "r", "target": raft.id, "t": 12.0, "rescue": false}
	for item: Dictionary in items.values():
		var score := _rope_score(player, item.pos, 3)
		if score < best_score:
			best_score = score
			best = {"from": player.id, "kind": "i", "target": item.id, "t": 6.0, "rescue": false}
	if best.is_empty():
		player.cd = 0.4
		_event("miss", player.pos + player.face * 80.0)
		return
	ropes[player.id] = best
	_event("rope", player.pos)

func _rope_score(player: Dictionary, target: Vector2, priority: int) -> float:
	var offset: Vector2 = target - player.pos
	var distance := offset.length()
	if distance > Defs.ROPE_RANGE or distance < 1.0:
		return INF
	if distance > 90.0 and player.face.dot(offset / distance) < 0.5:
		return INF
	return priority * 1000.0 + distance

func _interact(player: Dictionary) -> void:
	if player.st == Defs.RIDE:
		var raft: Dictionary = rafts.get(player.raft, {})
		var shore := _shore_near(raft.pos) if not raft.is_empty() else Vector2.INF
		if shore == Vector2.INF:
			_event("nope", player.pos)
			return
		_leave_raft(player)
		player.pos = shore
		player.board_cd = 1.0
		_event("land", shore)
		return
	if player.st != Defs.WALK:
		return
	for other: Dictionary in players.values():
		if other.st == Defs.STUCK and other.id != player.id and other.pos.distance_to(player.pos) < 60.0:
			other.pos = other.pos.move_toward(player.pos, 34.0)
			other.sink = 0.0
			other.st = Defs.WALK
			_event("tug", other.pos)
			return
	var nearest := {}
	var nearest_distance := 38.0
	for item: Dictionary in items.values():
		var distance: float = item.pos.distance_to(player.pos)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = item
	if not nearest.is_empty():
		var slot := _free_slot(player)
		if slot < 0:
			slot = player.sel
			add_item(player.items[slot], nearest.pos)
		player.items[slot] = nearest.type
		player.sel = slot
		items.erase(nearest.id)
		for from: int in ropes.keys():
			if ropes[from].kind == "i" and ropes[from].target == nearest.id:
				ropes.erase(from)
		_event("pickup", player.pos)
		return
	for raft: Dictionary in rafts.values():
		if raft.riders.is_empty() and raft.pos.distance_to(player.pos) < 64.0 and _free_slot(player) >= 0:
			player.items[_free_slot(player)] = Defs.RAFT
			rafts.erase(raft.id)
			_event("pickup", player.pos)
			return

func _board(player: Dictionary, raft: Dictionary) -> void:
	raft.riders.append(player.id)
	player.raft = raft.id
	player.st = Defs.RIDE
	player.sink = 0.0
	_event("board", raft.pos)

func _leave_raft(player: Dictionary) -> void:
	if rafts.has(player.raft):
		rafts[player.raft].riders.erase(player.id)
	player.raft = 0
	if player.st == Defs.RIDE:
		player.st = Defs.WALK

func _water_near(pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var tx := int(floor(pos.x / Defs.TILE))
	var ty := int(floor(pos.y / Defs.TILE))
	for x in range(tx - 1, tx + 2):
		for y in range(ty - 1, ty + 2):
			var spot := terrain.center(x, y)
			if terrain.tile(x, y) == Defs.WATER and spot.distance_to(pos) < best.distance_to(pos) and spot.distance_to(pos) < 50.0:
				best = spot
	return best

func _shore_near(pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var tx := int(floor(pos.x / Defs.TILE))
	var ty := int(floor(pos.y / Defs.TILE))
	for x in range(tx - 2, tx + 3):
		for y in range(ty - 2, ty + 3):
			var spot := terrain.center(x, y)
			if Defs.firm(terrain.tile(x, y)) and spot.distance_to(pos) < 62.0 and spot.distance_to(pos) < best.distance_to(pos):
				best = spot
	return best

# --- tick ------------------------------------------------------------------

func tick(dt: float) -> void:
	if won:
		return
	time += dt
	_tick_wind(dt)
	for player: Dictionary in players.values():
		_tick_player(player, dt)
	_tick_ropes(dt)
	for raft: Dictionary in rafts.values():
		_tick_raft(raft, dt)
	for creature: Dictionary in creatures.values():
		if creature.kind == Defs.SNUFFLER:
			_tick_snuffler(creature, dt)
		else:
			_tick_grumble(creature, dt)
	if not players.is_empty():
		var everyone := true
		for player: Dictionary in players.values():
			if player.pos.distance_to(terrain.goal) > Defs.GOAL_RADIUS:
				everyone = false
		if everyone:
			won = true
			win_time = time
			_event("win", terrain.goal)

func _tick_wind(dt: float) -> void:
	wind_t += dt
	var limit: float = [Defs.WIND_CALM, Defs.WIND_WARN, Defs.WIND_GUST][wind]
	if wind_t >= limit:
		wind_t = 0.0
		wind = (wind + 1) % 3
		if wind == Defs.GUST:
			_event("gust", Vector2.ZERO)

func _move(pos: Vector2, delta: Vector2, radius: float) -> Vector2:
	var next := pos + Vector2(delta.x, 0)
	if not terrain.blocked(next, radius):
		pos = next
	next = pos + Vector2(0, delta.y)
	if not terrain.blocked(next, radius):
		pos = next
	return pos

func _pulled(id: int) -> bool:
	for rope: Dictionary in ropes.values():
		if rope.kind == "p" and rope.target == id:
			return true
	return false

func blown(player: Dictionary) -> bool:
	return wind == Defs.GUST and terrain.tile_at(player.pos) == Defs.RIDGE and not terrain.sheltered(player.pos)

func _setback(player: Dictionary, where: Vector2, why: String) -> void:
	_event(why, player.pos)
	_leave_raft(player)
	_drop_all(player, where)
	ropes.erase(player.id)
	for from: int in ropes.keys():
		if ropes[from].kind == "p" and ropes[from].target == player.id:
			ropes.erase(from)
	player.pos = where
	player.st = Defs.STUN
	player.stun = 1.5
	player.sink = 0.0

func _tick_player(player: Dictionary, dt: float) -> void:
	player.cd = maxf(0.0, player.cd - dt)
	player.board_cd = maxf(0.0, player.board_cd - dt)
	if player.st == Defs.RIDE:
		return
	if player.st == Defs.STUN:
		player.stun -= dt
		if player.stun > 0.0:
			return
		player.st = Defs.WALK
	var axis: Vector2 = player.axis
	if axis.length() > 0.1:
		player.face = axis.normalized()
	if player.board_cd <= 0.0 and player.st != Defs.STUCK:
		for raft: Dictionary in rafts.values():
			if raft.riders.size() < Defs.RAFT_SEATS and raft.pos.distance_to(player.pos) < 26.0:
				_board(player, raft)
				return
	var tile := terrain.tile_at(player.pos)
	match tile:
		Defs.WATER:
			if player.st != Defs.SWIM:
				player.st = Defs.SWIM
				_event("splash", player.pos)
			var velocity := axis * Defs.SWIM_SPEED
			if not _pulled(player.id):
				velocity.y += Defs.CURRENT
			player.pos = _move(player.pos, velocity * dt, Defs.PLAYER_R)
			if player.pos.y > (terrain.h - 3) * Defs.TILE:
				_setback(player, terrain.washup(terrain.zone_at(player.pos.x)), "washed")
		Defs.BOG:
			if player.st == Defs.STUCK:
				# Nobody came: after a while you crawl back out the way you came in.
				player.stun += dt
				if player.stun >= Defs.STUCK_ESCAPE:
					_setback(player, terrain.entrance(terrain.zone_at(player.pos.x), player.pos.y), "fell")
				return
			player.st = Defs.WALK
			player.sink += dt / Defs.SINK_TIME
			if player.sink >= 1.0:
				player.sink = 1.0
				player.st = Defs.STUCK
				player.stun = 0.0
				_event("stuck", player.pos)
			else:
				player.pos = _move(player.pos, axis * Defs.WALK_SPEED * Defs.BOG_FACTOR * dt, Defs.PLAYER_R)
		Defs.PIT, Defs.VOID:
			_setback(player, terrain.entrance(terrain.zone_at(player.pos.x), player.pos.y), "fell")
		_:
			player.st = Defs.WALK
			player.sink = maxf(0.0, player.sink - dt * 2.0)
			var delta := axis * Defs.WALK_SPEED * (Defs.MUD_FACTOR if tile == Defs.MUD else 1.0) * dt
			if blown(player):
				delta.y += Defs.WIND_PUSH * (1.6 if has_item(player, Defs.RAFT) else 1.0) * dt
			var before: Vector2 = player.pos
			player.pos = _move(player.pos, delta, Defs.PLAYER_R)
			for creature: Dictionary in creatures.values():
				if creature.kind == Defs.GRUMBLE:
					var gap: Vector2 = player.pos - creature.pos
					var reach := Defs.GRUMBLE_R + Defs.PLAYER_R
					if gap.length() < reach:
						var pushed: Vector2 = creature.pos + (gap.normalized() if gap.length() > 0.01 else Vector2.LEFT) * reach
						player.pos = pushed if not terrain.blocked(pushed, Defs.PLAYER_R) else before

func _tick_ropes(dt: float) -> void:
	for from: int in ropes.keys():
		var rope: Dictionary = ropes[from]
		var thrower: Dictionary = players.get(from, {})
		rope.t -= dt
		if thrower.is_empty() or rope.t <= 0.0 or (thrower.st != Defs.WALK and thrower.st != Defs.RIDE):
			ropes.erase(from)
			continue
		match rope.kind:
			"p":
				var other: Dictionary = players.get(rope.target, {})
				if other.is_empty() or other.st == Defs.RIDE or other.st == Defs.STUN:
					ropes.erase(from)
					continue
				var offset: Vector2 = thrower.pos - other.pos
				var distance := offset.length()
				var in_trouble: bool = other.st == Defs.SWIM or other.st == Defs.STUCK or terrain.tile_at(other.pos) == Defs.BOG
				if distance > Defs.ROPE_SNAP:
					_event("snap", other.pos)
					ropes.erase(from)
				elif in_trouble:
					if distance > 4.0:
						other.pos = _move(other.pos, offset / distance * Defs.ROPE_PULL * dt, Defs.PLAYER_R)
				elif rope.rescue:
					ropes.erase(from)
				elif distance > Defs.TETHER_LEN:
					var excess := distance - Defs.TETHER_LEN
					var a_free := blown(thrower)
					var b_free := blown(other)
					if thrower.st == Defs.RIDE or (b_free and not a_free):
						other.pos = _move(other.pos, offset / distance * excess, Defs.PLAYER_R)
					elif a_free and not b_free:
						thrower.pos = _move(thrower.pos, -offset / distance * excess, Defs.PLAYER_R)
					else:
						other.pos = _move(other.pos, offset / distance * excess * 0.5, Defs.PLAYER_R)
						thrower.pos = _move(thrower.pos, -offset / distance * excess * 0.5, Defs.PLAYER_R)
			"r":
				if not rafts.has(rope.target) or rafts[rope.target].pos.distance_to(thrower.pos) > Defs.ROPE_SNAP:
					ropes.erase(from)
			"i":
				var item: Dictionary = items.get(rope.target, {})
				if item.is_empty():
					ropes.erase(from)
					continue
				item.pos = item.pos.move_toward(thrower.pos, 220.0 * dt)
				if item.pos.distance_to(thrower.pos) < 22.0:
					ropes.erase(from)

func _tick_raft(raft: Dictionary, dt: float) -> void:
	var paddle := Vector2.ZERO
	for id: int in raft.riders:
		paddle += players[id].axis
	var velocity := paddle.limit_length(1.5) * Defs.RAFT_PADDLE
	raft.beached = _shore_near(raft.pos) != Vector2.INF and raft.pos.distance_to(_shore_near(raft.pos)) < 40.0
	var roped := false
	for rope: Dictionary in ropes.values():
		if rope.kind == "r" and rope.target == raft.id and players.has(rope.from):
			var offset: Vector2 = players[rope.from].pos - raft.pos
			if offset.length() > 30.0:
				velocity += offset.normalized() * 120.0
			roped = true
	if not roped and not (raft.beached and paddle.length() < 0.1):
		velocity.y += Defs.CURRENT * Defs.RAFT_DRAG
	var next: Vector2 = raft.pos + Vector2(velocity.x * dt, 0)
	if terrain.tile_at(next) == Defs.WATER:
		raft.pos = next
	next = raft.pos + Vector2(0, velocity.y * dt)
	if terrain.tile_at(next) == Defs.WATER:
		raft.pos = next
	if raft.pos.y > (terrain.h - 3) * Defs.TILE:
		var bank := terrain.washup(terrain.zone_at(raft.pos.x))
		for id: int in raft.riders.duplicate():
			_setback(players[id], bank, "washed")
		raft.pos = bank + Vector2(Defs.TILE, 0)
	for index in range(raft.riders.size()):
		var seat := Vector2.ZERO if raft.riders.size() == 1 else Vector2(-9 + index * 18, 0)
		players[raft.riders[index]].pos = raft.pos + seat

func _creature_step(creature: Dictionary, delta: Vector2) -> bool:
	var next := _move(creature.pos, delta, 8.0)
	if delta.length() > 0.0:
		creature.dir = delta.normalized()
	var tile := terrain.tile_at(next)
	if not Defs.firm(tile) or tile == Defs.CAVE or tile == Defs.RIDGE:
		return false
	creature.pos = next
	return true

func _tick_snuffler(c: Dictionary, dt: float) -> void:
	c.shy = maxf(0.0, c.shy - dt)
	c.t -= dt
	if c.held != Defs.NONE:
		c.munch -= dt
		if c.munch <= 0.0:
			c.held = Defs.NONE
	match int(c.st):
		Defs.C_IDLE:
			if c.held == Defs.NONE and c.shy <= 0.0:
				for item: Dictionary in items.values():
					if item.type == Defs.SNACKS and item.pos.distance_to(c.pos) < 180.0:
						c.st = Defs.C_CHASE
						c.target_kind = "i"
						c.target = item.id
						return
				for player: Dictionary in players.values():
					if has_item(player, Defs.SNACKS) and player.st != Defs.RIDE and player.pos.distance_to(c.pos) < 140.0:
						c.st = Defs.C_CHASE
						c.target_kind = "p"
						c.target = player.id
						return
			if c.t <= 0.0:
				c.t = _rng.randf_range(0.8, 2.6)
				if c.pos.distance_to(c.home) > 170.0:
					c.dir = (c.home - c.pos).normalized()
				elif _rng.randf() < 0.3:
					c.dir = Vector2.ZERO
				else:
					c.dir = Vector2.from_angle(_rng.randf() * TAU)
			if not _creature_step(c, c.dir * 60.0 * dt):
				c.t = 0.0
		Defs.C_CHASE:
			var goal := Vector2.INF
			if c.target_kind == "i" and items.has(c.target):
				goal = items[c.target].pos
			elif c.target_kind == "p" and players.has(c.target) and has_item(players[c.target], Defs.SNACKS) and players[c.target].st != Defs.RIDE:
				goal = players[c.target].pos
			if goal == Vector2.INF or goal.distance_to(c.pos) > 280.0:
				c.st = Defs.C_IDLE
				return
			if goal.distance_to(c.pos) < 16.0:
				if c.target_kind == "i":
					items.erase(c.target)
				else:
					var victim: Dictionary = players[c.target]
					victim.items[victim.items.find(Defs.SNACKS)] = Defs.NONE
				c.held = Defs.SNACKS
				c.munch = 25.0
				c.st = Defs.C_FLEE
				c.t = 4.0
				c.flee = goal
				for player: Dictionary in players.values():
					if player.pos.distance_to(c.pos) < c.flee.distance_to(c.pos) or c.flee == c.pos:
						c.flee = player.pos
				_event("steal", c.pos)
			elif not _creature_step(c, (goal - c.pos).normalized() * 125.0 * dt):
				c.st = Defs.C_IDLE
				c.shy = 1.0
		Defs.C_FLEE:
			var away: Vector2 = c.pos - c.flee
			if away.length() < 1.0:
				away = Vector2.LEFT
			if not _creature_step(c, away.normalized() * 150.0 * dt):
				c.flee = c.pos + Vector2.from_angle(_rng.randf() * TAU) * 40.0
			if c.t <= 0.0:
				c.st = Defs.C_IDLE

func _tick_grumble(c: Dictionary, dt: float) -> void:
	c.t -= dt
	match int(c.st):
		Defs.C_IDLE, Defs.C_RETURN:
			for item: Dictionary in items.values():
				if item.type == Defs.SNACKS and item.pos.distance_to(c.pos) < 150.0:
					c.st = Defs.C_CHASE
					c.target = item.id
					_event("grumble", c.pos)
					return
			if c.st == Defs.C_RETURN:
				c.pos = c.pos.move_toward(c.home, 50.0 * dt)
				if c.pos == c.home:
					c.st = Defs.C_IDLE
		Defs.C_CHASE:
			if not items.has(c.target):
				c.st = Defs.C_RETURN
				return
			var goal: Vector2 = items[c.target].pos
			c.pos = c.pos.move_toward(goal, 45.0 * dt)
			if c.pos.distance_to(goal) < 20.0:
				items.erase(c.target)
				c.st = Defs.C_EAT
				c.t = 25.0
				_event("munch", c.pos)
		Defs.C_EAT:
			if c.t <= 0.0:
				c.st = Defs.C_RETURN
		Defs.C_STOMP:
			var prey: Dictionary = players.get(c.target, {})
			if c.t <= 0.0 or prey.is_empty() or prey.pos.distance_to(c.pos) > 420.0:
				c.st = Defs.C_RETURN
				return
			var next: Vector2 = c.pos.move_toward(prey.pos, 60.0 * dt)
			if next.distance_to(c.home) < 260.0 and not Defs.solid(terrain.tile_at(next)):
				c.pos = next

# --- snapshots (host -> client) ---------------------------------------------

func player_rows() -> Array:
	var rows: Array = []
	for p: Dictionary in players.values():
		rows.append([p.id, int(p.pos.x), int(p.pos.y), p.st, int(rad_to_deg(p.face.angle())), p.sel,
			p.items[0], p.items[1], p.items[2], int(p.sink * 10.0)])
	return rows

func entity_rows() -> Array:
	var rows: Array = []
	for item: Dictionary in items.values():
		rows.append(["i", item.id, item.type, int(item.pos.x), int(item.pos.y)])
	for c: Dictionary in creatures.values():
		rows.append(["c", c.id, c.kind, int(c.pos.x), int(c.pos.y), c.st, c.held])
	for raft: Dictionary in rafts.values():
		rows.append(["r", raft.id, 0, int(raft.pos.x), int(raft.pos.y)])
	for rope: Dictionary in ropes.values():
		rows.append(["o", rope.from, ["p", "r", "i"].find(rope.kind), rope.target, 0])
	return rows

static func _numbers(row: Variant, from: int, count: int) -> bool:
	if not row is Array or row.size() < from + count:
		return false
	for index in range(from, from + count):
		if not (row[index] is float or row[index] is int) or not is_finite(float(row[index])):
			return false
	return true

## Client side: replace player state with the host's rows. Returns false if malformed.
func apply_players(rows: Variant) -> bool:
	if not rows is Array or rows.size() > Defs.MAX_PLAYERS:
		return false
	for row: Variant in rows:
		if not _numbers(row, 0, 10) or int(row[0]) < 1:
			return false
	var seen: Dictionary = {}
	for row: Array in rows:
		var id := int(row[0])
		seen[id] = true
		var p: Dictionary = players[id] if players.has(id) else add_player(id)
		p.pos = Vector2(float(row[1]), float(row[2]))
		p.st = clampi(int(row[3]), 0, Defs.STUN)
		p.face = Vector2.from_angle(deg_to_rad(float(row[4])))
		p.sel = clampi(int(row[5]), 0, 2)
		for index in range(3):
			p.items[index] = clampi(int(row[6 + index]), 0, Defs.SNACKS)
		p.sink = clampf(float(row[9]) / 10.0, 0.0, 1.0)
	for id: int in players.keys():
		if not seen.has(id):
			players.erase(id)
	return true

## Client side: merge a chunk of entity rows, stamping each so stale ones can be pruned.
func apply_entities(rows: Variant, stamp: float) -> bool:
	if not rows is Array or rows.size() > 64:
		return false
	for row: Variant in rows:
		if not row is Array or row.size() < 5 or not row[0] is String or not _numbers(row, 1, 4):
			continue
		var id := int(row[1])
		var pos := Vector2(float(row[3]), float(row[4]))
		match row[0]:
			"i":
				items[id] = {"id": id, "type": clampi(int(row[2]), 1, Defs.SNACKS), "pos": pos, "seen": stamp}
			"c":
				if _numbers(row, 5, 2):
					var previous: Vector2 = creatures[id].pos if creatures.has(id) else pos
					creatures[id] = {"id": id, "kind": clampi(int(row[2]), 0, 1), "pos": pos, "st": int(row[5]),
						"held": int(row[6]), "seen": stamp, "dir": pos - previous}
			"r":
				rafts[id] = {"id": id, "pos": pos, "riders": [], "seen": stamp}
			"o":
				ropes[id] = {"from": id, "kind": ["p", "r", "i"][clampi(int(row[2]), 0, 2)], "target": int(row[3]), "seen": stamp}
	return true

func prune(cutoff: float) -> void:
	for table: Dictionary in [items, creatures, rafts, ropes]:
		for id: int in table.keys():
			if float(table[id].get("seen", 0.0)) < cutoff:
				table.erase(id)

## World position of whatever a rope is attached to (for drawing).
func rope_end(rope: Dictionary) -> Vector2:
	var table: Dictionary = {"p": players, "r": rafts, "i": items}[rope.kind]
	return table[rope.target].pos if table.has(rope.target) else Vector2.INF
