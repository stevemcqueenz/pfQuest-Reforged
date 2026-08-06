# AwesomeWotlk — worldapi flavor (temporarily hosted here)

This directory vendors [NoM0Re/awesome_wotlk](https://github.com/NoM0Re/awesome_wotlk)
(GPLv3 — the actively maintained fork of FrostAtom/awesome_wotlk that this
community's DLL line comes from; it carries the VoiceChat module and fixes the
origin repo lacks) at fork commit `1442992`, plus one addition: **WorldAPI**
(`src/AwesomeWotlkLib/WorldAPI.cpp/h`), exporting to Lua

    UnitPosition("unit")   -> x, y, z          (world yards)
    WorldToScreen(x, y, z) -> sx, sy, visible  (UI space, origin bottom-left;
                                                visible is 1/nil; coords are
                                                returned even when not visible
                                                so markers can edge-clamp)

Both wrap functions the client already contains and the repo had already
reverse-engineered (`WorldFrame_3Dto2D` @ 0x004F6D20, unit vtable
`GetPosition`) but never exposed. Purpose: in-world waypoint markers
(Skyrim-style pins) for pfQuest-Reforged / GW2_UI Reforged — the piece of the
SuperWoW-style Waypoint-UI concept that pure Lua cannot do on 3.3.5a.

The module is byte-identical against FrostAtom or NoM0Re (GameClient.h is
unchanged between them) and first compiled green on MSVC/Win32 (CI run #1)
against the FrostAtom base before being rebased onto this one.

Version-global gotcha: both repos push `AwesomeWotlk = 1` as the Lua global;
the "r37"-style numbers users know are RELEASE numbering. Addon-side feature
detection must therefore use `type(WorldToScreen) == "function"`, never the
version global.

## Why is a C++ project inside the pfQuest repo?

Temporary hosting, nothing more. The session that produced this had no
permission to create repos or forks, and the maintainer was on a phone.

**Migration plan:** fork NoM0Re/awesome_wotlk on GitHub -> apply the WorldAPI
change there (2 new files + 2-line Entry.cpp + 1-line CMakeLists edit) ->
delete this branch -> offer the two exports upstream as a suggestion.

## Building

`.github/workflows/build-worldapi.yml` on this branch builds it (MSVC, Win32 —
the 12340 client is 32-bit) and uploads the DLL + patcher as a 14-day artifact
on every push to this branch. No local toolchain needed. The fork's own
`windows-release.yml` sits inert inside this subdirectory (workflows only run
from the repo root).

Omitted from the fork's tree: `docs/assets/wow_soft.jpg` (binary screenshot,
not needed to build).

## License

GPLv3, same as upstream (LICENSE included). All modifications GPL.
