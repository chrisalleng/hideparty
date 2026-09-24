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

Detection is a direct read of the local player's **entity status** each frame,
which is the same value the client itself uses to decide what you're doing. No
packet tracking, no chat-text matching, so it can't drift out of sync, isn't
localisation-dependent, and can't get stuck showing frames.

`FFXiMain.dll` holds a 16-byte-per-entry table of status names indexed by that
status value. The fishing entries are:

| Status | Name | Meaning |
| --- | --- | --- |
| 6 | `(FISHING)` | Rod cast, line in the water |
| 38–43 | `(FISHING1)`–`(FISHING6)` | Mini-game reeling states |
| 50, 56 | `(FISH_2)`, `(FISH_3)` | Catch / result states |
| 51–53 | `(FISHF)`, `(FISHR)`, `(FISHL)` | Directional reeling states |
| 57–62 | `(FISH_31)`–`(FISH_36)` | Catch / result states |

The table decode is corroborated by the known ids sitting in it: `1 (B_IDLE)` is
engaged, `33 (CAMP)` is resting, and `85 (MOUNT)` is mounted.

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
