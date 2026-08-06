# AwesomeWotlk — worldapi flavor (temporarily hosted here)

This directory vendors [FrostAtom/awesome_wotlk](https://github.com/FrostAtom/awesome_wotlk)
(GPLv3) at upstream commit `3cbae1e3f7dc0a676b9391d7b6c2a09c33e02ef8`, plus one
addition: **WorldAPI** (`src/AwesomeWotlkLib/WorldAPI.cpp/h`), exporting to Lua

    UnitPosition("unit")   -> x, y, z          (world yards)
    WorldToScreen(x, y, z) -> sx, sy, visible  (UI space, origin bottom-left;
                                                visible is 1/nil; coords are
                                                returned even when not visible
                                                so markers can edge-clamp)

Both wrap functions the client already contains and upstream had already
reverse-engineered (`WorldFrame_3Dto2D` @ 0x004F6D20, unit vtable
`GetPosition`) but never exposed. Purpose: in-world waypoint markers for
pfQuest-Reforged / GW2_UI Reforged — the piece of the SuperWoW-style
Waypoint-UI concept that pure Lua cannot do on 3.3.5a.

## Why is a C++ project inside the pfQuest repo?

Temporary hosting, nothing more. The session that produced this had no
permission to create repos or forks. The change also exists as a proper git
branch on upstream's full history (`worldapi`, one commit), ready to transplant.

**Migration plan:** fork FrostAtom/awesome_wotlk on GitHub -> push the
`worldapi` branch there -> delete this branch -> offer the two exports upstream
as a suggestion (their README invites them).

## Building

`.github/workflows/build-worldapi.yml` on this branch builds it (MSVC, Win32 —
the 12340 client is 32-bit) and uploads the DLL + patcher as a 14-day artifact
on every push to this branch. No local toolchain needed.

Omitted from upstream: `docs/assets/wow_soft.jpg` (binary screenshot, not
needed to build) and upstream's absent CI (this branch carries its own).

## License

GPLv3, same as upstream (LICENSE included). All modifications GPL.
