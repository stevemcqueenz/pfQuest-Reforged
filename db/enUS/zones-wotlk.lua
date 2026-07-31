-- generated WotLK data overlay (pfQuest Reforged)
-- source: Questie (https://github.com/Questie/Questie) wotlk database --
-- data only (ids, names, levels, masks, spawn coordinates); ids/format
-- follow pfQuest's native pfDB scheme.
pfDB["zones"]["enUS-wotlk"] = {
  -- Northrend outdoor zones whose IDs Blizzard RECYCLED: in the 1.12 data pfQuest
  -- ships natively these same IDs are placeholders ("Reuse Me 2/3/4/5/6",
  -- "Darrowmere Lake UNUSED"), and WotLK reused them for real zones. Without these
  -- overrides pfMap:GetMapIDByName() -- which resolves the OPEN world map by
  -- matching its name against pfDB.zones.loc -- finds nothing for these zones, so
  -- pfMap:GetMapID() returns nil and NO nodes are drawn at all (issue #1, "It
  -- doesn't work on Northrend"). ~14k spawns were unreachable across these six.
  [65] = "Dragonblight",         -- base 1.12 data: "Reuse Me 3"
  [66] = "Zul'Drak",             -- base 1.12 data: "Reuse Me 6"
  [67] = "The Storm Peaks",      -- base 1.12 data: "Reuse Me 5"
  [210] = "Icecrown",            -- base 1.12 data: "Reuse Me 2"
  [394] = "Grizzly Hills",       -- base 1.12 data: "Darrowmere Lake UNUSED"
  [2817] = "Crystalsong Forest", -- base 1.12 data: "Reuse Me 4"
  -- Vanilla ID 279 is literally named "Dalaran" (the Alterac crater -- a SUBZONE
  -- with no world map, and zero spawns in this database). It won the name lookup
  -- for Northrend's Dalaran city, so the 151 nodes stored under 4395 never
  -- rendered. Rename it so "Dalaran" resolves deterministically to the city below:
  -- GetMapIDByName iterates with pairs(), so two identical names are a coin flip.
  [279] = "Dalaran Crater",
  -- Same collision class, and it predates WotLK: vanilla ships TWO entries named
  -- "Alterac Valley" -- 2597 (the battleground map, 1612 spawns) and 2839 (zero
  -- spawns). pfMap:GetMapID() runs `GetMapIDByName(name) or customids[GetMapInfo()]`,
  -- so a name hit SHORT-CIRCUITS the AlteracValley->2597 customids fallback; when
  -- pairs() handed back 2839 first, every AV node silently vanished for that
  -- session. Disambiguate the empty one so 2597 always wins.
  [2839] = "Alterac Valley (unused duplicate)",
  [495] = "Howling Fjord",
  [3537] = "Borean Tundra",
  [3557] = "The Exodar",
  [3711] = "Sholazar Basin",
  [4100] = "The Culling of Stratholme",
  [4196] = "Drak'Tharon Keep",
  [4197] = "Wintergrasp",
  [4228] = "The Oculus",
  [4264] = "Halls of Stone",
  [4272] = "Halls of Lightning",
  [4273] = "Ulduar",
  [4277] = "Azjol-Nerub",
  [4298] = "Plaguelands: The Scarlet Enclave",
  [4395] = "Dalaran", -- was "Dalaran - Dungeon?" (generator artifact; never matched the map)
  [4415] = "The Violet Hold",
  [4416] = "Gundrak",
  [4493] = "The Obsidian Sanctum",
  [4494] = "Ahn'kahet: The Old Kingdom",
  [4500] = "The Eye of Eternity",
  [4742] = "Hrothgar's Landing",
  [4809] = "The Forge of Souls",
  [4812] = "Icecrown Citadel",
  [4813] = "Pit of Saron",
  [4987] = "The Ruby Sanctum",
}
