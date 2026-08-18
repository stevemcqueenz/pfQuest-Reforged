-- Skill-rank check: pin db/quests-skillrank335.lua, the merge that applies it,
-- and the QuestFilter gate that consumes it.
--
-- Why this exists: pfQuest models a profession requirement as PRESENCE only, so
-- a level-35 player holding First Aid 150 was shown "Horde Trauma", which needs
-- 225 (in-game QA report; cooking and fishing had the same shape). The rank
-- comes from AzerothCore's quest_template_addon, which is not present at
-- runtime -- so the values are pinned here, and both consumers are lifted out
-- of database.lua and driven, the way reworkcheck335.lua does it.
--
-- Usage: lua5.1 tools/skillrankcheck335.lua   (from the addon root)

local failures, checks = 0, 0
local function fail(fmt, ...) failures = failures + 1; print("  FAIL  " .. string.format(fmt, ...)) end
local function ok(fmt, ...) checks = checks + 1; print("  ok    " .. string.format(fmt, ...)) end

-- ---------------------------------------------------------------------------
-- the data
-- ---------------------------------------------------------------------------
pfDB = { quests = {} }
if not pcall(dofile, "db/quests-skillrank335.lua") or not pfDB["quests"]["skillrank"] then
  fail("db/quests-skillrank335.lua did not load or did not define the skillrank table")
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
local sr = pfDB["quests"]["skillrank"]

-- uniform shape: every entry a table with a positive numeric rank, and an
-- optional numeric skill id. Non-uniform generated data is the bug class that
-- bit the coordinate tables, so it is checked rather than assumed.
local n, shapebad = 0, 0
for id, e in pairs(sr) do
  n = n + 1
  if type(id) ~= "number" or type(e) ~= "table"
    or type(e.rank) ~= "number" or e.rank <= 0
    or (e.skill ~= nil and type(e.skill) ~= "number") then
    shapebad = shapebad + 1
    if shapebad <= 3 then fail("entry %s has the wrong shape", tostring(id)) end
  end
end
if shapebad == 0 then ok("all %d entries are { rank = number [, skill = number] }", n) end
if n >= 200 then ok("%d rank-gated quests (the server DB has ~256)", n)
else fail("only %d entries -- the extractor lost rows", n) end

-- the reported quest, and one of the 59 that carried NO skill id at all
if sr[6623] and sr[6623].rank == 225 then
  ok("quest 6623 (Horde Trauma) needs First Aid 225, as reported in QA")
else
  fail("quest 6623's rank is %s, expected 225", tostring(sr[6623] and sr[6623].rank))
end
if sr[8228] and sr[8228].rank == 150 and sr[8228].skill == 356 then
  ok("quest 8228 gains BOTH fishing (356) and its rank 150 -- it was ungated before")
else
  fail("quest 8228 did not gain skill 356 / rank 150")
end

-- ---------------------------------------------------------------------------
-- the merge, lifted out of database.lua and driven
-- ---------------------------------------------------------------------------
do
  local src = io.open("database.lua"):read("*a")
  local block = string.match(src,
    "\n(if pfDB%[\"quests\"%]%[\"skillrank\"%] then\n.-\n  pfDB%[\"quests\"%]%[\"skillrank\"%] = nil\nend)\n")
  local chunk = block and loadstring(block)
  if not chunk then
    fail("merge: could not lift the skillrank block out of database.lua")
  else
    pfDB = {
      quests = {
        data = {
          -- has its own skill id already, and a rank to gain
          [6623] = { skill = 129, lvl = 45, min = 35 },
          -- carries no skill id: gains both
          [8228] = { lvl = 40 },
          -- pfQuest disagrees is impossible (the generator refuses), but a
          -- STALE overlay entry for a quest the data no longer has must not
          -- create one out of nothing
        },
        skillrank = { [6623] = { rank = 225 }, [8228] = { rank = 150, skill = 356 },
                      [999999] = { rank = 300, skill = 171 } },
      },
    }
    local okc, err = pcall(chunk)
    if not okc then
      fail("merge: the lifted block errored -> %s", tostring(err))
    else
      local q = pfDB.quests.data[6623]
      if q.skillrank == 225 and q.skill == 129 then
        ok("merge: rank applied, the existing skill id untouched")
      else
        fail("merge: 6623 ended up skill=%s rank=%s", tostring(q.skill), tostring(q.skillrank))
      end
      if q.lvl == 45 and q.min == 35 then ok("merge: the quest's other fields survive")
      else fail("merge: a non-skill field was lost") end
      local q2 = pfDB.quests.data[8228]
      if q2.skill == 356 and q2.skillrank == 150 then ok("merge: an ungated quest gains both halves")
      else fail("merge: 8228 ended up skill=%s rank=%s", tostring(q2.skill), tostring(q2.skillrank)) end
      if pfDB.quests.data[999999] == nil then ok("merge: a stale overlay id creates no quest")
      else fail("merge: a stale overlay id invented a quest entry") end
      if pfDB.quests.skillrank == nil then ok("merge: the overlay is freed afterwards")
      else fail("merge: the overlay table was left in memory") end
    end
  end
end

-- ---------------------------------------------------------------------------
-- the QuestFilter gate, lifted and driven
--
-- The block uses a bare `return` to reject, so it is wrapped in a function
-- whose fall-through means "shown". That is exactly how it behaves inside
-- QuestFilter, where every other gate is written the same way.
-- ---------------------------------------------------------------------------
do
  local src = io.open("database.lua"):read("*a")
  local block = string.match(src,
    "\n(  if quests%[id%]%[\"skillrank\"%] and quests%[id%]%[\"skill\"%] then\n.-\n  end)\n")
  local chunk = block and loadstring(
    "local quests, id, pfDatabase = ...\n" .. block .. "\nreturn true")
  if not chunk then
    fail("filter: could not lift the skillrank gate out of database.lua")
  else
    -- the player's skills, as GetPlayerSkillCached reports them: the RANK, or
    -- false when the skill is missing entirely
    local player = { [129] = 150 }
    local db = { GetPlayerSkillCached = function(_, s) return player[s] or false end }
    local function shown(q) return chunk({ [1] = q }, 1, db) == true end

    if not shown({ skill = 129, skillrank = 225 }) then
      ok("filter: First Aid 150 does NOT see the quest needing 225 (the QA report)")
    else
      fail("filter: the under-ranked quest is still shown")
    end
    if shown({ skill = 129, skillrank = 150 }) then
      ok("filter: rank EQUAL to the requirement is shown (>= , not >)")
    else
      fail("filter: an exactly-met requirement was hidden")
    end
    if shown({ skill = 129, skillrank = 100 }) then
      ok("filter: rank above the requirement is shown")
    else
      fail("filter: an over-met requirement was hidden")
    end
    if not shown({ skill = 171, skillrank = 300 }) then
      ok("filter: a profession the player lacks entirely is hidden")
    else
      fail("filter: a missing profession slipped through the rank gate")
    end
    -- honest degrade: a rank we cannot evaluate must not hide the quest on a guess
    if shown({ skillrank = 300 }) then
      ok("filter: a rank with no skill id leaves the quest visible")
    else
      fail("filter: an unevaluable rank hid the quest")
    end
    if shown({ skill = 129 }) then
      ok("filter: a quest with no rank is untouched by this gate")
    else
      fail("filter: a rank-less quest was hidden")
    end
  end
end

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
