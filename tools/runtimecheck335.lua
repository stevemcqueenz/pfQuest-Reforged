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

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
