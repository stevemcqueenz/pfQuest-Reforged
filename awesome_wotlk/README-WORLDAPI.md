# WorldAPI flavor of AwesomeWotLK

**Base: [noname08662/awesome_wotlk](https://github.com/noname08662/awesome_wotlk) @ v37**
(the actively maintained community line; lineage FrostAtom -> someweirdhuman ->
noname08662), verbatim, plus one added module. v37 is the exact release the
maintainer runs, so swapping in this build loses nothing the installed r37 has
-- interact keybinding, MSDF fonts, camera/nameplate work, all of it.

Why the base moved (third time, final): the first vendoring used
FrostAtom/awesome_wotlk (the original, long stale), the second NoM0Re's fork of
it -- both predate the community line's feature growth, and field testing
caught it immediately: the Interact keybinding vanished from the keybinds UI
because that whole feature only exists in the someweirdhuman/noname08662 line
(introduced around its v25: "move keybinds (now only /interact) to c level").
Building on the line users actually run is the only swap that is a pure
superset.

## The added module: WorldAPI.cpp/h

Two Lua globals, exposing projection machinery the client already has
(GameClient.h maps `CGWorldFrame::To2D` @ 0x004F6D20) but never exported:

    UnitPosition("unit")  -> x, y, z          world yards
    WorldToScreen(x,y,z)  -> sx, sy, visible  UI space, origin bottom-left

`visible` is `1`/`nil` (kept from the first WorldAPI builds; reads the same as
a boolean in `if visible then`). Coordinates are still returned when not
visible so callers can edge-clamp (off-screen navigator arrows).

Integration is deliberately tiny: 2 new files + 1 line in
`src/AwesomeWotlkLib/CMakeLists.txt` + 2 lines in `Entry.cpp`
(include + `WorldAPI::initialize()`).

## Version detection (addon side)

Every lineage pushes `AwesomeWotlk = 1` as the version global; the r/v numbers
are RELEASE naming, not queryable. Addons must feature-detect:
`type(WorldToScreen) == "function"` -- never sniff versions.

## Install

Drop-in for an existing v37/r37 install: replace `AwesomeWotlkLib.dll` with the
built one (rename the old one `.bak` first). No re-patch needed; `skia.dll`
and the rest are unchanged from the v37 release (the CI artifact includes them
anyway for a from-scratch install: run `AwesomeWotlkPatch.exe` on a clean
`Wow.exe` copy in that case).

## Purpose

The client-side half of in-world waypoint markers for pfQuest-Reforged /
GW2_UI -- the piece pure Lua cannot do on 3.3.5a. The addon degrades to the
compass strip / arrow when the exports are absent.

## Migration plan

This branch is temporary hosting (the driving session cannot create forks).
Proper home: a fork of noname08662/awesome_wotlk carrying the `worldapi`
branch, and ideally an upstream PR -- the module is small, self-contained and
GPLv3 like its base.
