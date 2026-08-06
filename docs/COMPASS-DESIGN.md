# HorizonCompass — design record and stage 2 specification

Stage 1 (shipped on `dev`) deliberately renders ONE marker: the route arrow's
current target. That narrowness is the de-risking strategy — the projection math
and the strip's feel must survive one in-game session before the marker taxonomy
multiplies on top of it. This file records the full design so stage 2 is built
to a spec, not improvised.

**Stage 2 status (shipped on `dev`, in-game QA pending):** the full marker
taxonomy below (corpse, route target, turn-ins, active objectives, available
with difficulty tint, dungeon entrances via meta-DB meeting stones, daily/event
badge), the diamond-plate housing with the ~115% owner cue, the view-driven
label policy with hysteresis + crossfade + edge clamp, the objective
description line (layout preference b), and the stage-2 settings inventory
(`compassscale`, `compassavail`, `compassturnin`, `compassdungeon`,
`compassdesc`, `compasscap`). Every numeric behavior is pinned in
`tools/compasscheck335.lua`; visuals and feel stay in-game QA, as ever.

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
from the map.

**Marker housing (maintainer direction):** the type icon never floats alone on
the strip -- it sits inside a diamond PLATE so markers feel like they belong to
the compass. The plate is two generated layers (`img/marker_fill.tga` +
`img/marker_edge.tga`, tools/gen_marker_assets.py): both WHITE, vertex-tinted at
runtime -- fill takes the theme bg, edge takes the theme ACCENT. Because
pfQuestTheme already switches accent by context (teal standalone, parchment gold
when GW2_UI is loaded), one asset set renders the GW2 identity automatically
without pfQuest ever depending on GW2_UI's texture files (charter: standalone).
NOT a copy of Waypoint-UI's visuals -- only the containment idea. The labeled
(view-selected) marker's plate can scale up slightly (~115%) as the selection
cue, replacing any need for a highlight texture.

| Marker | Source | Notes |
|---|---|---|
| Quest available (!) | pfMap nodes, `available` texture, layer ≤ 2 | gray/red tint when `qmin` > player level (too high to take) — `GetQuestDifficultyColor` exists natively |
| Active objective | pfMap nodes for questlog quests | the current stage-1 behavior, kept |
| Turn-in ready (?) | node `complete`/`complete_c` texture | highest priority after the explicit arrow target |
| Route target | `route.lua`'s single current destination: the user's MANUAL pick (Navigate with arrow / browser or map click, `SetTarget`) or, absent one, the router's AUTOMATIC nearest objective across the (auto-tracked) quest log | the guidance anchor -- this is stage 1's only marker, kept as the fallback label owner |
| Dungeon entrance | pfQuest `meta` DB (instance portals) | off by default; it is ambient info |
| Daily / event quest | `isDaily` (GetQuestLogTitle slot 8, guarded — AzerothCore backport) + our `quests-eventtags335.lua` overlay | small badge overlay on the base marker, not a distinct marker |
| **Corpse** | `GetCorpseMapPosition()` — **verified present on 3.3.5a** + `UnitIsDeadOrGhost("player")` | shown ONLY while dead/ghost; highest priority of all (nothing else matters mid-corpse-run) |

## Objective kind (kill vs collect vs interact) — already encoded

Every pfQuest node carries its minimap texture: `cluster_mob` (kill),
`cluster_item` (collect), `cluster_misc` (interact), each with a mono variant.
The compass marker mirrors `node.texture` -- same icon language as the minimap,
no new classification logic anywhere.

## Objective text — already generated

`pfDatabase:BuildQuestDescription()` produces the per-QTYPE "what to do" line
("Speak with X to obtain [!] Quest", kill/collect progress forms) and is
precomputed onto every node as `meta.description`; the route arrow displays
exactly this (route.lua:628-634). The compass consumes the same field for the
top-priority marker. OPEN LAYOUT DECISION (in-game QA call, stage 2): the
description line lives either (a) as a third line above the marker (tower risk)
or (b) below the strip beside the degree readout -- current preference (b),
plus a `compassdesc` toggle either way.

## Label policy — VIEW-DRIVEN, one label at a time (maintainer's correction)

The mock's label sits on the marker nearest the center needle: the label follows
what the player is FACING, and rotating hands it to whatever marker rotates into
view. The first draft of this spec had it purely priority-driven, which would pin
one label to an edge-clamped icon while the player looks elsewhere -- wrong
default for a compass. The synthesis:

- **Selection**: the marker nearest the center needle within a capture window
  (~ +/-15 degrees) gets the label; ties inside the window break by priority
  (manual route target > turn-in > active > available).
- **Fallback**: when NO marker is inside the window, the ROUTE TARGET keeps its
  label even edge-clamped. Since pfQuest always maintains one route target while
  any quest is logged (manual pick, else auto-nearest objective), the strip is
  NEVER guidance-free: at minimum one clamped, labeled marker at the edge says
  which way to walk -- the same destination the arrow points at.
- **Override**: while dead, the corpse marker owns the label unconditionally.
- **Transitions**: alpha crossfade (~0.2s) when the labeled marker changes.
- **Hysteresis (the thrash hazard)**: two markers straddling the center would
  flicker-fight the label every frame. The incumbent keeps it until a challenger
  is CLEARLY closer to center (>= ~4 degree margin) AND a minimum hold (~0.5s)
  has passed. This is the edge case that makes or breaks the feel; it gets a
  numeric harness block (sequence of facings in, label-owner sequence out).
- Still exactly ONE label at a time; everything else icon-only. Cap 8 visible
  markers, nearest-first within class, lowest class dropped first.
- No hover interactions: the strip sits where a mouse-enabled frame would eat
  camera drags. Revisit only on real demand. Moving the strip (shipped): the
  arrow's shift+drag gesture, but the mouse is enabled ONLY while shift is held
  (MODIFIER_STATE_CHANGED) so the strip stays click-transparent otherwise --
  the wide-frame version of this same constraint. Position persists in
  `compasspos`, restored OnShow, same shape as `arrowpos`/`trackerpos`.

## Settings inventory (stage 2)

Existing: enable (`compass`), width (`compasswidth`, live), metric
(`compassmetric`, live). Added in stage 2, all live where feasible:

| Setting | Default | Notes |
|---|---|---|
| Compass Bar Scale | 1 (0.5-2) | same pattern as the tracker scale |
| Show available quests (!) | on | per-class toggle |
| Show turn-ins (?) | on | per-class toggle |
| Show dungeon entrances | off | ambient info |
| Show objective description | on | the BuildQuestDescription line below the strip |
| Marker cap | 8 (4-12) | text option, clamped |

Deliberately NOT settings: FOV (fixed 180 -- a slider there changes the math
users build muscle memory against), label selection mode (the view-driven
synthesis IS the sane default; a mode knob would just relitigate it).

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
