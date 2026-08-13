-- Rework-overlay check: pin db/wotlkrework335.lua and the merge that applies it.
--
-- Why this exists: the overlay corrects vanilla quest content that Wrath
-- changed (issue #43). Every value in it was taken from two independent 3.3.5a
-- sources that agree -- AzerothCore's world DB and Questie-335 -- but neither
-- is present at runtime, so the values are pinned here instead. A regeneration
-- or a hand-edit that drifts from what those sources say fails this gate.
--
-- The merge block is lifted out of database.lua and driven, the same way
-- trackingcheck335.lua drives the tracking merge.
--
-- Usage: lua5.1 tools/reworkcheck335.lua   (from the addon root)

local failures, checks = 0, 0
local function fail(fmt, ...) failures = failures + 1; print("  FAIL  " .. string.format(fmt, ...)) end
local function ok(fmt, ...) checks = checks + 1; print("  ok    " .. string.format(fmt, ...)) end

-- ---------------------------------------------------------------------------
-- the data, as both sources state it
-- ---------------------------------------------------------------------------
pfDB = {}
if not pcall(dofile, "db/wotlkrework335.lua") or not pfDB["rework335"] then
  fail("db/wotlkrework335.lua did not load or did not define pfDB[\"rework335\"]")
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
local rw = pfDB["rework335"]

-- quest 33 asks for the Wrath item, not the vanilla one
if rw.quests[33] and rw.quests[33].obj and rw.quests[33].obj.I
  and table.getn(rw.quests[33].obj.I) == 1 and rw.quests[33].obj.I[1] == 50432 then
  ok("quest 33 asks for item 50432 (Diseased Wolf Pelt)")
else
  fail("quest 33 objective is not the single item 50432")
end

-- the two drop maps, exactly as AC's creature_loot_template has them
local function samemap(got, want)
  if type(got) ~= "table" then return false end
  for k, v in pairs(want) do if got[k] ~= v then return false end end
  for k in pairs(got) do if want[k] == nil then return false end end
  return true
end
if rw.items[50432] and samemap(rw.items[50432].U, { [69] = 90, [299] = 90 }) then
  ok("Diseased Wolf Pelt drops from the two diseased wolves at 90")
else
  fail("item 50432's drop map is not { 69=90, 299=90 }")
end
-- the one that is easy to forget: 750 must LOSE the diseased wolves, or quest
-- 179 still sends players to mobs that no longer drop it
if rw.items[750] and samemap(rw.items[750].U, { [704] = 90, [705] = 90 }) then
  ok("Tough Wolf Meat drops only from the ragged wolves, so quest 179 stays right")
else
  fail("item 750's drop map is not { 704=90, 705=90 }")
end
if rw.items[750] and rw.items[750].U and (rw.items[750].U[69] or rw.items[750].U[299]) then
  fail("item 750 still lists a diseased wolf as a source")
else
  ok("item 750 no longer lists either diseased wolf")
end

local names = { { "unitnames", 69, "Diseased Timber Wolf" }, { "unitnames", 299, "Diseased Young Wolf" },
                { "itemnames", 50432, "Diseased Wolf Pelt" } }
local bad = 0
for _, n in ipairs(names) do
  if rw[n[1]] and rw[n[1]][n[2]] ~= n[3] then
    bad = bad + 1
    fail("%s[%d] is %q, expected %q", n[1], n[2], tostring(rw[n[1]][n[2]]), n[3])
  end
end
if bad == 0 then ok("all three corrected names match both sources") end

-- scope guard: this overlay is deliberately narrow. If it grows, that is a
-- decision, not an accident, and it should be visible here.
local nq, ni = 0, 0
for _ in pairs(rw.quests or {}) do nq = nq + 1 end
for _ in pairs(rw.items or {}) do ni = ni + 1 end
if nq <= 5 and ni <= 10 then ok("overlay still narrow: %d quests, %d items", nq, ni)
else fail("overlay has grown to %d quests / %d items without this gate being updated", nq, ni) end

-- ---------------------------------------------------------------------------
-- the merge, lifted out of database.lua and driven
-- ---------------------------------------------------------------------------
do
  local src = io.open("database.lua"):read("*a")
  local block = string.match(src, "\n(if pfDB%[\"rework335\"%] then\n.-\n  pfDB%[\"rework335\"%] = nil\nend)\n")
  local chunk = block and loadstring(block)
  if not chunk then
    fail("merge: could not lift the rework335 block out of database.lua")
  else
    pfDB = {
      locales = { enUS = "English", deDE = "German" },
      quests = { data = { [33] = { obj = { I = { 750 }, U = { 999 } }, lvl = 2, pre = { 5261 } } } },
      items = { data = { [750] = { U = { [69] = 80, [299] = 80, [704] = 80, [705] = 80 } } },
                enUS = { [750] = "Tough Wolf Meat" }, deDE = { [750] = "Zaehes Wolfsfleisch" } },
      units = { enUS = { [69] = "Timber Wolf", [299] = "Young Wolf" },
                deDE = { [69] = "Waldwolf", [299] = "Junger Wolf" } },
      rework335 = rw,
    }
    local okc, err = pcall(chunk)
    if not okc then
      fail("merge: the lifted block errored -> %s", tostring(err))
    else
      local q = pfDB.quests.data[33]
      if q.obj.I[1] == 50432 and table.getn(q.obj.I) == 1 then ok("merge: quest 33's item objective is replaced")
      else fail("merge: quest 33 objective is %s", tostring(q.obj.I[1])) end
      if q.obj.U and q.obj.U[1] == 999 then ok("merge: the quest's other objective fields survive")
      else fail("merge: obj.U was clobbered") end
      if q.lvl == 2 and q.pre and q.pre[1] == 5261 then ok("merge: level and prerequisites survive")
      else fail("merge: a non-objective field was lost") end

      local it750 = pfDB.items.data[750].U
      if it750[704] == 90 and it750[705] == 90 and not it750[69] and not it750[299] then
        ok("merge: item 750's sources are replaced, not merged")
      else
        fail("merge: item 750 still lists %s", it750[69] and "the diseased wolves" or "something unexpected")
      end
      local new = pfDB.items.data[50432]
      if new and new.U and new.U[69] == 90 and new.U[299] == 90 then ok("merge: the new item is created with its sources")
      else fail("merge: item 50432 was not created") end

      if pfDB.units.enUS[69] == "Diseased Timber Wolf" and pfDB.units.enUS[299] == "Diseased Young Wolf" then
        ok("merge: the two English mob names are corrected")
      else fail("merge: enUS mob names not corrected") end
      if pfDB.items.enUS[50432] == "Diseased Wolf Pelt" then ok("merge: the new item gets its English name")
      else fail("merge: item 50432 has no English name") end
      -- a locale that already carries a translated name keeps it; we have no
      -- translation for the new one and must not paste English over German
      -- npc 69 IS in unitnames and deDE already has a translation for it, so
      -- this is a real candidate the loop visits and must decline to touch
      if pfDB.units.deDE[69] == "Waldwolf" and pfDB.units.deDE[299] == "Junger Wolf" then
        ok("merge: an existing localised name is left alone")
      else
        fail("merge: overwrote the German name (%s)", tostring(pfDB.units.deDE[69]))
      end
      if pfDB.items.deDE[50432] == "Diseased Wolf Pelt" then ok("merge: a locale with NO name for the new item gets the English one")
      else fail("merge: deDE has no fallback name for item 50432") end

      if pfDB.rework335 == nil then ok("merge: frees the overlay when it is done")
      else fail("merge: left pfDB.rework335 in memory") end
    end
  end
end

-- ---------------------------------------------------------------------------
-- the file is actually loaded by the addon
-- ---------------------------------------------------------------------------
do
  local xml = io.open("init/data-wotlk.xml"):read("*a")
  if string.find(xml, "db\\wotlkrework335%.lua", 1) then ok("init/data-wotlk.xml includes db\\wotlkrework335.lua")
  else fail("init/data-wotlk.xml does not include db\\wotlkrework335.lua -- the fix would never load") end
end

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
