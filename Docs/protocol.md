# Hegel IP control protocol, as implemented by HegelKit

Sources:
- **[A]** Hegel "IP Control Codes", H95/H120/H190/H390/H590, 2024-04-30.
- **[B]** Hegel H590 control sheet, 2018-11-12.
- **[L]** Observed live on a real H590, 2026-11-16 (read-only queries).

## Wire format [A]
- TCP port **50001**, plain ASCII.
- Packet = `-<cmd>.<param>\r`. Terminator is CR only, no LF. Example: `-v.50\r` sets volume to 50 %.
- A packet preceded by `\n` is rejected with `-e.1` [L]. HegelKit never sends LF and the framer ignores stray LF/whitespace on input.

## Commands [A]
| cmd | meaning | params |
|---|---|---|
| `p` | power | `1` on, `0` off, `t` toggle, `?` status |
| `i` | input | `1`..N set, `?` status |
| `v` | volume | `0`-`100` percent, `u` / `d` step, `?` status |
| `m` | mute | `1` / `0`, `t` toggle, `?` status |
| `r` | reset-connection timer | `0`-`255` minutes, `~` stop, `?` status |

Hegel recommends `-r.3` every 2 minutes so the amp drops a dead connection. `AmpClient` does this by default
(`AmpClientConfiguration.keepaliveInterval = 120`, `keepaliveMinutes = 3`; set the interval to nil to disable).

## Replies [A][L]
- Same shape: `-p.1\r`, `-i.12\r`, `-v.33\r`, `-m.0\r`, `-r.~\r`.
- Invalid packet: `-e.<n>\r` (observed `-e.1\r`).
- **State replies are broadcast to every open connection** [L]: a client receives packets it did not ask for (front panel,
  other apps, other clients' queries). HegelKit treats incoming packets as a state stream, never as request/response pairs.
- Replies can arrive concatenated in one read, e.g. `-p.1\r-i.12\r-v.33\r-m.0\r` [L]; the framer handles any split.
- The amp accepts several simultaneous TCP clients [L].
- It answers on TCP while powered off (`-p.0`), and `-p.1` wakes it [L].
- Volume rounds when a max-volume limit is set (send 96, it may reply 97): always trust the reply [L].

## Sending too fast [L, found while building HegelKit]
Packets sent back to back are mostly dropped. On the H590, four queries in one write got one answer (`-p.1`); in four
separate writes with no gap, two answers; with 50 ms between writes, all four. `AmpClient` therefore spaces writes by
`minSendInterval` (default 100 ms). Any other client of this protocol should do the same.

## Inputs (number to name)
One table, `AmpModel.all` (Sources/HegelProtocol/AmpModel.swift); a new model is one entry. [A] unless noted.
- **H590**: 1 XLR 1, 2 XLR 2, 3 Analog 1, 4 Analog 2, 5 Analog 3, 6 BNC, 7 Coaxial, 8 Optical 1, 9 Optical 2, 10 Optical 3,
  11 USB, 12 Network. *Inferred*: the 2018 sheet [B] says inputs 1-12 and the manual lists 3 RCA inputs; the 2024 sheet [A]
  lists 11 and omits Analog 3, likely an error. Input 12 = Network matches the live amp [L].
- **H390**: 1 XLR, 2 Analog 1, 3 Analog 2, 4 BNC, 5 Coaxial, 6 Optical 1, 7 Optical 2, 8 Optical 3, 9 USB, 10 Network.
- **H190** (H120 identical): 1 Balanced, 2 Analog 1, 3 Analog 2, 4 Coaxial, 5 Optical 1, 6 Optical 2, 7 Optical 3, 8 USB, 9 Network.
- **H95**: 1 Analog 1, 2 Analog 2, 3 Coaxial, 4 Optical 1, 5 Optical 2, 6 Optical 3, 7 USB, 8 Network.
- **Röst**: matched by name for discovery; no input table in our sources.

## Discovery [L]
The H590 advertises `_raop._tcp` as `D8F710D3E204@H590` and `_airplay._tcp` as `H590`. `HegelDiscovery` browses both,
matches the name against `AmpModel.aliases`, resolves an IPv4 address, then confirms by connecting to 50001 and getting a
`-p.` reply. A name match alone never yields a result.

## Not verified
- The exact reply to a `-r.<n>` set (FakeAmp echoes it; the real amp was only queried read-only, and the keepalive
  was never sent to it during development except by the unit-test fake).
- Behaviour of H95/H120/H190/H390 (tables from the sheet only).
- The Linux build of `HegelProtocol` was verified in `swift:6.1` Docker (build + its 15 tests); HegelClient,
  HegelDiscovery and hegelctl are Apple-only (Network.framework) and are not declared on Linux.
