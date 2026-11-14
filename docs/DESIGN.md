# The Great Expedition — design doc & build log

> Living document. **Read "Status" first** when resuming: it says what is done,
> what is verified, and what comes next. Update it at the end of every work session.

## Pitch

A team of tiny explorers (1–8 players, co-op) crosses a procedurally generated
wilderness, west to east, to reach a strange landmark (a giant glowing egg).
Nobody climbs anything: the trouble is rivers, bogs, wind, caves and wildlife.
Each explorer carries only two items. The fun is working out how to get
*everyone* through with the gear you have. Short runs (5–10 min), a new route
per seed, friendly physics, no death — only setbacks and comedy.

## Pillars

1. **Everyone or no one.** The run ends only when every explorer is at the landmark.
2. **Few items, many uses.** Five items, each with more than one use, two slots each.
3. **Setbacks, not death.** Falling in = swept downstream, washed up, items dropped.
4. **Readable chaos.** Simple top-down physics; every hazard is telegraphed.
5. **New route every run.** Zone order and layout come from one integer seed.

## Stack & architecture

- Godot 4.7.2 (pinned in `.tools/`), GDScript, template: maccam912/godot-iroh-template.
- Transport: Iroh GDExtension (`native/iroh`), 4-letter room codes (`network/rooms.gd`).
  Explicit JSON packets, **host-authoritative**, no Godot high-level RPC.
- **All rules live in `game/sim/` as pure `RefCounted` code** — no nodes, no
  network, no rendering. A full expedition can be played in a headless test by
  calling `sim.tick(dt)`. Rendering and networking only read/feed the sim.

| Path | Role |
| --- | --- |
| `game/sim/defs.gd` (`Defs`) | Constants: tile ids, item ids, tuning numbers |
| `game/sim/terrain.gd` (`Terrain`) | Seed → tile grid, zones, spawn points. Deterministic |
| `game/sim/sim.gd` (`ExpeditionSim`) | World state + `tick(dt)`, inputs, actions, snapshots, events |
| `network/session.gd` (`Session` autoload) | Lobby, protocol, owns the sim (host) or a mirror (client) |
| `network/rooms.gd`, `rendezvous.gd` | Room codes (template, unchanged) |
| `game/main.tscn` + `main.gd` | Menu / lobby / game screen switching, input capture |
| `game/world_view.gd` | Draws terrain, explorers, items, creatures, darkness, wind |
| `game/hud.gd` | Inventory slots, hints, timer, banners |
| `game/art.gd` (`Art`) | Code-drawn explorers, items, creatures, egg (no sprite sheets yet) |
| `tests/sim_test.gd` | Headless rule tests: every hazard/item rule, 60-seed reachability, snapshot round-trip, random-input fuzz |
| `tests/protocol.gd` | Authority/validation tests on `Session._receive` |
| `tests/smoke_peer.gd` + `tools/check.py` | Real host + 2 clients over Iroh |
| `tests/render_game.gd` | Renders the game to `build/*.png` for visual checks |

Units: 1 tile = 32 px. World is `W × 40` tiles, travel is +x (east).

## World generation (`Terrain`)

Strip of zones left→right: **Camp** → 5 hazard zones in seed-shuffled order,
each followed by a small clearing → **Landmark**. Top/bottom rows are trees.

| Zone | Layout | Hazard |
| --- | --- | --- |
| River | Meandering water 9 tiles wide, sand banks | Current flows south. Swimmers can't cross unaided: bends nudge edge swimmers back onto their own bank; mid-river you reach the bottom = washed up on the west bank, stunned, items dropped |
| Bog | Mud (slow) with a wide mire of deep bog, tussock islands forming a zig-zag route plus decoys | In deep bog you sink (3 s) then are stuck until tugged or roped; after 8 s alone you crawl back to the bog entrance (no solo softlock) |
| Ridge | Open rock shelf, cliff edge (void) to the south, scattered boulders | Gusts blow south on a cycle (calm → warning → gust). Shelter = boulder just upwind. Blown off = tumble back to zone entrance |
| Cave | Solid rock with carved winding passages, pits | Dark. Pits invisible without light. Fall = back to cave entrance |
| Thicket | Tree wall with one narrow pass; a sleeping **Grumble** plugs it; **Snufflers** roam | Grumble must be lured (snack) or distracted (whistle). Snufflers steal snacks |

## Items (2 slots each; 3 when solo)

| Item | Primary use | Other uses |
| --- | --- | --- |
| Raft | Deploy on water from shore; holds **two**; riders paddle, current drags | Acts as a sail in gusts when carried (pushed harder). Empty raft drifts unless beached |
| Rope | Throw at a swimmer / stuck friend: pulls them to you | Pull an empty raft across; tether two walkers so a sheltered one anchors the other in wind |
| Lantern | Lights the cave around the carrier | Works dropped on the ground as a beacon |
| Whistle | Snufflers drop loot and flee; Grumble wakes and stomps toward whistler | Visible ping ring (also in the dark) |
| Snacks | Drop near Grumble: it leaves the pass to eat for ~25 s | Bait Snufflers away. Snufflers steal them from pockets |

Supply pile at camp scales with party size (see `ExpeditionSim._spawn_supplies`).

## Controls

WASD/arrows move · **Space** use selected item · **E** interact (pick up, board/leave
raft, tug stuck friend) · **Q** drop selected · **1/2/3** or **Tab** select slot.
Facing = last move direction (used for rope aim and raft deploy).

## Network protocol (version 2)

JSON, ≤1024 bytes per packet. Channel 0 reliable, channel 1 unreliable.

| Dir | Type | Delivery | Payload |
| --- | --- | --- | --- |
| C→H | `hello` | reliable | `version` |
| H→C | `welcome` | reliable | `version`, `phase`, `seed` |
| H→all | `lobby` | reliable | `ids` (roster) |
| H→all | `start` | reliable | `seed`, `ids` |
| C→H | `in` | unreliable 20 Hz | `ax:[x,y]` |
| C→H | `act` | reliable | `a`: use / interact / drop / slot, `v` |
| H→all | `sp` | unreliable 20 Hz | time, wind, win flag, player rows |
| H→all | `se` | unreliable 10 Hz | chunked entity rows (items, creatures, rafts, ropes) |
| H→all | `ev` | reliable | sim events for sound/juice |
| H→all | `chat` | reliable | text |

Clients never send positions. Entities not refreshed for 0.6 s are dropped on
the client, so chunked/lost `se` packets self-heal. The client regenerates the
terrain from `seed`, so the map is never sent.

## Milestones

- **M0 Setup** — template copied, identity renamed, native ext built, design doc.
- **M1 Core sim** — terrain gen, movement/collision, items pickup/drop, win check, tests.
- **M2 Hazards** — river+raft+rope, bog, ridge wind, cave pits, creatures, tests.
- **M3 Multiplayer** — lobby, start, snapshots, actions, events; protocol + Iroh smoke tests.
- **M4 Presentation** — world view, darkness, HUD, hints, sounds, win screen.
- **M5 Polish (next)** — see backlog.

## Backlog / ideas (not started)

- Client-side prediction + interpolation buffer (currently simple smoothing).
- Mouse/touch aim, gamepad, Android touch controls.
- Player names & colour pick in lobby; emotes; "ready" state; host migration.
- Kenney sprite art pass for explorers/creatures (currently vector-drawn in code).
- Music; ambient river/wind loops; more juice (screen shake, particles).
- More zones: beaver dam, fog marsh, rope bridge gap, night meadow with fireflies.
- More landmarks (abandoned observatory, sleeping giant) chosen by seed.
- Difficulty/length options; daily seed; end-of-run stats ("most dunked").
- Run summary screen with route map; replay same seed.
- Reconnect/resume; late-join spawns at the rearmost explorer.

## Status

**Last updated: 2026-11-14 (end of session 1).** M0–M4 are done; M5 polish is next.

### Done and verified this session

| What | Evidence |
| --- | --- |
| Template copied, renamed (`great-expedition/1` ALPN + session id), native ext built | `python3.11 tools/setup.py` → "Ready" |
| Terrain gen, all 5 zones, items, creatures, win | `tests/sim_test.gd` → `SIM_PASS 271 checks` |
| Authority/validation of every message type | `tests/protocol.gd` → `PROTOCOL_PASS` |
| Real Iroh host + 2 clients: join, start, mirrored world, walk to a supply, pick it up, chat, leave | `python3.11 tools/check.py` → `IROH_SMOKE_PASS` |
| Menu, each zone, darkness, raft/rope/snuffler, win panel render correctly | `tests/render_game.gd` → `build/shot_*.png`, inspected by eye |

### Not verified yet

- **Nobody has hand-played a run with a keyboard.** Rules are covered by tests and
  screenshots, but feel/tuning (speeds, gust timing, snuffler greed, cave size) is a
  first guess. Play a solo run and a 2–3 player run before tuning anything else.
- Join by 4-letter **code** against the live rendezvous service (`tools/check.py --codes`)
  and relay-only (`--relay-only`) were not run. Ticket-based joining was.
- Exports (macOS app / Windows / Linux / Android) were not built for this game.
- Late join mid-run, host leaving mid-run, and 8-player packet sizes are untested
  over a real network (packet size is unit-checked for 3 players only).

### Releases

CI (`.github/workflows/build.yml`) builds Windows, Linux and macOS on every push and,
on `main`, publishes release `build-<run number>` with the three zips. Android and the
dedicated server were dropped from CI (the export presets and `tools/` still support them).

### Known rough edges

- Clients render host snapshots with simple smoothing: no prediction, so your own
  explorer has one round-trip of input lag when you are not the host.
- Snufflers and the Grumble have no pathfinding (they walk straight and give up at
  trees/water). The Grumble ignores tile collision; trees are kept clear of its pass.
- Supplies scale with party size at start only; late joiners add no supplies.
- `--host` on the command line hosts a lobby but there is no auto-start, so a
  headless dedicated server cannot begin a run yet.
- Art is all code-drawn; audio is Kenney CC0 (`assets/`), one music loop.

### Next steps, in order

1. Hand-play solo and multiplayer; tune numbers in `game/sim/defs.gd`.
2. Client-side prediction for the local explorer (run the same `_tick_player`
   locally, reconcile to snapshots).
3. Lobby polish: names/colours, ready-up, show who is who.
4. Run `tools/check.py --codes --relay-only`; build a macOS export and test two machines.
5. Backlog items above (touch/gamepad, more zones and landmarks, run stats).

### How to resume

```sh
python3.11 tools/setup.py                 # once per checkout: engine + native ext
python3.11 tools/godot.py                 # play (add `-- --solo --seed=7` to jump in)
python3.11 tools/check.py                 # protocol + sim + real Iroh smoke
python3.11 tools/godot.py --script res://tests/render_game.gd -- --quiet   # screenshots → build/
```

System `python3` is 3.9 on this Mac; the tools need 3.11+, hence `python3.11`.
After adding a new `class_name` script, run `tools/godot.py --headless --import` once.
