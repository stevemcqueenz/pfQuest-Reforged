# HorizonCompass — design record and stage 2 specification

Stage 1 (shipped on `dev`) deliberately renders ONE marker: the route arrow's
current target. That narrowness is the de-risking strategy — the projection math
and the strip's feel must survive one in-game session before the marker taxonomy
multiplies on top of it. This file records the full design so stage 2 is built
to a spec, not improvised.

## Edge cases stage 1 already handles (each is a shipped-bug lesson)

| Case | Behavior |
|---|---|
| On a taxi | strip hides entirely (facing is garbage on flight paths — the arrow shipped that bug) |
| Indoors / instances (`GetPlayerMapPosition` = 0,0) | markers hide, cardinals stay (facing still works) |
| Zone without dimension data | distance label HIDES — never fabricated from a guess |
| Target behind the player (outside 180° FOV) | marker clamps to the strip edge at 40% alpha as a turn hint |
| Feature disabled / mid-session toggle | OnUpdate lives on a separate always-shown driver, so hiding the strip can never strand the loop that re-shows it |
| Width option changed | applied live via a config dirty-check inside the perf cap — no /reload |
| Metric option changed | display-time conversion only (yd × 0.9144); internals stay yards so no consumer can be unit-poisoned |
| Perf | arrow-identical 0.02s cap + facing/pos/target dirty-skip; zero steady-path allocations; strings re-format only on rounded-value change |

## Stage 2: the marker taxonomy (data source per type — all already shipped)

Reuse pfQuest's map-dot textures (`img/available.tga`, `complete.tga`, cluster
and faction icons) so the strip speaks the visual language users already know
from the map. No new art.

| Marker | Source | Notes |
|---|---|---|
| Quest available (!) | pfMap nodes, `available` texture, layer ≤ 2 | gray/red tint when `qmin` > player level (too high to take) — `GetQuestDifficultyColor` exists natively |
| Active objective | pfMap nodes for questlog quests | the current stage-1 behavior, kept |
| Turn-in ready (?) | node `complete`/`complete_c` texture | highest priority after the explicit arrow target |
| Waypoint | the route arrow target | explicit user intent — always labeled |
| Dungeon entrance | pfQuest `meta` DB (instance portals) | off by default; it is ambient info |
| Daily / event quest | `isDaily` (GetQuestLogTitle slot 8, guarded — AzerothCore backport) + our `quests-eventtags335.lua` overlay | small badge overlay on the base marker, not a distinct marker |
| **Corpse** | `GetCorpseMapPosition()` — **verified present on 3.3.5a** + `UnitIsDeadOrGhost("player")` | shown ONLY while dead/ghost; highest priority of all (nothing else matters mid-corpse-run) |

## Label policy (the "when to show more info" question)

The mock shows the right answer: exactly ONE marker carries text at a time.
- Priority: corpse (when dead) > explicit waypoint/arrow target > turn-in ready
  > nearest active objective > nearest available.
- The top-priority marker gets title + distance above the strip; everything else
  is icon-only. Two labels minimum-distance apart is unreadable at strip scale.
- Cap: 8 visible markers, nearest-first within priority class; overflow drops
  the lowest class first. `log()`-style honesty: no indicator pretends to show
  everything.
- No hover interactions on stage 2: the strip sits in screen-top space where a
  mouse-enabled frame would eat camera drags. Revisit only if users ask.

## Units

`compassmetric` config ("Compass Bar: Metric Distances (meters)"), default off
(yards — WoW's native unit). Conversion at display time only.

## Explicitly out of scope (and why)

- Group-member markers: party positions come from map-percent only in the same
  zone; cross-zone is noise. Revisit with real demand.
- In-world pins: separate feature on the WorldAPI DLL (`WorldToScreen`) — the
  compass strip must stay fully functional WITHOUT any DLL. The strip is the
  degrade path, so it can never depend on the thing it degrades from.
- Minimap-style tracking (herbs/ores): pfQuest tracks these as map nodes
  already; projecting resource nodes onto the strip is clutter with no
  navigation value — they are area-search targets, not destinations.

## Verification model for stage 2

Every marker provider gets a compasscheck335 block: synthetic node table in,
expected marker set out (type, priority, clamped state). The corpse provider is
drivable headless (fake `GetCorpseMapPosition`/`UnitIsDeadOrGhost`). Label
policy is pure (list in, chosen-one out) — pin it numerically. Visuals stay
in-game QA, as ever.
