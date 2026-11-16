# hegel-remote

An open-source remote for Hegel amplifiers that support IP control (TCP port 50001): iPhone and Mac, SwiftUI.

> Unofficial. Not affiliated with, endorsed by or supported by Hegel Music Systems AS. "Hegel" and model names are
> used only to describe compatibility.

Status: early development. First target: Hegel H590.

## HegelKit (Swift package)

`Package.swift` builds the protocol/networking core: `HegelProtocol` (pure, builds on Linux), `HegelClient`,
`HegelDiscovery` and the `hegelctl` CLI. See `Sources/README.md` and `Docs/protocol.md`.

```
swift test
swift run hegelctl --host <amp-ip> status
```
