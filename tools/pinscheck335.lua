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

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
