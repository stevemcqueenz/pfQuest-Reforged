-- Reforged one-shot generator: extract quest RELATION fields from the AzerothCore
-- Questie WotLK quest DB and emit db/quests-relations335.lua, an overlay pfQuest's
-- QuestFilter consults to hide quests that pfQuest's single ANY-prereq model can't.
-- Fields emitted (safe semantics -- only need questlog/history, no extra API):
--   excl  = exclusiveTo         (hide if any listed quest is in log/complete)
--   chain = nextQuestInChain    (hide if that later quest is in log/complete)
--   prg   = preQuestGroup       (ALL must be complete; pfQuest's `pre` only checks ANY)
-- Run:  lua5.1 tools/gen_relations335.lua  <path-to-questie>/Database/Wotlk/wotlkQuestDB.lua
local src = arg[1] or (os.getenv("HOME").."/refs/questie-ac/Database/Wotlk/wotlkQuestDB.lua")
QuestieDB = {}
QuestieLoader = { ImportModule = function() return QuestieDB end }
assert(loadstring(io.open(src):read("*a")))()
local data = assert(loadstring(QuestieDB.questData))()

local K = { prg = 12, chain = 22, excl = 16 } -- questKeys indices
local function idlist(t)
  if type(t) ~= "table" or #t == 0 then return nil end
  local seen, out = {}, {}
  for _, v in ipairs(t) do
    v = tonumber(v)
    if v and v > 0 and not seen[v] then seen[v] = true; out[#out+1] = v end
  end
  table.sort(out)
  return out[1] and out or nil
end

local ids = {}
for id in pairs(data) do ids[#ids+1] = id end
table.sort(ids)

local out = { 'pfDB["quests"]["relations"] = {' }
local n = 0
for _, id in ipairs(ids) do
  local q = data[id]
  local excl, prg = idlist(q[K.excl]), idlist(q[K.prg])
  local chain = tonumber(q[K.chain]); if not (chain and chain > 0) then chain = nil end
  if excl or prg or chain then
    n = n + 1
    local parts = {}
    if excl  then parts[#parts+1] = 'excl={'..table.concat(excl, ',')..'}' end
    if prg   then parts[#parts+1] = 'prg={'..table.concat(prg, ',')..'}' end
    if chain then parts[#parts+1] = 'chain='..chain end
    out[#out+1] = string.format('  [%d]={%s},', id, table.concat(parts, ','))
  end
end
out[#out+1] = '}'
local f = io.open("db/quests-relations335.lua", "w")
f:write(table.concat(out, "\n"), "\n")
f:close()
print(string.format("wrote db/quests-relations335.lua: %d quests with relations", n))
