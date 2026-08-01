-- Icecrown / Scourgeholme spawn data -- GENERATED from the maintainer's own
-- AzerothCore world DB (acore_world, AC rev 13e8857b515d, mod-playerbots fork).
--
-- Reported via issue #1: the [78] Icecrown quests "The Purging Of Scourgeholme",
-- "The Restless Dead" and "The Scourgestone" showed their quest GIVERS but no
-- objectives. Cause: the objective mobs have ZERO spawn coordinates in pfQuest,
-- in mainline Questie AND in the Questie-AzerothCore fork -- so there was nothing
-- to import from the usual sources. They do exist in the server DB.
--
-- World (x,y) -> map percentage was NOT taken from DBC bounds; it was fitted
-- empirically from 143 NPCs that appear both in acore_world (map 571) and in
-- pfQuest zone 210 with a single unambiguous spawn:
--     pctX = -0.01592986 * worldY + 86.80283   (mean residual 0.043%)
--     pctY = -0.02394430 * worldX + 225.67845  (mean residual 0.052%)
-- Cross-check: the derived clusters land immediately beside the known quest-giver
-- positions (The Ebon Watcher 83.0/73.0, Father Gustav 82.9/72.8), which were not
-- part of the fit.
--
-- NPC 30546 (The Restless Dead) is SUMMONED and has no creature row at all, so its
-- nodes come from that quest's own quest_poi polygon -- i.e. the exact area the
-- client itself highlights. Marked as such rather than pretending it is a spawn.
--
-- Entries are emitted WHOLE: database.lua's patchtable() replaces a key outright.
-- All five had empty coord tables, so nothing is being overwritten.
local d = pfDB["units"]["data-wotlk"]
local add = {
  -- Reanimated Crusader (36 nodes)
  [30202] = { ["coords"] = { {80.65,63.56,210},{81.56,66.33,210},{76.96,71.27,210},{77.83,70.73,210},{78.64,69.4,210},{76.66,68.7,210},{79.21,65.31,210},{79.77,65.14,210},{80.14,64.68,210},{80.07,66.57,210},{78.96,66.34,210},{79.51,66.91,210},{77.49,66.18,210},{76.98,69.61,210},{76.22,69.69,210},{78.21,68.52,210},{78.52,67.22,210},{76.7,66.59,210},{76.92,67.81,210},{78.27,65.06,210},{78.63,63.86,210},{78.28,63.7,210},{78.4,65.98,210},{77.39,67.33,210},{78.27,68.95,210},{75.9,67.09,210},{75.97,68.02,210},{79.47,68.21,210},{79.01,67.49,210},{78.75,68.52,210},{80.41,68.13,210},{80.71,66.87,210},{81.29,64.74,210},{80.66,66.27,210},{80.68,65.02,210},{78.95,64.71,210} } },
  -- Wrathstrike Gargoyle (7 nodes)
  [30482] = { ["coords"] = { {79.55,56.64,210},{78.13,57.85,210},{75.61,62.75,210},{76.57,62.87,210},{80.27,63.97,210},{77.77,67.71,210},{80.22,68.62,210} } },
  -- Forgotten Depths Underking (13 nodes)
  [30541] = { ["coords"] = { {75.1,58.96,210},{77.68,56.72,210},{75.42,57.93,210},{78.6,63.8,210},{73.37,62.64,210},{77.2,58.01,210},{76.79,63.58,210},{79.96,65.3,210},{77.18,71.53,210},{77.47,67.1,210},{75.88,65.01,210},{79.39,68.23,210},{80.49,66.64,210} } },
  -- Forgotten Depths High Priest (16 nodes)
  [30543] = { ["coords"] = { {78.94,60.94,210},{79.35,60.08,210},{79.57,61.47,210},{80.2,62.01,210},{79.94,60.39,210},{80.56,60.91,210},{76.2,60.99,210},{77.58,68.76,210},{77.5,68.6,210},{79.53,64.12,210},{78.5,56.57,210},{79.19,56.44,210},{77.71,65.51,210},{73.37,62.64,210},{75.22,60.42,210},{77.2,58.01,210} } },
  -- Restless Soul (quest_poi 13110) (10 nodes)
  [30546] = { ["coords"] = { {81.64,66.54,210},{81.31,64.77,210},{80.83,63.65,210},{78.33,63.55,210},{75.95,67.36,210},{75.92,68.17,210},{76.4,69.59,210},{77.09,70.85,210},{77.61,71.76,210},{82.87,72.82,210} } },
}
for id, e in pairs(add) do
  local old = d[id]
  if old then for k, v in pairs(old) do if k ~= "coords" then e[k] = v end end end
  d[id] = e
end
