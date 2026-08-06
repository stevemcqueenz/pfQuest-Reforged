-- In-world pins (stage 1) contract check: load the REAL pins.lua under the
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

_G.GetPlayerMapPosition = function() return posx, posy end
_G.GetRealZoneText = function() return zonename end
_G.GetUnitSpeed = function() return speed end
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
-- pfMap: PercentToWorld reads minimap_sizes[mapID] = {widthYards, heightYards}
-- (map.lua:271). mapID 113 exists, "Nowhere" resolves to a sizeless map.
local zonemap = { Testzone = 113, Nowhere = 999 }
_G.pfMap = {
  minimap_sizes = { [113] = { 5450, 3633.3 } },
  GetMapIDByName = function(self, name) return zonemap[name] end,
  str2rgb = function() return 0.5, 0.5, 0.5 end,
}
_G.pfQuestTheme = {
  accent = { 0.2, 1.0, 0.8 },
  bg = { 0.08, 0.08, 0.08 },
}
_G.pfUI = { font_default = "Fonts\\FRIZQT__.TTF" }
UIParent:SetWidth(1024)
UIParent:SetHeight(768)

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

-- install the DLL fakes and load for real
_G.UnitPosition = function() return wpx, wpy, wpz end
_G.WorldToScreen = function() return scrx, scry, scrvis end

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
                     "EtaFor", "FormatEta", "NavigatorAngle", "StepMode" }) do
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
-- (a) state machine -- visible->waypoint / not-visible->navigator with the
-- ~0.25s boundary hysteresis: a FLAPPING visible flag must produce ZERO mode
-- changes, a sustained change follows ~0.25s late (sequence in, states out)
-- ---------------------------------------------------------------------------
local st = {}
check(pins.StepMode(st, true, 0) == "waypoint", "state t0: visible adopts waypoint instantly")
check(pins.StepMode(st, false, 0.05) == "waypoint", "state: one invisible tick does not swap")

-- boundary flap: raw flag toggles every 0.1s (two 0.05s ticks per phase) for
-- 2 seconds -- the exact screen-edge camera-bob pattern the hold exists for
st = {}
pins.StepMode(st, true, 1.0)
local changes, lastmode, t = 0, st.mode, 1.05
for i = 1, 40 do
  local vis = math.fmod(math.floor((i - 1) / 2), 2) == 1 -- 2 ticks off, 2 on, ...
  local m = pins.StepMode(st, vis, t)
  if m ~= lastmode then changes = changes + 1 lastmode = m end
  t = t + 0.05
end
check(changes == 0, "flapping visibility (0.1s phases): ZERO mode changes (got %d)", changes)
check(st.mode == "waypoint", "flap ends still in waypoint (the incumbent held)")

-- sustained transition: held for the 0.25s window, then swaps exactly once
st = {}
pins.StepMode(st, true, 10)
check(pins.StepMode(st, false, 10.1) == "waypoint", "sustained invisible +0.00s: held")
check(pins.StepMode(st, false, 10.2) == "waypoint", "sustained invisible +0.10s: held")
check(pins.StepMode(st, false, 10.34) == "waypoint", "sustained invisible +0.24s: still held")
check(pins.StepMode(st, false, 10.36) == "navigator", "sustained invisible +0.26s: navigator takes over")
check(pins.StepMode(st, true, 10.40) == "navigator", "swap back is not instant either")
check(pins.StepMode(st, true, 10.66) == "waypoint", "sustained visible 0.26s: waypoint returns")

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

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
