-- Runtime check: build our own UI objects and DRIVE them, under the 3.3.5a stub.
--
-- Why this exists: tools/loadall-style checks LOAD every file and confirm it parses,
-- but they never build a tracker row, so a method that does not exist on one of our
-- objects is invisible to them. That is exactly how v1.0.30 shipped
--   tracker.lua:523: attempt to call method 'Show' (a nil value)
-- with a green parse and a green load. The progress bar is a plain Lua table, not a
-- frame, so it only has the methods theme.lua defines -- and Hide existed while Show
-- never did.
--
-- So: for each of our own objects, declare the methods the addon actually calls on it,
-- assert they exist, then run the real call sequence and check the result.
--
-- Usage: lua5.1 tools/runtimecheck335.lua   (from the addon root)

local failures, checks = 0, 0
local function fail(fmt, ...) failures = failures + 1; print("  FAIL  " .. string.format(fmt, ...)) end
local function ok(fmt, ...) checks = checks + 1; print("  ok    " .. string.format(fmt, ...)) end

local function requireMethods(obj, objname, methods)
  for _, m in ipairs(methods) do
    if type(obj[m]) ~= "function" then
      fail("%s is missing :%s() -- something calls it", objname, m)
    else
      checks = checks + 1
    end
  end
end

local function drive(label, fn)
  local okc, err = pcall(fn)
  if okc then ok(label) else fail("%s -> %s", label, tostring(err)) end
end

-- ---------------------------------------------------------------------------
-- minimal 3.3.5a-shaped widget stub (textures track their own width so fill
-- arithmetic is actually exercised, not just called)
-- ---------------------------------------------------------------------------
local function mkTexture()
  local t = { w = 0, shown = true }
  local noop = function() end
  return setmetatable(t, { __index = function(_, k)
    if k == "SetWidth" then return function(s, v) s.w = v end end
    if k == "GetWidth" then return function(s) return s.w end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    return noop
  end })
end
local parent = { CreateTexture = function() return mkTexture() end }
_G.pfQuest_config = {}
_G.GetLocale = function() return "enUS" end
_G.IsAddOnLoaded = function() return nil end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
_G.UIParent = _G.CreateFrame()

print("== pfQuest runtime check (3.3.5a stub) ==")

-- ---------------------------------------------------------------------------
-- theme.lua :: progress bar  (the object that broke in v1.0.30)
-- ---------------------------------------------------------------------------
dofile("theme.lua")
local T = _G.pfQuestTheme
if not T or not T.CreateProgressBar then
  fail("pfQuestTheme.CreateProgressBar missing")
else
  local bar = T.CreateProgressBar(parent, 3)
  -- every method tracker.lua calls on a bar
  requireMethods(bar, "progress bar", { "SetPoint", "SetProgress", "Refresh", "SetEnabled", "Hide" })

  -- ButtonAdd / Reset path: enable, then clear
  drive("bar: reset path (SetEnabled + SetProgress(nil))", function()
    bar:SetEnabled(pfQuest_config["trackerbars"] ~= "0")
    bar:SetProgress(nil)
  end)

  -- percentage path, then the post-layout refresh the tracker performs
  drive("bar: percentage path + post-layout Refresh", function()
    bar:SetEnabled(pfQuest_config["trackerbars"] ~= "0")
    bar:SetProgress(1.0, 1, 1, 1)
    bar.track.w = 180
    bar:Refresh()
  end)
  if bar.fill.w == 180 then ok("bar: 100%% fills the full track (180px)")
  else fail("bar: 100%% filled %s px, expected 180 (the v1.0.30 sliver bug)", tostring(bar.fill.w)) end

  drive("bar: 25%% fills a quarter", function()
    bar:SetProgress(0.25); bar:Refresh()
  end)
  if bar.fill.w == 45 then ok("bar: 25%% fills 45px")
  else fail("bar: 25%% filled %s px, expected 45", tostring(bar.fill.w)) end

  -- bars turned off
  pfQuest_config["trackerbars"] = "0"
  drive("bar: disabled path", function()
    bar:SetEnabled(pfQuest_config["trackerbars"] ~= "0")
    bar:SetProgress(1.0, 1, 1, 1)
    bar:Refresh()
  end)
  if bar.track.shown == false and bar.fill.shown == false then ok("bar: disabled hides both textures")
  else fail("bar: disabled left track=%s fill=%s shown", tostring(bar.track.shown), tostring(bar.fill.shown)) end
  pfQuest_config["trackerbars"] = nil
end

-- ---------------------------------------------------------------------------
-- Invalid POI names in the tracking lists (issue #16). The merged database
-- carries internal server NPCs -- the "[DND] TAR Pedestal" set spawns in every
-- capital and rides the vendor, repair AND banker lists -- so SearchMetaRelation
-- filters them by name. Pin the predicate: junk out, real POIs untouched.
-- ---------------------------------------------------------------------------
do
  -- database.lua cannot be loaded here (it merges the whole DB at load time), so
  -- lift the REAL predicate out of the real source and run that -- editing the
  -- patterns in database.lua is what this check must notice.
  local src = io.open("database.lua"):read("*a")
  local block = string.match(src, "(local invalidnames.-\nend)\npfDatabase%.IsInvalidPOIName")
  local chunk = block and loadstring(block .. "\nreturn IsInvalidPOIName")
  local f = chunk and chunk()
  if not f then
    fail("meta filter: could not lift IsInvalidPOIName out of database.lua")
  else
    local junk = {
      "[DND] TAR Pedestal - Accessories", "[DND] TAR Pedestal - Trainer, Priest",
      "Spirit Healer (DND)", "test spirit healer (DND)", "[UNUSED] Grall Twomoons",
      "[UNUSED] [PH] Berail Spiritwhisper", "Yor <UNUSED>", "TEST Resist Gear",
      "Netherstorm Rare Chimaera UNUSED", "Waypoint (Only GM can see it)",
    }
    local real = {
      "Innkeeper Gryshka", "Doras", "Thrall", "Gryphon Master Talonaxe",
      "Auctioneer Fitch", "Bank of Ironforge", "Ancient Gem", "Protector Bialon",
      "Grimtak", "Karolek", "Sana Shieldscar", "Mailbox",
    }
    local bad = 0
    for i = 1, table.getn(junk) do
      if not f(junk[i]) then fail("meta filter: junk NOT caught -> %s", junk[i]); bad = bad + 1 end
    end
    if bad == 0 then ok("meta filter: all %d internal names rejected", table.getn(junk)) end
    bad = 0
    for i = 1, table.getn(real) do
      if f(real[i]) then fail("meta filter: real POI wrongly rejected -> %s", real[i]); bad = bad + 1 end
    end
    if bad == 0 then ok("meta filter: all %d legitimate POI names kept", table.getn(real)) end
    if not f(nil) then ok("meta filter: nil name is not a match") else fail("meta filter: nil matched") end
  end
end

-- ---------------------------------------------------------------------------
-- Multiple things standing on one spot (issue #22). A spawn point can produce
-- more than one node type -- the server pools Cobalt with Rich Cobalt and
-- Saronite with Titanium at identical coordinates -- but the pin can only be
-- described by one of them, so the rest were invisible and whole Northrend
-- zones read as a single ore. Pin the collector the tooltip uses.
-- ---------------------------------------------------------------------------
do
  -- map.lua cannot be loaded here (it builds frames at load time), so lift the
  -- REAL function out of the real source and run that -- editing it in map.lua
  -- is what this check must notice.
  local src = io.open("map.lua"):read("*a")
  local block = string.match(src, "(local function collectextras.-\nend)\npfMap%.CollectExtraSpawns")
  local chunk = block and loadstring(block .. "\nreturn collectextras")
  local f = chunk and chunk()
  if not f then
    fail("extra spawns: could not lift collectextras out of map.lua")
  else
    local node = {
      ["Cobalt Deposit"] = { spawn = "Cobalt Deposit", level = "350 [Mining]" },
      ["Rich Cobalt Deposit"] = { spawn = "Rich Cobalt Deposit", level = "375 [Mining]" },
      ["Titanium Vein"] = { spawn = "Titanium Vein", level = "450 [Mining]" },
    }
    local extras = f(node, "Cobalt Deposit")
    if extras and table.getn(extras) == 2 then ok("extra spawns: the two other nodes on the spot are returned")
    else fail("extra spawns: got %s entries, expected 2", extras and table.getn(extras) or "nil") end
    if extras and extras[1].spawn == "Rich Cobalt Deposit" and extras[2].spawn == "Titanium Vein" then
      ok("extra spawns: stable alphabetical order, not table order")
    else
      fail("extra spawns: order was %s, %s", extras and extras[1] and extras[1].spawn,
           extras and extras[2] and extras[2].spawn)
    end
    if extras and extras[1].level == "375 [Mining]" then ok("extra spawns: each carries its own skill requirement")
    else fail("extra spawns: level came through as %s", extras and extras[1] and tostring(extras[1].level)) end

    -- the header's own node must never be repeated
    local only = f({ ["Cobalt Deposit"] = { spawn = "Cobalt Deposit" } }, "Cobalt Deposit")
    if only == nil then ok("extra spawns: a spot holding only the pin's own node adds nothing")
    else fail("extra spawns: the pin's own node was listed again") end

    -- several quests on the SAME mob must collapse to one name, not one per quest
    local quests = {
      ["Quest A"] = { spawn = "Fizzcrank Mechagnome", quest = "Quest A" },
      ["Quest B"] = { spawn = "Fizzcrank Mechagnome", quest = "Quest B" },
      ["Quest C"] = { spawn = "Scourge Ghoul", quest = "Quest C" },
    }
    -- header is a THIRD name, so both mobs are extras and the repeat must collapse
    local q = f(quests, "Cobalt Deposit")
    if q and table.getn(q) == 2 and q[1].spawn == "Fizzcrank Mechagnome"
      and q[2].spawn == "Scourge Ghoul" then
      ok("extra spawns: repeated names collapse, so two quests on one mob list it once")
    else
      fail("extra spawns: quest case returned %s entries (%s)", q and table.getn(q) or "nil",
           q and q[1] and q[1].spawn or "-")
    end

    -- entries with no spawn name (quest-only markers) must not produce blanks
    local blanks = f({ ["Some Quest"] = { quest = "Some Quest" } }, "Cobalt Deposit")
    if blanks == nil then ok("extra spawns: entries with no name are skipped")
    else fail("extra spawns: a nameless entry was listed") end

    if f(nil, "x") == nil then ok("extra spawns: an empty node table is handled")
    else fail("extra spawns: nil node table did not return nil") end
  end
end

-- ---------------------------------------------------------------------------
-- Minimap pin frame level (issue #15). A minimap pin is a CHILD of the minimap,
-- and a child below its parent's frame level renders behind the parent's own
-- textures. Upstream used a fixed 4 + layer, which only works while the minimap
-- sits near level 0. ElvUI puts it at 10, and the reporter's own output showed
-- pins=14 shown=14 with nothing visible. Pin the rule that the level is relative
-- to whatever the minimap is actually at.
-- ---------------------------------------------------------------------------
do
  local src = io.open("map.lua"):read("*a")
  local block = string.match(src, "(local function minimapNodeLevel.-\nend)\npfMap%.MinimapNodeLevel")
  local chunk = block and loadstring("pfMap = pfMap or {}\n" .. block .. "\nreturn minimapNodeLevel")
  local f = chunk and chunk()
  if not f then
    fail("minimap level: could not lift minimapNodeLevel out of map.lua")
  else
    -- Blizzard's minimap, near the bottom of the stack
    pfMap = { mlevel = 0 }
    if f(0) > 0 then ok("minimap level: a pin sits above a level-0 minimap")
    else fail("minimap level: pin at %d is not above a level-0 minimap", f(0)) end

    -- ElvUI's, at 10: every layer must still clear it, which the old 4 + layer did not
    pfMap = { mlevel = 10 }
    local worst, bad = nil, 0
    for layer = 0, 20 do
      local lvl = f(layer)
      if lvl <= 10 then bad = bad + 1; worst = worst or layer end
    end
    if bad == 0 then ok("minimap level: every layer clears a level-10 minimap (ElvUI)")
    else fail("minimap level: %d layers still sit at or below a level-10 minimap, from layer %s", bad, tostring(worst)) end

    -- and it must track the minimap rather than assume a number
    pfMap = { mlevel = 200 }
    if f(0) > 200 then ok("minimap level: it follows the minimap wherever another addon puts it")
    else fail("minimap level: pin at %d does not clear a level-200 minimap", f(0)) end

    -- higher layers must still stack above lower ones
    pfMap = { mlevel = 10 }
    if f(3) > f(1) then ok("minimap level: higher layers still stack above lower ones")
    else fail("minimap level: layer 3 (%d) does not sit above layer 1 (%d)", f(3), f(1)) end

    -- no cached level yet: fall back to asking the frame, not to zero
    pfMap = { drawlayer = { GetFrameLevel = function() return 10 end } }
    if f(0) > 10 then ok("minimap level: with no cached level it asks the minimap directly")
    else fail("minimap level: first-call fallback gave %d for a level-10 minimap", f(0)) end

    -- the upstream constant must be gone from the minimap path, and the world
    -- map must still keep its own fixed level
    if string.find(src, 'obj == "minimap" and 4') then
      fail("minimap level: the minimap path is back on the fixed 4 + layer, which ElvUI sits above")
    else
      ok("minimap level: the minimap path no longer uses a fixed constant")
    end
    if string.find(src, "frame:SetFrameLevel%(112 %+ frame%.layer%)") then
      ok("minimap level: the world map keeps its own fixed level")
    else
      fail("minimap level: the world map path no longer uses its fixed level")
    end
  end
end

-- ---------------------------------------------------------------------------
-- The indoor/outdoor probe (issue #15). It detects indoors by NUDGING the
-- minimap zoom and reading it back. Two things have to hold: it must put the
-- zoom back exactly, and the MINIMAP_UPDATE_ZOOM its own SetZoom fires must not
-- dirty the cache it is filling, or it re-runs every frame and storms an event
-- other minimap addons react to.
-- ---------------------------------------------------------------------------
do
  local src = io.open("map.lua"):read("*a")

  -- a fake minimap that clamps SetZoom the way the client does, and a watcher
  -- wired exactly like map.lua's
  local zoom, events = 0, 0
  local dirty, probing = false, nil
  local drawlayer = {
    GetZoom = function() return zoom end,
    SetZoom = function(_, v)
      if v < 0 then v = 0 elseif v > 5 then v = 5 end
      zoom = v
      events = events + 1
      if not probing then dirty = true end   -- mirrors indoorwatch:OnEvent
    end,
  }

  local block = string.match(src, "(local function minimap_indoor_probe.-\nend)")
  local cvars = { minimapZoom = "3", minimapInsideZoom = "3" }
  local env = {
    pfMap = { drawlayer = drawlayer },
    GetCVar = function(k) return cvars[k] end,
    tonumber = tonumber, type = type,
  }
  local chunk = block and loadstring(
    "local indoorprobing\n" ..
    "local function setprobing(v) indoorprobing = v end\n" ..
    block .. "\nreturn minimap_indoor_probe, function() return indoorprobing end")
  if not chunk then
    fail("indoor probe: could not lift minimap_indoor_probe out of map.lua")
  else
    setfenv(chunk, setmetatable(env, { __index = _G }))
    local probe, getflag = chunk()
    -- the lifted copy sets its OWN local flag, so mirror it into the fake watcher
    local realprobe = probe
    probe = function()
      probing = true
      local r = realprobe()
      probing = nil
      return r
    end

    for _, start in ipairs({ 0, 1, 3, 5 }) do
      zoom = start
      probe()
      if zoom ~= start then
        fail("indoor probe: zoom started at %d and ended at %d", start, zoom)
      else
        checks = checks + 1
      end
    end
    ok("indoor probe: the zoom is restored exactly, including at both ends of the range")

    -- and the source must actually carry the guard, in both places
    if string.find(src, "indoorprobing") and string.find(src, "if indoorprobing then") then
      ok("indoor probe: its own zoom events are ignored, so the cache holds")
    else
      fail("indoor probe: no guard against the MINIMAP_UPDATE_ZOOM it fires itself")
    end

    -- the old arithmetic restore is what broke at the range ends: prove the
    -- shipped code no longer does GetZoom() + tempzoom
    if string.find(src, "tempzoom") then
      fail("indoor probe: still restoring the zoom by arithmetic, which clamping breaks")
    else
      ok("indoor probe: no arithmetic restore left in the source")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Faction on the map tooltip (issue #31). Several rares belong to one faction
-- and cannot be fought by the other. Two halves have to hold: the search
-- functions have to put units[id].fac on the node, and the tooltip has to show
-- it only when it names one side.
--
-- The sharp part is not the display, it is the ASSIGNMENT. SearchMetaRelation
-- and the quest walk reuse ONE meta table for every entity they visit, so a
-- faction written for one unit and not cleared for the next would label an
-- unrelated node -- and with 9979 units carrying a fac, that would be most of
-- them.
-- ---------------------------------------------------------------------------
do
  local src = io.open("database.lua"):read("*a")
  local mob = string.match(src, "\n(function pfDatabase:SearchMobID.-\nend)\n")
  local obj = string.match(src, "\n(function pfDatabase:SearchObjectID.-\nend)\n")
  if not mob or not obj then
    fail("faction: could not lift SearchMobID/SearchObjectID out of database.lua")
  else
    local nodes = {}
    local env = {
      pfDatabase = { BuildQuestDescription = function() return "" end,
                     SearchObjectSkill = function() return nil, nil end },
      -- called as pfMap:AddNode(meta), so the meta table is the SECOND argument
      pfMap = { AddNode = function(_, m)
        -- AddNode copies the meta table key by key; mirror that, or every node
        -- would alias the one table and the leak this checks for would vanish
        local copy = {}
        for k, v in pairs(m) do copy[k] = v end
        table.insert(nodes, copy)
      end },
      pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end }),
      pfDB = { units = { loc = { [1] = "Faction Rare", [2] = "Plain Rare" } },
               objects = { loc = { [3] = "A Chest" } } },
      UNKNOWN = "Unknown",
      SecondsToTime = function(s) return tostring(s) end,
      units = {
        [1] = { fac = "A", lvl = "60", coords = { { 10, 10, 139, 300 } } },
        [2] = { lvl = "60", coords = { { 20, 20, 139, 300 } } },
      },
      objects = { [3] = { coords = { { 30, 30, 139, 300 } } } },
    }
    local chunk = loadstring(mob .. "\n" .. obj)
    setfenv(chunk, setmetatable(env, { __index = _G }))
    chunk()

    -- ONE shared meta table, walked the way SearchMetaRelation walks a track.
    -- The faction-carrying unit goes FIRST and both a factionless object and a
    -- factionless unit follow it, so either one inheriting it is caught.
    local meta = {}
    env.pfDatabase:SearchMobID(1, meta)
    env.pfDatabase:SearchObjectID(3, meta)
    env.pfDatabase:SearchMobID(2, meta)

    if nodes[1] and nodes[1].faction == "A" then ok("faction: a unit's fac reaches the node")
    else fail("faction: the node has faction=%s", tostring(nodes[1] and nodes[1].faction)) end
    if nodes[2] and nodes[2].faction == nil then
      ok("faction: an object does not inherit a unit's faction through the shared meta table")
    else
      fail("faction: the object leaked faction=%s from the unit before it",
           tostring(nodes[2] and nodes[2].faction))
    end
    if nodes[3] and nodes[3].faction == nil then
      ok("faction: a unit with no fac does not inherit the previous unit's")
    else
      fail("faction: unit 2 leaked faction=%s", tostring(nodes[3] and nodes[3].faction))
    end
  end

  -- and the display half: the value has to reach the frame the tooltip reads
  local msrc = io.open("map.lua"):read("*a")
  if string.find(msrc, "frame%.faction = tab%.faction") then
    ok("faction: the node frame carries it through to the tooltip")
  else
    fail("faction: map.lua never copies faction onto the node frame, so the tooltip cannot see it")
  end

  local lines
  local tooltip = {
    AddDoubleLine = function(_, l, r) table.insert(lines, tostring(l) .. " " .. tostring(r)) end,
  }
  -- lifted loosely on purpose: the point is to run whatever condition the
  -- source carries against every fac value, not to pin one spelling of it
  local block = string.match(msrc, "\n(  if this%.faction.-\n  end)\n")
  if not block then
    fail("faction: could not lift the tooltip block out of map.lua")
  else
    local chunk = loadstring("local this, tooltip = ...\n" .. block)
    setfenv(chunk, setmetatable(
      { pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end }) },
      { __index = _G }))
    local cases = {
      { "A", "Faction: Alliance" }, { "H", "Faction: Horde" },
      { "AH", nil }, { nil, nil },
    }
    local bad = 0
    for _, case in ipairs(cases) do
      lines = {}
      chunk({ faction = case[1] }, tooltip)
      if lines[1] ~= case[2] then
        bad = bad + 1
        fail("faction: fac=%s drew %s, expected %s",
             tostring(case[1]), tostring(lines[1]), tostring(case[2]))
      end
    end
    if bad == 0 then
      ok("faction: Alliance and Horde are named, \"AH\" and no faction draw nothing")
    end
  end
end

-- ---------------------------------------------------------------------------
-- World map dropdown position (issue #20). WDM puts two things in the corner
-- our dropdown anchors to: WDM_WorldMapButton, a tracking button at strata
-- TOOLTIP that draws straight over our right end, and Blizzard's floor
-- dropdown, whose 64px artwork on a 32px frame overlaps ours by 20px. We step
-- aside for either. What has to hold is that we step aside for exactly those
-- two, only while they are actually shown, and back again when they are not --
-- a dropdown that drifted 40px left on a stock client would be our bug, not a
-- fix for anyone.
-- ---------------------------------------------------------------------------
do
  local src = io.open("quest.lua"):read("*a")
  local block = string.match(src, "\n(  local BASE_X, BASE_Y = .-\n  end)\n")
  if not block then
    fail("map dropdown: could not lift the reposition block out of quest.lua")
  else
    local points, cleared = {}, 0
    local mapButton = {
      ClearAllPoints = function() cleared = cleared + 1 end,
      SetPoint = function(_, _, _, _, x, y) table.insert(points, { x, y }) end,
    }
    local fakeG = {}
    local env = { _G = fakeG, pfQuest = { mapButton = mapButton } }
    local chunk = loadstring(block .. "\nreturn reposition")
    setfenv(chunk, setmetatable(env, { __index = _G }))
    local reposition = chunk()

    local function shown(v) return { IsShown = function() return v end } end
    local function run(wdm, level)
      fakeG["WDM_WorldMapButton"] = wdm
      env.WorldMapLevelDropDown = level
      points = {}
      reposition()
      return points[1]
    end

    local cases = {
      { nil,          nil,          0,   -10, "stock client, neither present" },
      { shown(true),  nil,        -40,   -10, "WDM tracking button only" },
      { nil,          shown(true),  0,   -36, "floor dropdown only" },
      { shown(true),  shown(true),-40,   -36, "both" },
      { shown(false), shown(false), 0,   -10, "both present but hidden" },
    }
    local bad = 0
    for _, c in ipairs(cases) do
      -- force a change every time, so each case really re-anchors
      mapButton.offsetX, mapButton.offsetY = nil, nil
      local got = run(c[1], c[2])
      if not got or got[1] ~= c[3] or got[2] ~= c[4] then
        bad = bad + 1
        fail("map dropdown: %s -> (%s, %s), expected (%d, %d)",
             c[5], tostring(got and got[1]), tostring(got and got[2]), c[3], c[4])
      end
    end
    if bad == 0 then
      ok("map dropdown: offsets correct for all %d WDM combinations, and unmoved without it",
         table.getn(cases))
    end

    -- it runs on every map update, so re-anchoring when nothing changed would
    -- be pure churn
    mapButton.offsetX, mapButton.offsetY = nil, nil
    run(shown(true), shown(true))
    points = {}
    reposition()
    reposition()
    if table.getn(points) == 0 then ok("map dropdown: no re-anchor when nothing changed")
    else fail("map dropdown: re-anchored %d times with no change", table.getn(points)) end
  end

  -- and it has to actually be driven: once when the map opens, and again
  -- whenever the floor dropdown appears or goes away underneath us
  if string.find(src, "pfQuest%.mapButton:SetScript%(\"OnShow\".-reposition%(%)") then
    ok("map dropdown: repositioned when the map is shown")
  else
    fail("map dropdown: OnShow never calls reposition, so it would never move")
  end
  if string.find(src, "WorldMapLevelDropDown:HookScript%(\"OnShow\", reposition%)")
    and string.find(src, "WorldMapLevelDropDown:HookScript%(\"OnHide\", reposition%)") then
    ok("map dropdown: follows the floor dropdown appearing and disappearing")
  else
    fail("map dropdown: not hooked to the floor dropdown's visibility")
  end
end

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
