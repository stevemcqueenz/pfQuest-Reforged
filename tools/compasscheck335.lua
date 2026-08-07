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
-- EachZoneNode is the SHARED taxonomy provider (pins.lua consumes it too):
-- its presence is part of the contract, not an implementation detail
for _, m in ipairs({ "ProjectOffset", "BearingTo", "YardsTo", "UpdateSettings", "EachZoneNode" }) do
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

-- ---------------------------------------------------------------------------
-- (f) marker providers -- synthetic node tables in, expected marker set out
-- (COMPASS-DESIGN.md "Stage 2: the marker taxonomy"). The node shape mirrors
-- map.lua:643-651: pfMap.nodes[addon][zoneID]["x|y"][title] = meta with
-- title/texture/qlvl/qmin/vertex/description/questid/qlogid. zoneID 113 was
-- memoized by the OnUpdate fires above (GetRealZoneText -> GetMapIDByName).
-- ---------------------------------------------------------------------------
local C = compass.CLASS
check(type(C) == "table" and C.CORPSE == 1 and C.WAYPOINT == 2 and C.ROUTE == 3,
      "class constants exported (corpse=1 waypoint=2 route=3)")

local IMG = "pfQuest-Reforged\\img\\"
local function node(title, tex, extra)
  local t = { title = title, texture = tex and (IMG .. tex) or nil, vertex = { 0, 0, 0 } }
  if extra then for k, v in pairs(extra) do t[k] = v end end
  return t
end

-- one entry per class in the current zone, plus decoys that must NOT map
pfMap.nodes = {
  PFDB = {
    [113] = {
      -- ready turn-in: complete_c is the COLORED ? pfDatabase paints once the
      -- log quest's complete flag is set (database.lua:1666-1675)
      ["62|48"] = { ["Turnin Quest"] = node("Turnin Quest", "complete_c", { description = "Turn it in" }) },
      -- NOT-ready ender: plain complete (grey ?) while objectives are open --
      -- must produce NO marker (maintainer: clutter next to the objective)
      ["63|49"] = { ["Unfinished"] = node("Unfinished", "complete") },
      ["55|55"] = { ["Avail Quest"] = node("Avail Quest", "available", { qlvl = 72, qmin = 70 }) },
      ["52|52"] = { ["Current Giver"] = node("Current Giver", "available_c") },
      ["45|45"] = { ["Hard Quest"] = node("Hard Quest", "available", { qlvl = 78, qmin = 75 }) },
      ["48|60"] = { ["Untextured"] = node("Untextured", nil) },
    },
    -- a different zone: must never leak into the current-zone scan
    [999] = { ["10|10"] = { ["Elsewhere"] = node("Elsewhere", "complete") } },
  },
  PFQUEST = {
    [113] = {
      ["40|61"] = { ["Kill Quest"] = node("Kill Quest", "cluster_mob", { qlogid = 7, title = "Daily Test" }) },
    },
  },
}
-- badge seams: event id via the merged quest DB, daily via GetQuestLogTitle
-- slot 8 (the fake serves qlogid 7 as "Daily Test"); dungeon entrance via the
-- meta DB meeting stones (negative object ids, coords {x, y, zone, respawn})
_G.pfDB = {
  ["quests"] = { ["data"] = { [777] = { ["event"] = 12 } } },
  ["meta"] = { ["meetingstone"] = { [-179597] = "AH" } },
  ["objects"] = {
    ["data"] = { [179597] = { ["coords"] = { { 30, 40, 113, 10 }, { 50, 50, 999, 10 } } } },
    ["loc"] = { [179597] = "Meeting Stone RFC" },
  },
}
-- rename the PFQUEST node title to match the daily fake's log slot
pfMap.nodes.PFQUEST[113]["40|61"] = { ["Daily Test"] = node("Daily Test", "cluster_mob", { qlogid = 7 }) }

local target = pfQuest.route.coords[1]
local list = compass.list
local function classcount(cls)
  local n = 0
  for i = 1, list.n do if list[i].class == cls then n = n + 1 end end
  return n
end
local function findclass(cls)
  for i = 1, list.n do if list[i].class == cls then return list[i] end end
  return nil
end

pfQuest_config["compasscap"] = "8"
compass.BuildMarkers(0.4, 0.6, target, false)

check(findclass(C.ROUTE) ~= nil and findclass(C.ROUTE).key == target[3],
      "provider: route target present as class ROUTE keyed by its node")
check(findclass(C.TURNIN) ~= nil and findclass(C.TURNIN).title == "Turnin Quest",
      "provider: complete_c texture (ready turn-in) maps to TURNIN")
-- ready vs not-ready enders, pure form: the texture encodes readiness
check(compass.ClassifyNode(IMG .. "complete_c") == C.TURNIN,
      "classify: ready ender (complete_c) is TURNIN")
check(compass.ClassifyNode(IMG .. "complete") == nil,
      "classify: not-ready ender (plain complete) maps to nothing")
-- and through the provider: the not-ready ender cell produces NO marker
local unfinished = nil
for i = 1, list.n do if list[i].title == "Unfinished" then unfinished = list[i] end end
check(unfinished == nil, "provider: not-ready ender produces no marker")
check(findclass(C.ACTIVE) ~= nil and findclass(C.ACTIVE).icon == IMG .. "cluster_mob",
      "provider: cluster_mob maps to ACTIVE and the icon mirrors node.texture")
check(classcount(C.AVAIL) == 2, "provider: 2 available nodes map to AVAIL (got %d)", classcount(C.AVAIL))
local leaked = nil
for i = 1, list.n do
  local e = list[i]
  if e.title == "Current Giver" or e.title == "Elsewhere" or e.title == "Untextured" then leaked = e.title end
end
check(leaked == nil, "provider: available_c / other-zone / untextured nodes excluded (leaked %s)", tostring(leaked))
-- difficulty tint: qmin 75 > player 71 -> the faked GetQuestDifficultyColor red
local hard
for i = 1, list.n do if list[i].title == "Hard Quest" then hard = list[i] end end
check(hard and near(hard.tr, 1) and near(hard.tg, 0.1),
      "provider: too-high available quest tinted via GetQuestDifficultyColor")
local avail
for i = 1, list.n do if list[i].title == "Avail Quest" then avail = list[i] end end
check(avail and near(avail.tr, 1) and near(avail.tg, 1) and near(avail.tb, 1),
      "provider: takeable available quest stays untinted")
check(findclass(C.ACTIVE).badge == true,
      "provider: isDaily (GetQuestLogTitle slot 8, guarded) sets the badge")
check(findclass(C.CORPSE) == nil, "provider: no corpse marker while alive")
check(findclass(C.DUNGEON) == nil, "provider: dungeon entrances absent while compassdungeon=0")
-- sorted invariant: class ascending across the whole list
local sorted = true
for i = 2, list.n do if list[i].class < list[i - 1].class then sorted = false end end
check(sorted, "provider: list sorted by class ascending")

-- event badge via the merged quest DB (db/quests-eventtags335.lua overlay)
pfMap.nodes.PFDB[113]["55|55"]["Avail Quest"].questid = 777
compass.BuildMarkers(0.4, 0.6, target, false)
for i = 1, list.n do if list[i].title == "Avail Quest" then avail = list[i] end end
check(avail and avail.badge == true, "provider: event quest id (eventtags overlay) sets the badge")

-- dungeon entrances: toggle on -> exactly the current-zone stone appears
pfQuest_config["compassdungeon"] = "1"
compass.BuildMarkers(0.4, 0.6, target, false)
local dun = findclass(C.DUNGEON)
check(dun ~= nil and dun.title == "Meeting Stone RFC" and near(dun.x, 30) and near(dun.y, 40),
      "provider: meta DB meeting stone in this zone maps to DUNGEON")
check(classcount(C.DUNGEON) == 1, "provider: other-zone stone coords excluded")
pfQuest_config["compassdungeon"] = "0"

-- provider toggles: compassavail/compassturnin drop exactly their class
pfQuest_config["compassavail"] = "0"
pfQuest_config["compassturnin"] = "0"
compass.BuildMarkers(0.4, 0.6, target, false)
check(classcount(C.AVAIL) == 0 and classcount(C.TURNIN) == 0,
      "provider: compassavail/compassturnin=0 drop their classes")
check(findclass(C.ACTIVE) ~= nil, "provider: ACTIVE unaffected by the toggles")
pfQuest_config["compassavail"] = "1"
pfQuest_config["compassturnin"] = "1"

-- route-target dedupe: a node cell on the target's exact coords must not
-- render twice (the ROUTE marker already stands there)
pfMap.nodes.PFDB[113]["60|50"] = { [target[3].title] = node(target[3].title, "complete_c") }
compass.BuildMarkers(0.4, 0.6, target, false)
local attarget = 0
for i = 1, list.n do
  if near(list[i].x, 60) and near(list[i].y, 50) then attarget = attarget + 1 end
end
check(attarget == 1, "provider: node on the route target's coords deduped (got %d markers there)", attarget)
pfMap.nodes.PFDB[113]["60|50"] = nil

-- ---------------------------------------------------------------------------
-- (g) corpse provider, driven headless through the faked seams (contract:
-- shown ONLY while dead AND GetCorpseMapPosition is non-zero; highest class)
-- ---------------------------------------------------------------------------
dead, corpsex, corpsey = 1, 0.3, 0.35
compass.BuildMarkers(0.4, 0.6, target, true)
local corpse = findclass(C.CORPSE)
check(corpse ~= nil and near(corpse.x, 30) and near(corpse.y, 35),
      "corpse: dead + non-zero corpse position yields the CORPSE marker")
check(list[1] == corpse, "corpse: sorts first (highest class of all)")
dead, corpsex, corpsey = 1, 0, 0
compass.BuildMarkers(0.4, 0.6, target, true)
check(findclass(C.CORPSE) == nil, "corpse: 0,0 corpse position (other map) yields none")
dead = nil
compass.BuildMarkers(0.4, 0.6, target, false)
check(findclass(C.CORPSE) == nil, "corpse: none while alive")

-- corpse owns the label unconditionally while dead (policy override)
dead, corpsex, corpsey = 1, 0.3, 0.35
compass.BuildMarkers(0.4, 0.6, target, true)
local st = {}
for i = 1, list.n do list[i].rel = 1.0 end -- corpse far off-center: still owns
local own = compass.SelectLabel(list, st, 100)
check(own ~= nil and own.class == C.CORPSE, "corpse: owns the label even off-center")
dead = nil

-- ---------------------------------------------------------------------------
-- (g2) custom waypoint provider (Phase A2) -- the compass consumes the
-- pfQuest.waypoint surface (the module itself is driven end-to-end in
-- pinscheck335, which loads the real waypoint.lua); a faked provider pins
-- the CONSUMER contract: CLASS_WAYPOINT between CORPSE and ROUTE, star art
-- in the accent tint, label-or-"Waypoint" title, own-zone gating, and the
-- route-cell dedupe when the arrow already points at the waypoint's node.
-- ---------------------------------------------------------------------------
local wpstate
pfQuest.waypoint = { Get = function() return wpstate end }

wpstate = { x = 50, y = 50, zone = 113, label = "Meet here" }
compass.BuildMarkers(0.4, 0.6, target, false)
local wpm = findclass(C.WAYPOINT)
check(wpm ~= nil and wpm.title == "Meet here",
      "waypoint: marker present, titled by its label (got %s)", tostring(wpm and wpm.title))
check(wpm ~= nil and wpm.icon == "pfQuest-Reforged\\img\\fav",
      "waypoint: star art (img/fav) as the distinct icon")
check(list[1] == wpm and findclass(C.ROUTE) ~= nil,
      "waypoint: sorts ahead of the route target (class between corpse and route)")

-- corpse still outranks it
dead, corpsex, corpsey = 1, 0.3, 0.35
compass.BuildMarkers(0.4, 0.6, target, true)
check(list[1] ~= nil and list[1].class == C.CORPSE and list[2] ~= nil and list[2].class == C.WAYPOINT,
      "waypoint: the corpse still sorts first while dead (corpse > waypoint > route)")
dead = nil

-- label falls back to "Waypoint" without a label
wpstate = { x = 50, y = 50, zone = 113 }
compass.BuildMarkers(0.4, 0.6, target, false)
wpm = findclass(C.WAYPOINT)
check(wpm ~= nil and wpm.title == "Waypoint", "waypoint: unlabeled point titles as Waypoint")

-- other-zone waypoint never renders here
wpstate = { x = 50, y = 50, zone = 999 }
compass.BuildMarkers(0.4, 0.6, target, false)
check(findclass(C.WAYPOINT) == nil, "waypoint: other-zone point produces no marker")

-- route-cell dedupe: when the route target IS the waypoint's node (the
-- arrow-follow wiring), exactly one marker stands on that cell -- WAYPOINT
wpstate = { x = 60, y = 50, zone = 113 }
compass.BuildMarkers(0.4, 0.6, target, false)
local attarget2 = 0
for i = 1, list.n do
  if near(list[i].x, 60) and near(list[i].y, 50) then attarget2 = attarget2 + 1 end
end
check(attarget2 == 1 and findclass(C.WAYPOINT) ~= nil and findclass(C.ROUTE) == nil,
      "waypoint: route target on the waypoint cell deduped to the WAYPOINT marker")

-- empty-window label fallback prefers a present waypoint over the route
local wq = { key = "wq", class = C.WAYPOINT, rel = 1.0 }
local rt = { key = "rt", class = C.ROUTE, rel = 0.9 }
own = compass.SelectLabel({ n = 2, wq, rt }, {}, 40.0)
check(own == wq, "waypoint: empty-window label fallback prefers the waypoint")

wpstate = nil
pfQuest.waypoint = nil
compass.BuildMarkers(0.4, 0.6, target, false)
check(findclass(C.WAYPOINT) == nil, "waypoint: cleared point leaves no marker")

-- ---------------------------------------------------------------------------
-- (g3) rare spawns (Phase A3, compassrares) -- pfDB.meta.rares (unit id ->
-- level) resolved through the units DB coords ({x, y, zone, respawn}), per
-- zone; lowest class, below dungeon
-- ---------------------------------------------------------------------------
check(C.RARE == 8 and C.DUNGEON == 7, "rare: class sits below dungeon (rare=8 dungeon=7)")
pfDB["meta"]["rares"] = { [61] = 11 }
pfDB["units"] = {
  ["data"] = { [61] = { ["coords"] = { { 30, 40, 113, 5400 }, { 50, 50, 999, 5400 } }, ["lvl"] = "11" } },
  ["loc"] = { [61] = "Fenros" },
}
pfQuest_config["compassrares"] = "1"
compass.BuildMarkers(0.4, 0.6, target, false)
local rare = findclass(C.RARE)
check(rare ~= nil and rare.title == "Fenros" and near(rare.x, 30) and near(rare.y, 40),
      "rare: meta-list rare in this zone maps to RARE with the units-DB name")
check(rare ~= nil and rare.icon == "pfQuest-Reforged\\img\\tracking\\rares",
      "rare: pfQuest's own skull rare art")
check(classcount(C.RARE) == 1, "rare: other-zone spawn coords excluded")
pfQuest_config["compassrares"] = "0"
compass.BuildMarkers(0.4, 0.6, target, false)
check(findclass(C.RARE) == nil, "rare: toggle off removes the markers")

-- ---------------------------------------------------------------------------
-- (h) label policy as a pure sequence -- (facing, markers) in, owner out
-- (COMPASS-DESIGN.md "Label policy"; window 15deg, margin 4deg, hold 0.5s)
-- ---------------------------------------------------------------------------
local m1 = { key = "m1", class = 5, rel = 0.05 }
local m2 = { key = "m2", class = 5, rel = 0.10 }
local route = { key = "route", class = 3, rel = 1.0 }
local slots = { n = 3, m1, m2, route }
st = {}

own = compass.SelectLabel(slots, st, 10.0)
check(own == m1, "label t0: nearest-in-window owns (m1)")
-- challenger far closer but hold not passed: incumbent keeps it (no thrash)
m1.rel, m2.rel = 0.09, 0.01
own = compass.SelectLabel(slots, st, 10.1)
check(own == m1, "label t0.1: challenger blocked by the 0.5s hold")
m1.rel, m2.rel = 0.10, 0.005
own = compass.SelectLabel(slots, st, 10.3)
check(own == m1, "label t0.3: still held")
-- hold passed AND margin cleared: handover
own = compass.SelectLabel(slots, st, 10.6)
check(own == m2, "label t0.6: hold+margin cleared, m2 takes the label")
-- immediately after, m1 marginally closer: new incumbent m2 keeps it
m1.rel, m2.rel = 0.06, 0.065
own = compass.SelectLabel(slots, st, 10.7)
check(own == m2, "label t0.7: marginal flip suppressed (no thrash back)")
-- margin cleared but within m2's fresh hold: still m2
m1.rel, m2.rel = 0.001, 0.10
own = compass.SelectLabel(slots, st, 10.9)
check(own == m2, "label t0.9: margin alone insufficient inside the hold")
own = compass.SelectLabel(slots, st, 11.2)
check(own == m1, "label t1.2: hold expired, m1 takes it back")

-- fallback: nothing in the window -> the ROUTE TARGET keeps the label even
-- though another marker is nearer to center (both outside the window)
m1.rel, m2.rel, route.rel = 0.9, 0.5, 1.2
own = compass.SelectLabel(slots, st, 20.0)
check(own == route, "label fallback: route target owns when the window is empty")

-- tie inside the window breaks by class priority
local t1 = { key = "t1", class = 6, rel = 0.1 }
local t2 = { key = "t2", class = 4, rel = -0.1 }
own = compass.SelectLabel({ n = 2, t1, t2 }, {}, 30.0)
check(own == t2, "label tie: equal distance resolves by class (turn-in beats available)")

-- ---------------------------------------------------------------------------
-- (i) cap enforcement -- lowest class dropped first, nearest kept within class
-- ---------------------------------------------------------------------------
local caplist = { n = 0 }
local seq = {
  { class = 5, dist2 = 10 }, { class = 5, dist2 = 5 }, { class = 3, dist2 = 7 },
  { class = 4, dist2 = 1 }, { class = 5, dist2 = 2 }, { class = 2, dist2 = 9 },
}
local evicted = 0
for i = 1, 6 do
  if compass.CapInsert(caplist, 4, seq[i]) then evicted = evicted + 1 end
end
check(caplist.n == 4 and evicted == 2, "cap: 6 candidates, cap 4 -> 2 evicted")
check(caplist[1].class == 2 and caplist[2].class == 3 and caplist[3].class == 4,
      "cap: higher classes all survive")
check(caplist[4].class == 5 and near(caplist[4].dist2, 2),
      "cap: nearest of the lowest class kept, farther ones dropped first")

-- ---------------------------------------------------------------------------
-- (j) end-to-end: drive the real OnUpdate over the synthetic zone and check
-- the pooled widgets bind, clamp and label
-- ---------------------------------------------------------------------------
compass.BuildMarkers(0.4, 0.6, target, false)
facing = facing + 0.01 -- defeat the dirty-skip
okE, errE = fireOnUpdate()
check(okE, "OnUpdate over the synthetic zone%s", okE and "" or " -> " .. tostring(errE))
local shown, mergedN = 0, 0
for i = 1, list.n do
  if compass.markers[i]:IsShown() then shown = shown + 1 end
  if list[i].merged then mergedN = mergedN + 1 end
end
check(shown == list.n - mergedN and shown >= 1,
      "all %d unmerged markers render (%d shown, %d merged away)", list.n - mergedN, shown, mergedN)
local anyclamped = nil
for i = 1, list.n do if list[i].clamped then anyclamped = true end end
check(anyclamped and true or false, "behind-the-player markers report clamped=true after a fire")
-- indoors: 0,0 position hides every marker but keeps the strip
posx, posy = 0, 0
facing = facing + 0.01
okE, errE = fireOnUpdate()
check(okE, "OnUpdate indoors (0,0)%s", okE and "" or " -> " .. tostring(errE))
shown = 0
for i = 1, 12 do if compass.markers[i]:IsShown() then shown = shown + 1 end end
check(shown == 0, "indoors: every marker hidden (position unknown, bearings would lie)")
check(compass:IsShown() == true, "indoors: the strip itself stays up (facing still valid)")
posx, posy = 0.4, 0.6

-- ---------------------------------------------------------------------------
-- (k) overlap collapse: plates within MERGE_PX hide behind the most important
-- one at that spot (maintainer QA: three ? plates stacked over one camp and a
-- cardinal letter). Slots arrive sorted by (class asc, dist asc) like the real
-- list; kept/merged is decided against KEPT plates only.
-- ---------------------------------------------------------------------------
local mslots = {
  { key = "a", class = 3, off = 100 },
  { key = "b", class = 4, off = 110 },  -- 10px from kept a -> merges
  { key = "c", class = 5, off = 130 },  -- 20px from MERGED b, 30 from kept a -> kept
  { key = "d", class = 5, off = -100 }, -- alone on the left -> kept
  { key = "e", class = 6, off = -104 }, -- 4px from kept d -> merges
  n = 5,
}
compass.MergeOverlaps(mslots, 16)
check(not mslots[1].merged and not mslots[4].merged,
      "merge: highest-priority plate at each spot kept")
check(mslots[2].merged and mslots[5].merged,
      "merge: overlapping lower-priority plates hidden")
check(not mslots[3].merged,
      "merge: distance measured against kept plates only, not merged ones")
local lstate2 = {}
local lslots2 = {
  { key = "k1", class = 4, rel = 0.10, off = 40 },
  { key = "k2", class = 5, rel = 0.02, off = 44, merged = true },
  n = 2,
}
local lowner2 = compass.SelectLabel(lslots2, lstate2, 100)
check(lowner2 and lowner2.key == "k1",
      "label: a merged (hidden) marker cannot own the label")

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
