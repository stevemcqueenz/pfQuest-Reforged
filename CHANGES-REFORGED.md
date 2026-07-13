# pfQuest Reforged — UX modernization

> Versioning: from **v1.0.0** on, releases are numbered vMAJOR.MINOR.PATCH,
> auto-computed by CI on every push to main (release notes come from the
> commit log). The 8.1.0-reforged.N entries below are the pre-v1 history.

Built on pfQuest-wotlk (Shagu, txtsd — GPLv3). The battle-tested engine
(database, query, routing, map pin math) is untouched; this pass modernizes
the experience layer.

## New
- **Shared visual system** (`theme.lua`): flat dark panels with 1px borders,
  a single teal accent, header strips, and a reusable thin progress-bar
  factory. Everything below draws from it, so the addon reads as one UI.

## Tracker
- Per-quest **progress bar** under every quest title, colored by the same
  red→yellow→green ramp as the percent text.
- Flat dark panel chrome with a header strip and accent divider (replaces the
  bare black wash).
- Accent-tinted row highlight (hover + map-pin cross-highlight) instead of
  the white flash.
- Row spacing rebalanced so objectives clear the progress bar.

## Database browser
- **Resizable window** (drag the corner grip; 640×420 up to 1280×960), size
  persists per character. All four result lists and rows follow the width.
- Flat dark chrome + header strip matching the tracker.
- Accent-tinted row hover (replaces the white wash).

## Notes
- Load order gains `theme.lua` (before all UI files).
- No database, query, route, or map logic was modified.
- Known follow-up candidates: keyboard navigation of browser results,
  per-tab search (currently all four tabs rebuild per search), memoized
  map-pin tooltips.

## 8.1.0-reforged.12

- CRITICAL FIX: installing into the canonical `pfQuest-Reforged` folder left
  half the addon dead -- empty settings window, disabled navigation arrow,
  and a `menu.lua` crash on opening the minimap menu. The ADDON_LOADED
  initialization gates (config defaults, settings entries, SavedVariables
  like `pfQuest_track`) compared the install folder name against a hardcoded
  list (`pfQuest`/`pfQuest-tbc`/`pfQuest-wotlk`) that predates the rename;
  any other folder name skipped ALL of it. The gates now prefix-match any
  `pfQuest*` folder (with a run-once guard), and the texture-path probe
  additionally parses the REAL folder name from the load path, so even
  version-suffixed folders from zip extractors work.
- Every earlier install folder name keeps working unchanged.

## 8.1.0-reforged.11

- Out of beta: all "Beta" labels dropped (README rewritten for the Reforged
  fork; the stale upstream beta warning claimed no WotLK database ships --
  since reforged.10 it does). Release zips are now versioned instead of
  Beta-numbered.

## 8.1.0-reforged.10

- **Full WotLK quest database.** The inherited database was a TBC data set on
  a WotLK client -- complete through Outland, nearly empty in Northrend. A
  new machine-generated `-wotlk` overlay closes the gap: **2,487 quests,
  2,465 NPCs, 372 objects, 1,001 items and 24 zone names** (Borean Tundra
  through Icecrown), converted from the quest/spawn data of the
  Questie project (https://github.com/Questie/Questie) into pfQuest's native
  pfDB format. Data only: ids, names, levels, faction/race/class masks,
  prerequisite chains and spawn coordinates. The merged database now matches
  Questie's WotLK coverage 1:1 (9,086 quests). Known limits: converted drop
  sources carry no drop-rate percentages, and the overlay ships enUS names
  (other locales fall back to English for the new entries).
- Locale merge fix: expansion overlays now fall back to the enUS overlay for
  locales without their own translation -- the fallback existed but was
  unreachable (dead condition), which would have skipped the wotlk overlay
  entirely on non-English clients.
- Updated `/db query` chat output ships since reforged.9.

## 8.1.0-reforged.9

- `/db query` now reports its result in chat ("server query complete -- N
  quests flagged as completed (N new)"); it used to finish silently, leaving
  no way to tell whether the server sync ran.
- KNOWN GAP (analysis, no change yet): the inherited database is complete for
  vanilla + TBC but contains almost no Northrend quest data (2,487 quests
  present in Questie's WotLK database are missing here, 2,230 of them Wrath
  era). A full WotLK data import is planned.

## 8.1.0-reforged.8

- RENAMED: the addon now presents as **pfQuest Reforged** (addon-list title
  matches GW2 UI WotLK Reforged's branding). The canonical install folder is
  `pfQuest-Reforged` (new `pfQuest-Reforged.toc`, and the addon-path probe
  learned the new folder name so textures resolve); `pfQuest` and
  `pfQuest-wotlk` folders keep working via their identical toc aliases.

## 8.1.0-reforged.7

- FIX (packaging): installs extracted as a folder named `pfQuest` loaded the
  stale VANILLA loader (`pfQuest.toc`, Interface 11200) instead of the wotlk
  one -- it skipped `init\data-tbc.xml` / `init\enUS-tbc.xml`, so the TBC and
  WotLK database overlays never loaded (empty pfQuest data in Outland and
  Northrend; vanilla zones were unaffected). `pfQuest.toc` is now identical
  to `pfQuest-wotlk.toc` (Interface 30300, full overlay list), so both
  install folder names load the complete database. Renaming the folder to
  `pfQuest-wotlk` is no longer required (but keeps working).
- REMOVED: `pfQuest-tbc.toc`. This fork targets the 3.3.5a client only; the
  Reforged code is neither run nor verified on 2.4.3, so the TBC loader was
  an invitation to broken installs. Two loaders remain, both identical
  wotlk loaders: `pfQuest.toc` (canonical) and `pfQuest-wotlk.toc`
  (compatibility with existing renamed installs).

## 8.1.0-reforged.6

- FIX: collect quests lost ALL their map/minimap icons after picking up the
  first drop (e.g. 1/12 items looted) and only the turn-in marker survived
  until /reload. Root cause: the reforged.2 "corroborate isComplete against
  the leaderboard" guard still trusted the RAW per-objective done flag --
  the same flag reforged.5 proved to lie on some cores. When a core flaps
  isComplete AND raises the done flag on the first loot (text still x/y with
  x < y), the corroboration agreed with the lie and SearchQuestID early-
  returned after the caller had already deleted the quest's nodes; since the
  quest state never changed again, nothing re-added them. The corroboration
  now parses the trailing x/y count from the objective text (the same ground
  truth the objective parser uses) and only falls back to the flag when the
  text has no count. Harness-verified: with the old check the combined flap
  dropped a collect quest from 26 tracked nodes to 1 on the first loot; with
  the fix all 26 survive (52/52 on the multi-kill scenario, full quirk x
  tracking-mode matrix green).

## 8.1.0-reforged.5

- FIX: killing the first mob of a multi-kill objective (e.g. 1/12) removed
  that mob's map/minimap nodes although the objective was incomplete. Some
  custom cores raise the per-objective "done" flag on the first kill; the
  parsed x/y count from the objective text now takes precedence over the
  flag (the flag only decides when the text does not parse). Reproduced and
  verified in the offline harness: with the old logic the spurious flag
  dropped 52 tracked spawns to 30 on the kill; with the fix all 52 survive.

## 8.1.0-reforged.4

- FIX: the new arrow spun wildly on any movement -- the rotation mixed the
  client's degree-based `atan2` with radian `GetPlayerFacing`/`math.sin`.
  All bearing math is now radians end-to-end (`math.atan2`), the same way
  Zygor's Astrolabe pins the radian function for its arrow.
- The arrow now eases toward a new bearing across the shortest wrap
  (Zygor-style smoothing) instead of snapping on waypoint switches.
- The arrow hides while you are on a taxi flight -- position and facing race
  along the flight path, so the bearing is meaningless up there.
- New settings under Map & Minimap: **World Map Node Size** and **Minimap
  Node Size** sliders (8-24px, default 14) -- world-map changes apply live,
  minimap pins pick the size up on their next update. Icon (quest giver)
  pins follow the world-map size unless the advanced
  `worldmapUtilityNodeSize` key is set explicitly.

## 8.1.0-reforged.3

- New waypoint arrow: a clean, smoothly-rotating arrow (drawn for this addon,
  no third-party assets) replaces the 108-cell sprite sheet -- it turns
  continuously instead of snapping between pre-rendered frames, and keeps the
  red->yellow->green "facing the target" tint.
- The waypoint texts (title / objective / distance) now sit on the same soft
  dark panel the GW2_UI flight timer uses, sized dynamically to the longest
  line so long quest names never float on bare world.

## 8.1.0-reforged.2

- Fixed: quest markers vanished from the world map AND minimap the moment a
  quest's progress changed (e.g. the first kill for an objective). Two causes,
  both in the node-rebuild queue:
  - Nodes were deleted BEFORE the re-add decision; when the re-add was skipped
    (manual mode, tracked-mode gates, or a transiently unreadable quest-log
    slot during the post-kill QUEST_LOG_UPDATE burst) the queue entry was
    consumed and nothing ever restored the nodes. The WotLK auto-quest-watch
    flips the quest state on the very first kill, which is exactly when it hit.
    The rebuild now decides first and deletes only when it will re-add (or when
    hiding is intended, e.g. untracked quests in tracked-only mode); transient
    verify failures retry instead of wiping.
  - Some cores flap the quest's isComplete flag for a moment during that same
    burst; SearchQuestID trusted it unconditionally and re-added nothing. The
    flag is now corroborated against the objective leaderboard before the
    early-exit.
- Manual mode: quests you have shown by hand now REFRESH on progress instead of
  disappearing.
