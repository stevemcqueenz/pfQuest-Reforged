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
  -- Eastern Plaguelands: not a WotLK zone, but the one Azeroth zone with no
  -- mining data at all, and the one whose map rectangle database.lua corrects.
  [139] = "Eastern Plaguelands",
}

-- Zones whose coordinates come from a map rectangle rather than a fit against
-- pfQuest's own data. They only land correctly if pfDB.minimap carries THAT
-- rectangle's width: without an entry at all the minimap loop skips the zone,
-- and with the wrong width it undoes the placement on the minimap only. Eastern
-- Plaguelands is the sharp case, since pfQuest ships a perfectly plausible 3:2
-- size for it that happens to be the 1.12 one.
local NEEDS_MINIMAP_ENTRY = {
  { 4197, 2975.00 }, { 2817, 2722.92 }, { 139, 4031.25 },
}

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

-- Zone-level coverage the REBUILD owes, for the two zones players reported as
-- empty or thin. These come through the rebuild rather than the additive path,
-- so they are counted separately.
-- An id of nil means "the whole zone", which is the honest assertion where the
-- complaint was that a zone was empty rather than that one ore was missing.
local REBUILD_MUST_COVER = {
  { 139, 2047, "Truesilver Deposit", "Eastern Plaguelands", 60 },
  { 139, 324, "Rich Thorium Vein", "Eastern Plaguelands", 20 },
  { 4, 2047, "Truesilver Deposit", "Blasted Lands", 25 },
  { 4, nil, "every gathering node", "Blasted Lands", 150 },
  { 17, nil, "every gathering node", "The Barrens", 500 },
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
  -- An entity can belong on a list without us adding a single coordinate for
  -- it: pfQuest may already know exactly where it is and simply never have
  -- listed it (Everfrost Chip, Netherwing Egg, Glowcap and eight others were
  -- invisible that way). So a list entry is backed by OUR coords or pfQuest's.
  local pfcoords = { objects = {}, units = {} }
  for _, f in ipairs({ "objects", "objects-tbc", "objects-wotlk", "objects-wotlk-sw335",
                       "units", "units-tbc", "units-wotlk", "units-wotlk-icecrown335",
                       "units-wotlk-acfill335" }) do
    dofile("db/" .. f .. ".lua")
  end
  for _, db in ipairs({ "objects", "units" }) do
    for _, key in ipairs({ "data", "data-tbc", "data-wotlk" }) do
      for id, e in pairs(pfDB[db][key] or {}) do
        for _, c in pairs(e.coords or {}) do
          pfcoords[db][id] = pfcoords[db][id] or {}
          pfcoords[db][id][c[3]] = true
        end
      end
    end
  end

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
        elseif g[spec.db]["coords"][raw] == nil and not pfcoords[spec.db][raw] then
          bad = bad + 1; fail("meta.%s: %d is listed but nothing knows where it is", track, raw)
        elseif type(value) ~= spec.kind then
          bad = bad + 1; fail("meta.%s: %d has a %s value, pfQuest stores %s here", track, raw, type(value), spec.kind)
        elseif meta[track] and meta[track][id] then
          bad = bad + 1; fail("meta.%s: %d is already answered by pfQuest's own meta", track, raw)
        end
      end
    end
  end
  if bad == 0 then ok("meta: %d entries, all correctly signed, typed, backed by coords and absent from pfQuest's meta", count) end

  -- Entities pfQuest could already place but never listed. Regenerating from
  -- the emitted coordinates alone would silently drop every one of them.
  local UNLISTED = {
    { "chests", -193997, "Everfrost Chip" }, { "chests", -185915, "Netherwing Egg" },
    { "chests", -182053, "Glowcap" }, { "chests", -184793, "Primitive Chest" },
    { "chests", -184740, "Wicker Chest" }, { "chests", -184741, "Dented Footlocker" },
    { "chests", -181665, "Burial Chest" }, { "herbs", -181285, "Nightmare Vine" },
    { "rares", 32422, "Tukemuth" },
  }
  local gone = 0
  for _, want in ipairs(UNLISTED) do
    if (g["meta"][want[1]] or {})[want[2]] == nil then
      gone = gone + 1
      fail("meta.%s: %s (%d) had coords but no list entry -- it must be listed here", want[1], want[3], want[2])
    end
  end
  if gone == 0 then ok("meta: all %d entities pfQuest could place but never listed are on a list now", table.getn(UNLISTED)) end

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
        data = {
          -- an object the base database already knows, with a coordinate
          [181555] = { coords = { { 10, 20, 3483, 300 } }, quest = true },
          -- a rebuilt object with one coordinate in a rebuilt zone and one
          -- outside it: the first must go, the second must survive
          [1731] = { coords = { { 10, 10, 12, 300 }, { 90, 90, 3483, 300 } } },
          -- and one that is NOT rebuilt, sitting in a rebuilt zone: untouched
          [9999] = { coords = { { 55, 55, 12, 300 } } },
        },
        enUS = { [181555] = "Fel Iron Deposit" },
      },
      units = {
        data = {
          [32517] = { coords = { { 11, 21, 3711, 600 } }, lvl = "76", rnk = "2" },
          -- a rare the server never spawns: its LIST entry goes, its coords stay
          [10819] = { coords = { { 60, 40, 139, 0 } } },
        },
        enUS = { [32517] = "Loque'nahak" },
      },
      meta = {
        herbs = {}, mines = { [-181555] = 300 }, chests = {}, fish = {},
        -- 10819 is the stale one, 572 (Leprithus, event-spawned) must survive
        rares = { [10819] = 55, [572] = 30 },
        -- what pfQuest actually ships under "banker": barkeeps and vendors
        banker = { [233] = "A", [274] = "A" },
      },
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
        rebuild = {
          zones = { [12] = true },
          objects = { [1731] = { { 40, 41, 12, 300 } } },
        },
        stale_rares = { [10819] = true },
        bankers = { [2455] = "A" },
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

      local rebuilt = pfDB.objects.data[1731].coords
      local inzone, outzone, fresh = 0, 0, 0
      for _, c in pairs(rebuilt) do
        if c[3] == 12 and c[1] == 10 then inzone = inzone + 1 end
        if c[3] == 3483 then outzone = outzone + 1 end
        if c[3] == 12 and c[1] == 40 then fresh = fresh + 1 end
      end
      if inzone == 0 then ok("rebuild merge: the shipped coordinate in a rebuilt zone is dropped")
      else fail("rebuild merge: a shipped coordinate survived in a rebuilt zone") end
      if outzone == 1 then ok("rebuild merge: the same object's coordinate outside the rebuilt zones survives")
      else fail("rebuild merge: an out-of-scope coordinate was dropped, count %d", outzone) end
      if fresh == 1 then ok("rebuild merge: the server coordinate replaces it")
      else fail("rebuild merge: the replacement coordinate is missing") end
      if pfDB.objects.data[9999] and table.getn(pfDB.objects.data[9999].coords) == 1 then
        ok("rebuild merge: an object that is not rebuilt keeps its coordinates in the same zone")
      else
        fail("rebuild merge: a non-rebuilt object in a rebuilt zone lost its coordinates")
      end

      -- issue #21: the rare that never spawns leaves the LIST, not the database
      if pfDB.meta.rares[10819] == nil then ok("stale rares: the unspawnable rare is off the Rare Mobs track")
      else fail("stale rares: 10819 is still on the rare track") end
      if pfDB.meta.rares[572] == 30 then ok("stale rares: a rare that is not listed stale stays on the track")
      else fail("stale rares: pruned a rare that was not listed") end
      if pfDB.units.data[10819] and table.getn(pfDB.units.data[10819].coords) == 1 then
        ok("stale rares: the unit keeps its coordinates, so search and quests still find it")
      else fail("stale rares: the prune removed the unit's coordinates too") end

      -- issue #29: the banker list is REPLACED, not added to. Merging would
      -- leave all 420 wrong entries in place and fix nothing.
      if pfDB.meta.banker[2455] == "A" then ok("bankers: the rebuilt list is installed")
      else fail("bankers: rebuilt entry missing, got %s", tostring(pfDB.meta.banker[2455])) end
      if pfDB.meta.banker[274] == nil and pfDB.meta.banker[233] == nil then
        ok("bankers: the shipped barkeeps and vendors are gone, the list is replaced not merged")
      else fail("bankers: a shipped non-banker survived the rebuild") end

      if pfDB.tracking335 == nil then ok("merge: frees the overlay when it is done")
      else fail("merge: left pfDB.tracking335 in memory") end
    end
  end
end

-- ---------------------------------------------------------------------------
-- The Azeroth gathering REBUILD (issue #28). This is the only part of the
-- addon that REMOVES shipped data, so it gets the most assertions: the right
-- objects, the right zones, nothing overlapping the additive path, and above
-- all the invariant the removal rests on, that none of these objects is used by
-- a quest.
-- ---------------------------------------------------------------------------
do
  local rb = g["rebuild"]
  if type(rb) ~= "table" or type(rb["zones"]) ~= "table" or type(rb["objects"]) ~= "table" then
    fail("rebuild: db/tracking335.lua has no rebuild section")
  else
    -- zones must be Azeroth only: never a zone the additive path emits into
    local bad, nz = 0, 0
    for z in pairs(rb["zones"]) do
      nz = nz + 1
      if ALLOWED_ZONES[z] and z ~= 139 then
        bad = bad + 1
        fail("rebuild: zone %d (%s) is an Outland/Northrend zone and must not be rebuilt", z, ALLOWED_ZONES[z])
      end
    end
    if bad == 0 then ok("rebuild: all %d rebuilt zones are Azeroth", nz) end

    -- coordinates: shape, range, and a zone that is actually being rebuilt
    local n, badshape, badpct, badzone = 0, 0, 0, 0
    for id, coords in pairs(rb["objects"]) do
      for _, c in pairs(coords) do
        n = n + 1
        if type(c[1]) ~= "number" or type(c[2]) ~= "number"
          or type(c[3]) ~= "number" or type(c[4]) ~= "number" or c[5] ~= nil then
          badshape = badshape + 1
        elseif c[1] < 0 or c[1] > 100 or c[2] < 0 or c[2] > 100 or c[4] < 0 then
          badpct = badpct + 1
        elseif not rb["zones"][c[3]] then
          badzone = badzone + 1
          if badzone <= 3 then fail("rebuild: object %d has a coord in zone %d, which is not being rebuilt", id, c[3]) end
        end
      end
    end
    if badshape == 0 and badpct == 0 then ok("rebuild: all %d coordinates are in-range { xPct, yPct, zone, respawn }", n)
    else fail("rebuild: %d malformed and %d out-of-range coordinates", badshape, badpct) end
    if badzone == 0 then ok("rebuild: every coordinate lands in a zone the rebuild owns") end

    -- nothing may be in BOTH the additive path and the rebuild, or a node gets two pins
    local clash = 0
    for id, coords in pairs(g["objects"]["coords"]) do
      if rb["objects"][id] then
        for _, c in pairs(coords) do
          if rb["zones"][c[3]] then
            clash = clash + 1
            if clash <= 3 then fail("rebuild: object %d is filled AND rebuilt in zone %d -- two pins per node", id, c[3]) end
          end
        end
      end
    end
    if clash == 0 then ok("rebuild: no object is both filled and rebuilt in the same zone") end

    -- Respawn must look like a spawn timer. The column next to spawntimesecs in
    -- AzerothCore's gameobject table is animprogress, which is 255 on nearly
    -- every row, and reading it by mistake put "Respawn: 4 Min 15 Sec" on every
    -- node without anything noticing. Real timers are whole tens of seconds and
    -- at least a minute; 255 is neither.
    local sane, odd = 0, 0
    for _, db in ipairs({ "rebuild", "objects" }) do
      local src = (db == "rebuild") and rb["objects"] or g["objects"]["coords"]
      for _, coords in pairs(src) do
        for _, c in pairs(coords) do
          local r = c[4]
          if r >= 60 and math.mod(r, 10) == 0 then sane = sane + 1 else odd = odd + 1 end
        end
      end
    end
    if sane > (sane + odd) * 0.9 then
      ok("rebuild: %d of %d respawn values look like real spawn timers", sane, sane + odd)
    else
      fail("rebuild: only %d of %d respawn values look like spawn timers -- wrong SQL column?", sane, sane + odd)
    end

    -- the zones players actually reported as empty or thin must come back full
    local short = 0
    for _, want in ipairs(REBUILD_MUST_COVER) do
      local zone, id, name, zonename, least = want[1], want[2], want[3], want[4], want[5]
      local cnt = 0
      if id then
        for _, c in pairs(rb["objects"][id] or {}) do
          if c[3] == zone then cnt = cnt + 1 end
        end
      else
        for _, coords in pairs(rb["objects"]) do
          for _, c in pairs(coords) do
            if c[3] == zone then cnt = cnt + 1 end
          end
        end
      end
      if cnt < least then
        short = short + 1
        fail("rebuild: %s in %s has %d nodes, expected at least %d", name, zonename, cnt, least)
      end
    end
    if short == 0 then ok("rebuild: the zones reported as empty or thin are covered") end
  end
end

-- ---------------------------------------------------------------------------
-- The invariant the removal rests on. An earlier version of this check asked
-- whether a rebuilt object was a quest objective through obj/start/end -> O,
-- got zero hits, and concluded no quest pin could be affected. That was the
-- wrong question: pfQuest pins a gathering node for a quest through the ITEM,
-- obj.I -> items[item].O, obj.IR -> itemreq, and items[item].R -> refloot.
-- Asked properly, 132 quests DO have object pins in the rebuilt zones. What has
-- to hold is not that none are touched, but that none is left with nothing.
-- ---------------------------------------------------------------------------
do
  local rb = g["rebuild"]
  pfDB = {}
  dofile("db/init.lua")
  for _, f in ipairs({ "quests", "quests-tbc", "quests-wotlk",
                       "items", "items-tbc", "items-wotlk", "refloot",
                       "objects", "objects-tbc", "objects-wotlk" }) do
    dofile("db/" .. f .. ".lua")
  end
  local function patch(base, diff)
    for k, v in pairs(diff or {}) do
      if v == "_" then base[k] = nil else base[k] = v end
    end
  end
  for _, db in ipairs({ "quests", "items", "objects" }) do
    patch(pfDB[db]["data"], pfDB[db]["data-tbc"])
    patch(pfDB[db]["data"], pfDB[db]["data-wotlk"])
  end

  local function objectsForItem(item, out)
    local it = pfDB["items"]["data"][item]
    if not it then return end
    for o in pairs(it["O"] or {}) do out[o] = true end
    for ref in pairs(it["R"] or {}) do
      local rl = pfDB["refloot"]["data"] and pfDB["refloot"]["data"][ref]
      for o in pairs(rl and rl["O"] or {}) do out[o] = true end
    end
  end

  local seen, touched, zeroed = 0, 0, 0
  for _, q in pairs(pfDB["quests"]["data"]) do
    seen = seen + 1
    local objs = {}
    for _, key in ipairs({ "obj", "start", "end" }) do
      local t = q[key]
      if type(t) == "table" then
        for _, o in pairs(t["O"] or {}) do objs[o] = true end
        for _, i in pairs(t["I"] or {}) do objectsForItem(i, objs) end
        for _, i in pairs(t["IR"] or {}) do objectsForItem(math.abs(i), objs) end
      end
    end
    local before, after, hit = 0, 0, false
    for o in pairs(objs) do
      local e = pfDB["objects"]["data"][o]
      for _, c in pairs(e and e["coords"] or {}) do
        before = before + 1
        if rb["objects"][o] and rb["zones"][c[3]] then hit = true else after = after + 1 end
      end
      for _, _c in pairs(rb["objects"][o] or {}) do after = after + 1 end
    end
    if hit then
      touched = touched + 1
      if before > 0 and after == 0 then zeroed = zeroed + 1 end
    end
  end
  if seen < 1000 then fail("rebuild: only %d quests loaded, the quest check is not meaningful", seen) end
  if zeroed == 0 then
    ok("rebuild: %d quests have object pins in the rebuilt zones and not one is left with zero", touched)
  else
    fail("rebuild: %d quests would be left with NO object pins at all", zeroed)
  end
end

-- ---------------------------------------------------------------------------
-- The two list repairs: rares that cannot spawn (issue #21) and the banker
-- track (issue #29). Both are checked against the SHIPPED lists, because both
-- are only worth anything if they actually change what pfQuest ends up with --
-- a stale-rare id that is not on the rare track prunes nothing, and a banker
-- list that happens to match the shipped one fixes nothing.
-- ---------------------------------------------------------------------------
do
  pfDB = {}
  dofile("db/init.lua")
  for _, f in ipairs({ "units", "units-tbc", "units-wotlk", "units-wotlk-sw335",
                       "units-wotlk-icecrown335", "units-wotlk-acfill335",
                       "meta", "meta-tbc" }) do
    dofile("db/" .. f .. ".lua")
  end
  for _, d in ipairs({ "data-tbc", "data-wotlk" }) do
    for k, v in pairs(pfDB["units"][d] or {}) do
      if v == "_" then pfDB["units"]["data"][k] = nil else pfDB["units"]["data"][k] = v end
    end
  end
  -- meta patches whole TRACKS, not entries: meta-tbc's banker table replaces
  -- meta's outright, which is why the shipped banker list is meta-tbc's.
  for track, ids in pairs(pfDB["meta-tbc"] or {}) do pfDB["meta"][track] = ids end
  local units, meta = pfDB["units"]["data"], pfDB["meta"]

  local function placeable(id)
    local e = units[id]
    return e and e["coords"] and next(e["coords"]) ~= nil
  end

  -- ------------------------------------------------------------- stale rares
  local stale = g["stale_rares"]
  if type(stale) ~= "table" then
    fail("stale rares: db/tracking335.lua has no stale_rares section")
  else
    local n, notlisted, noncoord, badkey = 0, 0, 0, 0
    for id, v in pairs(stale) do
      n = n + 1
      if type(id) ~= "number" or id <= 0 or v ~= true then badkey = badkey + 1 end
      if meta["rares"][id] == nil then
        notlisted = notlisted + 1
        if notlisted <= 5 then fail("stale rares: %d is not on the shipped rare track, pruning it does nothing", id) end
      end
      if not placeable(id) then noncoord = noncoord + 1 end
    end
    if n == 0 then fail("stale rares: the section is empty, issue #21 would still show both mobs") end
    if badkey == 0 and n > 0 then ok("stale rares: %d entries, all positive unit ids set to true", n) end
    if notlisted == 0 and n > 0 then ok("stale rares: every one of them is on the shipped rare track today") end
    if noncoord == 0 and n > 0 then ok("stale rares: every one of them draws a pin today, so removing it changes the map")
    else if noncoord > 0 then fail("stale rares: %d have no coordinates and never drew a pin", noncoord) end end
    -- the reported pair has to be in there
    for _, id in ipairs({ 10819, 10820 }) do
      if stale[id] then ok("stale rares: %d is pruned (issue #21)", id)
      else fail("stale rares: %d is still advertised", id) end
    end
    -- and the event-only case must NOT be: Leprithus has no ordinary spawn row
    -- but is spawned by a game event, so his pin is right.
    if not stale[572] then ok("stale rares: Leprithus (event-spawned) is left alone")
    else fail("stale rares: pruned Leprithus, who does spawn during a game event") end
    -- a regeneration that lost the spawn table would prune the whole track
    if n < 25 then ok("stale rares: %d pruned, far short of the whole track", n)
    else fail("stale rares: %d pruned -- that is not a handful of ghosts", n) end
  end

  -- ----------------------------------------------------------------- bankers
  local bankers = g["bankers"]
  if type(bankers) ~= "table" then
    fail("bankers: db/tracking335.lua has no bankers section")
  else
    local n, badkey, badval, noncoord, kept = 0, 0, 0, 0, 0
    for id, v in pairs(bankers) do
      n = n + 1
      if type(id) ~= "number" or id <= 0 then badkey = badkey + 1 end
      -- SearchMetaRelation matches this with string.find(value, faction), so it
      -- has to be one of pfQuest's own faction strings and never a number
      if v ~= "A" and v ~= "H" and v ~= "AH" then
        badval = badval + 1
        if badval <= 5 then fail("bankers: %d has value %s, expected \"A\", \"H\" or \"AH\"", id, tostring(v)) end
      end
      if not placeable(id) then
        noncoord = noncoord + 1
        if noncoord <= 5 then fail("bankers: %d has no coordinates, it would list a banker with no pin", id) end
      end
      if meta["banker"][id] then kept = kept + 1 end
    end
    if n < 30 then fail("bankers: only %d entries, every capital and neutral hub has one", n) end
    if badkey == 0 then ok("bankers: %d entries, all positive unit ids", n) end
    if badval == 0 then ok("bankers: every value is an A/H/AH string, the type SearchMetaRelation needs") end
    if noncoord == 0 then ok("bankers: every one of them has a coordinate to draw") end
    -- the point of the rebuild: the shipped list is not a banker list. If the
    -- new one mostly agrees with it, something reverted.
    if kept <= n * 0.1 then
      ok("bankers: %d of %d overlap the shipped list -- it really is a different list", kept, n)
    else
      fail("bankers: %d of %d were already on the shipped list, the rebuild did nothing", kept, n)
    end
    -- spot checks in both directions: real bankers in, the reported false
    -- positives out. 233 Farmer Saldean, 274 Barkeep Hann and 295 Innkeeper
    -- Farley are all on pfQuest's shipped banker list and none is a banker.
    local missing = 0
    for _, id in ipairs({ 2455, 2625, 8123, 19246 }) do
      if not bankers[id] then missing = missing + 1; fail("bankers: real banker %d is missing", id) end
    end
    if missing == 0 then ok("bankers: the capital, Dalaran, Booty Bay and Shattrath bankers are all there") end
    local wrong = 0
    for _, id in ipairs({ 233, 274, 295 }) do
      if bankers[id] then wrong = wrong + 1; fail("bankers: %d is not a banker but is on the new list", id) end
    end
    if wrong == 0 then ok("bankers: the barkeeps, farmers and innkeepers pfQuest listed are gone") end
  end
end

-- ---------------------------------------------------------------------------
-- node icons (issue #23). Without an icons.lua entry a node falls back to the
-- generic profession icon, so every WotLK ore drew a mining pick. Two things
-- to hold: every node we list has an icon, and every icon path resolves to a
-- file that is actually shipped -- a typo there renders nothing at all, and
-- nothing else in the addon would notice.
-- ---------------------------------------------------------------------------
do
  local src = io.open("icons.lua"):read("*a")
  local registered, paths, n = {}, {}, 0
  for id, path in string.gfind(src, "AddCustomIcon%((-?%d+), \"([^\"]+)\"") do
    registered[tonumber(id)] = path
    paths[path] = true
    n = n + 1
  end
  if n < 100 then fail("icons: only %d registrations parsed out of icons.lua", n) end

  local badfile = 0
  for path in pairs(paths) do
    -- icons.lua writes Lua-escaped backslashes; on disk it is a .tga under img/
    local file = string.gsub(path, "[\\]+", "/") .. ".tga"
    local fh = io.open(file, "rb")
    if fh then
      fh:close()
    else
      badfile = badfile + 1
      fail("icons: %s is registered but %s is not shipped", path, file)
    end
  end
  if badfile == 0 then ok("icons: all %d registered textures exist on disk", n) end

  local noicon = 0
  for track, entries in pairs(g["meta"]) do
    if track ~= "fish" and track ~= "rares" then
      for id in pairs(entries) do
        if not registered[id] then
          noicon = noicon + 1
          if noicon <= 6 then
            fail("icons: %s %d has no icon, it would draw the generic %s pick", track, id, track)
          end
        end
      end
    end
  end
  if noicon == 0 then ok("icons: every herb, ore and chest we list has its own icon") end
end

-- ---------------------------------------------------------------------------
-- Eastern Plaguelands rectangle correction (issue #18). Blizzard rescaled the
-- EPL map during Wrath; pfQuest's data is still on the 1.12 rectangle, so every
-- node there sat about 7.9% of the map from where it really is. database.lua
-- converts them during the packing walk. Pin the conversion and the zone size
-- that has to match it.
-- ---------------------------------------------------------------------------
do
  local src = io.open("database.lua"):read("*a")

  -- it has to actually run: the corrector is only useful if the packing loop
  -- calls it, and nothing else would notice if that call were dropped
  -- ORDER. The tracking335 overlay already stores its EPL nodes on the 3.3.5a
  -- rectangle, so the correction has to run BEFORE that overlay merges. Running
  -- it after -- which is what folding it into PackCoords did -- converts those
  -- nodes a second time and lands every one about 7.2% out. Both halves of that
  -- mistake are pinned here.
  local packbody = string.match(src, "local function packEntryCoords.-\nend")
  if packbody and string.find(packbody, "correctEPL") then
    fail("EPL: PackCoords applies the correction, which double-corrects the tracking335 nodes")
  else
    ok("EPL: the correction is not folded into the packing walk")
  end
  local atcall = string.find(src, "\ncorrectEPLDatabase%(pfDB%)")
  local atmerge = string.find(src, "\nif pfDB%[\"tracking335\"%] then")
  if atcall and atmerge and atcall < atmerge then
    ok("EPL: the correction runs before the tracking335 overlay merges")
  else
    fail("EPL: the correction runs at %s and the tracking335 merge at %s -- it must come first",
         tostring(atcall), tostring(atmerge))
  end

  -- and behaviourally, with the two real blocks run in the order the assertion
  -- above requires: a shipped coordinate is corrected, an overlay coordinate is
  -- left exactly as it was generated
  local eplblock = string.match(src, "(local EPL_ZONE.-\nend)\npfDatabase%.CorrectEPLDatabase")
  local mergeblock = string.match(src, "\n(if pfDB%[\"tracking335\"%] then\n.-\n  pfDB%[\"tracking335\"%] = nil\nend)\n")
  local chunk = eplblock and mergeblock
    and loadstring("local floor = math.floor\nlocal pfDatabase = {}\n" .. eplblock
                   .. "\ncorrectEPLDatabase(pfDB)\n" .. mergeblock)
  if not chunk then
    fail("EPL: could not lift the correction and the merge to run them in order")
  else
    pfDB = {
      locales = { enUS = "English" },
      objects = {
        data = { [2047] = { coords = { { 50, 50, 139, 300 } } } },
        enUS = { [2047] = "Truesilver Deposit" },
      },
      units = { data = {}, enUS = {} },
      areatrigger = { data = {} },
      meta = { herbs = {}, mines = {}, chests = {}, fish = {}, rares = {} },
      tracking335 = {
        objects = { coords = { [324] = { { 60, 40, 139, 600 } } }, names = {} },
        units = { coords = {}, names = {}, info = {} },
        meta = { mines = { [-324] = 275 } },
      },
    }
    local okc, err = pcall(chunk)
    if not okc then
      fail("EPL: running the correction and the merge in order errored -> %s", tostring(err))
    else
      local shipped = pfDB.objects.data[2047].coords[1]
      if math.abs(shipped[1] - 45.48) < 0.01 and math.abs(shipped[2] - 44.46) < 0.01 then
        ok("EPL: a coordinate pfQuest ships is converted onto the 3.3.5a rectangle")
      else
        fail("EPL: a shipped coordinate became (%s, %s), expected (45.48, 44.46)", shipped[1], shipped[2])
      end
      local added = pfDB.objects.data[324].coords[1]
      if added[1] == 60 and added[2] == 40 then
        ok("EPL: an overlay coordinate is left exactly as it was generated")
      else
        fail("EPL: an overlay coordinate was moved to (%s, %s) -- it is corrected twice", added[1], added[2])
      end
    end
  end

  local block = string.match(src, "(local EPL_ZONE.-\nend)\npfDatabase%.CorrectEPLCoord")
  local chunk = block and loadstring("local floor = math.floor\n" .. block .. "\nreturn correctEPL")
  local f = chunk and chunk()
  if not f then
    fail("EPL: could not lift correctEPL out of database.lua")
  else
    -- a coordinate in any other zone must come back untouched
    local other = { 50, 50, 1519, 300 }
    f(other)
    if other[1] == 50 and other[2] == 50 then ok("EPL: coordinates in other zones are left alone")
    else fail("EPL: a zone-1519 coordinate was rewritten to %s, %s", other[1], other[2]) end

    -- and the conversion itself, on three points spanning the map
    local cases = { { 50, 50, 45.48, 44.46 }, { 10, 90, 7.06, 82.87 } }
    local bad = 0
    for i = 1, table.getn(cases) do
      local c = cases[i]
      local tup = { c[1], c[2], 139, 300 }
      f(tup)
      if math.abs(tup[1] - c[3]) > 0.01 or math.abs(tup[2] - c[4]) > 0.01 then
        bad = bad + 1
        fail("EPL: (%s, %s) converted to (%s, %s), expected (%s, %s)",
             c[1], c[2], tup[1], tup[2], c[3], c[4])
      end
    end
    if bad == 0 then ok("EPL: the 1.12 rectangle converts onto the 3.3.5a one") end

    -- no shipped EPL coordinate may be pushed off the map by the conversion
    pfDB = {}
    dofile("db/init.lua")
    for _, fn in ipairs({ "objects", "objects-tbc", "objects-wotlk", "objects-wotlk-sw335",
                          "units", "units-tbc", "units-wotlk", "units-wotlk-icecrown335",
                          "units-wotlk-acfill335", "areatrigger", "areatrigger-tbc" }) do
      dofile("db/" .. fn .. ".lua")
    end
    local off, seen = 0, 0
    for _, db in ipairs({ "objects", "units", "areatrigger" }) do
      for _, key in ipairs({ "data", "data-tbc", "data-wotlk" }) do
        for _, e in pairs(pfDB[db][key] or {}) do
          for _, c in pairs(e.coords or {}) do
            if c[3] == 139 then
              local tup = { c[1], c[2], c[3], c[4] }
              f(tup)
              seen = seen + 1
              if tup[1] < 0 or tup[1] > 100 or tup[2] < 0 or tup[2] > 100 then off = off + 1 end
            end
          end
        end
      end
    end
    if seen < 1000 then fail("EPL: only %d coordinates found, expected thousands", seen) end
    if off == 0 then ok("EPL: all %d coordinates stay on the map after conversion", seen)
    else fail("EPL: %d coordinates land outside 0..100 after conversion", off) end
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
  for _, want in ipairs(NEEDS_MINIMAP_ENTRY) do
    local z, width = want[1], want[2]
    local s = sizes[z]
    if not s then
      bad = bad + 1
      fail("minimap: zone %d has nodes but no pfDB.minimap rectangle -- no minimap dots", z)
    elseif math.abs(s[1] - width) > width * 0.01 then
      bad = bad + 1
      fail("minimap: zone %d is %.2f wide, the rectangle its coordinates use is %.2f", z, s[1], width)
    elseif math.abs(s[1] / s[2] - 1.5) > 0.01 then
      bad = bad + 1
      fail("minimap: zone %d is %.1f x %.1f, ratio %.3f -- every WorldMapArea is 3:2",
           z, s[1], s[2], s[1] / s[2])
    end
  end
  if bad == 0 then
    ok("minimap: all %d rectangle-placed zones carry the matching 3:2 size",
       table.getn(NEEDS_MINIMAP_ENTRY))
  end
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
