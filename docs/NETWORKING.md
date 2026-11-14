# Networking contract

> Transport, room codes and trust notes below still apply. The **wire protocol and
> `Session` API described here are the template demo's**; the game's protocol
> (version 2: lobby, start, input, actions, chunked snapshots, events) is in
> [DESIGN.md](DESIGN.md).

## Layers

`Rooms` creates/resolves/revokes a four-character code through the existing HTTP
service. It then gives `Session` a public Iroh endpoint ID. `Session` polls an
`IrohServer` or `IrohClient` and implements this demo's protocol. Rust owns Iroh,
QUIC streams/datagrams, and a two-thread Tokio runtime. Godot objects stay on the
main thread; async networking communicates through bounded queues.

The code service is **discovery**, not a game server or packet relay. Game messages
use Iroh. The host simulates the world. Iroh can establish direct routes and use
its N0 preset relays when necessary. `--relay-only` disables direct IP transports
for testing. No inbound port-forwarding setup is required for the relay route.

## Godot-facing interface

```gdscript
await Rooms.host()             # Host and obtain a short code
await Rooms.join("ABCD")       # Resolve code then connect
Session.host()                 # Host without HTTP discovery
Session.join(full_ticket)      # Connect without HTTP discovery
Session.direction = Vector2(1, 0)
Session.send_chat("Hello")
Session.leave()
```

Use the scene-tree `Session` and `Rooms` autoloads; no project-specific game class
is needed. `Session.players` maps numeric connection IDs to demo positions.
`status_changed`, `chat_received`, and `Rooms.changed` drive UI. Host ID is 1.
Clients are assigned IDs >= 2; those IDs are session-local and are not accounts.

The native objects derive from `MultiplayerPeerExtension`, but this template
**polls packets directly**. Do not also assign the same peer to
`multiplayer.multiplayer_peer`: Godot would poll/consume the same stream. This
transport does not implement high-level SceneMultiplayer's relay/authentication
protocol. `@rpc`, `MultiplayerSpawner`, and `MultiplayerSynchronizer` are not a
promised drop-in feature. Build and test a separate adapter if your game needs them.

## Demo wire protocol

The application ALPN is `godot-iroh-template/1` in Rust's `lib.rs`. JSON messages
are UTF-8 and at most 1024 bytes. Objects are parsed as data, never deserialized
as Godot objects. The native ceiling is 1200 bytes reliable / 1024 bytes unreliable.
Four native channel IDs (0–3) are available.

| Channel | Delivery | Messages |
| --- | --- | --- |
| 0 | Reliable, ordered stream | `hello`, `welcome`, `chat` |
| 1 | Unreliable, ordered datagrams | `input`, `state` |

The client first sends `hello` with version 1. The host admits at most eight total
players, rejects mismatched versions, and times out unintroduced peers after five
seconds. The Rust connection attempt has a 15-second deadline; the Godot welcome
deadline is 18 seconds. Reliable channel order is preserved within the channel;
there is no cross-channel ordering guarantee.

Clients send an input direction at 20 Hz. The host clamps its length to one,
applies speed and arena limits at Godot's physics tick, and stops stale inputs after
500 ms. Clients never submit authoritative positions. The host sends whole-world
snapshots at 20 Hz. Clients only accept snapshots from host ID 1. Chat is limited
to 160 characters and the host accepts at most one message per peer per 750 ms.

The demo displays snapshots directly. Prediction, rollback, interpolation,
reconnect/resume, persistent identities, lobby ready/start rules, and host migration
are deliberately left to the game. A disconnect returns to the offline playground.

## Short-code service

Configuration lives in `project.godot`:

```ini
[network]
iroh/rendezvous_url="https://iroh-rendezvous.maccam912.workers.dev"
iroh/session_id="godot-iroh-starter/1"
```

Change `session_id` for every new game and incompatible application protocol.
The client rejects a code belonging to a different session namespace. Set the
URL to an empty string to disable codes, or point it at a service implementing:

- `POST /v1/join-codes` with `endpoint_id`, `session_id`, and `expires_in: 600`.
  Returns `code`, matching IDs, `expires_at` (UTC), and `revoke_token`.
- `GET /v1/join-codes/{code}` resolves the endpoint/session/expiry, or returns 404.
- `DELETE /v1/join-codes/{code}` with `Authorization: Bearer <revoke_token>` revokes it.

The supplied service accepts endpoint strings up to 256 characters, so codes store
the compact 43-character public endpoint ID, not the larger full ticket. Iroh
address lookup resolves that ID. Full tickets encode the endpoint ID plus current
address hints and can be useful when a local route is available.

Each new room/code request captures a generation number. Leaving, rehosting,
or switching joins invalidates it. A late create response is revoked rather than
displayed. Renewal first creates a replacement and then revokes the old code, so
service failures do not terminate an existing game. Revocation tokens stay in
memory. Normal leave/quit attempts revocation; crashes, suspension, or network
loss can prevent it, so codes expire server-side after ten minutes.

The owner-managed endpoint is configured here with permission for this starter.
It is not bundled service infrastructure, and its URL is not a secret. If you
publish a template for other people, decide whether they should share that service
or configure their own; this project does not deploy or modify the Worker.

## Trust and capacity

Iroh encrypts connections and authenticates the remote endpoint's key. A four-letter
code is a lookup convenience, not a password or account login. Anyone who obtains
or guesses a valid code/ticket may attempt to join. Add host approval, invitations,
or application authentication before using this for private or adversarial rooms.

The host is authoritative but also trusted; this demo does not prevent host cheating.
Packet sizes, queue sizes, frame receive budgets, player count, and basic numeric
inputs are bounded. This is a small-room starter, not a claim of Internet-scale
abuse resistance. Reliable queue saturation reports a send error; there is no
unbounded retry buffer. Important game transactions should have explicit message
IDs, acknowledgements, and application-level retry/disconnect policy.

Tickets can contain IP address hints; share them as connection details, not secrets.
Neither session IDs nor numeric peer IDs establish user identity. The N0 preset
uses external services: review relay configuration/costs and availability for a
production game. See [Iroh's connection and trust model](https://docs.rs/iroh/1.4.1/iroh/).
