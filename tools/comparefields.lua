-- Field-level comparison of pfQuest's pre-existing (vanilla+tbc) quest data
-- vs Questie's wotlk database: quest level, required level, race/class masks,
-- quest giver/ender NPCs, objective sets.
dofile("stub.lua")
local pfqbase = "../pfq/pfQuest-wotlk-main/"
local questiebase = "../questie/Database/"

pfQuest_config, pfQuest_history, pfBrowser_fav, pfQuest_colors = {}, {}, {}, {}
pfQuest_server, pfQuest_track, pfQuest_questcache = {}, {}, {}

local function L(f) local ok, e = pcall(dofile, pfqbase .. f) if not ok then print("LOAD-FAIL", f, e) end end
for _, f in ipairs({
  "db/init.lua", "db/quests.lua", "db/quests-tbc.lua", "db/enUS/quests.lua", "db/enUS/quests-tbc.lua",
}) do L(f) end

local function patchtable(base, diff)
  for k, v in pairs(diff or {}) do
    if type(v) == "string" and v == "_" then base[k] = nil else base[k] = v end
  end
end
local quests, loc = {}, {}
patchtable(quests, pfDB["quests"]["data"])
patchtable(quests, pfDB["quests"]["data-tbc"])
patchtable(loc, pfDB["quests"]["enUS"])
patchtable(loc, pfDB["quests"]["enUS-tbc"])

local QDB = {}
QuestieLoader = { ImportModule = function() return QDB end }
dofile(questiebase .. "Wotlk/wotlkQuestDB.lua")
local qQuests = assert(loadstring(QDB.questData))()

local function idset(t)
  local out = {}
  if type(t) == "table" then
    for _, v in ipairs(t) do
      if type(v) == "number" then out[v] = true
      elseif type(v) == "table" and type(v[1]) == "number" then out[v[1]] = true end
    end
  end
  return out
end
local function setsEqual(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end
local function setstr(s)
  local l = {}
  for k in pairs(s) do l[#l + 1] = k end
  table.sort(l)
  return table.concat(l, ",")
end

local stats = {}
local samples = {}
local function hit(field, id, pv, qv)
  stats[field] = (stats[field] or 0) + 1
  samples[field] = samples[field] or {}
  if #samples[field] < 5 then
    local t = loc[id]
    t = type(t) == "table" and t.T or "?"
    samples[field][#samples[field] + 1] = string.format("%d '%s': pfq=%s questie=%s", id, tostring(t), tostring(pv), tostring(qv))
  end
end

local common = 0
local ALLRACE = { [0] = true, [255] = true, [1791] = true } -- "no restriction" encodings
for id, p in pairs(quests) do
  local q = qQuests[id]
  if type(p) == "table" and type(q) == "table" then
    common = common + 1
    -- levels
    local plvl, qlvl = p.lvl or 0, q[5] or 0
    if qlvl == -1 then qlvl = plvl end -- Questie -1 = scales/unknown
    if plvl ~= qlvl and qlvl > 0 and plvl > 0 then hit("questLevel", id, plvl, qlvl) end
    local pmin, qmin = p.min or 0, q[4] or 0
    if pmin ~= qmin and pmin > 0 and qmin > 0 then hit("requiredLevel", id, pmin, qmin) end
    -- masks
    local prace, qrace = p.race or 0, q[6] or 0
    if not (ALLRACE[prace] and ALLRACE[qrace]) and prace ~= qrace then hit("raceMask", id, prace, qrace) end
    local pclass, qclass = p.class or 0, q[7] or 0
    if pclass ~= qclass then hit("classMask", id, pclass, qclass) end
    -- start/end npcs
    local psu = idset(p.start and p.start.U)
    local qsu = idset(type(q[2]) == "table" and q[2][1])
    if not setsEqual(psu, qsu) then hit("startNPCs", id, setstr(psu), setstr(qsu)) end
    local peu = idset(p["end"] and p["end"].U)
    local qeu = idset(type(q[3]) == "table" and q[3][1])
    if not setsEqual(peu, qeu) then hit("endNPCs", id, setstr(peu), setstr(qeu)) end
    -- objective sets
    local qobj = type(q[10]) == "table" and q[10] or {}
    for i, key in ipairs({ "U", "O", "I" }) do
      local ps = idset(p.obj and p.obj[key])
      local qs = idset(qobj[i])
      if not setsEqual(ps, qs) then hit("obj" .. key, id, setstr(ps), setstr(qs)) end
    end
  end
end

print("common quests compared:", common)
local order = { "questLevel", "requiredLevel", "raceMask", "classMask", "startNPCs", "endNPCs", "objU", "objO", "objI" }
for _, f in ipairs(order) do
  print(string.format("%-14s mismatches: %d", f, stats[f] or 0))
end
print("")
for _, f in ipairs(order) do
  if samples[f] then
    print("== " .. f .. " samples ==")
    for _, s in ipairs(samples[f]) do print("  " .. s) end
  end
end
