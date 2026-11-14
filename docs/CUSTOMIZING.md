# Turn the starter into a game

> Template guide, kept for reference. Identity steps 1–4 are already done for
> The Great Expedition and `demo/` has been replaced by `game/`.

## Identity

1. Copy this source folder (or use GitHub's **Use this template** after publishing).
   Exclude `.tools`, `.godot`, `build`, native binaries, and Rust `target` when copying.
2. Change `config/name` and `config/icon` in `project.godot`.
3. Change the Android package and macOS bundle IDs/names/versions in
   `export_presets.cfg` to a namespace you own.
4. Change `network/iroh/session_id` in `project.godot` to `your-game/1`, and change
   the Rust `ALPN` constant to `your-game/1`. Rebuild. New games must not discover
   or accept one another merely because they came from the same template.
5. Keep or replace the rendezvous service URL. The supplied URL is owner-managed;
   an empty URL disables short codes while preserving ticket connections.

There is no need to rename the internal Rust crate or Java package just to rename
your game. If you do, update the Cargo package/library names, native output names
in `build_native.py`, `.gdextension.in`, Java `System.loadLibrary`, Java package
and manifest registration, and the JNI function symbol in `lib.rs` together.

## Gameplay

Replace `demo/main.tscn`, `demo/main.gd`, and `demo/arena.gd` with your scenes. These
files are UI/presentation examples and contain no required transport code.

`network/session.gd` contains the deliberately tiny demo simulation and protocol.
Replace `players`/movement/snapshots with your world state. Preserve the boundaries:

- Clients submit intent. The host validates identity, ownership, range, and timing
  before changing game state.
- Host snapshots describe accepted state. Clients should not promote their own
  speculative state to authority.
- Reliable messages are appropriate for join/chat/actions that must arrive.
  Ordered unreliable messages suit replaceable snapshots/input samples.
- Keep messages below the packet limit. For larger worlds, design replication
  interest, deltas, or bounded chunking; do not simply enlarge an unbounded queue.

For responsive action games, add interpolation and client prediction according to
your simulation's needs. For turn-based games, use validated reliable actions and
state revision numbers. The template does not impose a genre, camera, physics
engine, or fixed world scene.

## Test the boundary you changed

`tests/protocol.gd` checks movement clamping, unknown-peer rejection, host-only
snapshots, malformed data, and reset. Extend these when changing authority rules.
`tools/check.py` runs real Iroh processes and verifies two clients, movement, chat,
and disconnect cleanup. The optional code/relay checks use live external services.

For a new game, also test a slow join, wrong protocol, full room, host departure,
invalid input, network interruption, mobile background/resume, and reconnection.
Add physical Android and cross-OS playtests before claiming those behaviors work.

## Frequent problems

| Symptom | Check |
| --- | --- |
| Offline works, Host does not | Run setup; inspect native load errors; use the pinned editor |
| Four-character code fails | Expired/revoked code, different `session_id`, HTTP outage, Iroh lookup/relay access |
| Full ticket works, code does not | Check the HTTP service and Iroh address lookup separately |
| Android compiles but cannot connect | Ensure IrohAndroid plugin and JNI context initialization are packaged and enabled |
| macOS export rejects library | Rebuild without `--host-only`; export requires ARM64 + Intel |
| Android update cannot install | Signing key differs from the previously installed APK |
| `@rpc` does not work | This starter polls explicit packets; see NETWORKING.md |
| Export builds but game behavior differs | Test the exported executable/device, not only the editor |

Keep [VALIDATION.md](VALIDATION.md) current so the next developer can tell which
claims have local evidence and which still need CI or device testing.
