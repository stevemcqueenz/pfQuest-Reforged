-- dump pfQuest's merged quest DB (id<TAB>title) for cross-addon comparison
dofile("stub.lua")
local base = "../pfq/pfQuest-wotlk-main/"

pfQuest_config, pfQuest_history, pfBrowser_fav, pfQuest_colors = {}, {}, {}, {}
pfQuest_server, pfQuest_track, pfQuest_questcache = {}, {}, {}

local function L(f)
  local ok, err = pcall(dofile, base .. f)
  if not ok then print("LOAD-FAIL", f, err) end
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
  "compat/pfUI.lua", "compat/client.lua", "locales.lua", "database.lua",
}) do L(f) end

local out = io.open("pfquest-quests.tsv", "w")
local n = 0
for id in pairs(pfDB["quests"]["data"]) do
  local loc = pfDB["quests"]["loc"][id]
  out:write(tostring(id) .. "\t" .. tostring(loc and loc.T or "") .. "\n")
  n = n + 1
end
out:close()
print("pfquest quests:", n)
