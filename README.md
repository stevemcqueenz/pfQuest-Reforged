# pfQuest Reforged

**A quest helper and database browser for WotLK 3.3.5a — with a complete
Wrath of the Lich King database and a modernized interface.**

Accept a quest and the relevant NPCs, monsters, and objects are automatically
pinned on your world map and minimap, with a smooth navigation arrow guiding
you to the nearest objective. Open the database browser (`/db`) to look up any
unit, item, object, or quest in the game.

Built on [pfQuest](https://github.com/shagu/pfQuest) (Shagu, GPLv3) via the
pfQuest-wotlk client port (txtsd). Reforged adds:

- **A full WotLK database** — the inherited data set ended at Outland; the
  Reforged overlay adds 2,487 Northrend-era quests, 2,465 NPCs, 372 objects,
  1,001 items, and all Northrend zones (data converted from the
  [Questie](https://github.com/Questie/Questie) project's WotLK database).
  Total coverage: 9,086 quests, verified 1:1 against Questie.
- **Server-accurate spawn data** — where the public data sets are wrong or simply
  empty, coordinates are recovered from an
  [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) `acore_world`
  database, which is what 3.3.5a servers actually run. World coordinates are
  converted to map positions with per-zone transforms fitted from NPCs present in
  both data sets, and a zone is skipped entirely if its fit is not clean — no
  guessed coordinates ship. Every batch is cross-checked against Questie where the
  two overlap. AzerothCore is preferred; Questie fills the gaps. Spawn tooltips show
  the server's real respawn timer rather than a guess.
- **Minimap nodes in Northrend** — upstream pfQuest ships map dimensions for vanilla
  and TBC only, and silently skips the minimap for any zone without them, so Northrend
  had world-map dots but never minimap dots. The Northrend rectangles are derived from
  the same AzerothCore data and validated against the 57 zones pfQuest already had
  (median error 0.09%).
- **A modernized interface** — flat dark theme with a single teal accent,
  tracker progress bars, a resizable database browser, map/minimap node-size
  sliders, and a clean smoothly-rotating navigation arrow.
- **~50% lower memory footprint** — spawn coordinates and item drop tables (the
  bulk of the loaded database) are packed into compact strings at load and
  decoded lazily only when the map/search/browser needs them, taking total addon
  memory from roughly **90 MB to 43 MB** in-game with no change to behavior.
- **Smarter quest availability** — the filter now honors exclusive quests, chain
  progression, and all-of-N prerequisites (relations sourced from Questie), so
  fewer quests you're already locked out of show up on the map.
- **A hardened map-pin lifecycle** — quest icons no longer vanish from the
  map/minimap on quest progress (several server-quirk races fixed and
  regression-tested in an offline harness).
- **HorizonCompass:** a modern compass strip in the Skyrim / Horizon Zero Dawn
  style. Cardinal letters and ticks scroll as you turn; your surroundings ride
  the strip as themed diamond markers: ready turn-ins, active objectives with
  kill/collect/interact icons, available quest givers (tinted when above your
  level), your route target, and your corpse during a corpse run. One label at
  a time follows what you are facing, with the quest name, live distance, and
  the objective text below the strip. Movable with shift+drag, scalable, with
  per-marker-type toggles and yards or meters. Off by default: enable
  "Compass Bar" in `/db config`.
- **In-world waypoint pylons:** with the optional
  [AwesomeWotLK](https://github.com/noname08662/awesome_wotlk) WorldAPI client
  mod, guidance steps into the 3D world. Your destination gets a glowing pylon
  with a light beam, distance and travel-time readout; walk close and it hands
  off to a pinpoint with the objective text and animated chevrons; look away
  and an indicator orbits the screen center pointing back. Optional extras:
  nearby quest markers as smaller pylons, party member markers that keep
  working inside dungeons (a dead member gets a beam so the healer can find
  the body), and adjustable pylon color. Everything detects the client mod
  automatically and the addon is fully functional without it.
- **Custom waypoints and utility POIs:** `/way 45 67` or alt+click on the
  world map plants a personal waypoint every surface follows, auto-clearing on
  arrival. `/way mail`, `/way flight`, `/way inn`, `/way repair` target the
  nearest mailbox, flight master, innkeeper, or repair vendor, sourced from
  server data for the whole 3.3.5a world. Selecting a tracking type on the
  minimap button (flight masters, mailboxes, innkeepers, repair) mirrors those
  locations onto the compass and pylons while it is active.
- **Quest tracker upgrades:** per-quest progress bars, adjustable width and
  scale, and alt+click on any quest row to point the arrow, compass, and pylon
  at it (alt+click again returns to automatic nearest-objective routing).
- **Quest icons on nameplates:** the map's icon language beside enemy
  nameplates: kill/collect/interact markers on objective mobs, a ? on ready
  turn-in NPCs, and a ! on available quest givers in the zone. Works on stock
  plates and on ElvUI/TidyPlates/Aloft/KUI skinned plates; with the
  AwesomeWotLK client mod it uses real nameplate unit tokens instead of the
  frame scan. Scale and position are adjustable, and when GW2 UI's own quest
  plate icons are active pfQuest defers automatically so plates never carry
  double icons. On by default: "Quest Icons On Nameplates" in `/db config`.
- **A reorganized settings window:** `/db config` now opens a sectioned window
  with a sidebar (General, Quest Tracker, Map and Minimap, Compass Bar,
  In-world Pins, and more) instead of a wall of checkboxes; sections for
  optional components appear only when they are available.
- **[GW2 UI (WotLK Reforged)](https://github.com/stevemcqueenz/GW2UI---WotLK---Reforged)
  integration** — right-click a quest in the GW2 tracker to navigate with the
  pfQuest arrow, sort the tracker by nearest objective, and get matching
  skins on the world map. Compass and pylons automatically adopt the GW2
  parchment-gold accent when GW2 UI is loaded. Fully optional; pfQuest
  Reforged runs standalone.

## Commands and gestures

| Action | Effect |
|---|---|
| `/db <search>` | database browser |
| `/pfquest` | all commands |
| `/way 45 67 [label]` | personal waypoint at map coordinates; `/way` alone clears |
| `/way mail` / `flight` / `inn` / `repair` | waypoint to the nearest utility POI |
| Alt+click a tracker quest (pfQuest or GW2 tracker) | arrow, compass, and pylon follow that quest; again for automatic |
| Alt+click on the world map | personal waypoint at the clicked spot |
| Shift+drag the compass strip or arrow | move it; position is remembered |
| Minimap tracking selection | mirrors flight masters, mailboxes, innkeepers, repair vendors onto compass and pylons |

## Install

1. Download the latest release zip.
2. Extract into `Interface\AddOns\` — the folder is named `pfQuest-Reforged`
   (existing `pfQuest` or `pfQuest-wotlk` folder names keep working, but
   remove old copies first so only one is installed).
3. Log in. `/db <search>` opens the browser, `/pfquest` lists all commands,
   `/db query` syncs your completed quests from the server.

## Notes

- WotLK 3.3.5a clients only (Interface 30300). For Vanilla or TBC use
  [upstream pfQuest](https://github.com/shagu/pfQuest).
- The in-world pylons need the AwesomeWotLK client mod with the WorldAPI
  module; every other feature, including the compass, works on an unmodified
  client. The addon detects the mod automatically, there is nothing to
  configure.
- The WotLK overlay ships English names; other locales fall back to English
  for Northrend content. Converted drop sources carry no drop-rate
  percentages.
- Changelog: [CHANGES-REFORGED.md](CHANGES-REFORGED.md).

## Credits & license

- [Shagu](https://github.com/shagu) — pfQuest, the engine and the
  vanilla/TBC databases (GPLv3; this fork remains GPLv3)
- [txtsd](https://github.com/txtsd) — the original WotLK client port
- [Questie](https://github.com/Questie/Questie) — the WotLK quest/spawn data
  the Reforged overlay was converted from, and the cross-check every
  AzerothCore-sourced batch is validated against
- [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) — the
  `acore_world` schema and data model the server-accurate spawn corrections are
  recovered from (AGPLv3 project; only coordinate data is used here, no code)
