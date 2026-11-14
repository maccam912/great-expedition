# The Great Expedition

A co-op game for 1–8 tiny explorers. Cross a procedurally generated wilderness —
a river, a mire, a windy ridge, a dark hollow and a pass plugged by a sleeping
Grumble — and get **everyone** to the giant glowing egg. Each explorer carries
two items: a raft (holds two), a rope, a lantern, a whistle, snacks. New route
every run, no death, plenty of setbacks.

Built with Godot 4.7.2 on [godot-iroh-template](https://github.com/maccam912/godot-iroh-template):
peer-to-peer over Iroh with four-letter join codes, host-authoritative.

**Design, architecture, protocol, status and next steps: [docs/DESIGN.md](docs/DESIGN.md).**

## Play

Needs Python 3.11+, Rust (rustup) and a C toolchain for the first setup.

```sh
python3 tools/setup.py     # downloads pinned Godot into .tools/, builds the Iroh extension
python3 tools/godot.py     # run the game  (tools/godot.py --editor for the editor)
```

- **Solo:** Start solo expedition (you get three item slots instead of two).
- **Party:** one player clicks *Host a party* and shares the join code; others type
  it and click *Join*; the host starts the run. *Copy ticket* is a fallback that
  skips the code service.

| Key | Action |
| --- | --- |
| WASD / arrows | Move (and paddle the raft) |
| Space | Use the selected item |
| E | Interact: pick up, step off the raft, tug a stuck friend, pick up an empty raft |
| Q | Drop the selected item |
| 1 / 2 / 3, Tab | Select item slot |
| Esc twice | Leave the run |

## Test

```sh
python3 tools/check.py     # protocol rules, 271 sim rule checks, real host + 2 clients over Iroh
python3 tools/godot.py --script res://tests/render_game.gd -- --quiet   # screenshots in build/
```

All game rules live in `game/sim/` as plain data + `tick(dt)` with no nodes or
networking, so they are tested headlessly. See [docs/VALIDATION.md](docs/VALIDATION.md)
for what has and has not been exercised.

## Build

Exports and CI are inherited from the template: [docs/BUILDING.md](docs/BUILDING.md),
[docs/NETWORKING.md](docs/NETWORKING.md) (transport), [docs/CUSTOMIZING.md](docs/CUSTOMIZING.md).

## Credits and licenses

Game and template code: MIT. Sound effects and music: [Kenney](https://kenney.nl) (CC0).
Transport derives from Tipragot's MIT Godot-Iroh work; see [THIRD_PARTY.md](THIRD_PARTY.md).
