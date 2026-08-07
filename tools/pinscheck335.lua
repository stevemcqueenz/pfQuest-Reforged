-- In-world pins (stage 1+2) contract check: load the REAL pins.lua under the
-- 3.3.5a frame stub, fake the world at the seams (WorldToScreen / UnitPosition
-- / GetUnitSpeed / GetPlayerMapPosition), and drive the actual public surface
-- (pfQuest.pins) plus the real driver OnUpdate. Same mold as
-- compasscheck335.lua: explicit fakes, no catch-all __index, assertions that
-- can actually fail. Each check cites the PINS-DESIGN.md clause it pins.
--
-- Usage: lua5.1 tools/pinscheck335.lua [pins.lua]   (from the addon root)

local PINS_FILE = arg and arg[1] or "pins.lua"

local failures, checks = 0, 0
local function fail(f, ...) failures = failures + 1; print("  FAIL  " .. string.format(f, ...)) end
local function ok(f, ...) checks = checks + 1; print("  ok    " .. string.format(f, ...)) end
local function check(cond, f, ...) if cond then ok(f, ...) else fail(f, ...) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-4 end

dofile("tools/framestub335.lua").install()

-- ---------------------------------------------------------------------------
-- world-state fakes, mutable per test case. All EXPLICIT: unknown globals
-- stay nil so a call pins.lua should not be making errors instead of passing.
-- ---------------------------------------------------------------------------
local posx, posy = 0.4, 0.6
local zonename = "Testzone"
local speed = 7
-- the DLL pair (NOT installed yet -- the feature-detect block below loads the
-- module once WITHOUT them first)
local wpx, wpy, wpz = -7188.48, -3803.71, 9.08
local scrx, scry, scrvis = 614.4, 343.49, 1
-- optional per-coordinate WorldToScreen override for the multi-pin checks:
-- extras need DISTINCT deterministic screen points, the fixed scrx/scry pair
-- cannot provide that. nil = the classic fixed-return behavior.
local wts

_G.GetPlayerMapPosition = function() return posx, posy end
_G.GetRealZoneText = function() return zonename end
_G.GetUnitSpeed = function() return speed end
-- corpse seam (A1): alive by default; the corpse-override block flips these.
-- Token-aware (A4 amendment): party tokens read their own death flag
local dead, corpsex, corpsey = nil, 0, 0
local partyDead = {}
_G.UnitIsDeadOrGhost = function(unit)
  if unit and unit ~= "player" then return partyDead[unit] end
  return dead
end
_G.GetCorpseMapPosition = function() return corpsex, corpsey end
-- party seams (A4): solo by default; the 2-return UnitClass shape (never a
-- third classID on 3.3.5a) with the FILE token keying RAID_CLASS_COLORS
local partyN, raidN = 0, 0
_G.GetNumPartyMembers = function() return partyN end
_G.GetNumRaidMembers = function() return raidN end
_G.UnitName = function(u) return "Member-" .. tostring(u) end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
-- chat capture (A2): /way feedback assertions read the last line
local msgs = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) msgs[#msgs + 1] = m end }
local function lastmsg() return msgs[#msgs] or "" end
-- the stub's GetTime is frozen at 1000; the pins perf cap (perfTick = now +
-- 0.02, route.lua:515 idiom) would then skip every fire after the first, so
-- advance time on each read to keep the real per-frame path exercised.
do
  local now = 1000
  _G.GetTime = function() now = now + 0.05 return now end
end

-- ---------------------------------------------------------------------------
-- the addon surface pins.lua expects, faked at the seams
-- ---------------------------------------------------------------------------
_G.pfQuest_config = { pins = "1", pinssize = "100", pinsbeam = "1" }
_G.pfQuestConfig = { path = "pfQuest-Reforged" }
_G.pfQuest = { debug = function() end }
pfQuest.route = CreateFrame("Frame", "pfQuestRoute", _G.WorldFrame)
-- route target shape per route.lua: { x_percent, y_percent, node_meta,
-- distance } -- only a valid target while slot 4 is set (route.lua:491)
pfQuest.route.coords = {
  { 60, 50, { title = "Test Node", texture = nil }, 25.5 },
}
-- SetTarget/IsTarget recorders (A2): waypoint.lua points the arrow at its
-- stored map node through these; identity compare stands in for route.lua's
-- field compare, which is all the assertions need
pfQuest.route.SetTarget = function(node) pfQuest.route.settarget = node or nil end
pfQuest.route.IsTarget = function(node)
  return node ~= nil and node == pfQuest.route.settarget or nil
end
-- pfMap: PercentToWorld reads minimap_sizes[mapID] = {widthYards, heightYards}
-- (map.lua:271). mapID 113 exists, "Nowhere" resolves to a sizeless map.
local zonemap = { Testzone = 113, Nowhere = 999 }
_G.pfMap = {
  minimap_sizes = { [113] = { 5450, 3633.3 } },
  GetMapIDByName = function(self, name) return zonemap[name] end,
  str2rgb = function() return 0.5, 0.5, 0.5 end,
  -- the zone node store the shared provider scans (pfMap.nodes[addon][zid]
  -- [coords][title] = meta) plus its rebuild trigger; filled per test case
  nodes = {},
  queue_update = 0,
  -- minimal node-store recorders (A2): waypoint.lua registers its point as
  -- a real pfMap node; store the meta VERBATIM so the arrow=true flag and
  -- the SetTarget identity are the module's own, not a transcription
  AddNode = function(self, meta)
    local a = meta["addon"] or "PFDB"
    local z, c = meta["zone"], meta["x"] .. "|" .. meta["y"]
    self.nodes[a] = self.nodes[a] or {}
    self.nodes[a][z] = self.nodes[a][z] or {}
    self.nodes[a][z][c] = self.nodes[a][z][c] or {}
    self.nodes[a][z][c][meta["title"]] = meta
  end,
  DeleteNode = function(self, addon) self.nodes[addon] = nil end,
  UpdateNodes = function() end,
}
-- rare / dungeon DB seams (A3/A5): meta lists resolved through units and
-- objects coords, {x, y, zone, respawn} tuples; the 999-zone coords must
-- never leak into zone 113
_G.pfDB = {
  ["meta"] = {
    ["rares"] = { [61] = 11 },
    ["meetingstone"] = { [-179597] = "AH" },
  },
  ["units"] = {
    ["data"] = { [61] = { ["coords"] = { { 44.5, 60, 113, 5400 }, { 50, 50, 999, 5400 } }, ["lvl"] = "11" } },
    ["loc"] = { [61] = "Fenros" },
  },
  ["objects"] = {
    ["data"] = { [179597] = { ["coords"] = { { 41.5, 60.2, 113, 10 }, { 50, 50, 999, 10 } } } },
    ["loc"] = { [179597] = "Meeting Stone RFC" },
  },
}
_G.pfQuestTheme = {
  accent = { 0.2, 1.0, 0.8 },
  bg = { 0.08, 0.08, 0.08 },
}
_G.pfUI = { font_default = "Fonts\\FRIZQT__.TTF" }
_G.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return tostring(k) end })
UIParent:SetWidth(1024)
UIParent:SetHeight(768)

-- ---------------------------------------------------------------------------
-- the shared taxonomy provider lives in compass.lua (EachZoneNode); load the
-- REAL module so the multi-pin path runs end-to-end against the actual
-- provider, never a stub of it. The compass driver itself stays dormant
-- (pfQuest_config carries no compass="1"), proving pins do not depend on the
-- strip being ENABLED -- only on the module being loaded.
-- ---------------------------------------------------------------------------
local cok, cerr = pcall(dofile, "compass.lua")
if not cok then
  fail("compass.lua (shared provider) could not be loaded: %s", tostring(cerr))
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end

-- the REAL waypoint module (A2): /way parsing, storage, the map-node
-- arrow-follow wiring and the arrival auto-clear all live in waypoint.lua;
-- the pins tier consumes its Get()/pinnode surface. Overridable path so the
-- negative-test drill can point at a scratch copy.
local WAY_FILE = arg and arg[2] or "waypoint.lua"
local wok, werr = pcall(dofile, WAY_FILE)
if not wok then
  fail("%s (waypoint module) could not be loaded: %s", WAY_FILE, tostring(werr))
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end

-- ---------------------------------------------------------------------------
-- (d) feature-detect -- contract: without the DLL exports the file is fully
-- inert: ZERO frames created, zero handlers, no public surface. Never a
-- version global. WorldToScreen/UnitPosition are deliberately still nil here.
-- ---------------------------------------------------------------------------
local created = 0
local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function(...) created = created + 1 return realCreateFrame(...) end

local loaded, err = pcall(dofile, PINS_FILE)
check(loaded, "%s loads with the DLL absent%s", PINS_FILE, loaded and "" or " -> " .. tostring(err))
check(created == 0, "DLL absent: zero frames created (got %d)", created)
check(pfQuest.pins == nil, "DLL absent: no public surface (pfQuest.pins stays nil)")

-- install the DLL fakes and load for real. UnitPosition is token-aware
-- (A4 amendment): party tokens resolve world coords from partyWorld, an
-- absent entry models an unresolvable member (other instance/out of range)
local partyWorld = {}
_G.UnitPosition = function(unit)
  if unit and unit ~= "player" then
    local pw = partyWorld[unit]
    if pw then return pw[1], pw[2], pw[3] end
    return nil
  end
  return wpx, wpy, wpz
end
_G.WorldToScreen = function(x, y, z)
  if wts then return wts(x, y, z) end
  return scrx, scry, scrvis
end

loaded, err = pcall(dofile, PINS_FILE)
if not loaded then
  fail("%s could not be loaded under the stub: %s", PINS_FILE, tostring(err))
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
check(created > 0, "DLL present: frames created (%d)", created)
_G.CreateFrame = realCreateFrame

local pins = pfQuest and pfQuest.pins
check(type(pins) == "table", "pfQuest.pins exists (public surface)")
local missing = 0
for _, m in ipairs({ "ToUiCoords", "PercentToWorld", "ScaleForDistance",
                     "EtaFor", "FormatEta", "NavigatorAngle", "StepMode",
                     "Clamp", "PinpointText" }) do
  local has = pins and type(pins[m]) == "function"
  check(has, "pfQuest.pins.%s is a function", m)
  if not has then missing = missing + 1 end
end
if type(pins) ~= "table" or missing > 0 then
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end

-- ---------------------------------------------------------------------------
-- ToUiCoords -- the ONE calibration site: DLL coords are screen percent on a
-- fixed 1024x768 base, rescaled to UIParent's actual dimensions
-- ---------------------------------------------------------------------------
local x, y = pins.ToUiCoords(614.4, 343.49, 1024, 768)
check(near(x, 614.4) and near(y, 343.49),
      "ToUiCoords identity at the 1024x768 base (got %s, %s)", tostring(x), tostring(y))
x, y = pins.ToUiCoords(512, 384, 1280, 960)
check(near(x, 640) and near(y, 480),
      "ToUiCoords rescales center to a larger UI (got %s, %s)", tostring(x), tostring(y))

-- ---------------------------------------------------------------------------
-- PercentToWorld -- delta form off the player's own paired sample; world +X
-- north / +Y west, map-x east and map-y south both DECREASE their world axis
-- ---------------------------------------------------------------------------
local tX, tY = pins.PercentToWorld(0.4, 0.6, 60, 50, 1000, 2000, 113)
-- map-y 50% is NORTH of the player's 60% -> worldX grows by 0.1 * 3633.3
-- map-x 60% is EAST of the player's 40% -> worldY falls by 0.2 * 5450
check(near(tX, 1000 + 363.33) and near(tY, 2000 - 1090),
      "PercentToWorld axis pairing and signs (got %s, %s)", tostring(tX), tostring(tY))
tX, tY = pins.PercentToWorld(0.4, 0.6, 40, 60, 1000, 2000, 113)
check(near(tX, 1000) and near(tY, 2000),
      "PercentToWorld at the player's own percent returns the player's world position")
check(pins.PercentToWorld(0.4, 0.6, 60, 50, 1000, 2000, 999) == nil,
      "PercentToWorld with a sizeless zone returns nil (never fabricates)")

-- ---------------------------------------------------------------------------
-- (c) distance scale -- clamps at BOTH ends (spec: min % at max distance,
-- max % at min distance; defaults 50/150), linear ramp between
-- ---------------------------------------------------------------------------
check(near(pins.ScaleForDistance(0), 1.5), "scale at 0 yd clamps to the 150%% max")
check(near(pins.ScaleForDistance(40), 1.5), "scale at the near edge (40 yd) still max")
check(near(pins.ScaleForDistance(400), 0.5), "scale at the far edge (400 yd) clamps to the 50%% min")
check(near(pins.ScaleForDistance(1e6), 0.5), "scale at extreme range stays at the min clamp")
check(near(pins.ScaleForDistance(220), 1.0), "scale at the midpoint (220 yd) is exactly 1.0")
check(pins.ScaleForDistance(100) > pins.ScaleForDistance(300),
      "scale is monotonically shrinking with distance")

-- ---------------------------------------------------------------------------
-- (b) ETA -- speed 0 / negative / non-finite yields NO eta (spec: never show
-- infinity); formatting is mm:ss from a minute up, Ns below
-- ---------------------------------------------------------------------------
check(pins.EtaFor(100, 0) == nil, "ETA at speed 0 is nil (hidden, never infinity)")
check(pins.EtaFor(100, -5) == nil, "ETA at negative speed is nil")
check(pins.EtaFor(100, 0 / 0) == nil, "ETA at nan speed is nil")
check(pins.EtaFor(100, math.huge) == nil, "ETA at infinite speed is nil")
check(near(pins.EtaFor(70, 7), 10), "ETA 70 yd at run speed 7 = 10s")
check(pins.FormatEta(10) == "10s", "FormatEta(10) = 10s (got %s)", tostring(pins.FormatEta(10)))
check(pins.FormatEta(59.4) == "59s", "FormatEta(59.4) rounds to 59s")
check(pins.FormatEta(59.7) == "1:00", "FormatEta(59.7) rounds up to 1:00")
check(pins.FormatEta(90) == "1:30", "FormatEta(90) = 1:30 (got %s)", tostring(pins.FormatEta(90)))
check(pins.FormatEta(3725) == "62:05", "FormatEta(3725) = 62:05 (plain minutes, no hours)")

-- ---------------------------------------------------------------------------
-- (e) navigator angle -- ccw from screen-right, for the four axis directions
-- ---------------------------------------------------------------------------
check(near(pins.NavigatorAngle(522, 384, 512, 384), 0), "navigator angle right of center = 0")
check(near(pins.NavigatorAngle(512, 394, 512, 384), math.pi / 2), "navigator angle above center = pi/2")
check(near(pins.NavigatorAngle(502, 384, 512, 384), math.pi), "navigator angle left of center = pi")
check(near(pins.NavigatorAngle(512, 374, 512, 384), -math.pi / 2), "navigator angle below center = -pi/2")

-- ---------------------------------------------------------------------------
-- (a) state machine -- three states (stage 2): invisible -> navigator,
-- visible+near -> pinpoint, visible+far -> waypoint, with the ~0.25s boundary
-- hysteresis on EVERY transition: a FLAPPING input must produce ZERO mode
-- changes, a sustained change follows ~0.25s late (sequence in, states out).
-- All far-distance sequences use 100 yd (well outside the 28/33 near band).
-- ---------------------------------------------------------------------------
local st = {}
check(pins.StepMode(st, true, 100, 0) == "waypoint", "state t0: visible far adopts waypoint instantly")
check(pins.StepMode(st, false, 100, 0.05) == "waypoint", "state: one invisible tick does not swap")

-- boundary flap: raw flag toggles every 0.1s (two 0.05s ticks per phase) for
-- 2 seconds -- the exact screen-edge camera-bob pattern the hold exists for
st = {}
pins.StepMode(st, true, 100, 1.0)
local changes, lastmode, t = 0, st.mode, 1.05
for i = 1, 40 do
  local vis = math.fmod(math.floor((i - 1) / 2), 2) == 1 -- 2 ticks off, 2 on, ...
  local m = pins.StepMode(st, vis, 100, t)
  if m ~= lastmode then changes = changes + 1 lastmode = m end
  t = t + 0.05
end
check(changes == 0, "flapping visibility (0.1s phases): ZERO mode changes (got %d)", changes)
check(st.mode == "waypoint", "flap ends still in waypoint (the incumbent held)")

-- sustained transition: held for the 0.25s window, then swaps exactly once
st = {}
pins.StepMode(st, true, 100, 10)
check(pins.StepMode(st, false, 100, 10.1) == "waypoint", "sustained invisible +0.00s: held")
check(pins.StepMode(st, false, 100, 10.2) == "waypoint", "sustained invisible +0.10s: held")
check(pins.StepMode(st, false, 100, 10.34) == "waypoint", "sustained invisible +0.24s: still held")
check(pins.StepMode(st, false, 100, 10.36) == "navigator", "sustained invisible +0.26s: navigator takes over")
check(pins.StepMode(st, true, 100, 10.40) == "navigator", "swap back is not instant either")
check(pins.StepMode(st, true, 100, 10.66) == "waypoint", "sustained visible 0.26s: waypoint returns")

-- three-state basics: near+visible adopts pinpoint instantly on a fresh
-- state; visibility beats distance (a near target behind the camera is
-- navigator, not pinpoint); a navigator reappearing near hands straight to
-- pinpoint after the hold -- never via a waypoint flash
st = {}
check(pins.StepMode(st, true, 10, 0) == "pinpoint", "state t0: visible near adopts pinpoint instantly")
check(pins.StepMode(st, false, 10, 0.10) == "pinpoint", "near turned invisible: held through the window")
check(pins.StepMode(st, false, 10, 0.40) == "navigator", "near but invisible 0.26s: navigator wins (visibility beats distance)")
check(pins.StepMode(st, true, 20, 0.50) == "navigator", "reappearing near: navigator still holds")
check(pins.StepMode(st, true, 20, 0.80) == "pinpoint", "reappearing near 0.26s: straight to pinpoint, no waypoint flash")

-- the near-boundary walk (spec): distance oscillating 27..34 yd -- across
-- BOTH band edges -- flipping every 0.05s tick for 2s must not thrash; the
-- hold absorbs it because neither desire survives 0.25s continuously
st = {}
pins.StepMode(st, true, 100, 20)
changes, lastmode, t = 0, st.mode, 20.05
for i = 1, 40 do
  local d = math.fmod(i, 2) == 0 and 27 or 34
  local m = pins.StepMode(st, true, d, t)
  if m ~= lastmode then changes = changes + 1 lastmode = m end
  t = t + 0.05
end
check(changes == 0, "fast near-boundary walk (27/34 yd per tick): ZERO mode changes (got %d)", changes)
check(st.mode == "waypoint", "fast walk ends still in waypoint (the incumbent held)")

-- same walk from a pinpoint incumbent: it must hold too
st = {}
pins.StepMode(st, true, 10, 30)
changes, lastmode, t = 0, st.mode, 30.05
for i = 1, 40 do
  local d = math.fmod(i, 2) == 0 and 27 or 34
  local m = pins.StepMode(st, true, d, t)
  if m ~= lastmode then changes = changes + 1 lastmode = m end
  t = t + 0.05
end
check(changes == 0, "fast walk from pinpoint incumbent: ZERO mode changes (got %d)", changes)
check(st.mode == "pinpoint", "fast walk ends still in pinpoint (the incumbent held)")

-- the slow band walk: 29..31 yd held 0.4s per phase -- clearly LONGER than
-- the hold, so only the hysteresis BAND (28 enter / 33 leave) keeps this
-- stable; from either incumbent both values sit inside the band and the
-- desire never flips
for _, start in ipairs({ { 100, "waypoint" }, { 10, "pinpoint" } }) do
  st = {}
  pins.StepMode(st, true, start[1], 40)
  changes, lastmode, t = 0, st.mode, 40.05
  for i = 1, 40 do
    local d = math.fmod(math.floor((i - 1) / 8), 2) == 0 and 29 or 31 -- 8 ticks (0.4s) per phase
    local m = pins.StepMode(st, true, d, t)
    if m ~= lastmode then changes = changes + 1 lastmode = m end
    t = t + 0.05
  end
  check(changes == 0, "slow band walk (29/31 yd, 0.4s phases) from %s: ZERO mode changes (got %d)",
        start[2], changes)
  check(st.mode == start[2], "slow band walk ends still in %s", start[2])
end

-- sustained crossing of the near boundary switches after the hold, both ways
st = {}
pins.StepMode(st, true, 100, 50)
check(pins.StepMode(st, true, 20, 50.1) == "waypoint", "sustained near +0.00s: waypoint held")
check(pins.StepMode(st, true, 20, 50.34) == "waypoint", "sustained near +0.24s: still held")
check(pins.StepMode(st, true, 20, 50.36) == "pinpoint", "sustained near +0.26s: pinpoint takes over")
check(pins.StepMode(st, true, 40, 50.5) == "pinpoint", "back out past the leave edge: held")
check(pins.StepMode(st, true, 40, 50.76) == "waypoint", "sustained far 0.26s: waypoint returns")

-- ---------------------------------------------------------------------------
-- end-to-end: drive the REAL driver OnUpdate (shagu idiom: the client sets
-- `this` before every handler call; do the same around each Fire)
-- ---------------------------------------------------------------------------
local driver = pins.driver
check(driver and driver.scripts and type(driver.scripts.OnUpdate) == "function",
      "an OnUpdate handler exists on the pins driver")
local function fire()
  _G.this = driver
  local okF, errF = pcall(driver.Fire, driver, "OnUpdate")
  _G.this = nil
  return okF, errF
end

-- expected world numbers for the faked scene, derived through the same public
-- math the module uses (not hand-transcribed constants)
local exX, exY = pins.PercentToWorld(posx, posy, 60, 50, wpx, wpy, 113)
local exDist = math.sqrt((exX - wpx) ^ 2 + (exY - wpy) ^ 2)

-- visible target: waypoint mode
scrvis = 1
local okE, errE = fire()
check(okE, "OnUpdate enabled+visible fire 1%s", okE and "" or " -> " .. tostring(errE))
okE, errE = fire()
check(okE, "OnUpdate enabled+visible fire 2%s", okE and "" or " -> " .. tostring(errE))
check(pins.waypoint:IsShown() == true, "visible target: waypoint shown")
check(pins.navigator:IsShown() == false, "visible target: navigator hidden")
local pt = pins.waypoint.points and pins.waypoint.points.CENTER
check(pt ~= nil and near(pt.x, 614.4),
      "waypoint anchored at ToUiCoords x (got %s)", tostring(pt and pt.x))
check(pins.waypoint.dist:GetText() == math.floor(exDist + 0.5) .. " yd",
      "distance text matches the world-space yards (got %s)", tostring(pins.waypoint.dist:GetText()))
check(pins.waypoint.eta:IsShown() == true, "moving at speed 7: ETA line shown")
check(pins.waypoint.eta:GetText() == pins.FormatEta(exDist / 7),
      "ETA text matches dist/speed (got %s)", tostring(pins.waypoint.eta:GetText()))
check(pins.waypoint.beam:IsShown() == true, "pinsbeam=1: beam shown")

-- standing still: the ETA line hides ENTIRELY (spec: never show infinity)
speed = 0
fire()
fire()
check(pins.waypoint.eta:IsShown() == false, "speed 0: ETA line hidden entirely")
check(pins.waypoint:IsShown() == true, "speed 0: waypoint itself stays up")
speed = 7

-- beam toggle is live
pfQuest_config["pinsbeam"] = "0"
fire()
check(pins.waypoint.beam:IsShown() == false, "pinsbeam=0: beam hidden")
pfQuest_config["pinsbeam"] = "1"
fire()
check(pins.waypoint.beam:IsShown() == true, "pinsbeam back on: beam returns")

-- off-screen target: the raw flag flips but the driver must HOLD waypoint
-- through the hysteresis window (fires advance ~0.05s each), then hand off
scrvis = nil
fire()
check(pins.waypoint:IsShown() == true, "invisible fire 1: still waypoint (hysteresis)")
for i = 1, 6 do fire() end
check(pins.navigator:IsShown() == true, "sustained invisible: navigator shown")
check(pins.waypoint:IsShown() == false, "sustained invisible: waypoint hidden")
-- navigator orbits at the fixed radius from screen center along the target
-- direction; with the target's screen point right+below center the pin sits
-- right of center and below it
pt = pins.navigator.points and pins.navigator.points.CENTER
check(pt ~= nil and pt.x > 512, "navigator orbit point is right of center (got %s)", tostring(pt and pt.x))

-- one visible fire must NOT bounce straight back (driver-side hysteresis)
scrvis = 1
fire()
check(pins.navigator:IsShown() == true, "single visible fire: navigator still holds")
for i = 1, 6 do fire() end
check(pins.waypoint:IsShown() == true, "sustained visible: waypoint returns")

-- indoors/other-map view (GetPlayerMapPosition 0,0): everything hides -- the
-- percent->world anchor pair is invalid there
posx, posy = 0, 0
fire()
check(pins.waypoint:IsShown() == false and pins.navigator:IsShown() == false,
      "position 0,0: both pins hidden (anchor pair invalid)")
posx, posy = 0.4, 0.6

-- zone without size data: PercentToWorld nil -> hidden, never fabricated
zonename = "Nowhere"
fire()
fire()
check(pins.waypoint:IsShown() == false and pins.navigator:IsShown() == false,
      "sizeless zone: both pins hidden (no percent->world mapping)")
zonename = "Testzone"

-- disabled: first line early-out; both hidden, and not a one-way door
pfQuest_config["pins"] = "0"
okE, errE = fire()
check(okE, "OnUpdate with pins=\"0\" does not error%s", okE and "" or " -> " .. tostring(errE))
check(pins.waypoint:IsShown() == false and pins.navigator:IsShown() == false,
      "pins=\"0\": both elements hidden")
pfQuest_config["pins"] = "1"
fire()
fire()
check(pins.waypoint:IsShown() == true, "re-enable: waypoint returns")

-- no route target: nothing to point at, both hide
pfQuest.route.coords = {}
fire()
check(pins.waypoint:IsShown() == false and pins.navigator:IsShown() == false,
      "no route target: both pins hidden")

-- ---------------------------------------------------------------------------
-- (b) Pinpoint text fallback chain, pure form: description -> title -> nil
-- (nil tells the caller to fall back to the distance line -- never empty)
-- ---------------------------------------------------------------------------
check(pins.PinpointText({ description = "0/1 Vial", title = "Quest" }) == "0/1 Vial",
      "PinpointText prefers the description")
check(pins.PinpointText({ description = "", title = "Quest" }) == "Quest",
      "PinpointText: empty description falls to the title")
check(pins.PinpointText({ title = "Quest" }) == "Quest",
      "PinpointText: no description falls to the title")
check(pins.PinpointText({}) == nil, "PinpointText: neither field -> nil (distance fallback)")
check(pins.PinpointText(nil) == nil, "PinpointText: no node -> nil")

-- ---------------------------------------------------------------------------
-- Clamp -- the defensive settings parse every new option goes through
-- ---------------------------------------------------------------------------
check(pins.Clamp("42", 10, 100, 50) == 42, "Clamp passes an in-range value through")
check(pins.Clamp("5", 10, 100, 50) == 10, "Clamp raises a low value to the floor")
check(pins.Clamp("999", 10, 100, 50) == 100, "Clamp lowers a high value to the ceiling")
check(pins.Clamp("abc", 10, 100, 50) == 50, "Clamp: garbage string falls to the default")
check(pins.Clamp(nil, 10, 100, 50) == 50, "Clamp: nil falls to the default")

-- ---------------------------------------------------------------------------
-- (a/b) end-to-end near handoff: driver walks waypoint -> pinpoint through
-- the hold, the objective text runs the fallback chain, then walks back out
-- ---------------------------------------------------------------------------
-- far target again: adopt waypoint on the fresh state
pfQuest.route.coords = { { 60, 50, { title = "Test Node" }, 25.5 } }
fire()
check(pins.waypoint:IsShown() == true, "far target restored: waypoint adopted")

-- near target: 0.2% off the player's percent = ~13 world yards, inside the
-- 28 yd enter edge (derived through the module's own PercentToWorld)
local nearNode = { title = "Test Quest", description = "0/1 Vial of Arcane Water" }
pfQuest.route.coords[1] = { 40.2, 60.2, nearNode, 25.5 }
local nX, nY = pins.PercentToWorld(posx, posy, 40.2, 60.2, wpx, wpy, 113)
local nearDist = math.sqrt((nX - wpx) ^ 2 + (nY - wpy) ^ 2)
check(nearDist < 28, "harness scene: near target inside the enter band (%.1f yd)", nearDist)
fire()
check(pins.waypoint:IsShown() == true, "near fire 1: still waypoint (handoff debounced)")
check(pins.pinpoint:IsShown() == false, "near fire 1: pinpoint not yet shown")
for i = 1, 6 do fire() end
check(pins.pinpoint:IsShown() == true, "sustained near: pinpoint shown")
check(pins.waypoint:IsShown() == false, "sustained near: waypoint hidden")
check(pins.navigator:IsShown() == false, "sustained near: navigator hidden")
pt = pins.pinpoint.points and pins.pinpoint.points.CENTER
check(pt ~= nil and near(pt.x, 614.4),
      "pinpoint anchored at ToUiCoords x (got %s)", tostring(pt and pt.x))
check(pins.pinpoint.text:GetText() == "0/1 Vial of Arcane Water",
      "pinpoint text is the objective description (got %s)", tostring(pins.pinpoint.text:GetText()))

-- fallback 2: node without a description -> quest title
pfQuest.route.coords[1][3] = { title = "Test Quest" }
fire()
check(pins.pinpoint.text:GetText() == "Test Quest",
      "no description: pinpoint text falls to the title (got %s)", tostring(pins.pinpoint.text:GetText()))

-- fallback 3: node with neither -> the distance line (never empty)
pfQuest.route.coords[1][3] = {}
fire()
check(pins.pinpoint.text:GetText() == math.floor(nearDist + 0.5) .. " yd",
      "no text at all: pinpoint falls to the distance line (got %s)", tostring(pins.pinpoint.text:GetText()))

-- walking back out (far target sustained) hands back to the waypoint late
pfQuest.route.coords[1] = { 60, 50, { title = "Test Node" }, 25.5 }
fire()
check(pins.pinpoint:IsShown() == true, "far fire 1: pinpoint still holds (handoff debounced)")
for i = 1, 6 do fire() end
check(pins.waypoint:IsShown() == true, "sustained far: waypoint returns")
check(pins.pinpoint:IsShown() == false, "sustained far: pinpoint hidden")

-- ---------------------------------------------------------------------------
-- (c) stage-2 settings -- every new option parses defensively, clamps, and
-- applies to the live widgets
-- ---------------------------------------------------------------------------
-- pinspointsize: pinpoint plate px = PINPOINT_BASE(20) * percent
pfQuest_config["pinspointsize"] = "200"
fire()
check(pins.pinpoint:GetWidth() == 40, "pinspointsize 200: pinpoint plate 40 px (got %s)",
      tostring(pins.pinpoint:GetWidth()))
check(pins.pinpoint.icon:GetWidth() == 24, "pinspointsize 200: pinpoint icon rides along (24 px)")
pfQuest_config["pinspointsize"] = "9999"
fire()
check(pins.pinpoint:GetWidth() == 60, "pinspointsize 9999 clamps to 300%% -> 60 px")
pfQuest_config["pinspointsize"] = "abc"
fire()
check(pins.pinpoint:GetWidth() == 20, "pinspointsize garbage falls to the 100%% default -> 20 px")
pfQuest_config["pinspointsize"] = "100"

-- pinsopacity: whole-tier alpha on all three elements
pfQuest_config["pinsopacity"] = "50"
fire()
check(pins.waypoint:GetAlpha() == 0.5 and pins.pinpoint:GetAlpha() == 0.5
      and pins.navigator:GetAlpha() == 0.5, "pinsopacity 50: all three elements at alpha 0.5")
pfQuest_config["pinsopacity"] = "500"
fire()
check(pins.waypoint:GetAlpha() == 1, "pinsopacity 500 clamps to 100%% -> alpha 1")
pfQuest_config["pinsopacity"] = "3"
fire()
check(near(pins.waypoint:GetAlpha(), 0.1), "pinsopacity 3 clamps to the 10%% floor -> alpha 0.1")
pfQuest_config["pinsopacity"] = "100"

-- pinsminscale/pinsmaxscale: wired into the waypoint's distance scaling; the
-- far target sits past SCALE_FAR so the MIN clamp is what renders
pfQuest_config["pinsminscale"] = "80"
fire()
check(pins.waypoint:GetWidth() == 22, "pinsminscale 80: far waypoint 28*0.8 -> 22 px (got %s)",
      tostring(pins.waypoint:GetWidth()))
-- crossed pair: min above max collapses to one scale instead of inverting the ramp
pfQuest_config["pinsminscale"] = "200"
pfQuest_config["pinsmaxscale"] = "100"
fire()
check(pins.waypoint:GetWidth() == 28, "crossed min/max pair collapses to the max (28 px flat)")
pfQuest_config["pinsminscale"] = "abc"
pfQuest_config["pinsmaxscale"] = nil
fire()
check(pins.waypoint:GetWidth() == 14, "pinsminscale garbage falls to the 50%% default -> 14 px")
pfQuest_config["pinsminscale"] = nil
fire()

-- pinsnavradius/pinsnavsize: orbit radius and plate size of the navigator
scrvis = nil
for i = 1, 8 do fire() end
check(pins.navigator:IsShown() == true, "navigator up for the orbit checks")
pfQuest_config["pinsnavradius"] = "200"
pfQuest_config["pinsnavsize"] = "150"
fire()
check(pins.navigator:GetWidth() == 33, "pinsnavsize 150: plate 22*1.5 -> 33 px (got %s)",
      tostring(pins.navigator:GetWidth()))
check(pins.navigator.chevron:GetWidth() == 24, "pinsnavsize 150: chevron rides along (24 px)")
local ux, uy = pins.ToUiCoords(scrx, scry, 1024, 768)
local ang = pins.NavigatorAngle(ux, uy, 512, 384)
pt = pins.navigator.points and pins.navigator.points.CENTER
check(pt ~= nil and near(pt.x, 512 + math.cos(ang) * 200) and near(pt.y, 384 + math.sin(ang) * 200),
      "pinsnavradius 200: orbit point at radius 200 along the target bearing (got %s, %s)",
      tostring(pt and pt.x), tostring(pt and pt.y))
pfQuest_config["pinsnavradius"] = "9"
fire()
pt = pins.navigator.points and pins.navigator.points.CENTER
check(pt ~= nil and near(pt.x, 512 + math.cos(ang) * 50) and near(pt.y, 384 + math.sin(ang) * 50),
      "pinsnavradius 9 clamps to the 50 floor")
pfQuest_config["pinsnavradius"] = nil
pfQuest_config["pinsnavsize"] = nil
scrvis = 1

-- ===========================================================================
-- MULTI-PIN exploration (pinsmulti, docs/PINS-DESIGN.md multi-pin note):
-- an ambient layer of up to pinsmulticap extra plates from the shared
-- compass taxonomy -- distance-culled, distance-faded, screen-merged, with
-- subordinate beams. Everything below drives the REAL provider (compass.lua
-- loaded above) through the real driver OnUpdate.
-- ===========================================================================

local T = pins.tunables
check(type(T) == "table" and type(T.MULTI_RADIUS) == "number",
      "pins.tunables exposed (the one-block-of-knobs contract)")

-- ---------------------------------------------------------------------------
-- (b) distance fade ramp, pure: endpoints and monotonicity
-- ---------------------------------------------------------------------------
check(near(pins.MultiAlpha(0), 1), "multi fade: solid (1.0) at 0 yd")
check(near(pins.MultiAlpha(T.MULTI_SOLID), 1), "multi fade: still solid at the near edge (%d yd)", T.MULTI_SOLID)
check(near(pins.MultiAlpha(T.MULTI_RADIUS), T.MULTI_FLOOR),
      "multi fade: floor (%.2f) at the show radius", T.MULTI_FLOOR)
check(near(pins.MultiAlpha(T.MULTI_RADIUS * 10), T.MULTI_FLOOR),
      "multi fade: never below the floor beyond the radius")
local mid = pins.MultiAlpha((T.MULTI_SOLID + T.MULTI_RADIUS) / 2)
check(mid < 1 and mid > T.MULTI_FLOOR, "multi fade: strictly inside the band mid-ramp")
local mono, prev = true, pins.MultiAlpha(T.MULTI_SOLID)
for d = T.MULTI_SOLID + 5, T.MULTI_RADIUS, 5 do
  local a = pins.MultiAlpha(d)
  if a > prev + 1e-9 then mono = false end
  prev = a
end
check(mono, "multi fade: monotonically non-increasing across the ramp")

-- ---------------------------------------------------------------------------
-- (a) screen-space merge, pure: route-wins, priority/nearest-wins, chain,
-- hidden extras neither merge nor suppress, navigator mode (no route ref)
-- ---------------------------------------------------------------------------
local mslots = {
  { show = true, ux = 100, uy = 100 }, -- kept (most important, first)
  { show = true, ux = 110, uy = 100 }, -- 10 from kept 1 -> merged
  { show = true, ux = 130, uy = 100 }, -- 20 from MERGED 2, 30 from 1 -> kept (chain)
  { show = true, ux = 400, uy = 310 }, -- near the route ref -> merged (route wins)
  { show = nil, ux = 100, uy = 100 },  -- hidden: neither merged nor suppressing
  n = 5,
}
pins.MergeScreenOverlaps(mslots, 405, 300, 28)
check(not mslots[1].merged, "merge: first (most important) extra kept")
check(mslots[2].merged, "merge: extra within radius of a nearer kept extra hides")
check(not mslots[3].merged, "merge: merged extras suppress nothing (chain case)")
check(mslots[4].merged, "merge: the route target's plate always wins")
check(not mslots[5].merged, "merge: a hidden extra is not marked merged")
local mslots2 = { { show = nil, ux = 50, uy = 50 }, { show = true, ux = 52, uy = 50 }, n = 2 }
pins.MergeScreenOverlaps(mslots2, nil, nil, 28)
check(not mslots2[2].merged, "merge: a hidden extra does not suppress a shown one")
local mslots3 = { { show = true, ux = 405, uy = 300 }, n = 1 }
pins.MergeScreenOverlaps(mslots3, nil, nil, 28)
check(not mslots3[1].merged, "merge: no route ref (navigator mode) suppresses nothing")

-- ---------------------------------------------------------------------------
-- (d) pinsmulti off (the default): zero extra frames created OR shown --
-- the pool must not even exist until the first enabled tick
-- ---------------------------------------------------------------------------
local mcreated = 0
local realCF = _G.CreateFrame
_G.CreateFrame = function(...) mcreated = mcreated + 1 return realCF(...) end
fire()
fire()
check(mcreated == 0 and pins.multiframes[1] == nil,
      "pinsmulti off: zero extra frames created (pool not built)")
check(pins.multilist.n == 0, "pinsmulti off: extras list stays empty")

-- ---------------------------------------------------------------------------
-- the synthetic zone. Player at map 40,60 (fractions 0.4,0.6); zone 113 is
-- 5450x3633.3 yd, so 1% of map-x = 54.5 yd (world-Y axis) and 1% of map-y =
-- 36.3 yd (world-X axis). Route target at 42,61 (~115 yd, waypoint mode).
-- Expected distances are derived through the module's own public math, never
-- hand-transcribed.
-- ---------------------------------------------------------------------------
local IMG = "pfQuest-Reforged\\img\\"
local function mknode(title, tex)
  return { title = title, texture = tex and (IMG .. tex) or nil, vertex = { 0, 0, 0 } }
end
local nodeReady = mknode("Ready Turnin", "complete_c")   -- 41|60: ~54 yd, class TURNIN
local nodeActive = mknode("Kill Area", "cluster_mob")    -- 42|60: ~109 yd, class ACTIVE
local nodeAvail1 = mknode("Giver Near", "available")     -- 43|60: ~163 yd, class AVAIL
local nodeAvail2 = mknode("Giver Far", "available")      -- 44|60: ~218 yd, class AVAIL
local nodeBeyond = mknode("Beyond Radius", "available")  -- 47|60: ~381 yd > 300 -> culled
local nodeUnready = mknode("Unfinished Ender", "complete") -- 40|61: not-ready -> excluded
local nodeAtRoute = mknode("At Route Plate", "available") -- 42|61.2: merges into the route pin
local nodeOnCell = mknode("On Target Cell", "available") -- 42|61: the route cell -> deduped
pfMap.nodes = {
  PFDB = {
    [113] = {
      ["41|60"] = { ["Ready Turnin"] = nodeReady },
      ["42|60"] = { ["Kill Area"] = nodeActive },
      ["43|60"] = { ["Giver Near"] = nodeAvail1 },
      ["44|60"] = { ["Giver Far"] = nodeAvail2 },
      ["47|60"] = { ["Beyond Radius"] = nodeBeyond },
      ["40|61"] = { ["Unfinished Ender"] = nodeUnready },
      ["42|61.2"] = { ["At Route Plate"] = nodeAtRoute },
      ["42|61"] = { ["On Target Cell"] = nodeOnCell },
    },
  },
}
pfMap.queue_update = 1
pfQuest.route.coords = { { 42, 61, { title = "Multi Target" }, 25.5 } }

-- deterministic per-coordinate projection: world deltas spread across the
-- screen (54.5 UI units per 1% of map-x, beyond the 28-unit merge radius),
-- everything visible unless wtsInvis says otherwise
local wtsInvis
wts = function(x, y, z)
  local v = 1
  if wtsInvis and wtsInvis(x, y) then v = nil end
  return 500 + (y - wpy), 300 + (x - wpx), v
end

local function worldOf(x, y) return pins.PercentToWorld(posx, posy, x, y, wpx, wpy, 113) end
local function distOf(x, y)
  local ex, ey = worldOf(x, y)
  return math.sqrt((ex - wpx) ^ 2 + (ey - wpy) ^ 2)
end
local dReady, dActive, dAvail1 = distOf(41, 60), distOf(42, 60), distOf(43, 60)
check(distOf(47, 60) > T.MULTI_RADIUS, "harness scene: the far giver sits beyond the show radius (%.0f yd)", distOf(47, 60))
check(dReady < T.MULTI_RADIUS, "harness scene: the nearest extra sits inside it (%.0f yd)", dReady)

-- enable, cap 8: the pool builds ONCE (exactly MULTI_MAX frames), the list
-- fills through the real EachZoneNode walk
pfQuest_config["pinsmulti"] = "1"
pfQuest_config["pinsmulticap"] = "8"
-- the navradius checks above left the committed mode at navigator; walk the
-- ~0.25s hysteresis hold so the route target is back in waypoint mode (its
-- plate position is the extras' merge reference)
for i = 1, 8 do fire() end
_G.CreateFrame = realCF
check(mcreated == T.MULTI_MAX, "enable: pool built once, exactly %d frames (got %d)", T.MULTI_MAX, mcreated)
check(pins.waypoint:IsShown() == true, "enable: the route target keeps its full waypoint treatment")

local ml = pins.multilist
check(ml.n == 5, "cap 8: 5 extras listed (radius, readiness and route-cell cull the other 3; got %d)", ml.n)
local keys = {}
for i = 1, ml.n do keys[ml[i].key] = i end
check(keys[nodeBeyond] == nil, "radius cull: the beyond-radius giver never enters the list")
check(keys[nodeUnready] == nil, "readiness: the not-ready ender never enters the list (shared ClassifyNode)")
check(keys[nodeOnCell] == nil, "dedupe: the route target's own cell never enters the list")
check(ml[1] and ml[1].key == nodeReady and ml[2] and ml[2].key == nodeActive,
      "ordering: CapInsert semantics, class ascending first (turn-in, then objective)")
check(keys[nodeAtRoute] == 3 and keys[nodeAvail1] == 4 and keys[nodeAvail2] == 5,
      "ordering: within a class nearest-first in world yards")

-- rendering: unmerged in-radius extras show; the one on the route plate merges
local mf = pins.multiframes
check(mf[1]:IsShown() and mf[2]:IsShown() and mf[4]:IsShown() and mf[5]:IsShown(),
      "render: all four clear extras shown")
check(ml[3].merged == true and mf[3]:IsShown() == false,
      "render: the extra on the route plate merges away (route wins, end to end)")

-- fade: alpha follows MultiAlpha(dist) * pinsopacity(=1); farther = fainter
check(near(mf[1]:GetAlpha(), pins.MultiAlpha(dReady)),
      "fade: nearest extra at MultiAlpha(%.0f yd) (got %s)", dReady, tostring(mf[1]:GetAlpha()))
check(near(mf[4]:GetAlpha(), pins.MultiAlpha(dAvail1)),
      "fade: far extra at MultiAlpha(%.0f yd)", dAvail1)
check(mf[4]:GetAlpha() < mf[1]:GetAlpha(), "fade: farther extra is fainter")

-- scale: extras shrink with range through the same ScaleForDistance clamps
check(mf[1]:GetWidth() == math.floor(T.MULTI_BASE * pins.ScaleForDistance(dReady, 0.5, 1.5) + 0.5),
      "scale: extra plate rides ScaleForDistance (got %s)", tostring(mf[1]:GetWidth()))
check(mf[4]:GetWidth() < mf[1]:GetWidth(), "scale: farther extra is smaller")

-- nearest-only distance line
check(mf[1].dtext:IsShown() == true and mf[1].dtext:GetText() == math.floor(dReady + 0.5) .. " yd",
      "nearest extra shows the distance line (got %s)", tostring(mf[1].dtext:GetText()))
check(mf[2].dtext:IsShown() == false and mf[4].dtext:IsShown() == false,
      "all other extras carry no text (plate+icon only)")

-- ---------------------------------------------------------------------------
-- subordinate beams (pinsmultibeam, default on)
-- ---------------------------------------------------------------------------
check(mf[1].beam:IsShown() == true, "beams: shown by default on a shown extra")
check(mf[1].beam:GetHeight() == math.floor(dReady + 0.5),
      "beams: height follows distance inside the clamp (got %s)", tostring(mf[1].beam:GetHeight()))
check(mf[4].beam:GetHeight() == T.MULTI_BEAM_MAX,
      "beams: far extra clamps to the subordinate max height")
-- (b) the beam is a CHILD of the plate frame, so the extra's distance-fade
-- alpha (checked above on the frame) multiplies its fixed gradient base
check(mf[1].beam.parent == mf[1] and mf[4].beam.parent == mf[4],
      "beams: alpha rides the plate's fade alpha (child of the faded frame)")
-- (c) the subordinate constants stay below the main beam's
check(T.MULTI_BEAM_ALPHA < T.BEAM_ALPHA, "beams: base alpha subordinate to the main beam")
check(T.MULTI_BEAM_MAX < T.BEAM_MAX and T.MULTI_BEAM_MIN < T.BEAM_MIN,
      "beams: height clamp subordinate to the main beam")
-- (a) toggle off: every beam hides, every plate stays
pfQuest_config["pinsmultibeam"] = "0"
fire()
-- a hidden plate's beam is invisible through parentage regardless of its own
-- flag (and the flag reconciles on the next show), so the contract is about
-- EFFECTIVE visibility: no shown plate may carry a shown beam
local beamsOff, platesOn = true, true
for i = 1, ml.n do
  if mf[i]:IsShown() and mf[i].beam:IsShown() then beamsOff = false end
  if not ml[i].merged and not mf[i]:IsShown() then platesOn = false end
end
check(beamsOff, "pinsmultibeam=0: every visible extra's beam hidden")
check(platesOn, "pinsmultibeam=0: the plates stay up")
pfQuest_config["pinsmultibeam"] = "1"
fire()
check(mf[1].beam:IsShown() == true, "pinsmultibeam back on: beams return")

-- ---------------------------------------------------------------------------
-- (e) extras hidden when the WorldToScreen visible flag is nil (no navigator
-- for extras -- off-screen ambient pins simply vanish)
-- ---------------------------------------------------------------------------
local aX, aY = worldOf(41, 60)
wtsInvis = function(x, y) return math.abs(x - aX) < 0.01 and math.abs(y - aY) < 0.01 end
fire()
check(mf[1]:IsShown() == false, "invisible extra: hidden, no navigator handoff")
check(mf[2]:IsShown() == true, "invisible extra: the others are unaffected")
check(mf[2].dtext:IsShown() == true and mf[1].dtext:IsShown() == false,
      "invisible extra: the distance line moves to the new nearest")
wtsInvis = nil
fire()
check(mf[1]:IsShown() == true, "extra returns when its projection is visible again")

-- ---------------------------------------------------------------------------
-- (c) cap: clamped 1..8, garbage falls to the default 4, list re-ranks
-- ---------------------------------------------------------------------------
pfQuest_config["pinsmulticap"] = "2"
fire()
fire()
check(ml.n == 2 and ml[1].key == nodeReady and ml[2].key == nodeActive,
      "pinsmulticap 2: only the two most important extras remain")
check(mf[3]:IsShown() == false and mf[4]:IsShown() == false and mf[5]:IsShown() == false,
      "pinsmulticap 2: the dropped extras' frames hide")
pfQuest_config["pinsmulticap"] = "99"
fire()
fire()
check(ml.n == 5, "pinsmulticap 99 clamps to the pool ceiling (all 5 candidates back)")
pfQuest_config["pinsmulticap"] = "abc"
fire()
fire()
check(ml.n == 4 and keys ~= nil and ml[4].key == nodeAvail1,
      "pinsmulticap garbage falls to the default 4 (farthest giver dropped)")
pfQuest_config["pinsmulticap"] = "8"
fire()
fire()

-- ---------------------------------------------------------------------------
-- off again: not a one-way door, and the whole tier still sleeps together
-- ---------------------------------------------------------------------------
mcreated = 0
_G.CreateFrame = function(...) mcreated = mcreated + 1 return realCF(...) end
pfQuest_config["pinsmulti"] = "0"
fire()
local anyShown = false
for i = 1, T.MULTI_MAX do if mf[i]:IsShown() then anyShown = true end end
check(not anyShown, "pinsmulti back to 0: every extra hidden")
check(pins.waypoint:IsShown() == true, "pinsmulti off: the route waypoint is untouched")
pfQuest_config["pinsmulti"] = "1"
fire()
fire()
check(mf[1]:IsShown() == true, "re-enable: extras return")
check(mcreated == 0, "re-enable: the pool is reused, never rebuilt (created once)")
_G.CreateFrame = realCF
-- pins="0" master switch puts the extras to sleep with the rest of the tier
pfQuest_config["pins"] = "0"
fire()
anyShown = false
for i = 1, T.MULTI_MAX do if mf[i]:IsShown() then anyShown = true end end
check(not anyShown, "pins=0: extras sleep with the whole tier")
pfQuest_config["pins"] = "1"

-- ===========================================================================
-- PHASE A. Everything below drives the REAL modules (pins + waypoint +
-- compass providers) through the real driver OnUpdates.
-- ===========================================================================
local CLS = pfQuest.compass.CLASS
local ANY = T.MULTI_MAX
local function anyExtraShown()
  for i = 1, ANY do if mf[i]:IsShown() then return true end end
  return nil
end
local function distText() return tostring(pins.waypoint.dist:GetText()) end
local function ydOf(x, y) return math.floor(distOf(x, y) + 0.5) .. " yd" end

-- ---------------------------------------------------------------------------
-- (A1) corpse-override sequence: dead -> corpse target + extras hidden ->
-- unghost -> route target back. Expected distances derive through the
-- module's own PercentToWorld, never hand-transcribed.
-- ---------------------------------------------------------------------------
for i = 1, 6 do fire() end
check(distText() == ydOf(42, 61), "corpse: baseline targets the route (%s)", distText())
check(anyExtraShown() == true, "corpse: baseline extras up")
dead, corpsex, corpsey = 1, 0.45, 0.55
fire()
fire()
check(distText() == ydOf(45, 55), "corpse: dead retargets the corpse (%s)", distText())
check(pins.waypoint.icon:GetTexture() == "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
      "corpse: skull icon bound to the plate")
check(anyExtraShown() == nil, "corpse: extras hide ENTIRELY while dead")
-- corpse on another map (0,0): guidance falls back to the route target, but
-- the extras stay asleep -- the dead state, not the corpse position, gates them
corpsex, corpsey = 0, 0
fire()
fire()
check(distText() == ydOf(42, 61), "corpse: 0,0 corpse (other map) falls back to the route target")
check(anyExtraShown() == nil, "corpse: extras stay hidden while dead even without a corpse position")
dead = nil
fire()
fire()
check(distText() == ydOf(42, 61), "corpse: unghost reverts to the route target")
for i = 1, 6 do fire() end
check(anyExtraShown() == true, "corpse: extras return after unghost")

-- ---------------------------------------------------------------------------
-- (A2) /way parse cases + waypoint target priority + arrow-follow wiring
-- ---------------------------------------------------------------------------
local way = pfQuest.waypoint
check(type(way) == "table" and type(way.HandleCommand) == "function"
      and type(way.Get) == "function", "pfQuest.waypoint public surface")

way.HandleCommand("41 60.5 Meet here")
local wp = way.Get()
check(wp ~= nil and wp.x == 41 and wp.y == 60.5 and wp.zone == 113 and wp.label == "Meet here",
      "/way x y label: parsed, stored with the player's zone")
check(string.find(lastmsg(), "Waypoint set", 1, true) ~= nil, "/way set: chat feedback")
check(way.pinnode ~= nil and way.pinnode.title == "Meet here", "pinnode titled by the label")

-- arrow-follow: the stored pfMap node carries arrow=true (map.lua:1230
-- admits it into the route candidates) and SetTarget points at it
local stored = pfMap.nodes["PFWAY"] and pfMap.nodes["PFWAY"][113]
  and pfMap.nodes["PFWAY"][113]["41|60.5"] and pfMap.nodes["PFWAY"][113]["41|60.5"]["Meet here"]
check(stored ~= nil and stored.arrow == true, "arrow-follow: map node registered with arrow=true")
check(stored ~= nil and pfQuest.route.settarget == stored, "arrow-follow: SetTarget on the stored node")

-- pins prefer the waypoint over the route target...
fire()
fire()
check(distText() == ydOf(41, 60.5), "pins target the waypoint over the route (%s)", distText())
-- ...but never over the corpse
dead, corpsex, corpsey = 1, 0.45, 0.55
fire()
fire()
check(distText() == ydOf(45, 55), "the corpse still beats the waypoint")
dead = nil
fire()
fire()
check(distText() == ydOf(41, 60.5), "waypoint target returns on unghost")

-- bad args: usage feedback, stored point untouched
way.HandleCommand("garbage words")
check(string.find(lastmsg(), "Usage", 1, true) ~= nil, "/way garbage: usage feedback")
check(way.Get() ~= nil and way.Get().x == 41, "/way garbage: stored point untouched")
way.HandleCommand("45")
check(string.find(lastmsg(), "Usage", 1, true) ~= nil, "/way with one arg: usage feedback")
way.HandleCommand("450 60")
check(string.find(lastmsg(), "Invalid", 1, true) ~= nil and way.Get().x == 41,
      "/way out-of-range percent: rejected, point untouched")

-- label optional: bare coords title as Waypoint
way.HandleCommand("43 60")
check(way.Get() ~= nil and way.Get().label == nil and way.pinnode.title == "Waypoint",
      "/way without label: Waypoint title")

-- /way alone clears: storage, chat, route target and map node all release
way.HandleCommand("")
check(way.Get() == nil, "/way alone clears the point")
check(string.find(lastmsg(), "Waypoint cleared", 1, true) ~= nil, "clear: chat feedback")
check(pfQuest.route.settarget == nil, "clear: the route target releases")
check(pfMap.nodes["PFWAY"] == nil, "clear: the map node is deleted")
way.HandleCommand("")
check(string.find(lastmsg(), "No waypoint set", 1, true) ~= nil, "clear with none set: honest message")
fire()
fire()
check(distText() == ydOf(42, 61), "pins revert to the route target after the clear")

-- ---------------------------------------------------------------------------
-- (A2) arrival auto-clear at ~15 yd, driven through the REAL waypoint driver
-- ---------------------------------------------------------------------------
local wd = way.driver
check(wd ~= nil and wd.scripts and type(wd.scripts.OnUpdate) == "function",
      "waypoint driver OnUpdate exists")
local function wfire()
  _G.this = wd
  local okW, errW = pcall(wd.Fire, wd, "OnUpdate")
  _G.this = nil
  return okW, errW
end
way.HandleCommand("40.1 60.1 Close") -- ~7 world yards from the player
check(way.Get() ~= nil, "auto-clear scene: near point set")
for i = 1, 15 do wfire() end
check(way.Get() == nil, "auto-clear: point inside ~15 yd clears itself")
check(string.find(lastmsg(), "Waypoint reached", 1, true) ~= nil, "auto-clear: arrival notice")
way.HandleCommand("60 50 Far")
for i = 1, 15 do wfire() end
check(way.Get() ~= nil, "auto-clear: a far point never clears")
way.HandleCommand("")

-- ---------------------------------------------------------------------------
-- (A3) rare spawns join the extras behind compassrares (with pinsmulti)
-- ---------------------------------------------------------------------------
local function countTitle(t)
  local n2, idx = 0, nil
  for i = 1, ml.n do
    if ml[i].key and ml[i].key.title == t then n2 = n2 + 1 idx = i end
  end
  return n2, idx
end
pfQuest_config["compassrares"] = "1"
for i = 1, 6 do fire() end
local rn, ri = countTitle("Fenros")
check(rn == 1 and ml[ri].class == CLS.RARE,
      "rares: the zone rare joins the extras as CLASS_RARE (found %d)", rn)
check(ml[ri] ~= nil and ml[ri].key.texture == "pfQuest-Reforged\\img\\tracking\\rares",
      "rares: skull art from the shared provider")
pfQuest_config["compassrares"] = "0"
for i = 1, 6 do fire() end
rn = countTitle("Fenros")
check(rn == 0, "rares: toggle off removes the extra")

-- ---------------------------------------------------------------------------
-- (A5) dungeon entrances join the extras behind pinsdungeon (with pinsmulti)
-- ---------------------------------------------------------------------------
pfQuest_config["pinsdungeon"] = "1"
for i = 1, 6 do fire() end
local dn, di = countTitle("Meeting Stone RFC")
check(dn == 1 and ml[di].class == CLS.DUNGEON,
      "dungeon: the zone meeting stone joins the extras as CLASS_DUNGEON (found %d)", dn)
pfQuest_config["pinsdungeon"] = "0"
for i = 1, 6 do fire() end
dn = countTitle("Meeting Stone RFC")
check(dn == 0, "dungeon: toggle off removes the extra")

-- ---------------------------------------------------------------------------
-- (A4, amended) party plates, world-anchored via the DLL's UnitPosition on
-- the party tokens: alive member = quiet class-colored plate (no beam, no
-- text, lowest priority); DEAD member = skull art, priority above the
-- ambient classes, subordinate beam and a distance line; unresolvable
-- member = no pin; and the layer KEEPS WORKING INDOORS where
-- GetPlayerMapPosition reads 0,0 -- the dungeon-resurrection use case.
-- ---------------------------------------------------------------------------
-- alive party entries are CLS.PARTY; dead ones sit in the open interval
-- between AVAIL and DUNGEON (above the ambient info, below quest guidance)
local function partyEntries()
  local alive, ai, deadn, di2 = 0, nil, 0, nil
  for i = 1, ml.n do
    local cl = ml[i].class
    if cl == CLS.PARTY then
      alive = alive + 1
      ai = i
    elseif cl > CLS.AVAIL and cl < CLS.DUNGEON then
      deadn = deadn + 1
      di2 = i
    end
  end
  return alive, ai, deadn, di2
end
partyN = 2
-- party1 stays UNRESOLVABLE (no partyWorld entry: other instance/range)
partyWorld["party2"] = { wpx + 100, wpy + 40, wpz + 5 } -- ~108 yd, resolves
pfQuest_config["pinsparty"] = "1"
for i = 1, 12 do fire() end
local alive, ai, deadn, dpi = partyEntries()
check(alive == 1 and deadn == 0,
      "party: resolving member renders, unresolvable member has NO pin (got %d/%d)", alive, deadn)
check(ai ~= nil and ml[ai].key.vertex[1] == 0.41 and ml[ai].key.vertex[3] == 0.94,
      "party alive: plate carries the RAID_CLASS_COLORS class color")
check(ai ~= nil and ml[ml.n].class == CLS.PARTY,
      "party alive: sorts last (lowest merge priority)")
check(ai ~= nil and mf[ai]:IsShown() == true and mf[ai].beam:IsShown() == false,
      "party alive: quiet plate, no beam even with pinsmultibeam on")
check(ai ~= nil and mf[ai].dtext:IsShown() == false, "party alive: no text line")

-- (b) dead resolving member: elevated priority + skull + beam + distance
partyDead["party2"] = 1
pfQuest_config["compassrares"] = "1"
pfQuest_config["pinsdungeon"] = "1"
for i = 1, 12 do fire() end
alive, ai, deadn, dpi = partyEntries()
check(deadn == 1 and alive == 0, "party dead: the member reclassifies (got %d/%d)", deadn, alive)
check(dpi ~= nil and ml[dpi].key.texture == "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
      "party dead: skull art (the corpse pylon language, class-tinted)")
check(dpi ~= nil and ml[dpi].key.vertex[1] == 0.41,
      "party dead: still class-tinted (identity survives)")
local rIdx, dgIdx
for i = 1, ml.n do
  if ml[i].class == CLS.RARE then rIdx = i end
  if ml[i].class == CLS.DUNGEON then dgIdx = i end
end
check(dpi ~= nil and rIdx ~= nil and dgIdx ~= nil and dpi < rIdx and dpi < dgIdx,
      "party dead: sorts ABOVE rares and dungeon markers (dead member beats ambient info)")
check(dpi ~= nil and mf[dpi].beam:IsShown() == true, "party dead: subordinate beam on")
local pdDist = math.sqrt(100 * 100 + 40 * 40)
check(dpi ~= nil and mf[dpi].dtext:IsShown() == true
      and mf[dpi].dtext:GetText() == math.floor(pdDist + 0.5) .. " yd",
      "party dead: distance line to the body (got %s)", tostring(dpi and mf[dpi].dtext:GetText()))
-- the beam is independent of the pinsmultibeam experiment knob
pfQuest_config["pinsmultibeam"] = "0"
for i = 1, 3 do fire() end
alive, ai, deadn, dpi = partyEntries()
check(dpi ~= nil and mf[dpi].beam:IsShown() == true,
      "party dead: beam stays on with pinsmultibeam off")
pfQuest_config["pinsmultibeam"] = "1"
pfQuest_config["compassrares"] = "0"
pfQuest_config["pinsdungeon"] = "0"

-- (d) THE DUNGEON CASE: GetPlayerMapPosition reads 0,0 -- the main tier and
-- the percent extras sleep, the party pin keeps working
posx, posy = 0, 0
for i = 1, 12 do fire() end
check(pins.waypoint:IsShown() == false and pins.pinpoint:IsShown() == false
      and pins.navigator:IsShown() == false,
      "indoors: the main tier sleeps (percent anchor invalid)")
alive, ai, deadn, dpi = partyEntries()
check(deadn == 1 and dpi ~= nil and mf[dpi]:IsShown() == true,
      "indoors: the DEAD party pin keeps working (world-anchored, the amendment's point)")
local nonparty = 0
for i = 1, ml.n do
  local cl = ml[i].class
  if not (cl == CLS.PARTY or (cl > CLS.AVAIL and cl < CLS.DUNGEON)) then nonparty = nonparty + 1 end
end
check(nonparty == 0, "indoors: the percent-anchored quest extras stand down")
posx, posy = 0.4, 0.6
partyDead["party2"] = nil
for i = 1, 12 do fire() end
check(pins.waypoint:IsShown() == true, "back outdoors: the main tier wakes")

-- (c) raids excluded, toggle off, pinsparty drives the layer alone
raidN = 5
for i = 1, 12 do fire() end
alive, ai, deadn, dpi = partyEntries()
check(alive == 0 and deadn == 0, "party: raids excluded (party only)")
raidN = 0
pfQuest_config["pinsparty"] = "0"
for i = 1, 12 do fire() end
alive, ai, deadn, dpi = partyEntries()
check(alive == 0 and deadn == 0, "party: toggle off removes the plates")
-- pinsparty activates the extras machinery WITHOUT pinsmulti
pfQuest_config["pinsmulti"] = "0"
pfQuest_config["pinsparty"] = "1"
for i = 1, 12 do fire() end
alive, ai, deadn, dpi = partyEntries()
check(alive == 1 and ml.n == 1,
      "party: pinsparty alone drives the layer (party plate only, no quest extras)")
pfQuest_config["pinsmulti"] = "1"
pfQuest_config["pinsparty"] = "0"
partyN = 0
for i = 1, 8 do fire() end

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
