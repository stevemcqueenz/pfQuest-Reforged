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
- **[GW2 UI (WotLK Reforged)](https://github.com/stevemcqueenz/GW2UI---WotLK---Reforged)
  integration** — right-click a quest in the GW2 tracker to navigate with the
  pfQuest arrow, sort the tracker by nearest objective, and get matching
  skins on the world map. Fully optional; pfQuest Reforged runs standalone.

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
- The WotLK overlay ships English names; other locales fall back to English
  for Northrend content. Converted drop sources carry no drop-rate
  percentages.
- Changelog: [CHANGES-REFORGED.md](CHANGES-REFORGED.md).

## Credits & license

- [Shagu](https://github.com/shagu) — pfQuest, the engine and the
  vanilla/TBC databases (GPLv3; this fork remains GPLv3)
- txtsd — the original WotLK client port
- [Questie](https://github.com/Questie/Questie) — the WotLK quest/spawn data
  the Reforged overlay was converted from
