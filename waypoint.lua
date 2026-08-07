-- pfQuest Reforged -- custom user waypoint (/way + ALT-click on the world map)
-- New Reforged machinery, no upstream counterpart. ONE user-placed point that
-- every Reforged guidance surface follows: the compass strip renders it as
-- CLASS_WAYPOINT, the in-world pins prefer it over the route target (never
-- over the corpse), and the stock route arrow follows it through pfQuest's
-- OWN machinery -- the waypoint is registered as a real pfMap node carrying
-- the meta `arrow = true` flag, which map.lua:1230 unconditionally admits
-- into the route candidates, and route.SetTarget orders it first. No
-- route.lua changes and no synthetic entries injected into route.coords.
-- Storage: pfQuest_config.customwaypoint = { x, y, zone, label } (persists
-- relogs; a single point, setting a new one replaces).

-- standalone guard (compass.lua idiom): without the quest core and the map
-- module there is nothing to hang a waypoint on
if not pfQuest or not pfQuest.route or not pfMap then return end

local floor, sqrt = math.floor, math.sqrt
local strfind, gsub = string.find, string.gsub
local GetTime = GetTime
local GetPlayerMapPosition = GetPlayerMapPosition
local GetRealZoneText = GetRealZoneText

local L = pfQuest_Loc
local PATH = (pfQuestConfig and pfQuestConfig.path) or "Interface\\AddOns\\pfQuest"
local ICON = PATH .. "\\img\\fav"
local accent = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1.0, 0.8 }

-- arrival auto-clear radius (yards) and the ALT-click "same spot" clear
-- radius (map percent, Euclidean -- ~2% of a zone axis)
local ARRIVE_YD2 = 15 * 15
local CLEAR_PCT2 = 2 * 2

local waypoint = {}
pfQuest.waypoint = waypoint

local function Message(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest|r: " .. text)
end

-- node-shaped table the PINS tier binds (title/texture/vertex, the BindIcon
-- contract). Rebuilt fresh on every Set so the identity change drives the
-- pins' icon/text rebinds; the star art (img/fav, pfQuest's user-marked
-- language) is vertex-tinted in the theme accent.
local function BuildPinNode(label)
  waypoint.pinnode = {
    title = label or L["Waypoint"],
    texture = ICON,
    vertex = { accent[1], accent[2], accent[3] },
  }
end

-- validated read of the saved point; nil when unset or malformed (a hand-
-- edited saved variable must degrade to "no waypoint", never error). Self-
-- heals the pins node binding, so consumers never race the login rebuild.
function waypoint.Get()
  local wp = pfQuest_config and pfQuest_config.customwaypoint
  if wp and tonumber(wp.x) and tonumber(wp.y) and tonumber(wp.zone) then
    if not waypoint.pinnode then BuildPinNode(wp.label) end
    return wp
  end
  return nil
end

-- the stored pfMap node (needed to release the route target on clear)
local mapnode

function waypoint.NodeClick()
  -- clicking the waypoint map pin clears it (any modifier)
  waypoint.Clear()
end

-- register the waypoint as a real pfMap node. meta.arrow = true is the
-- load-bearing bit: UpdateNodes admits arrow-flagged pins into the route
-- candidates regardless of the route* config (map.lua:1230), so the route
-- arrow, the route lines and the minimap all follow for free. layer is
-- preseeded to GetLayerByTexture(nil) = 1 so SetTarget's captured layer
-- matches what UpdateNode later recomputes -- IsTarget compares field
-- values, and a nil-vs-1 mismatch would silently drop the target ordering.
local function PlaceMapNode()
  local wp = waypoint.Get()
  if not wp or not pfMap.AddNode then return end
  pfMap:DeleteNode("PFWAY")
  local title = wp.label or L["Waypoint"]
  pfMap:AddNode({
    ["addon"] = "PFWAY",
    ["zone"] = wp.zone,
    ["x"] = wp.x,
    ["y"] = wp.y,
    ["title"] = title,
    ["spawn"] = title,
    ["layer"] = 1,
    ["arrow"] = true,
    ["icon"] = ICON,
    ["func"] = waypoint.NodeClick,
  })
  local coords = wp.x .. "|" .. wp.y
  mapnode = pfMap.nodes["PFWAY"] and pfMap.nodes["PFWAY"][wp.zone]
    and pfMap.nodes["PFWAY"][wp.zone][coords]
    and pfMap.nodes["PFWAY"][wp.zone][coords][title] or nil
  if mapnode and pfQuest.route.SetTarget then
    pfQuest.route.SetTarget(mapnode)
  end
  if pfMap.UpdateNodes then pfMap:UpdateNodes() end
end

function waypoint.Set(x, y, zone, label)
  if not pfQuest_config then return end
  x = floor(x * 10 + 0.5) / 10
  y = floor(y * 10 + 0.5) / 10
  pfQuest_config.customwaypoint = { ["x"] = x, ["y"] = y, ["zone"] = zone, ["label"] = label }
  BuildPinNode(label)
  PlaceMapNode()
  local where = x .. ", " .. y
  Message(L["Waypoint set"] .. ": " .. where .. (label and (" (" .. label .. ")") or ""))
end

-- reached = true announces arrival instead of a plain clear
function waypoint.Clear(reached)
  local had = waypoint.Get()
  if pfQuest_config then pfQuest_config.customwaypoint = nil end
  waypoint.pinnode = nil
  if pfMap.DeleteNode then pfMap:DeleteNode("PFWAY") end
  if mapnode and pfQuest.route.IsTarget and pfQuest.route.IsTarget(mapnode) then
    pfQuest.route.SetTarget(nil)
  end
  mapnode = nil
  if pfMap.UpdateNodes then pfMap:UpdateNodes() end
  if had then
    Message(reached and L["Waypoint reached"] or L["Waypoint cleared"])
  end
end

-- current PLAYER zone id, memoized by zone text (map.lua:1322 idiom)
local zoneName, zoneID
local function CurrentZoneID()
  local rz = GetRealZoneText()
  if rz ~= zoneName then
    zoneName = rz
    zoneID = pfMap.GetMapIDByName and pfMap:GetMapIDByName(rz) or nil
  end
  return zoneID
end

-- /way body (registered in slashcmd.lua): "/way 45 67", "/way 45 67 Meet
-- here", "/way" alone clears. Kept here so the harness can drive the parse
-- cases without loading the whole slash file.
function waypoint.HandleCommand(input)
  input = input or ""
  local _, _, xs, ys, label = strfind(input, "^%s*([%d%.,]+)%s+([%d%.,]+)%s*(.-)%s*$")
  if not xs then
    if strfind(input, "%S") then
      Message(L["Usage"] .. ": /way 45 67 [" .. L["label"] .. "], /way " .. L["clears the waypoint"])
    elseif waypoint.Get() then
      waypoint.Clear()
    else
      Message(L["No waypoint set"] .. ". " .. L["Usage"] .. ": /way 45 67 [" .. L["label"] .. "]")
    end
    return
  end
  -- decimal comma tolerated ("45,5 67,2")
  local x = tonumber((gsub(xs, ",", ".")))
  local y = tonumber((gsub(ys, ",", ".")))
  if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
    Message(L["Invalid coordinates"] .. ". " .. L["Usage"] .. ": /way 45 67 [" .. L["label"] .. "]")
    return
  end
  local zone = CurrentZoneID()
  if not zone then
    Message(L["The current zone is not in the database"])
    return
  end
  waypoint.Set(x, y, zone, label ~= "" and label or nil)
end

-- ALT+left-click on the open world map canvas sets the waypoint there;
-- ALT-clicking again near the current one (or /way) clears it. ALT, not
-- CTRL: holding CTRL over the map is already pfQuest's hide-cluster gesture
-- (map.lua:50, "Hold <Ctrl> To Hide Cluster") so CTRL-click would fight it;
-- ALT is unused on the map canvas (only tracker rows use ALT-click,
-- tracker.lua:507). Returns true when the click was consumed.
function waypoint.MapClick()
  -- the VIEWED map must resolve to a database zone; on the continent view
  -- return nil so the stock zoom-in still happens
  local zone = pfMap.GetMapID and pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone()) or nil
  if not zone then return nil end
  -- cursor -> map percent, the WorldMapButton_OnClick formula (FrameXML
  -- 3.3.5a WorldMapFrame.lua:722: screen pixels over GetEffectiveScale)
  local x, y = GetCursorPosition()
  local scale = WorldMapButton:GetEffectiveScale()
  x, y = x / scale, y / scale
  local cx, cy = WorldMapButton:GetCenter()
  local w, h = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
  if not cx or not w or w == 0 or h == 0 then return nil end
  local px = (x - (cx - w / 2)) / w * 100
  local py = ((cy + h / 2) - y) / h * 100
  if px < 0 or px > 100 or py < 0 or py > 100 then return nil end
  px = floor(px * 10 + 0.5) / 10
  py = floor(py * 10 + 0.5) / 10
  local wp = waypoint.Get()
  if wp and wp.zone == zone then
    local dx, dy = px - wp.x, py - wp.y
    if dx * dx + dy * dy <= CLEAR_PCT2 then
      waypoint.Clear()
      return true
    end
  end
  waypoint.Set(px, py, zone)
  return true
end

-- hook the GLOBAL, the map.lua:1608 idiom: the 3.3.5a XML function= binding
-- resolves the global at call time (proven by the shipped
-- WorldMapQuestFrame_OnMouseUp hook working in-game)
if type(WorldMapButton_OnClick) == "function" then
  local pfHookWorldMapButton_OnClick = WorldMapButton_OnClick
  WorldMapButton_OnClick = function(frame, mouseButton)
    if mouseButton == "LeftButton" and IsAltKeyDown() and waypoint.MapClick() then
      return
    end
    pfHookWorldMapButton_OnClick(frame, mouseButton)
  end
end

-- driver: arrival auto-clear (~15 yd) plus the login rebuild of the map
-- node from the saved point. Class-B loop: one throttle compare per frame,
-- then a table read and a few compares twice a second -- independent of the
-- compass/pins toggles, because the arrival notice must fire even when only
-- the map node is guiding.
local driver = CreateFrame("Frame", nil, UIParent)
waypoint.driver = driver
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function()
  -- saved point survives relogs; rebuild the map node and the pins binding
  local wp = waypoint.Get()
  if wp then
    BuildPinNode(wp.label)
    PlaceMapNode()
  end
end)
driver:SetScript("OnUpdate", function()
  if (this.tick or 0) > GetTime() then return end
  this.tick = GetTime() + 0.5
  local wp = waypoint.Get()
  if not wp then return end
  local xp, yp = GetPlayerMapPosition("player")
  -- 0,0 = position unknown (indoors/instance): no honest distance
  if xp == 0 and yp == 0 then return end
  if wp.zone ~= CurrentZoneID() then return end
  -- zone yard dimensions (map.lua:271); without size data never auto-clear
  -- on a guessed distance
  local size = pfMap.minimap_sizes and pfMap.minimap_sizes[wp.zone]
  if not size or not size[1] or not size[2] then return end
  local dx = (wp.x / 100 - xp) * size[1]
  local dy = (wp.y / 100 - yp) * size[2]
  if dx * dx + dy * dy <= ARRIVE_YD2 then
    waypoint.Clear(true)
  end
end)
