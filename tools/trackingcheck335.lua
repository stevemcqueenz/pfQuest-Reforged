-- Tracking-data check: pin db/tracking335.lua and the merge that consumes it.
--
-- Why this exists: db/tracking335.lua is ~10k generated coordinates that nothing
-- in the addon validates at runtime. A regeneration that widened the scope, lost
-- the fill-only policy, emitted a percentage outside 0..100 or got one of
-- pfQuest's value TYPES wrong would look exactly like a good one. The type
-- matters more than it sounds: SearchMetaRelation runs string.find(value,
-- faction) on the non-skill tracks, so a number in meta.fish throws, while a
-- string in meta.herbs silently breaks the skill slider comparison.
--
-- So the data invariants are asserted here, and the real merge block is lifted
-- out of database.lua and driven, the same way the IsInvalidPOIName check in
-- runtimecheck335.lua does it.
--
-- Usage: lua5.1 tools/trackingcheck335.lua   (from the addon root)

local failures, checks = 0, 0
local function fail(fmt, ...) failures = failures + 1; print("  FAIL  " .. string.format(fmt, ...)) end
local function ok(fmt, ...) checks = checks + 1; print("  ok    " .. string.format(fmt, ...)) end

-- Outland + Northrend, the only maps the generator emits for (EMIT_MAPS).
-- Hrothgar's Landing 4742 is deliberately NOT here: pfQuest has no rectangle for
-- it and nothing to check one against, so nodes there cannot be placed and must
-- not be emitted. Wintergrasp 4197 and Crystalsong Forest 2817 ARE here -- they
-- are covered from the WorldMapArea rectangle, and both need a pfDB.minimap
-- entry too, which is asserted separately below.
local ALLOWED_ZONES = {
  -- Outland (map 530), including the TBC starting zones that share it
  [3483] = "Hellfire Peninsula", [3518] = "Nagrand", [3519] = "Terokkar Forest",
  [3520] = "Shadowmoon Valley", [3521] = "Zangarmarsh", [3522] = "Blade's Edge Mountains",
  [3523] = "Netherstorm", [3524] = "Azuremyst Isle", [3525] = "Bloodmyst Isle",
  [3430] = "Eversong Woods", [3433] = "Ghostlands", [4080] = "Isle of Quel'Danas",
  -- Northrend (map 571)
  [65] = "Dragonblight", [66] = "Zul'Drak", [67] = "The Storm Peaks",
  [210] = "Icecrown", [394] = "Grizzly Hills", [495] = "Howling Fjord",
  [3537] = "Borean Tundra", [3711] = "Sholazar Basin", [4395] = "Dalaran",
  [4197] = "Wintergrasp", [2817] = "Crystalsong Forest",
}

-- Zones whose model does NOT come from a fit against pfQuest's own data, so the
-- coordinates can only land correctly if pfQuest also has the matching map
-- rectangle. Without the pfDB.minimap entry the minimap loop skips the zone.
local NEEDS_MINIMAP_ENTRY = { 4197, 2817 }

-- Which pfDB database each track's ids live in, and which sign they carry.
local TRACKS = {
  herbs  = { db = "objects", sign = -1, kind = "number" },
  mines  = { db = "objects", sign = -1, kind = "number" },
  chests = { db = "objects", sign = -1, kind = "number" },
  fish   = { db = "objects", sign = -1, kind = "string" },
  rares  = { db = "units",   sign = 1,  kind = "number" },
}

-- The entities that were missing outright. If a regeneration drops one of these
-- the release has silently lost the thing it exists to fix.
local MUST_COVER = {
  { "objects", 189978, "Cobalt Deposit", 300 }, { "objects", 189979, "Rich Cobalt Deposit", 300 },
  { "objects", 189980, "Saronite Deposit", 600 }, { "objects", 189981, "Rich Saronite Deposit", 500 },
  { "objects", 191133, "Titanium Vein", 500 },
  { "objects", 181555, "Fel Iron Deposit", 300 }, { "objects", 181556, "Adamantite Deposit", 250 },
  { "objects", 181569, "Rich Adamantite Deposit", 150 }, { "objects", 181557, "Khorium Vein", 500 },
  { "objects", 189973, "Goldclover", 150 }, { "objects", 191019, "Adder's Tongue", 60 },
  { "objects", 190169, "Tiger Lily", 80 }, { "objects", 190170, "Talandra's Rose", 50 },
  { "objects", 190171, "Lichbloom", 300 }, { "objects", 190172, "Icethorn", 300 },
  { "objects", 183043, "Ragveil", 60 }, { "objects", 181276, "Flame Cap", 60 },
  -- fishing pools (issue #18)
  { "objects", 192046, "Musselback Sculpin School", 10 },
  { "objects", 192052, "Imperial Manta Ray School", 100 },
  { "objects", 192049, "Fangtooth Herring School", 40 },
  -- rare mobs (issue #18)
  { "units", 32517, "Loque'nahak", 3 }, { "units", 32491, "Time-Lost Proto Drake", 2 },
  { "units", 32485, "King Krush", 2 }, { "units", 32386, "Vigdis the War Maiden", 3 },
  -- Wintergrasp, reachable only through the WorldMapArea rectangle
  { "objects", 190176, "Frost Lotus", 80 },
}

-- ---------------------------------------------------------------------------
-- the generated table
-- ---------------------------------------------------------------------------
pfDB = {}
local loaded = pcall(dofile, "db/tracking335.lua")
local g = loaded and pfDB["tracking335"]
if not g then
  fail("db/tracking335.lua did not load or did not define pfDB[\"tracking335\"]")
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
for _, key in ipairs({ "objects", "units", "meta" }) do
  if type(g[key]) ~= "table" then fail("tracking335.%s is %s, expected a table", key, type(g[key])) end
end

local total, badshape, badzone, badpct = 0, 0, 0, 0
local zonesused, perid = {}, { objects = {}, units = {} }
for _, db in ipairs({ "objects", "units" }) do
  for id, coords in pairs(g[db]["coords"]) do
    if type(id) ~= "number" or id <= 0 then fail("%s coords key %s is not a positive id", db, tostring(id)) end
    perid[db][id] = 0
    for _, c in pairs(coords) do
      total = total + 1
      perid[db][id] = perid[db][id] + 1
      if type(c[1]) ~= "number" or type(c[2]) ~= "number"
        or type(c[3]) ~= "number" or type(c[4]) ~= "number" or c[5] ~= nil then
        badshape = badshape + 1
      elseif c[1] < 0 or c[1] > 100 or c[2] < 0 or c[2] > 100 or c[4] < 0 then
        badpct = badpct + 1
      elseif not ALLOWED_ZONES[c[3]] then
        badzone = badzone + 1
        if badzone <= 5 then fail("%s %d: zone %d is outside Outland/Northrend", db, id, c[3]) end
      else
        zonesused[c[3]] = true
      end
    end
  end
end
if badshape == 0 then ok("coords: all %d tuples are { xPct, yPct, zone, respawn }, the shape pfQuest ships", total)
else fail("coords: %d tuples are not 4-number { xPct, yPct, zone, respawn }", badshape) end
if badpct == 0 then ok("coords: every percentage inside 0..100, every respawn >= 0")
else fail("coords: %d tuples out of range", badpct) end
if badzone == 0 then
  local n = 0
  for _ in pairs(zonesused) do n = n + 1 end
  ok("coords: %d zones used, all Outland/Northrend", n)
else
  fail("coords: %d tuples land outside the emitted maps", badzone)
end

-- ---------------------------------------------------------------------------
-- fill only: never a coordinate where pfQuest already has one for that
-- (entity, zone). This is the invariant that makes an additive merge safe.
-- ---------------------------------------------------------------------------
do
  local tracking = g
  pfDB = {}
  dofile("db/init.lua")
  for _, f in ipairs({ "objects", "objects-tbc", "objects-wotlk", "objects-wotlk-sw335",
                       "units", "units-tbc", "units-wotlk", "units-wotlk-sw335",
                       "units-wotlk-icecrown335", "units-wotlk-acfill335",
                       "enUS/objects", "enUS/objects-tbc", "enUS/objects-wotlk",
                       "enUS/units", "enUS/units-tbc", "enUS/units-wotlk" }) do
    dofile("db/" .. f .. ".lua")
  end
  local function patch(base, diff)
    for k, v in pairs(diff or {}) do
      if v == "_" then base[k] = nil else base[k] = v end
    end
  end
  for _, db in ipairs({ "objects", "units" }) do
    patch(pfDB[db]["data"], pfDB[db]["data-tbc"])
    patch(pfDB[db]["data"], pfDB[db]["data-wotlk"])
    patch(pfDB[db]["enUS"], pfDB[db]["enUS-tbc"])
    patch(pfDB[db]["enUS"], pfDB[db]["enUS-wotlk"])
  end

  local clashes, checked, named, redundant = 0, 0, 0, 0
  for _, db in ipairs({ "objects", "units" }) do
    for id, coords in pairs(tracking[db]["coords"]) do
      local shipped = pfDB[db]["data"][id]
      local have = {}
      if shipped and shipped["coords"] then
        for _, c in pairs(shipped["coords"]) do have[c[3]] = true end
      end
      for _, c in pairs(coords) do
        checked = checked + 1
        if have[c[3]] then
          clashes = clashes + 1
          if clashes <= 5 then fail("%s %d already has coords in zone %d -- fill-only broken", db, id, c[3]) end
        end
      end
    end
    for id in pairs(tracking[db]["names"]) do
      named = named + 1
      if tracking[db]["coords"][id] == nil then fail("%s names has %d with no coords", db, id) end
      if pfDB[db]["enUS"][id] then redundant = redundant + 1 end
    end
  end
  if clashes == 0 then ok("fill-only: none of the %d nodes lands in a zone pfQuest already covers for that entity", checked)
  else fail("fill-only: %d nodes collide with shipped data", clashes) end
  if redundant == 0 then ok("names: all %d are for entities the shipped database has no name for", named)
  else fail("names: %d entries would overwrite a shipped name", redundant) end
end

-- ---------------------------------------------------------------------------
-- the tracking lists: right database, right sign, right TYPE, and nothing
-- pfQuest's own meta already answers
-- ---------------------------------------------------------------------------
do
  pfDB = {}
  dofile("db/init.lua")
  dofile("db/meta.lua")
  dofile("db/meta-tbc.lua")
  local meta = pfDB["meta"]
  for k, v in pairs(pfDB["meta-tbc"]) do meta[k] = v end

  local bad, count = 0, 0
  for track, entries in pairs(g["meta"]) do
    local spec = TRACKS[track]
    if not spec then
      bad = bad + 1
      fail("meta: track %q is not one pfQuest has", tostring(track))
    else
      for id, value in pairs(entries) do
        count = count + 1
        local raw = id * spec.sign
        if raw <= 0 then
          bad = bad + 1; fail("meta.%s: id %d has the wrong sign for a %s track", track, id, spec.db)
        elseif g[spec.db]["coords"][raw] == nil then
          bad = bad + 1; fail("meta.%s: %d is listed but has no coords", track, raw)
        elseif type(value) ~= spec.kind then
          bad = bad + 1; fail("meta.%s: %d has a %s value, pfQuest stores %s here", track, raw, type(value), spec.kind)
        elseif meta[track] and meta[track][id] then
          bad = bad + 1; fail("meta.%s: %d is already answered by pfQuest's own meta", track, raw)
        end
      end
    end
  end
  if bad == 0 then ok("meta: %d entries, all correctly signed, typed, backed by coords and absent from pfQuest's meta", count) end

  -- pfQuest's own convention, restated so a regeneration cannot drift from it:
  -- the skill/level tracks are compared numerically against the slider, the
  -- rest are matched with string.find against the player's faction letter.
  local numeric = (type(g["meta"]["herbs"]) == "table")
  for id, v in pairs(g["meta"]["fish"] or {}) do
    if type(v) ~= "string" or not string.find(v, "A") or not string.find(v, "H") then
      numeric = false
      fail("meta.fish: %d is %q, expected the faction string \"AH\"", id, tostring(v))
    end
  end
  if numeric then ok("meta.fish: every value is the \"AH\" faction string SearchMetaRelation matches with string.find") end
end

-- ---------------------------------------------------------------------------
-- unit info: pfQuest stores level and rank as STRINGS, level may be a range
-- ---------------------------------------------------------------------------
do
  local bad, count = 0, 0
  for id, info in pairs(g["units"]["info"]) do
    count = count + 1
    if g["units"]["coords"][id] == nil then
      bad = bad + 1; fail("units.info: %d has info but no coords", id)
    elseif type(info[1]) ~= "string" or type(info[2]) ~= "string" then
      bad = bad + 1; fail("units.info: %d has lvl=%s rnk=%s, pfQuest stores both as strings",
                          id, type(info[1]), type(info[2]))
    elseif not string.find(info[1], "^%d+$") and not string.find(info[1], "^%d+%-%d+$") then
      bad = bad + 1; fail("units.info: %d has lvl %q, expected \"73\" or \"71-72\"", id, info[1])
    elseif info[2] ~= "2" and info[2] ~= "4" then
      bad = bad + 1; fail("units.info: %d has rnk %q, rares are rank 2 or 4", id, info[2])
    end
  end
  if bad == 0 then ok("units.info: %d rares carry a string level and a rare rank", count) end

  -- and meta.rares must be the LOW end of that level, as a number
  local mism = 0
  for id, lvl in pairs(g["meta"]["rares"] or {}) do
    local info = g["units"]["info"][id]
    local low = info and (tonumber(info[1]) or tonumber(string.match(info[1], "^(%d+)%-")))
    if low and low ~= lvl then
      mism = mism + 1
      fail("meta.rares: %d is %s but its level is %q (pfQuest uses the low end)", id, tostring(lvl), info[1])
    end
  end
  if mism == 0 then ok("meta.rares: every level matches the low end of the unit's level, as pfQuest stores it") end
end

-- ---------------------------------------------------------------------------
-- coverage: the entities this release exists to add are actually in there
-- ---------------------------------------------------------------------------
do
  local missing = 0
  for _, want in ipairs(MUST_COVER) do
    local db, id, name, least = want[1], want[2], want[3], want[4]
    local n = perid[db][id] or 0
    if n < least then
      missing = missing + 1
      fail("coverage: %s (%d) has %d nodes, expected at least %d", name, id, n, least)
    end
  end
  if missing == 0 then ok("coverage: all %d previously-absent entities present", table.getn(MUST_COVER)) end
end

-- ---------------------------------------------------------------------------
-- the merge itself. Lift the real block out of database.lua and drive it, so
-- editing that block is what this check notices.
-- ---------------------------------------------------------------------------
do
  local src = io.open("database.lua"):read("*a")
  local block = string.match(src, "\n(if pfDB%[\"tracking335\"%] then\n.-\n  pfDB%[\"tracking335\"%] = nil\nend)\n")
  local chunk = block and loadstring(block)
  if not chunk then
    fail("merge: could not lift the tracking335 block out of database.lua")
  else
    pfDB = {
      locales = { enUS = "English" },
      objects = {
        -- an object the base database already knows, with a coordinate
        data = { [181555] = { coords = { { 10, 20, 3483, 300 } }, quest = true } },
        enUS = { [181555] = "Fel Iron Deposit" },
      },
      units = {
        data = { [32517] = { coords = { { 11, 21, 3711, 600 } }, lvl = "76", rnk = "2" } },
        enUS = { [32517] = "Loque'nahak" },
      },
      meta = { herbs = {}, mines = { [-181555] = 300 }, chests = {}, fish = {}, rares = {} },
      tracking335 = {
        objects = {
          coords = {
            [181555] = { { 30, 40, 3519, 600 } },
            [189978] = { { 50, 60, 3537, 900 }, { 51, 61, 3537, 900 } },
            [192046] = { { 20, 30, 3537, 300 } },
          },
          -- 181555 is here ON PURPOSE even though the real generator never
          -- names an entity pfQuest can already name: it is what makes the
          -- "leaves an existing name alone" assertion below exercise the guard.
          names = { [189978] = "Cobalt Deposit", [192046] = "Musselback Sculpin School",
                    [181555] = "SHOULD NOT WIN" },
        },
        units = {
          coords = { [32491] = { { 70, 80, 67, 1800 } } },
          names = { [32491] = "Time-Lost Proto Drake" },
          info = { [32491] = { "80", "2" } },
        },
        meta = {
          mines = { [-189978] = 350 },
          fish = { [-192046] = "AH" },
          rares = { [32491] = 80 },
        },
      },
    }
    local okc, err = pcall(chunk)
    if not okc then
      fail("merge: the lifted block errored -> %s", tostring(err))
    else
      local existing = pfDB.objects.data[181555]
      if table.getn(existing.coords) == 2 and existing.coords[1][3] == 3483
        and existing.coords[2][3] == 3519 then
        ok("merge: appends to an existing object without dropping its coords")
      else
        fail("merge: existing object's coords are %d entries", table.getn(existing.coords))
      end
      if existing.quest == true then ok("merge: leaves the rest of an existing entry alone")
      else fail("merge: clobbered a field on the existing entry") end

      if pfDB.objects.data[189978] and table.getn(pfDB.objects.data[189978].coords) == 2 then
        ok("merge: creates the entry for an object pfQuest never had")
      else fail("merge: did not create the missing object entry") end

      local rare = pfDB.units.data[32491]
      if rare and table.getn(rare.coords) == 1 then ok("merge: creates the entry for a unit pfQuest never had")
      else fail("merge: did not create the missing unit entry") end
      if rare and rare.lvl == "80" and rare.rnk == "2" then ok("merge: gives a new rare its string level and rank")
      else fail("merge: new rare has lvl=%s rnk=%s", tostring(rare and rare.lvl), tostring(rare and rare.rnk)) end
      if pfDB.units.data[32517].lvl == "76" then ok("merge: leaves an existing unit's level alone")
      else fail("merge: overwrote a shipped unit level") end

      if pfDB.objects.enUS[189978] == "Cobalt Deposit" and pfDB.units.enUS[32491] == "Time-Lost Proto Drake" then
        ok("merge: names the new object and the new unit")
      else fail("merge: a new entity has no name") end
      if pfDB.objects.enUS[181555] == "Fel Iron Deposit" then ok("merge: leaves an existing name alone")
      else fail("merge: overwrote a shipped name") end

      if pfDB.meta.mines[-189978] == 350 then ok("merge: writes an object track at the negative id meta uses")
      else fail("merge: mines entry is %s", tostring(pfDB.meta.mines[-189978])) end
      if pfDB.meta.rares[32491] == 80 then ok("merge: writes a unit track at the positive id meta uses")
      else fail("merge: rares entry is %s", tostring(pfDB.meta.rares[32491])) end
      if pfDB.meta.fish[-192046] == "AH" then ok("merge: keeps the fishing pool's faction string a string")
      else fail("merge: fish entry is %s", tostring(pfDB.meta.fish[-192046])) end
      if pfDB.meta.mines[-181555] == 300 then ok("merge: leaves an existing skill requirement alone")
      else fail("merge: overwrote a shipped skill requirement") end

      if pfDB.tracking335 == nil then ok("merge: frees the overlay when it is done")
      else fail("merge: left pfDB.tracking335 in memory") end
    end
  end
end

-- ---------------------------------------------------------------------------
-- the zones we place from a map rectangle must also have that rectangle in
-- pfDB.minimap, or the minimap loop silently skips them
-- ---------------------------------------------------------------------------
do
  pfDB = {}
  dofile("db/init.lua")
  dofile("db/minimap.lua")
  dofile("db/minimap-tbc.lua")
  dofile("db/minimap-wotlk335.lua")
  local sizes = {}
  for _, k in ipairs({ "minimap", "minimap-tbc", "minimap-wotlk" }) do
    for z, s in pairs(pfDB[k] or {}) do sizes[z] = s end
  end
  local bad = 0
  for _, z in ipairs(NEEDS_MINIMAP_ENTRY) do
    local s = sizes[z]
    if not s then
      bad = bad + 1
      fail("minimap: zone %d has nodes but no pfDB.minimap rectangle -- no minimap dots", z)
    elseif math.abs(s[1] / s[2] - 1.5) > 0.01 then
      bad = bad + 1
      fail("minimap: zone %d is %.1f x %.1f, ratio %.3f -- every WorldMapArea is 3:2",
           z, s[1], s[2], s[1] / s[2])
    end
  end
  if bad == 0 then ok("minimap: both rectangle-placed zones have a 3:2 pfDB.minimap entry") end
end

-- ---------------------------------------------------------------------------
-- the file is actually loaded by the addon
-- ---------------------------------------------------------------------------
do
  local xml = io.open("init/data-wotlk.xml"):read("*a")
  if string.find(xml, "db\\tracking335%.lua", 1) then ok("init/data-wotlk.xml includes db\\tracking335.lua")
  else fail("init/data-wotlk.xml does not include db\\tracking335.lua -- the data would never load") end
end

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
