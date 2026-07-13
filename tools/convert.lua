-- Questie -> pfQuest WotLK data converter.
-- Reads Questie's wotlk databases (quest/npc/object/item + zone-name comments)
-- and emits pfQuest "-wotlk" overlay files containing ONLY the entries missing
-- from pfQuest's merged (vanilla + tbc) database. Data only: ids, names,
-- levels, masks, spawn coordinates. Run from the pfqharness directory:
--   lua5.1 convert.lua
dofile("stub.lua")
local pfqbase = "../pfq/pfQuest-wotlk-main/"
local questiebase = "../questie/Database/"

----------------------------------------------------------------------------
-- load pfQuest current db (vanilla + tbc overlays, merged like database.lua)
----------------------------------------------------------------------------
pfQuest_config, pfQuest_history, pfBrowser_fav, pfQuest_colors = {}, {}, {}, {}
pfQuest_server, pfQuest_track, pfQuest_questcache = {}, {}, {}

local function L(f)
  local ok, err = pcall(dofile, pfqbase .. f)
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
  "db/areatrigger-tbc.lua", "db/meta-tbc.lua", "db/zones-tbc.lua",
  "db/enUS/items-tbc.lua", "db/enUS/units-tbc.lua", "db/enUS/objects-tbc.lua",
  "db/enUS/quests-tbc.lua",
}) do L(f) end

local function patchtable(base, diff)
  for k, v in pairs(diff or {}) do
    if type(v) == "string" and v == "_" then
      base[k] = nil
    else
      base[k] = v
    end
  end
end

local merged = {}
for _, db in ipairs({ "quests", "units", "objects", "items", "zones" }) do
  merged[db] = { data = {}, loc = {} }
  patchtable(merged[db].data, pfDB[db] and pfDB[db]["data"])
  patchtable(merged[db].data, pfDB[db] and pfDB[db]["data-tbc"])
  patchtable(merged[db].loc, pfDB[db] and pfDB[db]["enUS"])
  patchtable(merged[db].loc, pfDB[db] and pfDB[db]["enUS-tbc"])
end

----------------------------------------------------------------------------
-- load Questie wotlk db
----------------------------------------------------------------------------
local QDB = {}
QuestieLoader = { ImportModule = function() return QDB end }
dofile(questiebase .. "Wotlk/wotlkQuestDB.lua")
dofile(questiebase .. "Wotlk/wotlkNpcDB.lua")
dofile(questiebase .. "Wotlk/wotlkObjectDB.lua")
dofile(questiebase .. "Wotlk/wotlkItemDB.lua")
local qQuests = assert(loadstring(QDB.questData))()
local qNpcs = assert(loadstring(QDB.npcData))()
local qObjects = assert(loadstring(QDB.objectData))()
local qItems = assert(loadstring(QDB.itemData))()
print("questie loaded:", "quests", (function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end)(qQuests))

-- zone names from the areaIdToUiMapId comments
local zoneNames = {}
for line in io.lines(questiebase .. "Zones/data/areaIdToUiMapId.lua") do
  local id, name = string.match(line, "^%s*%[(%d+)%]%s*=%s*%d+,%s*%-%-%s*(.+)%s*$")
  if id and name then zoneNames[tonumber(id)] = name end
end

----------------------------------------------------------------------------
-- conversion
----------------------------------------------------------------------------
local outQuests, outQuestsLoc = {}, {}
local neededUnits, neededObjects, neededItems = {}, {}, {}
local usedZones = {}

local function idlist(t)
  -- {id, id, ...} from either a plain id list or a {{id, text}, ...} tuple list
  if type(t) ~= "table" then return end
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "number" then
      out[#out + 1] = v
    elseif type(v) == "table" and type(v[1]) == "number" then
      out[#out + 1] = v[1]
    end
  end
  if #out > 0 then return out end
end

local missing = 0
for id, q in pairs(qQuests) do
  if not merged.quests.data[id] and type(q) == "table" and q[1] then
    missing = missing + 1
    local entry = {}
    if q[5] and q[5] > 0 then entry.lvl = q[5] end
    if q[4] and q[4] > 0 then entry.min = q[4] end
    if q[6] and q[6] > 0 then entry.race = q[6] end
    if q[7] and q[7] > 0 then entry.class = q[7] end

    local startedBy, finishedBy, objectives = q[2], q[3], q[10]
    if type(startedBy) == "table" then
      local U, O, I = idlist(startedBy[1]), idlist(startedBy[2]), idlist(startedBy[3])
      if U or O or I then entry.start = { U = U, O = O, I = I } end
    end
    if type(finishedBy) == "table" then
      local U, O = idlist(finishedBy[1]), idlist(finishedBy[2])
      if U or O then entry["end"] = { U = U, O = O } end
    end

    local obj
    if type(objectives) == "table" then
      local U, O, I = idlist(objectives[1]), idlist(objectives[2]), idlist(objectives[3])
      if U or O or I then obj = { U = U, O = O, I = I } end
    end
    -- requiredSourceItems -> pfQuest's itemreq gate list
    local IR = idlist(q[21])
    if IR then obj = obj or {}; obj.IR = IR end
    if obj then entry.obj = obj end

    local pre = idlist(q[13]) or idlist(q[12]) -- preQuestSingle, else preQuestGroup
    if pre then entry.pre = pre end

    outQuests[id] = entry
    local objText = ""
    if type(q[8]) == "table" then objText = table.concat(q[8], " ") end
    outQuestsLoc[id] = { T = q[1], O = objText }

    for _, set in ipairs({ entry.start, entry["end"], entry.obj }) do
      if set then
        for _, uid in ipairs(set.U or {}) do neededUnits[uid] = true end
        for _, oid in ipairs(set.O or {}) do neededObjects[oid] = true end
        for _, iid in ipairs(set.I or {}) do neededItems[iid] = true end
        for _, iid in ipairs(set.IR or {}) do neededItems[iid] = true end
      end
    end
  end
end
print("missing quests converted:", missing)

local function spawnsToCoords(spawns)
  local coords = {}
  for zone, points in pairs(spawns or {}) do
    if type(points) == "table" then
      for _, p in ipairs(points) do
        if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number"
          and p[1] >= 0 and p[2] >= 0 then -- -1,-1 marks "spawned by event/unknown"
          coords[#coords + 1] = { p[1], p[2], zone, 0 }
          usedZones[zone] = true
        end
      end
    end
  end
  return coords
end

local outUnits, outUnitsLoc = {}, {}
for uid in pairs(neededUnits) do
  local n = qNpcs[uid]
  if n and (not merged.units.data[uid] or not merged.units.loc[uid]) then
    if not merged.units.data[uid] then
      local entry = { coords = spawnsToCoords(n[7]) }
      local minl, maxl = n[4], n[5]
      if minl and maxl then entry.lvl = (minl == maxl) and tostring(minl) or (minl .. "-" .. maxl) end
      if n[13] then entry.fac = n[13] end
      outUnits[uid] = entry
    end
    if not merged.units.loc[uid] and n[1] then outUnitsLoc[uid] = n[1] end
  end
end

local outObjects, outObjectsLoc = {}, {}
for oid in pairs(neededObjects) do
  local o = qObjects[oid]
  if o and (not merged.objects.data[oid] or not merged.objects.loc[oid]) then
    if not merged.objects.data[oid] then
      outObjects[oid] = { coords = spawnsToCoords(o[4]) }
    end
    if not merged.objects.loc[oid] and o[1] then outObjectsLoc[oid] = o[1] end
  end
end

local outItems, outItemsLoc = {}, {}
for iid in pairs(neededItems) do
  local it = qItems[iid]
  if it and (not merged.items.data[iid] or not merged.items.loc[iid]) then
    if not merged.items.data[iid] then
      local entry = {}
      local U, O = {}, {}
      local anyU, anyO
      for _, uid in ipairs(it[2] or {}) do U[uid] = 0 anyU = true neededUnits[uid] = true end
      for _, oid in ipairs(it[3] or {}) do O[oid] = 0.1 anyO = true neededObjects[oid] = true end
      if anyU then entry.U = U end
      if anyO then entry.O = O end
      outItems[iid] = entry
    end
    if not merged.items.loc[iid] and it[1] then outItemsLoc[iid] = it[1] end
  end
end

-- second pass: drop-source units/objects discovered via items
for uid in pairs(neededUnits) do
  local n = qNpcs[uid]
  if n and not merged.units.data[uid] and not outUnits[uid] then
    local entry = { coords = spawnsToCoords(n[7]) }
    local minl, maxl = n[4], n[5]
    if minl and maxl then entry.lvl = (minl == maxl) and tostring(minl) or (minl .. "-" .. maxl) end
    if n[13] then entry.fac = n[13] end
    outUnits[uid] = entry
    if not merged.units.loc[uid] and n[1] then outUnitsLoc[uid] = n[1] end
  end
end
for oid in pairs(neededObjects) do
  local o = qObjects[oid]
  if o and not merged.objects.data[oid] and not outObjects[oid] then
    outObjects[oid] = { coords = spawnsToCoords(o[4]) }
    if not merged.objects.loc[oid] and o[1] then outObjectsLoc[oid] = o[1] end
  end
end

-- zones referenced by any emitted coordinate but unknown (or placeholder) in pfQuest
local outZonesLoc = {}
local unnamedZones = 0
for zone in pairs(usedZones) do
  local cur = merged.zones.loc[zone]
  if not cur or cur == "DELETE ME" then
    if zoneNames[zone] then
      outZonesLoc[zone] = zoneNames[zone]
    else
      unnamedZones = unnamedZones + 1
    end
  end
end

----------------------------------------------------------------------------
-- emit
----------------------------------------------------------------------------
local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function serialize(v, indent)
  if type(v) == "number" then
    return tostring(v)
  elseif type(v) == "string" then
    return string.format("%q", v)
  elseif type(v) == "table" then
    local pad = string.rep("  ", indent + 1)
    local parts = {}
    -- array part first
    for _, av in ipairs(v) do
      parts[#parts + 1] = pad .. serialize(av, indent + 1) .. ","
    end
    -- then sorted hash part
    local hashkeys = {}
    for k in pairs(v) do
      if type(k) ~= "number" or k > #v or k < 1 or k % 1 ~= 0 then hashkeys[#hashkeys + 1] = k end
    end
    table.sort(hashkeys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(hashkeys) do
      local kk = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
      parts[#parts + 1] = pad .. kk .. " = " .. serialize(v[k], indent + 1) .. ","
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, "\n") .. "\n" .. string.rep("  ", indent) .. "}"
  end
  return "nil"
end

local HEADER = "-- generated WotLK data overlay (pfQuest Reforged)\n" ..
  "-- source: Questie (https://github.com/Questie/Questie) wotlk database --\n" ..
  "-- data only (ids, names, levels, masks, spawn coordinates); ids/format\n" ..
  "-- follow pfQuest's native pfDB scheme.\n"

local function emit(path, tablepath, data)
  local f = assert(io.open(pfqbase .. path, "w"))
  f:write(HEADER)
  f:write(tablepath .. " = {\n")
  for _, id in ipairs(sortedKeys(data)) do
    f:write("  [" .. id .. "] = " .. serialize(data[id], 1) .. ",\n")
  end
  f:write("}\n")
  f:close()
end

emit("db/quests-wotlk.lua", 'pfDB["quests"]["data-wotlk"]', outQuests)
emit("db/units-wotlk.lua", 'pfDB["units"]["data-wotlk"]', outUnits)
emit("db/objects-wotlk.lua", 'pfDB["objects"]["data-wotlk"]', outObjects)
emit("db/items-wotlk.lua", 'pfDB["items"]["data-wotlk"]', outItems)
emit("db/enUS/quests-wotlk.lua", 'pfDB["quests"]["enUS-wotlk"]', outQuestsLoc)
emit("db/enUS/units-wotlk.lua", 'pfDB["units"]["enUS-wotlk"]', outUnitsLoc)
emit("db/enUS/objects-wotlk.lua", 'pfDB["objects"]["enUS-wotlk"]', outObjectsLoc)
emit("db/enUS/items-wotlk.lua", 'pfDB["items"]["enUS-wotlk"]', outItemsLoc)
emit("db/enUS/zones-wotlk.lua", 'pfDB["zones"]["enUS-wotlk"]', outZonesLoc)

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
print(string.format("emitted: %d quests, %d units, %d objects, %d items, %d zones (%d zone ids unnamed)",
  count(outQuests), count(outUnits), count(outObjects), count(outItems), count(outZonesLoc), unnamedZones))
