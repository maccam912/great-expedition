class_name Defs
## Shared constants for the simulation. No engine nodes, no state.

const TILE := 32.0
const ROWS := 40

# Tiles
enum { GRASS, TREE, WATER, SAND, MUD, BOG, ROCK, CAVE, PIT, RIDGE, VOID, GOAL }
# Zones
enum { Z_CAMP, Z_CLEARING, Z_RIVER, Z_BOG, Z_RIDGE, Z_CAVE, Z_THICKET, Z_LANDMARK }
const ZONE_NAMES := ["Base Camp", "Clearing", "The River", "The Mire", "Windy Ridge", "The Hollow", "Grumble Pass", "The Landmark"]
# Items (0 = empty slot)
enum { NONE, RAFT, ROPE, LANTERN, WHISTLE, SNACKS }
const ITEM_NAMES := ["", "Raft", "Rope", "Lantern", "Whistle", "Snacks"]
const ITEM_HINTS := ["", "Space: launch onto water", "Space: throw at a friend, raft or item", "Lights up dark places", "Space: whistle at creatures", "Space: toss as bait"]
# Player states
enum { WALK, SWIM, STUCK, RIDE, STUN }
# Creature kinds / states
enum { SNUFFLER, GRUMBLE }
enum { C_IDLE, C_CHASE, C_FLEE, C_EAT, C_STOMP, C_RETURN }
# Wind phases
enum { CALM, WARN, GUST }

const PLAYER_R := 10.0
const WALK_SPEED := 150.0
const MUD_FACTOR := 0.55
const BOG_FACTOR := 0.3
const SINK_TIME := 3.0
const SWIM_SPEED := 22.0
const CURRENT := 110.0
const RAFT_PADDLE := 75.0
const RAFT_DRAG := 0.6
const RAFT_SEATS := 2
const ROPE_RANGE := 300.0
const ROPE_SNAP := 370.0
const STUCK_ESCAPE := 8.0
const ROPE_PULL := 170.0
const TETHER_LEN := 110.0
const WIND_CALM := 3.2
const WIND_WARN := 1.0
const WIND_GUST := 3.0
const WIND_PUSH := 170.0
const LANTERN_LIGHT := 180.0
const WHISTLE_RANGE := 230.0
const GOAL_RADIUS := 140.0
const GRUMBLE_R := 26.0
const MAX_PLAYERS := 8

static func solid(tile: int) -> bool:
	return tile == TREE or tile == ROCK

static func firm(tile: int) -> bool:
	return tile == GRASS or tile == SAND or tile == RIDGE or tile == CAVE or tile == GOAL or tile == MUD
