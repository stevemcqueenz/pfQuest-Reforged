# Data provenance (not shipped in releases)

`gen_tracking335.py` generates `db/tracking335.lua`, the Outland and Northrend
entries for pfQuest's map tracking lists. pfQuest's `pfDB["meta"]` lists are
vanilla plus TBC: Northrend had ZERO entries in every one of them, so "Herbs &
Flowers", "Mines & Ores", "Chests & Treasures", "Fishing" and "Rare Mobs" all
found nothing there (issue #18); Outland was mostly covered apart from the ores
and several herbs, whose object entries shipped with an empty coords table.

It reads AzerothCore's `gameobject` / `gameobject_template` / `creature` /
`creature_template` base dumps (fetch instructions in the file's docstring) plus
GatherMate 1's `Constants.lua` for the curated gathering roster and the skill
each node requires, and converts world positions to map percentages with
per-zone linear models fitted against pfQuest's own merged database, the same
method as `db/units-wotlk-acfill335.lua`.

Two zones, Wintergrasp and Crystalsong Forest, have no pfQuest spawns to fit
against. Their models come from the WorldMapArea rectangle shipped by
Questie-335's `QuestieCompat.UiMapData`, which was validated before being
trusted: it reproduces the fitted models to a median 0.011% across 66 zones and
pfQuest's own coordinates to 0.041%, and for Wintergrasp it reproduces
GatherMate's independent extraction of the same nodes to 0.006%. That source is
retail-era and is wrong for the Burning Crusade starting zones by hundreds of
percent, so it is used only where there is nothing to fit, and only after
checking it. See `UIMAP_RECTS` in the tool.

Two properties make it safe to re-run: it emits only for maps 530 and 571, and
it emits a coordinate only where pfQuest has none for that entity in that zone.
Both are asserted by `trackingcheck335.lua`.

```sh
python3 tools/gen_tracking335.py --ac-dir ~/refs/ac-world \
    --gathermate ~/gathermate-and-database-3.3.5a/GatherMate
```

`convert.lua` is the Questie→pfDB converter that generated the WotLK data
overlay in `db/*-wotlk.lua` (quests, NPCs, objects, items, zone names). It
reads [Questie](https://github.com/Questie/Questie)'s `Database/Wotlk/*.lua`
and emits only the entries missing from pfQuest's merged vanilla+TBC database.
Kept here to document where the WotLK data came from and to regenerate the
overlay after a Questie data update.

It runs under plain `lua5.1` against `stub.lua` (a minimal WoW API shim so
the pfDB files load outside the client); adjust the `pfqbase` / `questiebase`
path variables at the top of the script to point at your repo checkout and a
sibling Questie clone before running:

```sh
cd tools
lua5.1 convert.lua
```

# Verification gates

`./tools/check.sh` runs everything. The release workflow already runs the parse
gate; the others are new and exist because a green parse is not evidence the
addon works.

## apicheck335.py -- 3.3.5a API surface

Cross-references every global call and `RegisterEvent` name against
[milkyway-codex](https://github.com/Shard-MW/milkyway-codex), the 3.3.5a API
dataset. Catches retail-only APIs that are nil on this client and Cataclysm+ events
that never fire.

Clone the codex once:

```sh
git clone --depth 1 https://github.com/Shard-MW/milkyway-codex ~/refs/milkyway-codex
```

or point `MILKYWAY_CODEX` / `--codex` at it. Without it the check SKIPS rather than
fails, so it never blocks a machine that has not set it up.

Events are a hard failure; global calls are advisory, because FrameXML defines many
functions in Lua that a C-API dataset will never list. Known-good names live in the
`FRAMEXML` and `EVENT_GAPS` sets at the top -- `EVENT_GAPS` is for events that
demonstrably exist (an unknown event name raises on `RegisterEvent`, so anything the
shipping addon registers without erroring is real) but are missing from the dataset.

## runtimecheck335.lua -- build our objects and drive them

The parse and load checks confirm files are valid and load. They never build a
tracker row, so a missing method on one of our own objects is invisible to them.
That is exactly how v1.0.30 shipped `tracker.lua:523: attempt to call method 'Show'
(a nil value)` with everything green: the progress bar is a plain Lua table, not a
frame, so it only has what theme.lua defines, and `Hide` existed while `Show` never
did.

For each of our objects it declares the methods the addon actually calls, asserts
they exist, then runs the real call sequence and checks the result -- so the fill
arithmetic is verified too, not just that it was called.

Verified against the real defect: reintroducing the v1.0.30 bar and running this
reports 7 failures and exits non-zero.

When you add an object with its own methods, add a block here.

## trackercheck335.lua -- end-to-end: load the real tracker and build rows

`runtimecheck335.lua` drives our objects through a sequence transcribed BY HAND from
tracker.lua, so it tests the transcription: change what tracker.lua calls and it still
passes. This one loads the real `tracker.lua` and `theme.lua` against
`framestub335.lua`, hands them a synthetic quest log, and calls the actual
`ButtonAdd` / `ButtonEvent` / `DoLayout` chain -- so it follows the addon automatically.

Verified against the real defect: reintroducing the v1.0.30 bar reports

    FAIL  ButtonAdd("Distress Call") -> tracker.lua:523: attempt to call method 'SetEnabled' (a nil value)

which is the exact line and call from issue #10.

### framestub335.lua, and the thing to be careful about

Two rules this stub follows, both learned the hard way while writing it:

1. **No catch-all `__index`.** Returning a noop for every unknown key makes
   `if not frame.field` always false (a function is truthy) and makes calling a method
   that does not exist SUCCEED -- which would mask exactly the v1.0.30 bug. Unknown
   keys stay nil, like a real frame. Widening the stub means adding a name to
   `FRAME_NOOPS` deliberately.
2. **Two-point anchoring is modelled, not stubbed.** A region anchored LEFT and RIGHT
   derives its width from its parent. With a no-op `SetPoint` no width ever resolves,
   and the harness cannot tell a working progress bar from a broken one -- that is the
   precise mechanism of the fill bug.

The general hazard: the more the stub fakes, the more you are testing the stub. Keep
what a test asserts on honestly modelled, and prefer no assertion to one that passes
without measuring anything. The bar FILL is deliberately NOT asserted in the
end-to-end file for that reason (`ButtonEvent` needs richer questlog data than the
harness fakes); it is covered in `runtimecheck335.lua` with a known track width.

None of this replaces in-game QA. It catches the class of bug where the addon is
plainly broken on load, which is the class that shipped twice.

## trackingcheck335.lua -- the tracking data and the merge that consumes it

`db/tracking335.lua` is ~10k generated coordinates that nothing in the addon
validates at runtime, so a regeneration that widened the scope, lost the
fill-only policy or got one of pfQuest's value TYPES wrong would look exactly
like a good one. The type matters more than it sounds: `SearchMetaRelation` runs
`string.find(value, faction)` on the non-skill tracks, so a number in
`meta.fish` throws, while a string in `meta.herbs` silently breaks the skill
slider comparison.

This asserts the data invariants (tuple shape, 0..100, Outland/Northrend zones
only, no coordinate where pfQuest already covers that entity in that zone, each
track's id sign and value type, unit level and rank as the strings pfQuest
stores, `meta.rares` taking the low end of a level range) and that the entities
the release exists to add are actually present. It then lifts the real merge
block out of `database.lua` and drives it against a synthetic `pfDB`, so editing
that block is what the check notices -- the same technique as the
`IsInvalidPOIName` block in `runtimecheck335.lua`.

It also asserts that the two zones placed from a map rectangle have a 3:2
`pfDB.minimap` entry, since without one the minimap loop silently skips the zone
and the nodes appear on the world map only.

Verified by breaking it thirteen ways: a zone outside the emitted maps, a
percentage out of range, a coordinate colliding with shipped data, a fishing
pool's faction string turned into a number, a rare's meta key given the object
sign, a unit level emitted as a number, `meta.rares` taking the high end of a
range, the merge dropping the level/rank assignment, the merge overwriting a
shipped name, Hrothgar's Landing leaking into the data, a node type dropped, the
Wintergrasp minimap entry removed, and a minimap rectangle given a non-3:2
ratio. Each is reported and exits non-zero.
