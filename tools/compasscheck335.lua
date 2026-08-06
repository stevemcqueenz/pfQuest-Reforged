-- HorizonCompass contract check: load the REAL compass.lua under the 3.3.5a frame
-- stub, fake the addon surface at the seams, and drive the actual public functions
-- the CONTRACT names (pfQuest.compass + ProjectOffset/BearingTo/YardsTo/
-- UpdateSettings). Same mold as trackercheck335.lua: real module, faked seams,
-- assertions that can actually fail. Each check cites the contract clause it pins.
--
-- Usage: lua5.1 tools/compasscheck335.lua [compass.lua]   (from the addon root)

local COMPASS_FILE = arg and arg[1] or "compass.lua"

local failures, checks = 0, 0
local function fail(f, ...) failures = failures + 1; print("  FAIL  " .. string.format(f, ...)) end
local function ok(f, ...) checks = checks + 1; print("  ok    " .. string.format(f, ...)) end
local function check(cond, f, ...) if cond then ok(f, ...) else fail(f, ...) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-4 end

dofile("tools/framestub335.lua").install()

-- ---------------------------------------------------------------------------
-- world-state fakes, mutable per test case
-- ---------------------------------------------------------------------------
local facing, posx, posy, ontaxi = 0, 0.4, 0.6, nil
local dead, corpsex, corpsey = nil, 0, 0
_G.GetPlayerFacing = function() return facing end
_G.GetPlayerMapPosition = function() return posx, posy end
_G.UnitOnTaxi = function() return ontaxi end
_G.GetRealZoneText = function() return "Testzone" end
-- corpse seam (contract: corpse marker ONLY while UnitIsDeadOrGhost and
-- GetCorpseMapPosition is non-zero; both 3.3.5a-native per milkyway)
_G.UnitIsDeadOrGhost = function() return dead end
_G.GetCorpseMapPosition = function() return corpsex, corpsey end
-- GetQuestDifficultyColor returns a {r,g,b} table on 3.3.5a (milkyway); a
-- fixed red stands in so tint assertions have a known value
_G.GetQuestDifficultyColor = function() return { r = 1, g = 0.1, b = 0.1 } end
-- GetQuestLogTitle: 3.3.5a shape with the AzerothCore isDaily backport in
-- slot 8 (guarded in the addon; the fake serves a single daily quest)
_G.GetQuestLogTitle = function(id)
  if id == 7 then return "Daily Test", 80, nil, nil, nil, nil, nil, 1, 99901 end
  return nil
end
-- the stub's GetTime is frozen at 1000; the compass perf cap (contract: perfTick =
-- now + 0.02, route.lua:515 idiom) would then skip every fire after the first, so
-- advance time on each read to keep the real per-frame path exercised.
do
  local now = 1000
  _G.GetTime = function() now = now + 0.05 return now end
end

-- ---------------------------------------------------------------------------
-- the addon surface compass.lua expects, faked at the seams
-- ---------------------------------------------------------------------------
_G.pfQuest_config = { compass = "1", compasswidth = "420" }
_G.pfQuestConfig = { path = "pfQuest-Reforged" }

-- route target: the contract's ONE marker is "the same node pfQuest.route.arrow
-- points at", i.e. pfQuest.route.coords[1]. Shape faked honestly per route.lua:
-- an entry is { x_percent, y_percent, node_meta, distance } -- the arrow only
-- treats it as a valid target when [4] (distance) is set (route.lua:491), and
-- node_meta carries title/texture/priority (route.lua:560, SetTarget fields).
_G.pfQuest = { debug = function() end }
pfQuest.route = CreateFrame("Frame", "pfQuestRoute", _G.WorldFrame)
pfQuest.route.coords = {
  { 60, 50, { title = "Test Node", texture = nil, priority = 1 }, 25.5 },
}
pfQuest.route.arrow = CreateFrame("Frame", "pfQuestRouteArrow", _G.UIParent)
pfQuest.route.arrow.title = pfQuest.route.arrow:CreateFontString()
pfQuest.route.arrow.description = pfQuest.route.arrow:CreateFontString()
pfQuest.route.arrow.distance = pfQuest.route.arrow:CreateFontString()

-- pfMap: YardsTo reads minimap_sizes[mapID] = {widthYards, heightYards}
-- (map.lua:271, route.lua:81-82). mapID 113 exists, 999 deliberately does not.
_G.pfMap = setmetatable({
  minimap_sizes = { [113] = { 5450, 3633.3 } },
  GetMapIDByName = function() return 113 end,
  -- the zone node store the providers scan: pfMap.nodes[addon][zoneID]
  -- [coords]["title"] = node meta (map.lua:643-651); empty by default, test
  -- blocks fill it per case
  nodes = {},
  str2rgb = function() return 0.5, 0.5, 0.5 end,
}, { __index = function() return function() end end })

-- pfQuestTheme: chrome seams (contract: SkinPanel for panel chrome, accent color).
-- CreateProgressBar mirrors theme.lua's return shape (track/fill textures +
-- SetProgress/SetPoint) in case the strip reuses it.
_G.pfQuestTheme = {
  accent = { 0.2, 1.0, 0.8 },
  bg = { 0.08, 0.08, 0.08 },
  border = { 0.2, 0.2, 0.2 },
  panelAlpha = 0.85,
  SkinPanel = function() end,
  HeaderStrip = function(frame, _) return frame:CreateTexture() end,
  CreateProgressBar = function(parent, height)
    local bar = { height = height or 3, track = parent:CreateTexture(), fill = parent:CreateTexture() }
    function bar.SetPoint() end
    function bar.SetProgress() end
    return bar
  end,
}
_G.pfUI = { font_default = "Fonts\\FRIZQT__.TTF" }
_G.pfUI_config = { global = { font_size = 12 } }
_G.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return tostring(k) end })
_G.pfQuestCompat = setmetatable({ client = 30300, GetPlayerFacing = function() return facing end },
                                { __index = function() return function() end end })

-- ---------------------------------------------------------------------------
-- load the REAL module
-- ---------------------------------------------------------------------------
local loaded, err = pcall(dofile, COMPASS_FILE)
if not loaded then
  fail("%s could not be loaded under the stub: %s", COMPASS_FILE, tostring(err))
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
ok("%s loads and builds its frame", COMPASS_FILE)

-- (a) public surface -- contract "EXACT names": pfQuest.compass with the four entry
-- points. requireMethods pattern: a missing one is a hard stop, the rest of the
-- harness would only cascade nil-call errors.
local compass = pfQuest and pfQuest.compass
check(type(compass) == "table", "pfQuest.compass exists (contract: public surface)")
local missing = 0
for _, m in ipairs({ "ProjectOffset", "BearingTo", "YardsTo", "UpdateSettings" }) do
  local has = compass and type(compass[m]) == "function"
  check(has, "pfQuest.compass.%s is a function", m)
  if not has then missing = missing + 1 end
end
if type(compass) ~= "table" or missing > 0 then
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end

-- ---------------------------------------------------------------------------
-- (b) pure math -- contract: BearingTo uses the route.lua:527-541 convention,
-- ProjectOffset is linear rel/(pi/2)*halfWidth clamped to +/- halfWidth
-- ---------------------------------------------------------------------------
-- target due EAST of the player (tx 60 vs player x 50), facing north (0):
-- dx = +15, dy = 0 -> rel = atan2(15, 0) = +pi/2 (positive = to the RIGHT)
local rel = compass.BearingTo(0.5, 0.5, 60, 50, 0)
check(near(rel, math.pi / 2), "BearingTo east/facing-north = +pi/2 (got %s)", tostring(rel))
-- mirror: target due WEST -> -pi/2 (to the LEFT). This is the sign convention the
-- whole strip hangs on; a flipped atan2 argument passes the east case's magnitude
-- but fails here.
rel = compass.BearingTo(0.5, 0.5, 40, 50, 0)
check(near(rel, -math.pi / 2), "BearingTo west/facing-north = -pi/2 (got %s)", tostring(rel))

-- ProjectOffset(pi/4, 200): inside the FOV -> 100, NOT clamped
local x, clamped = compass.ProjectOffset(math.pi / 4, 200)
check(near(x, 100), "ProjectOffset(pi/4, 200) = 100 (got %s)", tostring(x))
check(not clamped, "ProjectOffset(pi/4, 200) not clamped (contract: clamped only outside FOV)")
-- ProjectOffset(pi, 200): behind the player -> clamps to the strip edge (+200)
x, clamped = compass.ProjectOffset(math.pi, 200)
check(near(x, 200), "ProjectOffset(pi, 200) clamps to +200 (got %s)", tostring(x))
check(clamped and true or false, "ProjectOffset(pi, 200) reports clamped=true")
-- and the negative edge mirrors
x, clamped = compass.ProjectOffset(-math.pi, 200)
check(near(x, -200), "ProjectOffset(-pi, 200) clamps to -200 (got %s)", tostring(x))
check(clamped and true or false, "ProjectOffset(-pi, 200) reports clamped=true")

-- ---------------------------------------------------------------------------
-- (c) YardsTo -- contract: yards from pfMap.minimap_sizes[mapID], nil when the
-- zone has no size data (NEVER fabricates)
-- ---------------------------------------------------------------------------
local yards = compass.YardsTo(0.5, 0.5, 60, 50, 113)
check(type(yards) == "number" and yards > 0,
      "YardsTo with known mapID returns positive yards (got %s)", tostring(yards))
-- monotonic sanity: a farther target along the same axis must read as MORE yards --
-- a fabricated constant would pass the positivity check above but fail this.
local farther = compass.YardsTo(0.5, 0.5, 70, 50, 113)
check(type(farther) == "number" and type(yards) == "number" and farther > yards,
      "YardsTo grows with distance (%s -> %s)", tostring(yards), tostring(farther))
check(compass.YardsTo(0.5, 0.5, 60, 50, 999) == nil,
      "YardsTo with unknown mapID returns nil (contract: never fabricate)")

-- ---------------------------------------------------------------------------
-- UpdateSettings -- contract: re-reads pfQuest_config, resizes; compasswidth
-- clamps to 240..800 (config keys section)
-- ---------------------------------------------------------------------------
local okU, errU = pcall(compass.UpdateSettings, compass)
check(okU, "UpdateSettings()%s", okU and "" or " -> " .. tostring(errU))
pfQuest_config["compasswidth"] = "600"
pcall(compass.UpdateSettings, compass)
check(near(compass:GetWidth(), 600), "compasswidth=600 -> strip width 600 (got %s)", tostring(compass:GetWidth()))
pfQuest_config["compasswidth"] = "1000"
pcall(compass.UpdateSettings, compass)
check(near(compass:GetWidth(), 800), "compasswidth=1000 clamps to 800 (got %s)", tostring(compass:GetWidth()))
pfQuest_config["compasswidth"] = "100"
pcall(compass.UpdateSettings, compass)
check(near(compass:GetWidth(), 240), "compasswidth=100 clamps to 240 (got %s)", tostring(compass:GetWidth()))
pfQuest_config["compasswidth"] = "420"
pcall(compass.UpdateSettings, compass)

-- ---------------------------------------------------------------------------
-- (d)/(e) OnUpdate drive -- shagu idiom handlers use the `this` global (contract
-- style section); the 3.3.5a client sets it before every handler call, the stub
-- does not, so set it around each Fire exactly as the client would.
-- ---------------------------------------------------------------------------
-- Fire on the frame that actually CARRIES the handler (resolved below). Firing on
-- a frame with no handler is a no-op that cannot fail -- every "does not error"
-- check after it would pass vacuously and prove nothing.
local handlerHost
local function fireOnUpdate()
  if not handlerHost then return false, "no OnUpdate host resolved" end
  _G.this = handlerHost
  local okF, errF = pcall(handlerHost.Fire, handlerHost, "OnUpdate")
  _G.this = nil
  return okF, errF
end

-- The handler lives on compass.driver, an always-shown sibling, NOT on the strip:
-- if it lived on the strip, hiding the strip on disable would stop the very loop
-- that re-shows it (OnUpdate does not fire on hidden frames). Accept either home,
-- but the driver must exist when the strip carries no handler.
handlerHost = (compass.scripts and compass.scripts.OnUpdate) and compass
  or (compass.driver and compass.driver.scripts and compass.driver.scripts.OnUpdate and compass.driver)
check(handlerHost ~= nil, "an OnUpdate handler exists on the strip or its driver")

-- (e) enabled, valid position/facing/target: two fires (second exercises the
-- dirty-skip/perf path) must not error
pfQuest_config["compass"] = "1"
facing, posx, posy, ontaxi = 1.2, 0.4, 0.6, nil
local okE, errE = fireOnUpdate()
check(okE, "OnUpdate enabled+target fire 1%s", okE and "" or " -> " .. tostring(errE))
facing = 1.25 -- turn slightly so the dirty-check path is not the only one hit
okE, errE = fireOnUpdate()
check(okE, "OnUpdate enabled+target fire 2%s", okE and "" or " -> " .. tostring(errE))

-- (d) disabled: contract behavior/guards -- "OnUpdate first line: if compass ~= '1'
-- then hide+return". Must not error, and the strip must actually hide.
pfQuest_config["compass"] = "0"
local okD, errD = fireOnUpdate()
check(okD, "OnUpdate with compass=\"0\" does not error%s", okD and "" or " -> " .. tostring(errD))
check(compass:IsShown() == false, "OnUpdate with compass=\"0\" hides the strip")

-- and the disable is not a one-way door: re-enabling fires clean again
pfQuest_config["compass"] = "1"
okE, errE = fireOnUpdate()
check(okE, "OnUpdate after re-enable%s", okE and "" or " -> " .. tostring(errE))

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
