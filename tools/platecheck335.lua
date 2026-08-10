-- Quest-plate contract check: load the REAL nameplates.lua under the 3.3.5a frame
-- stub, fake the addon surface at the seams (pfMap.tooltips, pfQuest_config, the
-- WorldFrame child list, C_NamePlate for the native tier) and drive the actual
-- public functions plus the driver OnUpdate. Same mold as compasscheck335.lua:
-- real module, faked seams, assertions that can actually fail. Blocks:
--   (a) name-index classification (kill/loot/interact/ready-ender/available;
--       not-ready ender, available_c, other-zone giver and PFDB nodes EXCLUDED)
--   (b) stock-tier plate detection (border plate, ElvUI-style .UnitFrame plate,
--       non-plate child rejected)
--   (c) icon shows on a matching plate, hides on quest removal from the index
--   (d) settings clamps + live apply, enable toggle both ways
--   (e) GW2 UI dedupe (module presence defers; explicit GW2 off re-enables)
--   (f) native tier: NAME_PLATE_UNIT_ADDED/REMOVED drive icons by unit token
--
-- Usage: lua5.1 tools/platecheck335.lua [nameplates.lua]   (from the addon root)

local PLATE_FILE = arg and arg[1] or "nameplates.lua"

local failures, checks = 0, 0
local function fail(f, ...) failures = failures + 1; print("  FAIL  " .. string.format(f, ...)) end
local function ok(f, ...) checks = checks + 1; print("  ok    " .. string.format(f, ...)) end
local function check(cond, f, ...) if cond then ok(f, ...) else fail(f, ...) end end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-4 end

dofile("tools/framestub335.lua").install()

-- the stub's GetTime is frozen; the driver throttles at now + 0.25, so advance
-- time on each read and give fireTicks a big enough step to always pass it
do
  local now = 1000
  _G.GetTime = function() now = now + 0.3 return now end
end
_G.GetRealmName = function() return "Testrealm" end
_G.UnitIsPlayer = function() return nil end

-- ---------------------------------------------------------------------------
-- the addon surface nameplates.lua expects, faked at the seams
-- ---------------------------------------------------------------------------
_G.pfQuest_config = {
  plateicons = "1", plateiconscale = "100",
  plateiconx = "-17", plateicony = "-7", clustermono = "0",
}
_G.pfQuestConfig = { path = "pfQuest-Reforged" }
_G.pfQuest = {}
_G.pfDatabase = {}
_G.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return tostring(k) end })
-- one row so the GW2 hint mutation has a place to land (config.lua shape)
_G.pfQuest_defconfig = {
  { text = "Quest Icons On Nameplates", default = "1", type = "checkbox", config = "plateicons" },
}

-- pfMap seam: tooltips is the spawn-keyed index AddNode maintains
-- (map.lua:774): tooltips[spawn][title][map] = node meta. queue_update bumps
-- on node writes; PlayerZoneID mirrors the shared memoizer.
local mapid, zonename = 113, "Testzone"
local IMG = "pfQuest-Reforged\\img\\"
_G.pfMap = {
  queue_update = 1,
  PlayerZoneID = function() return mapid, zonename end,
  tooltips = {},
}

-- meta shapes mirror what SearchMobID/SearchItemID/SearchQuests store:
-- objective spawn nodes are untextured with spawntype/item (AddNode wraps
-- item into a table, map.lua:727); giver/ender nodes carry the texture.
pfMap.tooltips = {
  -- kill objective: untextured Unit spawn, empty item table
  ["Ravager"] = { ["Kill Quest"] = { [113] = { addon = "PFQUEST", spawntype = "Unit", item = {} } } },
  -- loot objective: drop-source unit, item name wrapped by AddNode
  ["Webwood Spider"] = { ["Loot Quest"] = { [113] = { addon = "PFQUEST", spawntype = "Unit", item = { "Spider Silk" }, itemid = 123 } } },
  -- interact objective: object spawn
  ["Strange Lever"] = { ["Use Quest"] = { [113] = { addon = "PFQUEST", spawntype = "Object", item = {} } } },
  -- ready turn-in ender: complete_c (database.lua:1671)
  ["Ready Ender"] = { ["Done Quest"] = { [113] = { addon = "PFQUEST", texture = IMG .. "complete_c" } } },
  -- NOT-ready ender: plain complete -- must be EXCLUDED
  ["Busy Ender"] = { ["Open Quest"] = { [113] = { addon = "PFQUEST", texture = IMG .. "complete" } } },
  -- available giver in the current zone
  ["Zone Giver"] = { ["New Quest"] = { [113] = { addon = "PFQUEST", texture = IMG .. "available" } } },
  -- available giver in ANOTHER zone -- excluded (givers are zone-gated)
  ["Far Giver"] = { ["Far Quest"] = { [999] = { addon = "PFQUEST", texture = IMG .. "available" } } },
  -- giver of a quest already in the log (available_c) -- excluded
  ["Current Giver"] = { ["Log Quest"] = { [113] = { addon = "PFQUEST", texture = IMG .. "available_c" } } },
  -- browser /db track node (addon PFDB) -- excluded, not quest-driven
  ["Browser Track"] = { ["Browser Track"] = { [113] = { addon = "PFDB", spawntype = "Unit", item = {} } } },
  -- one name in two roles: loot objective AND ready turn-in -> turn-in wins
  ["Dual Role"] = {
    ["Loot Quest 2"] = { [113] = { addon = "PFQUEST", spawntype = "Unit", item = { "Gizmo" } } },
    ["Done Quest 2"] = { [113] = { addon = "PFQUEST", texture = IMG .. "complete_c" } },
  },
}

-- ---------------------------------------------------------------------------
-- load the REAL module (stock tier first: no C_NamePlate)
-- ---------------------------------------------------------------------------
local loaded, err = pcall(dofile, PLATE_FILE)
if not loaded then
  fail("%s could not be loaded under the stub: %s", PLATE_FILE, tostring(err))
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
ok("%s loads under the stub", PLATE_FILE)

local np = pfQuest and pfQuest.nameplates
check(type(np) == "table", "pfQuest.nameplates exists (public surface)")
local missing = 0
for _, m in ipairs({ "ClassifyMeta", "BuildIndex", "IsNamePlate", "ScanChildren",
                     "RefreshPlates", "Gw2QuestPlatesActive" }) do
  local has = np and type(np[m]) == "function"
  check(has, "pfQuest.nameplates.%s is a function", m)
  if not has then missing = missing + 1 end
end
if type(np) ~= "table" or missing > 0 then
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
check(np.HasNativeAPI == false, "stock tier detected while C_NamePlate is absent")

local K = np.KIND

-- ---------------------------------------------------------------------------
-- (a) name-index classification
-- ---------------------------------------------------------------------------
np.BuildIndex()
local ix = np.index
check(ix["Ravager"] == K.KILL, "index: kill objective unit -> KILL")
check(ix["Webwood Spider"] == K.LOOT, "index: item drop source -> LOOT")
check(ix["Strange Lever"] == K.INTERACT, "index: object spawn -> INTERACT")
check(ix["Ready Ender"] == K.TURNIN, "index: complete_c ender -> TURNIN")
check(ix["Zone Giver"] == K.AVAIL, "index: in-zone available giver -> AVAIL")
check(ix["Busy Ender"] == nil, "index: NOT-ready ender (plain complete) EXCLUDED")
check(ix["Far Giver"] == nil, "index: other-zone giver EXCLUDED (zone gate)")
check(ix["Current Giver"] == nil, "index: available_c (giver of in-log quest) EXCLUDED")
check(ix["Browser Track"] == nil, "index: PFDB browser-track node EXCLUDED")
check(ix["Dual Role"] == K.TURNIN, "index: multi-role name resolves to the highest priority (TURNIN)")

-- cluster textures classify like the map does (a stored cluster node also
-- lands in tooltips; the same walk must read it identically)
check(np.ClassifyMeta({ addon = "PFQUEST", texture = IMG .. "cluster_mob" }, false) == K.KILL,
      "classify: cluster_mob texture -> KILL")
check(np.ClassifyMeta({ addon = "PFQUEST", texture = IMG .. "cluster_item_mono" }, false) == K.LOOT,
      "classify: cluster_item (mono variant) texture -> LOOT")
check(np.ClassifyMeta({ addon = "PFQUEST", texture = IMG .. "cluster_misc" }, false) == K.INTERACT,
      "classify: cluster_misc texture -> INTERACT")
check(np.ClassifyMeta({ addon = "PFQUEST", texture = IMG .. "available" }, true) == K.AVAIL
      and np.ClassifyMeta({ addon = "PFQUEST", texture = IMG .. "available" }, false) == nil,
      "classify: available giver honors the inzone gate")

-- ---------------------------------------------------------------------------
-- (b) stock-tier plate detection against synthetic frames
-- ---------------------------------------------------------------------------
local NP_BORDER = "Interface\\Tooltips\\Nameplate-Border"

local function region(objtype, tex)
  local r = {}
  function r.GetObjectType() return objtype end
  function r.GetTexture() return tex end
  return r
end
local function nameFS(text)
  local fs = { text = text }
  function fs.GetText(s) return s.text end
  function fs.SetText(s, t) s.text = t end
  function fs.GetObjectType() return "FontString" end
  return fs
end
-- a Blizzard-shaped plate: border texture in region slot 2, name in slot 7
local function mkStockPlate(name)
  local f = CreateFrame("Frame", nil, WorldFrame)
  f.regionList = {
    region("Texture", "Interface\\ArtBar"), region("Texture", NP_BORDER),
    region("Texture"), region("Texture"), region("Texture"), region("Texture"),
    nameFS(name),
  }
  function f.GetRegions(s) return unpack(s.regionList) end
  return f
end
-- an ElvUI-style skinned plate: .UnitFrame field, Blizzard regions intact
local function mkElvPlate(name)
  local f = mkStockPlate(name)
  f.regionList[2] = region("Texture", "ElvUI\\StatusBar") -- border replaced by the skin
  f.UnitFrame = {}
  return f
end
-- a non-plate WorldFrame child (some other addon's frame)
local function mkJunk()
  local f = CreateFrame("Frame", nil, WorldFrame)
  f.regionList = { region("Texture", "Interface\\Foo"), region("Texture", "Interface\\Bar") }
  function f.GetRegions(s) return unpack(s.regionList) end
  return f
end

check(np.IsNamePlate(mkStockPlate("X")) == true, "detect: border-texture plate recognized")
check(np.IsNamePlate(mkElvPlate("X")) == true, "detect: ElvUI-style .UnitFrame plate recognized")
check(not np.IsNamePlate(mkJunk()), "detect: non-plate WorldFrame child rejected")

-- ---------------------------------------------------------------------------
-- (c) end-to-end through the driver: scan, match, show, then hide on removal
-- ---------------------------------------------------------------------------
local wfChildren = {}
function WorldFrame.GetNumChildren() return table.getn(wfChildren) end
function WorldFrame.GetChildren() return unpack(wfChildren) end

local plateKill = mkStockPlate("Ravager")
local plateEnder = mkElvPlate("Ready Ender")
local plateNone = mkStockPlate("Innocent Bystander")
local junk = mkJunk()
wfChildren[1], wfChildren[2], wfChildren[3], wfChildren[4] = plateKill, plateEnder, plateNone, junk

-- shagu idiom: the client sets `this` before every handler call
local function fireTick()
  _G.this = np.driver
  local okF, errF = pcall(np.driver.Fire, np.driver, "OnUpdate")
  _G.this = nil
  return okF, errF
end

local okT, errT = fireTick()
check(okT, "driver tick 1 (activation + scan)%s", okT and "" or " -> " .. tostring(errT))
okT, errT = fireTick()
check(okT, "driver tick 2 (steady path)%s", okT and "" or " -> " .. tostring(errT))

check(np.plates[plateKill] ~= nil and np.plates[plateEnder] ~= nil,
      "scan: both plates registered with their name region")
check(np.plates[junk] == nil, "scan: the junk child was not registered")

local iconKill = np.icons[plateKill]
check(iconKill ~= nil and iconKill:IsShown(), "icon: shown on the kill-objective plate")
check(iconKill ~= nil and iconKill.tex and iconKill.tex:GetTexture() == np.ICONS[K.KILL],
      "icon: kill plate carries the cluster_mob texture")
local iconEnder = np.icons[plateEnder]
check(iconEnder ~= nil and iconEnder:IsShown(), "icon: shown on the ready turn-in plate (skinned)")
check(iconEnder ~= nil and iconEnder.tex:GetTexture() == np.ICONS[K.TURNIN],
      "icon: turn-in plate carries the complete_c texture")
check(np.icons[plateNone] == nil or not np.icons[plateNone]:IsShown(),
      "icon: no icon on a non-quest name")

-- OnShow hook: recycle the no-match plate into a quest mob and re-show it
plateNone.regionList[7]:SetText("Zone Giver")
_G.this = plateNone
plateNone:Fire("OnShow")
_G.this = nil
local iconGiver = np.icons[plateNone]
check(iconGiver ~= nil and iconGiver:IsShown() and iconGiver.tex:GetTexture() == np.ICONS[K.AVAIL],
      "recycle: OnShow re-reads the name and shows the available icon")

-- OnHide hook clears the icon
_G.this = plateNone
plateNone:Fire("OnHide")
_G.this = nil
check(not iconGiver:IsShown(), "recycle: OnHide hides the icon")
plateNone.shown = true

-- quest completion/removal: the mob leaves the index -> icon hides on refresh
pfMap.tooltips["Ravager"] = nil
pfMap.queue_update = 2 -- DeleteNode bumps this on the real path
fireTick()
check(np.index["Ravager"] == nil, "removal: name gone from the index after the rebuild")
check(not iconKill:IsShown(), "removal: kill plate icon hidden after quest removal")
check(iconEnder:IsShown(), "removal: unrelated plate icon stays")

-- zone change re-gates givers: leaving the zone drops the in-zone giver
zonename, mapid = "Otherzone", 999
fireTick()
check(np.index["Zone Giver"] == nil and np.index["Far Giver"] == K.AVAIL,
      "zone change: giver gate follows the player zone")
zonename, mapid = "Testzone", 113
fireTick()
check(np.index["Zone Giver"] == K.AVAIL, "zone change: back home restores the giver")

-- ---------------------------------------------------------------------------
-- (d) settings clamps + live apply
-- ---------------------------------------------------------------------------
pfQuest_config["plateiconscale"] = "500" -- clamps to 200 -> 32px
fireTick()
check(near(iconEnder:GetWidth(), 32), "settings: scale 500 clamps to 200 (32px, got %s)",
      tostring(iconEnder:GetWidth()))
pfQuest_config["plateiconscale"] = "10" -- clamps to 50 -> 8px
fireTick()
check(near(iconEnder:GetWidth(), 8), "settings: scale 10 clamps to 50 (8px)")
pfQuest_config["plateiconscale"] = "100"
pfQuest_config["plateiconx"] = "-500" -- clamps to -100
pfQuest_config["plateicony"] = "500" -- clamps to 100
fireTick()
local pt = iconEnder.points and iconEnder.points.LEFT
check(pt ~= nil and near(pt.x, -100) and near(pt.y, 100),
      "settings: x/y offsets clamp to +/-100 (got %s,%s)",
      tostring(pt and pt.x), tostring(pt and pt.y))
pfQuest_config["plateiconx"] = "-17"
pfQuest_config["plateicony"] = "-7"
fireTick()
pt = iconEnder.points and iconEnder.points.LEFT
check(pt ~= nil and near(pt.x, -17) and near(pt.y, -7), "settings: defaults re-apply live")

-- clustermono flips the cluster texture set live
pfMap.tooltips["Ravager"] = { ["Kill Quest"] = { [113] = { addon = "PFQUEST", spawntype = "Unit", item = {} } } }
pfMap.queue_update = 3
fireTick()
check(iconKill:IsShown() and iconKill.tex:GetTexture() == np.ICONS[K.KILL],
      "settings: kill icon back after re-add (color set)")
pfQuest_config["clustermono"] = "1"
fireTick()
check(iconKill.tex:GetTexture() == np.ICONS_MONO[K.KILL],
      "settings: clustermono=1 swaps to the mono cluster texture live")
pfQuest_config["clustermono"] = "0"
fireTick()

-- master toggle: off hides everything, on restores
pfQuest_config["plateicons"] = "0"
fireTick()
check(not iconKill:IsShown() and not iconEnder:IsShown(),
      "toggle: plateicons=0 hides every icon")
pfQuest_config["plateicons"] = "1"
fireTick()
fireTick()
check(iconKill:IsShown() and iconEnder:IsShown(),
      "toggle: plateicons=1 restores the icons without a reload")

-- ---------------------------------------------------------------------------
-- (e) GW2 UI dedupe
-- ---------------------------------------------------------------------------
check(np.Gw2QuestPlatesActive() == nil, "dedupe: no GW2 module -> pfQuest icons run")
_G.GwQuestPlateScanTip = {} -- GW2's quest plate module presence probe
check(np.Gw2QuestPlatesActive() == true, "dedupe: GW2 module present -> GW2 owns the plates")
fireTick()
check(not iconKill:IsShown() and not iconEnder:IsShown(),
      "dedupe: plateicons=1 treated as off while GW2 icons are active")
-- explicit GW2-off in the readable AceDB profile re-enables pfQuest
_G.GW2UI_DATABASE = {
  profileKeys = { ["Tester - Testrealm"] = "Default" },
  profiles = { ["Default"] = { NAMEPLATES_QUEST_ICON = false } },
}
check(np.Gw2QuestPlatesActive() == nil,
      "dedupe: GW2 quest icons explicitly off in its profile -> pfQuest may run")
fireTick()
fireTick()
check(iconKill:IsShown(), "dedupe: icons return once GW2's own icons are off")
-- flipping GW2 back on defers again
GW2UI_DATABASE.profiles["Default"].NAMEPLATES_QUEST_ICON = true
fireTick()
check(not iconKill:IsShown(), "dedupe: re-enabling GW2's icons defers pfQuest again")
_G.GwQuestPlateScanTip = nil
_G.GW2UI_DATABASE = nil
fireTick()
fireTick()
check(iconKill:IsShown(), "dedupe: GW2 gone -> pfQuest icons run again")

-- the settings-row hint lands when the module loads with GW2 active: reload
-- the file with the probe set and inspect the defconfig row
_G.GwQuestPlateScanTip = {}
dofile(PLATE_FILE)
check(pfQuest_defconfig[1].desc == "GW2 UI quest icons are active",
      "dedupe: settings row hints 'GW2 UI quest icons are active'")
_G.GwQuestPlateScanTip = nil

-- ---------------------------------------------------------------------------
-- (f) native tier (AwesomeWotLK-class): reload with C_NamePlate faked
-- ---------------------------------------------------------------------------
local tokenPlates = {}
local tokenNames = { nameplate1 = "Ravager", nameplate2 = "Innocent Bystander", nameplate3 = "PlayerToon" }
tokenPlates.nameplate1 = CreateFrame("Frame", nil, WorldFrame)
tokenPlates.nameplate2 = CreateFrame("Frame", nil, WorldFrame)
tokenPlates.nameplate3 = CreateFrame("Frame", nil, WorldFrame)
_G.C_NamePlate = {
  GetNamePlateForUnit = function(unit) return tokenPlates[unit] end,
}
_G.UnitName = function(u)
  if u == "player" then return "Tester" end
  return tokenNames[u]
end
_G.UnitIsPlayer = function(u) return u == "nameplate3" and 1 or nil end

dofile(PLATE_FILE) -- fresh instance picks the native tier
local np2 = pfQuest.nameplates
check(np2 ~= np and np2.HasNativeAPI == true, "native: tier detected via C_NamePlate")
check(np2.nativeDriver ~= nil and np2.nativeDriver.events
      and np2.nativeDriver.events["NAME_PLATE_UNIT_ADDED"] == true
      and np2.nativeDriver.events["NAME_PLATE_UNIT_REMOVED"] == true,
      "native: NAME_PLATE_UNIT_ADDED/REMOVED registered (feature-gated)")

local function fireTick2()
  _G.this = np2.driver
  local okF, errF = pcall(np2.driver.Fire, np2.driver, "OnUpdate")
  _G.this = nil
  return okF, errF
end
local function fireUnitEvent(ev, unit)
  _G.this = np2.nativeDriver
  _G.event = ev
  _G.arg1 = unit
  local okF, errF = pcall(np2.nativeDriver.Fire, np2.nativeDriver, "OnEvent", ev, unit)
  _G.this, _G.event, _G.arg1 = nil, nil, nil
  return okF, errF
end

fireTick2() -- activation + index build
local okN, errN = fireUnitEvent("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(okN, "native: ADDED handler fires%s", okN and "" or " -> " .. tostring(errN))
local nIcon = np2.icons[tokenPlates.nameplate1]
check(nIcon ~= nil and nIcon:IsShown() and nIcon.tex:GetTexture() == np2.ICONS[K.KILL],
      "native: quest mob token gets the kill icon via UnitName(token)")
fireUnitEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
check(np2.icons[tokenPlates.nameplate2] == nil or not np2.icons[tokenPlates.nameplate2]:IsShown(),
      "native: non-quest token gets no icon")
fireUnitEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")
check(np2.icons[tokenPlates.nameplate3] == nil or not np2.icons[tokenPlates.nameplate3]:IsShown(),
      "native: player plates are skipped (UnitIsPlayer)")
fireUnitEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check(not nIcon:IsShown() and np2.nativePlates.nameplate1 == nil,
      "native: REMOVED hides the icon and drops the token")

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
