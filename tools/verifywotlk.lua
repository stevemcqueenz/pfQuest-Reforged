-- verify the generated wotlk overlay end-to-end: load the full addon under the
-- 3.3.5a stub, SearchQuestID a deterministic sample of converted quests, and
-- report how many produce map nodes.
dofile("stub.lua")
local base = "../pfq/pfQuest-wotlk-main/"

pfQuest_config, pfQuest_history, pfBrowser_fav, pfQuest_colors = {}, {}, {}, {}
pfQuest_server, pfQuest_track, pfQuest_questcache = {}, {}, {}

local function L(f)
  local ok, err = pcall(dofile, base .. f)
  if not ok then print("LOAD-FAIL", f, err) os.exit(1) end
end

for _, f in ipairs({
  "db/init.lua", "db/items.lua", "db/units.lua", "db/objects.lua", "db/refloot.lua",
  "db/quests-itemreq.lua", "db/quests.lua", "db/zones.lua", "db/minimap.lua",
  "db/areatrigger.lua", "db/meta.lua",
  "db/enUS/items.lua", "db/enUS/units.lua", "db/enUS/objects.lua", "db/enUS/quests.lua",
  "db/enUS/zones.lua", "db/enUS/professions.lua",
  "db/items-tbc.lua", "db/units-tbc.lua", "db/objects-tbc.lua", "db/refloot-tbc.lua",
  "db/quests-itemreq-tbc.lua", "db/quests-tbc.lua", "db/minimap-tbc.lua",
  "db/areatrigger-tbc.lua", "db/meta-tbc.lua",
  "db/enUS/items-tbc.lua", "db/enUS/units-tbc.lua", "db/enUS/objects-tbc.lua", "db/enUS/quests-tbc.lua",
  "db/items-wotlk.lua", "db/units-wotlk.lua", "db/objects-wotlk.lua", "db/quests-wotlk.lua",
  "db/enUS/items-wotlk.lua", "db/enUS/units-wotlk.lua", "db/enUS/objects-wotlk.lua", "db/enUS/quests-wotlk.lua",
  "db/enUS/zones-wotlk.lua",
  "compat/pfUI.lua", "compat/client.lua", "theme.lua", "locales.lua",
  "config.lua", "database.lua", "icons.lua", "map.lua", "quest.lua", "route.lua", "tracker.lua",
}) do L(f) end

FAKE_QUESTLOG = {}
FireEvent("ADDON_LOADED", "pfQuest")
FireEvent("VARIABLES_LOADED")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD")

-- deterministic sample: every 25th converted (wotlk-era) quest id
local converted = {}
for id, data in pairs(pfDB["quests"]["data"]) do
  local loc = pfDB["quests"]["loc"][id]
  if type(id) == "number" and id >= 11600 and type(loc) == "table" and loc.T then
    converted[#converted + 1] = id
  end
end
table.sort(converted)
print("wotlk-era quests in merged db:", #converted)

local function countNodes()
  local n = 0
  for _, coords in pairs(pfMap.nodes["PFQUEST"] or {}) do
    for _, node in pairs(coords) do
      for _ in pairs(node) do n = n + 1 end
    end
  end
  return n
end

local tested, withNodes, zero = 0, 0, {}
for i = 1, #converted, 25 do
  local id = converted[i]
  pfMap.nodes["PFQUEST"] = {}
  pfDatabase:SearchQuestID(id, { addon = "PFQUEST" })
  tested = tested + 1
  local n = countNodes()
  if n > 0 then
    withNodes = withNodes + 1
  else
    zero[#zero + 1] = id
  end
end
print(string.format("sampled %d converted quests: %d produced nodes, %d produced none", tested, withNodes, tested - withNodes))
if #zero > 0 then
  local names = {}
  for i = 1, math.min(8, #zero) do
    local loc = pfDB["quests"]["loc"][zero[i]]
    names[#names + 1] = zero[i] .. " " .. (type(loc) == "table" and loc.T or "?")
  end
  print("no-node samples:", table.concat(names, " | "))
end

-- spot-check a known Borean Tundra chain entry incl. zone resolution
local probe = 11652 -- "The Plains of Nasam"
pfMap.nodes["PFQUEST"] = {}
pfDatabase:SearchQuestID(probe, { addon = "PFQUEST" })
local zonesHit = {}
for map in pairs(pfMap.nodes["PFQUEST"]) do zonesHit[#zonesHit + 1] = map .. " (" .. tostring(pfMap:GetMapNameByID(map) or pfDB["zones"]["loc"][map] or "?") .. ")" end
print("probe 11652 'The Plains of Nasam' nodes:", countNodes(), "maps:", table.concat(zonesHit, ", "))
os.exit(0)
