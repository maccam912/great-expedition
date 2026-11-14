class_name Terrain
extends RefCounted
## Deterministic seed -> tile grid. Travel is west to east through shuffled zones.

const WIDTHS := {
	Defs.Z_CAMP: 12, Defs.Z_CLEARING: 5, Defs.Z_RIVER: 15, Defs.Z_BOG: 18,
	Defs.Z_RIDGE: 26, Defs.Z_CAVE: 22, Defs.Z_THICKET: 16, Defs.Z_LANDMARK: 14,
}

var seed_value := 0
var w := 0
var h := Defs.ROWS
var tiles := PackedByteArray()
var zones: Array = []          # [{kind, x0, x1}] in tile columns, x1 exclusive
var spawn := Vector2.ZERO
var supplies := Vector2.ZERO
var goal := Vector2.ZERO
var grumble_home := Vector2.ZERO
var snuffler_homes: Array = []
var _rng := RandomNumberGenerator.new()

func generate(new_seed: int) -> void:
	seed_value = new_seed
	_rng.seed = new_seed
	var order := [Defs.Z_RIVER, Defs.Z_BOG, Defs.Z_RIDGE, Defs.Z_CAVE, Defs.Z_THICKET]
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: int = order[i]
		order[i] = order[j]
		order[j] = swap
	var kinds := [Defs.Z_CAMP]
	for kind: int in order:
		kinds.append(kind)
		kinds.append(Defs.Z_CLEARING)
	kinds[kinds.size() - 1] = Defs.Z_LANDMARK
	zones.clear()
	snuffler_homes.clear()
	w = 0
	for kind: int in kinds:
		zones.append({"kind": kind, "x0": w, "x1": w + int(WIDTHS[kind])})
		w += int(WIDTHS[kind])
	tiles.resize(w * h)
	tiles.fill(Defs.GRASS)
	for x in range(w):
		for y in [0, 1, h - 2, h - 1]:
			put(x, y, Defs.TREE)
	for y in range(h):
		put(0, y, Defs.TREE)
		put(w - 1, y, Defs.TREE)
	for zone: Dictionary in zones:
		var x0: int = zone.x0
		var x1: int = zone.x1
		match zone.kind:
			Defs.Z_CAMP:
				spawn = center(x0 + 4, h / 2)
				supplies = center(x0 + 8, h / 2)
				_sprinkle(x0 + 1, x1, 0.03, h / 2 - 5, h / 2 + 5)
			Defs.Z_CLEARING:
				_sprinkle(x0, x1, 0.05, -1, -1)
				if _rng.randf() < 0.5:
					snuffler_homes.append(center(x0 + 2, _rng.randi_range(6, h - 7)))
			Defs.Z_RIVER: _river(x0, x1)
			Defs.Z_BOG: _bog(x0, x1)
			Defs.Z_RIDGE: _ridge(x0, x1)
			Defs.Z_CAVE: _cave(x0, x1)
			Defs.Z_THICKET: _thicket(x0, x1)
			Defs.Z_LANDMARK:
				goal = center(x0 + 8, h / 2)
				for y in range(h / 2 - 4, h / 2 + 5):
					for x in range(x0 + 4, x0 + 13):
						if center(x, y).distance_to(goal) < 4.3 * Defs.TILE:
							put(x, y, Defs.GOAL)

# --- queries ---------------------------------------------------------------

func put(x: int, y: int, tile: int) -> void:
	if x >= 0 and y >= 0 and x < w and y < h:
		tiles[y * w + x] = tile

func tile(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return Defs.TREE
	return tiles[y * w + x]

func tile_at(pos: Vector2) -> int:
	return tile(int(floor(pos.x / Defs.TILE)), int(floor(pos.y / Defs.TILE)))

func center(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * Defs.TILE, (y + 0.5) * Defs.TILE)

func size_px() -> Vector2:
	return Vector2(w, h) * Defs.TILE

func zone_at(px: float) -> Dictionary:
	var column := int(floor(px / Defs.TILE))
	for zone: Dictionary in zones:
		if column >= zone.x0 and column < zone.x1:
			return zone
	return zones[0] if column < 0 else zones[zones.size() - 1]

## True when a circle at pos overlaps a solid tile.
func blocked(pos: Vector2, radius: float) -> bool:
	for offset: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		if Defs.solid(tile_at(pos + offset * radius)):
			return true
	return false

## A solid tile within three tiles upwind (north) blocks the gust.
func sheltered(pos: Vector2) -> bool:
	var x := int(floor(pos.x / Defs.TILE))
	var y := int(floor(pos.y / Defs.TILE))
	for step in range(1, 4):
		if Defs.solid(tile(x, y - step)):
			return true
	return false

## Where a zone's setback drops you: just west of the zone, on the same row.
func entrance(zone: Dictionary, y: float) -> Vector2:
	var low := 3
	var high := h - 4
	if zone.kind == Defs.Z_RIDGE:
		high = 13
	var row := clampi(int(floor(y / Defs.TILE)), low, high)
	var column: int = zone.x0 - 2
	for attempt in range(h):
		for candidate: int in [row + attempt, row - attempt]:
			if candidate >= low and candidate <= high and tile(column, candidate) == Defs.GRASS:
				return center(column, candidate)
	return center(column, row)

## West bank near the bottom of a river: where swimmers and rafts wash up.
func washup(zone: Dictionary) -> Vector2:
	var row := h - 6
	for x in range(zone.x0, zone.x1):
		if tile(x, row) == Defs.WATER:
			return center(x - 1, row)
	return center(zone.x0, row)

# --- zone builders ---------------------------------------------------------

func _sprinkle(x0: int, x1: int, chance: float, skip_from: int, skip_to: int) -> void:
	for x in range(x0, x1):
		for y in range(3, h - 3):
			if y >= skip_from and y <= skip_to:
				continue
			if _rng.randf() < chance:
				put(x, y, Defs.TREE)

func _river(x0: int, _x1: int) -> void:
	var phase := _rng.randf() * TAU
	var wobble := _rng.randf_range(0.16, 0.26)
	for y in range(h):
		var offset := int(round(1.5 + 1.5 * sin(y * wobble + phase)))
		var left := x0 + 1 + offset
		put(left, y, Defs.SAND)
		for x in range(left + 1, left + 10):
			put(x, y, Defs.WATER)
		put(left + 10, y, Defs.SAND)

func _bog(x0: int, x1: int) -> void:
	for x in range(x0, x1):
		for y in range(2, h - 2):
			put(x, y, Defs.MUD)
	var mire0 := x0 + 5
	var mire1 := x0 + 13
	for x in range(mire0, mire1):
		for y in range(2, h - 2):
			put(x, y, Defs.BOG)
	for route in range(3):
		var y := _rng.randi_range(5, h - 6)
		var x := mire0 - 1
		while x < mire1:
			x += _rng.randi_range(2, 3)
			y = clampi(y + _rng.randi_range(-2, 2), 3, h - 4)
			if x < mire1:
				put(x, y, Defs.GRASS)
				if _rng.randf() < 0.5:
					put(x, y + 1, Defs.GRASS)
	for decoy in range(14):
		put(_rng.randi_range(mire0, mire1 - 1), _rng.randi_range(3, h - 4), Defs.GRASS)

func _ridge(x0: int, x1: int) -> void:
	for x in range(x0, x1):
		for y in range(2, h):
			put(x, y, Defs.RIDGE if y < 16 else Defs.VOID)
	var x := x0 + 2
	while x < x1 - 2:
		for count in range(_rng.randi_range(2, 3)):
			var y := _rng.randi_range(3, 13)
			put(x, y, Defs.ROCK)
			if _rng.randf() < 0.6:
				put(x + 1, y, Defs.ROCK)
		x += _rng.randi_range(3, 4)

func _cave(x0: int, x1: int) -> void:
	for x in range(x0, x1):
		for y in range(h):
			put(x, y, Defs.ROCK)
	var rows: Array = []
	for index in range(3):
		var y := clampi(7 + index * 12 + _rng.randi_range(-2, 2), 4, h - 5)
		rows.append(y)
		var x := x0
		var drift := 0
		while x < x1:
			_carve(x, y, x0, x1)
			if _rng.randf() < 0.55:
				x += 1
			else:
				if drift == 0 or _rng.randf() < 0.3:
					drift = -1 if _rng.randf() < 0.5 else 1
				y = clampi(y + drift, 4, h - 5)
	for link in range(2):
		var x := _rng.randi_range(x0 + 4, x1 - 5)
		for y in range(int(rows[link]), int(rows[link + 1]) + 1):
			_carve(x, y, x0, x1)
	for x in range(x0 + 2, x1 - 2):
		for y in range(3, h - 3):
			if _rng.randf() < 0.16 and _open_around(x, y):
				put(x, y, Defs.PIT)

func _carve(cx: int, cy: int, x0: int, x1: int) -> void:
	for x in range(maxi(cx - 1, x0), mini(cx + 2, x1)):
		for y in range(cy - 1, cy + 2):
			if y >= 2 and y < h - 2:
				put(x, y, Defs.CAVE)

func _open_around(cx: int, cy: int) -> bool:
	for x in range(cx - 1, cx + 2):
		for y in range(cy - 1, cy + 2):
			if tile(x, y) != Defs.CAVE:
				return false
	return true

func _thicket(x0: int, x1: int) -> void:
	var wall := x0 + 9
	var pass_row := _rng.randi_range(8, h - 10)
	_sprinkle(x0, wall - 5, 0.07, -1, -1)
	_sprinkle(wall + 6, x1, 0.07, -1, -1)
	for y in range(h):
		if y != pass_row and y != pass_row + 1:
			put(wall, y, Defs.TREE)
			put(wall + 1, y, Defs.TREE)
	grumble_home = Vector2((wall + 1) * Defs.TILE, (pass_row + 1) * Defs.TILE)
	snuffler_homes.append(center(x0 + 3, clampi(pass_row + 6, 4, h - 5)))
	snuffler_homes.append(center(x0 + 4, clampi(pass_row - 6, 4, h - 5)))
