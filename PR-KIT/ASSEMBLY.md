# Upstream PR assembly (run when the maintainer is ready, ~14 days out)

Everything needed to open the WorldAPI PR against noname08662/awesome_wotlk.
The module source lives in THIS branch under awesome_wotlk/src/AwesomeWotlkLib/
(WorldAPI.cpp, WorldAPI.h) with its Entry.cpp and CMakeLists.txt wiring.

## Steps

1. Maintainer forks noname08662/awesome_wotlk on GitHub (one click, their
   account). Everything below can be driven by a session with push access to
   that fork.
2. Clone the fork, branch `worldapi` off upstream `main` (NOT off v37: PRs
   target the moving tip; the module compiled green against v37 and the
   touched surfaces rarely move, but re-verify the three integration points
   still apply cleanly).
3. Copy from THIS branch into the fork:
   - awesome_wotlk/src/AwesomeWotlkLib/WorldAPI.cpp -> src/AwesomeWotlkLib/WorldAPI.cpp
   - awesome_wotlk/src/AwesomeWotlkLib/WorldAPI.h   -> src/AwesomeWotlkLib/WorldAPI.h
   - Re-apply the wiring by hand (do not copy whole files, upstream may have
     moved): CMakeLists source list gains "WorldAPI.h" "WorldAPI.cpp" after
     the UnitAPI line; Entry.cpp gains #include "WorldAPI.h" after the
     UnitAPI include and WorldAPI::initialize(); after UnitAPI::initialize().
4. Append PR-KIT/api_reference_addition.md content to docs/api_reference.md
   (new "World" section) and add "[World](#world)" to the nav line at the top.
5. ONE commit, message = PR-KIT/COMMIT-MESSAGE.txt verbatim, author = the
   maintainer's own git identity. Per maintainer direction, NO co-author or
   tool attribution lines in this upstream commit or PR.
6. Push, open the PR with PR-KIT/PR-BODY.md as the body; replace the
   SCREENSHOTS_HERE line with the test screenshots (shopping list below).
7. If CI on the fork exists, let it run before submitting; otherwise note the
   green v37 CI run from this repo's build-worldapi.yml history in a comment
   if asked.

## Screenshot shopping list (taken during the maintainer's test pass)

1. Waypoint pylon with beam over a quest area, daylight
2. Pinpoint state up close: boxed objective text, descending chevrons
3. Off-screen navigator chevron orbiting screen center
4. Party member pin inside a dungeon, ideally the dead-member beam
   (the screenshot no map addon can take; sells UnitPosition alone)
5. Optional: /way mail pylon on a mailbox (non-quest use)

## Open item to resolve in the PR conversation

The UnitPosition naming question (retail collision) is asked in the body;
if upstream prefers UnitWorldPosition, rename in WorldAPI.cpp (one luaL_Reg
entry) and in the docs addition, and pfQuest-Reforged's feature detection
gains the alias check (pins.lua feature detect + README-WORLDAPI.md).
