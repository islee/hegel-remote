# HegelKit sources

Protocol and networking core for hegel-remote (Hegel amplifier remote). Protocol facts: `Docs/protocol.md`.

| Target | Platform | Role |
|---|---|---|
| `HegelProtocol` | any (stdlib only; builds on Linux) | `Command` encode, `PacketFramer`/`AmpEvent` decode, `AmpState`, `AmpModel` table |
| `HegelClient` | Apple (Network.framework) | `actor AmpClient`: connect, state stream, keepalive, paced writes, auto-reconnect |
| `HegelDiscovery` | Apple | `_raop`/`_airplay` Bonjour browse, `HegelNameMatcher`, confirm on port 50001 |
| `hegelctl` | macOS | CLI: `--host <ip> status|on|off|toggle|vol|mute|input|watch`, `discover` |

## Patterns
1. Incoming packets are a state stream (the amp broadcasts to all clients); never pair a reply to a request.
2. Model data is one table (`AmpModel.all`); a new model is one entry.
3. Apple-only targets are declared in `Package.swift` only on non-Linux hosts.

## Gotchas
- Writes must be spaced (>= 50 ms); the amp drops back-to-back packets. `AmpClient` does this.
- `connect()` on a refused port takes the full `connectTimeout` (Network.framework reports `.waiting`, not failure).
- `hegelctl --no-keepalive` avoids sending `-r.3`; use it for read-only checks.
