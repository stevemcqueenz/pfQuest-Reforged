# In-world waypoint pins — design record (the WorldAPI DLL tier)

Companion to COMPASS-DESIGN.md. This tier renders markers AT world positions
(Waypoint-UI-class); it requires the WorldAPI DLL exports (`WorldToScreen`,
`UnitPosition`) and feature-detects them -- the compass strip is the degrade
path and never depends on this.

Design distilled from maintainer-supplied screenshots of Waypoint-UI (five
states + its settings panels). Behavior observation only -- clean-room per the
porting rules; no license is visible on that project, so its code and assets
are untouchable regardless.

## The three-element model (the key insight from the screenshots)

Waypoint-UI is not one marker. It is three cooperating elements, switched by
distance and visibility:

1. **Waypoint** (far, on-screen): a diamond icon with a vertical light BEAM
   into the sky at the target position -- visible across a whole zone. Below
   it: info text with DISTANCE and an ETA ("330 yds / 30s"). Distance-based
   scaling: base size, clamped by a minimum % (at max distance) and maximum %
   (at min distance).
2. **Pinpoint** (near, on-screen): when close, the beam/diamond hands off to a
   small chevron marker at the exact spot, and the info text switches to the
   OBJECTIVE line ("0/1 Vial of Arcane Water"). Separate size setting.
3. **Navigator** (off-screen): when the target is not in the camera frustum, a
   directional indicator orbits the screen center at a configurable radius
   ("Distance"), pointing toward the target. "Dynamic Distance" adjusts that
   radius with viewport zoom.

State machine: far+visible -> Waypoint; near+visible -> Pinpoint;
not visible -> Navigator. `WorldToScreen`'s third return (visible 1/nil) is
exactly the Navigator switch; its coords keep updating while invisible, which
gives the Navigator its direction for free (angle of (sx,sy) from screen
center).

## What maps onto what (all inputs verified present)

| Element need | Our source |
|---|---|
| Target world x,y | route target node percent -> world yards via `pfMap.minimap_sizes` (compass already does this) |
| Target z | stage 1: player's own z from `UnitPosition("player")` (markers sit at eye level); honest limitation, ground-height query is a later DLL addition |
| Screen position + visibility | `WorldToScreen` (DLL, compiled green; screen-space scale calibrated in-game first) |
| Distance | yards, same derivation as the compass |
| **ETA** | distance / current speed -- `GetUnitSpeed` EXISTS on stock 3.3.5a; fall back to measured position delta if a core misreports it. Hide ETA while standing still (speed 0), never show "infinity" |
| Objective text (Pinpoint state) | `meta.description` / `BuildQuestDescription` -- same field as compass and arrow |
| Icon per type | pfQuest node textures, same language as map/compass |

## Settings surface (mirroring what their panel proves users want)

Waypoint: size %, min %, max % (distance scaling clamps), show beam, opacity,
show info text (+ its size/opacity). Pinpoint: size %. Navigator: size,
opacity, orbit distance, dynamic distance. Color override (shipped: the
`pinscolor` pylon color row, see "Visual polish"). Audio cues (set/arrive) --
LOW priority, needs sound assets, park it.

Coverage vs the Waypoint-UI panel is now COMPLETE except two items, each with
a reason: **audio cues** (parked: needs sound assets and a maintainer call on
the sound language) and **dynamic distance** (the navigator orbit radius is a
fixed setting, `pinsnavradius`: a zoom-following radius needs camera-zoom
polling every tick for a subtle effect on a surface that already lets the
user pick the radius directly -- deliberate skip, not an oversight).

Defaults follow their proven values: size 120%, min 50%, max 150%, beam on,
info text on, navigator dynamic distance on. Whole feature off by default and
hidden entirely when `type(WorldToScreen) ~= "function"`.

## Visual identity: GW2 flavor, not a Waypoint-UI copy (maintainer direction)

The screenshots are BEHAVIOR input only. Rendering uses our own language: the
same diamond plate housing as the compass (marker_fill/marker_edge, white art
vertex-tinted by pfQuestTheme -- teal standalone, GW2 gold with GW2_UI loaded),
pfQuest's type icons inside it, flat panels for info text via T.SkinPanel. The
Waypoint/Pinpoint/Navigator all share the housing so the whole tier reads as one
family with the strip.

## Beam on 3.3.5a (no new art)

A 1px-wide vertically-stretched solid texture with vertical alpha gradient via
SetGradientAlpha (native), anchored at the marker, height scaled by distance.
If SetGradientAlpha proves unreliable on this client for untextured solids, a
TGA gradient strip is the fallback -- pow2, trivial.

## Verification model

The state machine (far/near/off-screen transitions, hysteresis at the
near-handoff boundary so the beam and pinpoint do not flicker-swap at the
threshold) is pure logic: harness-drivable with a faked WorldToScreen. ETA
formatting pure. Screen-space rendering is in-game QA, gated first on the
WorldToScreen calibration one-liner.

## Order of operations (unchanged)

1. Compass strip stage-1 verdict in game (projection feel).
2. WorldToScreen calibration one-liner with the DLL artifact.
3. Compass stage 2 (build-to-spec).
4. Pins stage 1: Waypoint + Navigator for the route target only.
5. Pins stage 2: Pinpoint handoff + objective text + full settings.

## Stage 1 status (shipped on `dev`, in-game QA pending)

`pins.lua` implements step 4: Waypoint (diamond plate + gradient beam +
distance/ETA text, distance-scaled between the 50%/150% clamps) and Navigator
(orbiting chevron plate) for the route target only, switched by the
WorldToScreen visible flag through a ~0.25s hysteresis hold. Feature-detected
by `type(WorldToScreen)` -- fully inert (zero frames, settings rows hidden)
without the DLL. Percent->world uses the delta form: pfQuest has zone SIZES
(`pfMap.minimap_sizes`) but no world origins, so the player's own
UnitPosition + GetPlayerMapPosition pair anchors the conversion every tick --
no calibration state, correct immediately (axis pairing pinned by the
db/minimap-wotlk335.lua fit derivation). Settings: `pins` (off), `pinssize`
(100), `pinsbeam` (on). Numeric behavior is pinned in
`tools/pinscheck335.lua` (check.sh gate 6). In-game QA gates: the ToUiCoords
1024x768-base conclusion (one-line fix in `pins.lua` if widescreen drifts)
and the beam's SetGradientAlpha look on untextured solids.

## Stage 2 status (shipped on `dev`, in-game QA pending)

The Pinpoint near-range handoff and the full settings surface. The state
machine is three states now (waypoint / pinpoint / navigator, still pure and
harness-driven): within ~30 yards the Waypoint hands off to the Pinpoint -- a
smaller plate at the exact spot whose text is the OBJECTIVE line
(`meta.description`, the same precomputed field the compass label and the
route arrow print), falling back to the quest/node title and finally to the
distance line, so it is never empty. The handoff carries the stage-1 ~0.25s
hold PLUS a distance hysteresis band (enter below 28 yd, leave above 33 yd, a
Schmitt trigger keyed on the committed mode) so walking along the threshold
cannot flicker-swap; both mechanisms are negative-tested in the harness
(zeroing either one fails its check). New settings, all live and defensively
clamped: `pinsminscale` (50) / `pinsmaxscale` (150) wired into the distance
scaling, `pinsopacity` (100) whole-tier alpha, `pinspointsize` (100),
`pinsnavradius` (140), `pinsnavsize` (100). Rows exist only when the DLL is
present, like stage 1. In-game QA gates unchanged from stage 1, plus the
pinpoint handoff feel at the 28/33 band on a live client.

## Multi-pin exploration (shipped on `dev`, EXPERIMENTAL, in-game QA pending)

`pinsmulti` (off) adds an AMBIENT layer: up to `pinsmulticap` (default 4,
clamped 1..8) extra plates beyond the route target, drawn from the compass
taxonomy via the shared `pfQuest.compass.EachZoneNode` walk -- ready
turn-ins, active objectives and available givers, honoring the compass's
`compassavail`/`compassturnin` toggles. Dungeon entrances are excluded (3D
ambient noise) and the corpse adds nothing (the route target already follows
it while dead). The route target keeps the full waypoint/pinpoint/navigator
treatment; extras are plates only -- no beam text, no state machine, no
navigator (off-screen extras simply hide) -- except a small distance line on
the single nearest extra, and a subordinate beam per extra when
`pinsmultibeam` (on) allows it.

As part of this pass, turn-in markers now show only for READY quests
everywhere in the taxonomy (compass strip and pins alike): pfDatabase paints
the ender `complete_c` once the log quest's complete flag is set and plain
`complete` while objectives are open (database.lua:1666-1675), so
`ClassifyNode` maps only `complete_c` to TURNIN. A kill-quest in progress
shows its objective pylon, not its unfinished turn-in. No config row -- this
is the sane default.

All exploration knobs live in ONE tunables block at the top of `pins.lua`
(exposed as `pfQuest.pins.tunables` for the harness):

| Knob | Default | Meaning |
|---|---|---|
| `MULTI_MAX` | 8 | widget pool ceiling; `pinsmulticap` clamps 1..this |
| `MULTI_RADIUS` | 300 yd | show radius: extras beyond it never render (culled at build AND live) |
| `MULTI_SOLID` | 40 yd | full alpha inside this |
| `MULTI_FLOOR` | 0.35 | alpha floor reached at the show radius (times `pinsopacity`) |
| `MULTI_MERGE` | 28 UI units | screen-space merge radius against the route pin and kept extras |
| `MULTI_BASE` | 20 px | extra plate size (pinpoint-sized; rides `ScaleForDistance`) |
| `MULTI_NEAREST_DIST` | on | the single nearest extra shows a distance line |
| `MULTI_BEAM_ALPHA` | 0.2 | extra beam gradient base (main beam: 0.35) |
| `MULTI_BEAM_MIN/MAX` | 28/119 | extra beam height clamp (main: 40/170); fade rides frame alpha |

Selection: nearest-first within the cap by CapInsert semantics (class
ascending, then world-yard distance); after projection, extras within
`MULTI_MERGE` of the route pin's drawn plate or of a more important kept
extra hide behind it (route always wins; in navigator mode there is no route
reference on screen, so extras merge only among themselves).

Open questions for the in-game QA round-trip:

- Does a cap of 4 feel right, or does the scene want 2-3? (`pinsmulticap`)
- Is 300 yd the right ambient horizon, and 0.35 a readable-but-quiet floor?
- Is 28 UI units enough merge distance once plates scale down at range?
- Are the subordinate beams quiet enough next to the route beam, or should
  `pinsmultibeam` default off?
- Should extras carry titles? Hover is out per the compass no-mouse rule, so
  it would have to be always-on text -- likely too noisy; the nearest-only
  distance line is the current compromise.

## Phase A (shipped on `dev`, in-game QA pending)

**Corpse pylon (A1).** While `UnitIsDeadOrGhost("player")` and
`GetCorpseMapPosition` returns non-zero, the pins tier retargets the CORPSE
with the full waypoint/pinpoint/navigator treatment (skull icon, pinpoint
text "Your corpse"); absolute priority, mirroring the compass CLASS_CORPSE
rule, reverting on unghost. The multi-pin extras sleep entirely during the
corpse run. No setting: unconditional while pins are on.

**Custom waypoint (A2, `waypoint.lua`).** `/way 45 67 [label]` (map percent
of the current zone; `/way` clears) or ALT+left-click on the world map
canvas (ALT, not CTRL: holding CTRL over the map is already the
hide-cluster gesture; ALT-clicking near the placed point clears). Stored in
`pfQuest_config.customwaypoint = { x, y, zone, label }`, one point,
persists relogs. Pins prefer it over the route target but never over the
corpse; the compass renders it as CLASS_WAYPOINT (star art, accent tint,
between corpse and route). Auto-clears within ~15 yd with a chat notice.

**The route arrow DOES follow the waypoint, with zero route.lua changes.**
Finding: no synthetic route.coords entry is needed -- pfQuest already has
the machinery. The waypoint registers as a real pfMap node whose meta
carries `arrow = true`, which `map.lua:1230` unconditionally admits into
the route candidates on every UpdateNodes pass, and `route.SetTarget` on
the stored node orders it first. The node also renders on the world map and
minimap for free; clicking it (or ALT-clicking near it) clears the
waypoint.

**Ambient extras (A3/A5).** Rare spawns (`compassrares`, off) and dungeon
meeting stones (`pinsdungeon`, off) join the multi-pin extras when
`pinsmulti` is on, via per-zone cached DB scans in compass.lua (rares are
NOT pfMap nodes unless explicitly tracked; `pfDB.meta.rares` is the curated
unit-id list, vanilla+TBC coverage).

## Visual polish pass (shipped on `dev`, in-game QA pending)

The maintainer's "visual follow up and perfection" round: refinement only,
every behavior identical. The tier's visual language is now four layers per
plate, all runtime-tinted white art from `tools/gen_marker_assets.py`:

1. **Drop shadow** (`marker_fill`, black 0.35, 2 px down-right, drawn under
   everything): depth against bright ground.
2. **Glow halo** (`marker_glow`, 64x64 radial `(1-r^2)^2` falloff, ADD blend,
   accent-tinted, 1.6x the plate): the MAIN pin (waypoint diamond + pinpoint
   plate) pulses gently (sin, 2.5 s period, alpha 0.18-0.32; one SetAlpha per
   tick, only while shown); navigator static 0.25; extras/party/POI static at
   half (0.125); a DEAD party member keeps the full 0.25 as its
   find-the-body emphasis -- still accent-tinted, not red: the class-tinted
   skull already carries identity and a third hue would fight it.
3. **Plate** (fill + edge + icon, unchanged).
4. **Beam** (`beam_soft`, 32x256: horizontal gaussian core, vertically full
   alpha, ADD blend): the runtime SetGradientAlpha still owns the vertical
   fade, so height scaling is untouched. The main waypoint carries TWO
   layers -- wide faint halo (12 px, 0.16) + narrow brighter core (4 px, the
   original 0.35); extras keep one subordinate layer (6 px, 0.2). Chevrons
   (pinpoint marks + navigator arrow) moved to ADD blend so they read as
   light. ADD + gradient compose on 3.3.5a: the gradient writes per-corner
   vertex color/alpha, SetBlendMode picks the framebuffer op (milkyway
   widgets.ts:4141/4144; ElvUI-WotLK's vertex-tinted ADD sparks/glows are the
   precedent) -- no baked-fade TGA variant was needed.

**Pylon color override (`pinscolor`).** Default `""` = follow the theme
accent (teal standalone, GW2 gold with GW2_UI). A stored `"r,g,b"` (0-1
floats) overrides the accent for the ENTIRE pins tier -- beams, plate edges,
glows, chevrons, navigator, extras -- while fills stay theme bg and
class-colored party plates / death tint stay untouched. The settings row is a
swatch button opening the NATIVE 3.3.5a ColorPickerFrame (live-applies while
dragging via `.func` on OnColorSelect) plus a Reset button back to
theme-follow; parse is defensive (garbage -> theme follow) and re-tint rides
the driver's existing settings dirty path, no reload. The compass strip
deliberately does NOT reuse the override (the ask was the pylons; a live
compass re-tint spiders through its needle/cardinals/pool internals).

All constants live in the `pins.lua` tunables block and are exposed through
`pins.tunables`; wiring, parsing and re-tint are pinned in
`tools/pinscheck335.lua` (the color-parse fallback is negative-tested).
In-game QA gates: glow subtlety in daylight vs night, beam core readability
at range, pulse period feel, and the color picker round-trip
(pick/cancel/reset).

**Party pins (A4, amended).** `pinsparty` (off; party only, never raid)
rides the DLL's own `UnitPosition` on the party tokens: direct world
coords, no zone-size dependency, and the ONE guidance surface that keeps
working indoors and in dungeons, where `GetPlayerMapPosition` reads 0,0
and the whole percent tier stands down (the driver sleeps the main
elements but keeps ticking the world-anchored party layer). Alive members
are quiet class-colored dot plates: no beam, no text, lowest merge
priority. A DEAD member -- the primary use case is finding a body to
resurrect in a dungeon -- is elevated above the ambient info classes
(sorts between AVAIL and DUNGEON), wears the corpse pylon's skull art
still class-tinted so identity survives, and carries a subordinate beam
(independent of the `pinsmultibeam` experiment knob) plus its own distance
line. An unresolvable member (other instance, out of object-manager range)
simply has no pin: honest degrade, nothing fabricated. Positions poll at
the rebuild cadence and project per tick like every other extra.
