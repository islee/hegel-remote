# hegel-remote architecture

One repository, two layers:

```
Sources/HegelRemoteCore/   the apps' logic layer, a SwiftPM library, no SwiftUI: AmpController, SettingsStore, Skin,
                           InputCatalog, AmpActions, CustomButton, Playback/ (driver protocol + drivers),
                           ModelCapabilities, WheelDetentTracker, ReadoutText, FontRegistry
Tests/HegelRemoteCoreTests/ its unit tests (`swift test` on macOS; the same files as a non-hosted simulator bundle)
Sources/, Tests/ (rest)    HegelKit: protocol, client, discovery, hegelctl, FakeAmp + fakeamp (see Sources/README.md)
App/                       SwiftUI apps (iOS 17+, macOS 14+), one source tree, #if os(...) for the platform bits
  Intents/                 App Intents (Siri / Shortcuts) + App Shortcuts phrases, thin over Core
  Views/                   the screens, thin over Core
  Resources/Fonts/         Doto variable TTF (SIL OFL 1.1) + licence
Docs/                      protocol.md (wire protocol, live findings), this file, design/ (canvas), screenshots/
project.yml                XcodeGen spec -> HegelRemote.xcodeproj (generated, not tracked)
```

## Layers and the one rule

**Views never talk to the network and never branch on a model.** They read observable state from `AmpController`
and `SettingsStore` and call methods. Everything that could be reused by a widget, a Watch app or a web front end
sits in the `HegelRemoteCore` package target and imports only Foundation, Observation and HegelKit.

```
SwiftUI views / App Intents / (later: widgets, Watch)
        |            |
        v            v
  AmpController   AmpSession.run + AmpActionRunner        <- Core
        |            |
        v            v
     AmpClient (HegelKit: one TCP connection, paced writes, auto-reconnect, event stream)
        |
     the amp (TCP 50001) -- broadcasts every state change to all clients
```

### AmpController (`Sources/HegelRemoteCore/AmpController.swift`)
`@MainActor @Observable`. Owns the live `AmpClient`, folds its event stream into `amp: AmpState` and
`phase: idle | connecting | connected | unreachable(reason)`. Commands go through `AmpAction` so the UI, Siri and
custom buttons share one mapping to protocol packets and one confirmation rule (the next broadcast of that kind).

Volume is coalesced: wheel detents and slider drags set `pendingVolume`; one flush task sends `-v.<target>`
whenever the target changes (HegelKit paces writes at 100 ms because the H590 drops back-to-back packets) and
clears the pending value once the amp's reply catches up. The readout shows `displayVolume = pending ?? amp.volume`,
so it follows the finger; the amp's reply is always the truth (it may round when a max-volume limit is set).

Lifecycle: iOS drops the connection on background and reopens on foreground (a suspended socket is not
trustworthy); macOS keeps it. `AmpClient` reconnects with backoff on its own; the controller only maps its
connection events to `phase`.

### SettingsStore (`Sources/HegelRemoteCore/SettingsStore.swift`)
All persistence, UserDefaults-backed (free-account signing: no App Groups needed because intents run in the app
process). Scalars under plain keys (so `-lightSkinID silver` launch arguments override them, which the screenshot
script uses); collections as JSON. Holds: `AmpAddress` (host, port, model id, name), `appearance`, the skin
pairing (`lightSkinID`, `darkSkinID`), `iconChoice`, `suggestModelIcon`, `volumeControlOverride`,
`[InputSetting]`, `[CustomButton]`, `[Skin]` user skins, the Plex client id.

### Appearance, skin pairing, icon choice
(`Appearance.swift`, `IconChoice.swift`, pure Core logic with tests.)
- `AppearanceSetting` is `system` (default) / `light` / `dark`. `SkinPairing` names a light skin and a dark skin by
  id (default Silver / Black; any skin in either slot). `SkinResolver.resolve(appearance:systemIsDark:pairing:skins:)`
  returns the skin; a missing id falls back to Silver (light) or Black (dark).
- `SettingsStore.skin` is that resolver applied to `appearance`, `systemIsDark` (not persisted) and the pairing.
  The app side (`Views/ThemeSync.swift`, `followsTheme()`) sets `preferredColorScheme` from the appearance setting
  (nil for System) and writes the SwiftUI `colorScheme` into `systemIsDark`. An explicit Light/Dark ignores
  `systemIsDark`. Migration: the old single `skinID` key becomes both slots on first read, then is removed.
- `IconChoice` is `.default` or `.model(id)`; `AppIcons.availableModelIcons` lists models whose artwork exists
  (an unavailable stored choice resolves to the default) and `AppIcons.suggestion` offers the connected amp's icon
  only if it exists and is not already chosen. `App/AppIconApplier.swift` applies it: iOS calls
  `setAlternateIconName` only when the name differs and keeps a failure for Settings; macOS sets
  `NSApp.applicationIconImage` from `DockIcon-<Default|MODEL>-<Light|Dark>` and re-applies on KVO of
  `NSApp.effectiveAppearance` and on choice/appearance changes. The Finder and Dock show the default icon when the
  Mac app is not running. Icon art: `scripts/make_icon.py` (see README "Icons", including how to add a model).

### Data, not code
Per the project rule "one small interface, variations as data":

| Variation | Data type | Where a new one goes |
|---|---|---|
| Amp model | `AmpModel` (HegelKit: names, aliases, inputs) + `ModelCapabilities` (app: controls, volume range, support level, notes) | one row in each table |
| Skin | `Skin` (Codable: colours, readout font, volume control) | a JSON file / pasted JSON; built-ins are the same type |
| Model icon | `MODELS` in `make_icon.py`, `AppIcons.availableModelIcons`, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` | one entry in each (README "Icons") |
| Input | `InputSetting` (rename, enable, playback target) merged by `InputCatalog` | settings UI |
| Playback target | `PlaybackTarget` enum case + one `PlaybackDriver` | one case + one driver, `PlaybackDrivers.make` |
| Custom button | `CustomButton { label, [ButtonAction] }`, `ButtonAction = amp(AmpAction) | http(HTTPRequestSpec)` | settings editor |

Only the H590 is `verified`; the other models are listed as `untested` in the picker (same five IP commands per
Hegel's sheet, never tried on a unit). Adding real support for one is a change to `ModelCapabilities.all`.

### Playback (`Sources/HegelRemoteCore/Playback/`)
The Hegel IP protocol has **no transport commands**: every letter a-z was probed with `-<x>.?` on the real amp
(2026-11-16); only `p i v m r` answer, everything else returns `-e.2`. So Prev / Play-Pause / Next go to whatever
feeds the current input, via a per-input `PlaybackTarget` and a driver per kind:

- `PlexampDriver`: Plex Companion player API, `GET http://<host>:32500/player/playback/{playPause|skipNext|skipPrevious}?type=music&commandID=n`,
  state from `/player/timeline/poll?wait=0&type=music&commandID=n`. The timeline endpoint was verified read-only
  against the owner's Plexamp headless; the command endpoints and the `X-Plex-*` headers are unverified on the
  real player (tested against a fake HTTP server only).
- `MacMediaKeysDriver` (macOS only): posts system media-key events; drives whatever owns Now Playing. No state.
- `UnavailablePlaybackDriver`: the "none" case; carries the one-line reason the UI shows.

### Siri / Shortcuts (`App/Intents/`)
App Intents (no SiriKit entitlement). Each intent calls `IntentSupport.perform(AmpAction)`, which opens a short
`AmpSession` (connect, no keepalive, no auto-reconnect), sends, waits for the amp's confirming broadcast, and
returns the sentence Siri speaks ("Volume is 41."). They work with the UI closed because App Intents launch the
app in the background. `AmpInputEntity` exposes the enabled inputs under the user's names, so "switch the amp to
Pontus" resolves to input 1. An `Int` parameter cannot appear in an App Shortcut phrase, so "set the amp volume"
asks for the number.

### Fonts
Doto (SIL OFL 1.1, licence file beside it) is registered at launch with `CTFontManagerRegisterFontsForURL` on
both platforms, so there are no `UIAppFonts` / `ATSApplicationFontsPath` keys to keep in sync. If the family is
unavailable the readout uses the system monospaced font.

## Testing
- `swift test`: HegelKit (30 tests, incl. the `FakeAmp` emulator with the back-to-back-drop quirk) plus
  `HegelRemoteCoreTests` (59 tests): controller, intent path and custom buttons against `FakeAmp` on loopback
  (real sockets, real pacing); Plexamp driver and HTTP actions against `FakeHTTPServer`; skins, catalog, wheel
  math, readout and settings are pure.
- `xcodebuild test -scheme HegelRemoteMac -destination 'platform=macOS'` and
  `xcodebuild test -scheme HegelRemote -destination 'platform=iOS Simulator,...'` run the same Core tests as
  **non-hosted** bundles (no app launch involved). On the development Mac the simulator's xctest runner hangs
  before connecting under Xcode 26.6 for every project, hello-world included; the Mac destination works. Keeping
  the logic in a package target is what makes the tests independent of that.
- Interactive: `swift run fakeamp` is an H590 on 127.0.0.1:50001; the simulator shares the Mac's loopback.
  The real amp is never driven by tests or by development runs.

## What the amp cannot do over the network (so the app does not pretend)
- **DAC-Loop on/off**: set only in the device menu with the RC8 remote; the a-z probe found no IP command. Not
  offered as an amp action. A custom button's HTTP action can reach an IR blaster or a Home Assistant webhook
  later; the `ButtonAction` enum is open for an IR action kind.
- Sleep timer, home-theatre mode, startup volume, max volume: not reachable over IP either.
- **Future "amp settings" feature**: the H590 serves a web configuration page on port 80 (`/index.asp`, no
  auth) with forms for the device name (`/goform/HandleDeviceName`), network settings
  (`/goform/ProfileSettingHandler`) and firmware update (`/goform/UpgradeDevice`). Nothing in the app uses it yet;
  a settings screen could drive those three endpoints. Everything else stays front-panel only.

## Later stages (not blocked by this layout)
- Docker web app on Linux: reuse `HegelProtocol` (builds on Linux) and port `AmpClient` to a POSIX socket.
- Widgets / Watch: `AmpController` and `SettingsStore` have no SwiftUI dependency; a widget would need App Groups
  (paid account) to share UserDefaults, or its own `AmpSession` calls.
- Skin files: `Skin.decode(json:)` is the whole contract; `SettingsStore.userSkins` already stores decoded skins.
