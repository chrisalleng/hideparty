# hideparty (fishing-aware fork)

A fork of the [Ashita v4](https://www.ashitaxi.com/) `hideparty` addon by
**atom0s** / the Ashita Development Team, which lives in
[AshitaXI/Addons](https://github.com/AshitaXI/Addons) under `addons/hideparty`.
Upstream is a monorepo of every stock addon, so this is a standalone copy rather
than a GitHub fork; the first commit here is the unmodified upstream file, so
the changes below show up as a clean diff against it.

## Why

`hideparty` doesn't hide a window as such — it flips two visibility bytes on
four of the game's UI primitive objects: the main party frame, two alliance
frames, and the target frame. It re-applies that every frame in `d3d_present`.

The fishing mini-game draws its **stamina bar** inside the main party frame's
primitive, so hiding your frames also hides the stamina bar and leaves you
reeling blind. That's a problem if you run a replacement UI such as HXUI or
XIUI and keep the stock frames hidden permanently.

## What this fork changes

The addon now tracks whether the fishing mini-game is running and temporarily
restores the affected frame for its duration. Everything else about the addon —
the existing commands, the signature scans, the visibility writes — is
untouched.

Fishing state is read from packets rather than chat text, so it isn't
localisation-dependent:

| Signal | Meaning |
| --- | --- |
| outgoing `0x01A`, `uint16` @ `0x0A` == `14` | Cast Fishing Rod — session started |
| incoming `0x037`, `uint8` @ `0x30` | The server's own fishing flag: `0` = not fishing |
| outgoing `0x110`, `uint16` @ `0x0E` == `4` | Gave up / ended |
| incoming `0x00A` / `0x00B`, outgoing `0x0E7` | Zoned or logged out |

Because `0x037` both sets and clears the flag, the addon mirrors the server and
cannot get stuck showing frames if a start or end packet is missed.

## Commands

Everything upstream supports, plus:

| Command | Description |
| --- | --- |
| `/hideparty fishing` | Show the current mode. |
| `/hideparty fishing party0` | Restore the main party frame while fishing. **(default)** |
| `/hideparty fishing party1` | Restore the first alliance frame. |
| `/hideparty fishing party2` | Restore the second alliance frame. |
| `/hideparty fishing party` | Restore the party and both alliance frames. |
| `/hideparty fishing target` | Restore the target frame. |
| `/hideparty fishing all` | Restore every frame the addon hides. |
| `/hideparty fishing off` | Upstream behaviour; restore nothing while fishing. |

The mode is saved per character under
`config/addons/hideparty/<Character_ID>/settings.lua`.

`party0` is the default because the stamina bar was confirmed in-game to live
in the main party frame. The other modes are kept so the behaviour can be
adjusted without editing the addon.

## Installation

Clone straight into your Ashita `addons` directory:

```
git clone https://github.com/chrisalleng/hideparty.git addons/hideparty
```

This replaces the stock `hideparty` that ships with Ashita, so back up or remove
the existing `addons/hideparty` directory first. Load it the usual way:

```
/addon load hideparty
```

## Credits

Original addon by **atom0s** and the Ashita Development Team. Fishing-mini-game
detection follows the approach already used by the HorizonXI `fishaid` and
`hxifish` addons.

## License

GPL-3.0-or-later, matching upstream. See [LICENSE](LICENSE).
