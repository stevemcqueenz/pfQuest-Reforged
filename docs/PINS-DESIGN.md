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
opacity, orbit distance, dynamic distance. Color override. Audio cues
(set/arrive) -- LOW priority, needs sound assets, park it.

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
