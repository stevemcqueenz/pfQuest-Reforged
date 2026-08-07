# WorldAPI: expose the client's own world-to-screen projection to Lua (UnitPosition + WorldToScreen)

### What this adds

A small optional module (`src/AwesomeWotlkLib/WorldAPI.cpp/h`) exposing two Lua globals:

```
UnitPosition("unit")      -> x, y, z          world coordinates in yards, or nothing if the token does not resolve
WorldToScreen(x, y, z)    -> sx, sy, visible  screen position; visible is 1 when the point is inside the camera view, nil otherwise
```

The projection machinery is already reverse engineered in GameClient.h (`CGWorldFrame::To2D` at 0x004F6D20 and `PercToScreenPos`), it was just never exported to addons. This module only wires it up. `UnitPosition` resolves tokens through the same ObjectMgr path UnitAPI already uses.

### Why

This is the one capability that makes in-world UI possible on 3.3.5a: waypoint pylons at quest locations, off-screen direction indicators, marking a dead party member's body in a dungeon (`UnitPosition` reads the object manager, so it keeps working indoors where the map APIs return nothing). None of this can be done in pure Lua.

I built and field tested a full addon-side system on top of it in [pfQuest-Reforged](https://github.com/stevemcqueenz/pfQuest-Reforged) as proof: light-beam pylons with distance and ETA, a near-range pinpoint with objective text, an orbiting off-screen navigator, and party member pins inside instances. The screenshots below show what it enables.

SCREENSHOTS_HERE

### Design notes

- Tiny, additive footprint: two new files, one line in CMakeLists.txt, two lines in Entry.cpp. Registration uses the same `Hooks::FrameXML::registerLuaLib` pattern as UnitAPI. No new detours, no hooks, no behavior change for anyone not calling the functions, zero cost when unused.
- `visible` returns `1`/`nil` rather than a boolean, matching the client's own convention for such returns.
- Coordinates are still returned when `visible` is nil, so addons can clamp off-screen targets to the screen edge or drive direction indicators.
- `sx, sy` are in the `PercToScreenPos` UI space (origin bottom-left on a 1024x768 percent base); converting to UIParent coordinates addon-side is one multiply and confirmed correct in play.
- Addon authors should feature-detect with `type(WorldToScreen) == "function"` since the `AwesomeWotlk` version global does not carry release numbers.

### One naming question for you

Retail has a `UnitPosition` with different semantics (returns y, x, z, instance and only for group members). If you would rather avoid the name collision for future-proofing, I am happy to rename to `UnitWorldPosition` or anything you prefer before merge. `WorldToScreen` seems uncontested.

### Verification

Compiles clean on MSVC Win32 against v37 (CI in my fork), field tested on a live 3.3.5a client (build 12340): `UnitPosition("player")` plus `WorldToScreen` on the result returns correct screen coordinates at default and scaled UI settings. A documentation addition for `docs/api_reference.md` is included in this PR. Licensed GPLv3 like the rest of the project.

Happy to adjust anything to fit the project's conventions. Thanks for maintaining this line, it is what my whole community runs on.
