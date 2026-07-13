-- Minimal vanilla-style WoW stub for headless pfQuest runs (lua5.1)
local now = 1000.0
function GetTime() return now end
function AdvanceTime(dt) now = now + dt end
function time() return 1720000000 + math.floor(now) end
function date(...) return os.date(...) end
function GetLocale() return "enUS" end
function GetAddOnMetadata() return "8.1.0" end
function debugstack() return "" end
function GetBuildInfo() return "3.3.5", "12340", "2010-06-24", 30300 end

-- string aliases
strfind, strsub, strlen, strlower, strupper, gsub, format, strrep, strbyte, strchar =
  string.find, string.sub, string.len, string.lower, string.upper, string.gsub, string.format, string.rep, string.byte, string.char
strmatch = string.match
getn = table.getn
tinsert, tremove, sort, concat = table.insert, table.remove, table.sort, table.concat
mod = math.mod or function(a,b) return a % b end
ceil, floor, abs, min, max, sqrt = math.ceil, math.floor, math.abs, math.min, math.max, math.sqrt
function strsplit(delim, s) local out = {} for tok in string.gmatch(s, "([^"..delim.."]+)") do out[#out+1]=tok end return unpack(out) end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end

-- global strings (3.3.5 enUS)
QUEST_MONSTERS_KILLED = "%s slain: %d/%d"
QUEST_OBJECTS_FOUND = "%s: %d/%d"
QUEST_ITEMS_NEEDED = "%s: %d/%d"
QUEST_FACTION_NEEDED = "%s: %s / %s"
QUEST_INTERMEDIATE_ITEMS_NEEDED = "%s: (%d)"
ERR_QUEST_UNKNOWN_COMPLETE = "Quest completed."
ERR_QUEST_OBJECTIVE_COMPLETE_S = "%s (Complete)"
UNKNOWN = "Unknown"
WORLDMAP_POI_FRAMELEVEL = 100
UIDROPDOWNMENU_MENU_LEVEL = 1

-- event + frame machinery
local eventFrames = {}
local allFrames = {}
local frameId = 0

local function mkTexture()
  local t = {}
  setmetatable(t, { __index = function(tt, k)
    local f
    if k == "GetWidth" or k == "GetHeight" or k == "GetStringWidth" or k == "GetStringHeight" then f = function() return 14 end
    elseif k == "IsShown" then f = function() return tt.__shown ~= false end
    elseif k == "Show" then f = function() tt.__shown = true end
    elseif k == "Hide" then f = function() tt.__shown = false end
    elseif k == "GetVertexColor" then f = function() return 1,1,1,1 end
    elseif k == "GetTexture" then f = function() return tt.__tex end
    elseif k == "SetTexture" then f = function(_, a) tt.__tex = a end
    elseif type(k) == "string" and string.find(k, "^%u") then f = function() end
    else return nil end
    rawset(tt, k, f)
    return f
  end })
  return t
end

function CreateFrame(ftype, name, parent, template)
  frameId = frameId + 1
  local f = { __type = ftype, __name = name, __parent = parent, __shown = true, __scripts = {}, __events = {}, __level = 1, __kids = {} }
  setmetatable(f, { __index = function(t, k)
    local fn
    if k == "SetScript" then fn = function(_, ev, h) t.__scripts[ev] = h end
    elseif k == "GetScript" then fn = function(_, ev) return t.__scripts[ev] end
    elseif k == "HookScript" then fn = function(_, ev, h) local o = t.__scripts[ev]; t.__scripts[ev] = o and function(...) o(...) h(...) end or h end
    elseif k == "RegisterEvent" then fn = function(_, ev) t.__events[ev] = true; eventFrames[t] = true end
    elseif k == "UnregisterEvent" then fn = function(_, ev) t.__events[ev] = nil end
    elseif k == "Show" then fn = function() t.__shown = true end
    elseif k == "Hide" then fn = function() t.__shown = false end
    elseif k == "IsShown" or k == "IsVisible" then fn = function() return t.__shown end
    elseif k == "GetName" then fn = function() return t.__name end
    elseif k == "GetParent" then fn = function() return t.__parent end
    elseif k == "SetParent" then fn = function(_, p) t.__parent = p end
    elseif k == "CreateTexture" then fn = function() return mkTexture() end
    elseif k == "CreateFontString" then fn = function() return mkTexture() end
    elseif k == "GetWidth" then fn = function() return t.__w or 140 end
    elseif k == "GetHeight" then fn = function() return t.__h or 140 end
    elseif k == "SetWidth" then fn = function(_, w) t.__w = w end
    elseif k == "SetHeight" then fn = function(_, h) t.__h = h end
    elseif k == "GetFrameLevel" then fn = function() return t.__level end
    elseif k == "SetFrameLevel" then fn = function(_, l) t.__level = l end
    elseif k == "GetZoom" then fn = function() return 0 end
    elseif k == "GetEffectiveScale" or k == "GetScale" then fn = function() return 1 end
    elseif k == "GetLeft" or k == "GetBottom" then fn = function() return 0 end
    elseif k == "GetRight" or k == "GetTop" then fn = function() return 140 end
    elseif k == "GetCenter" then fn = function() return 70, 70 end
    elseif k == "GetID" then fn = function() return t.__id or 0 end
    elseif k == "SetID" then fn = function(_, i) t.__id = i end
    elseif k == "GetChildren" then fn = function() return unpack(t.__kids) end
    elseif k == "SetAlpha" then fn = function(_, a) t.__alpha = a end
    elseif k == "GetAlpha" then fn = function() return t.__alpha or 1 end
    elseif k == "GetFontString" then fn = function() return mkTexture() end
    elseif k == "GetNormalTexture" or k == "GetHighlightTexture" or k == "GetPushedTexture" or k == "GetCheckedTexture" then fn = function() return mkTexture() end
    elseif k == "AddMessage" then fn = function(_, msg) if _G.PRINT_ADDMSG then print("DBG:", (tostring(msg):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""))) end end
    elseif type(k) == "string" and string.find(k, "^%u") then fn = function() end
    else return nil end
    rawset(t, k, fn)
    return fn
  end })
  if name then _G[name] = f end
  if parent and type(parent) == "table" and parent.__kids then tinsert(parent.__kids, f) end
  tinsert(allFrames, f)
  return f
end

function FireEvent(ev, a1, a2, a3, a4, a5)
  for f in pairs(eventFrames) do
    if f.__events[ev] and f.__scripts.OnEvent then
      _G.this, _G.event = f, ev
      _G.arg1, _G.arg2, _G.arg3, _G.arg4, _G.arg5 = a1, a2, a3, a4, a5
      local ok, err = pcall(f.__scripts.OnEvent)
      if not ok then print("EVENT-ERR", ev, err) end
    end
  end
end

function TickFrames(dt)
  AdvanceTime(dt or 0.05)
  for _, f in ipairs(allFrames) do
    if f.__shown and f.__scripts.OnUpdate then
      _G.this = f
      _G.arg1 = dt or 0.05
      local ok, err = pcall(f.__scripts.OnUpdate)
      if not ok then print("UPDATE-ERR", f.__name or "?", err) end
    end
  end
end

function hooksecurefunc(a, b, c)
  if type(a) == "table" then local o = a[b]; a[b] = function(...) local r = { o(...) } c(...) return unpack(r) end
  else local o = _G[a]; _G[a] = function(...) local r = { o(...) } b(...) return unpack(r) end end
end

-- ui singletons
UIParent = CreateFrame("Frame", "UIParent")
WorldFrame = CreateFrame("Frame", "WorldFrame")
Minimap = CreateFrame("Frame", "Minimap")
MinimapCluster = CreateFrame("Frame", "MinimapCluster")
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame") WorldMapFrame:Hide()
WorldMapButton = CreateFrame("Frame", "WorldMapButton")
WorldMapDetailFrame = CreateFrame("Frame", "WorldMapDetailFrame")
GameTooltip = CreateFrame("Frame", "GameTooltip")
UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame")
QuestLogFrame = CreateFrame("Frame", "QuestLogFrame")
QuestLogListScrollFrame = CreateFrame("Frame", "QuestLogListScrollFrame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) end }
SlashCmdList = {}
UISpecialFrames = {}
GameFontWhite = {}
STANDARD_TEXT_FONT = "font"

-- dropdown stubs
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetSelectedID() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_GetSelectedValue() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetButtonWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_SetText() end
function ToggleDropDownMenu() end
function HideDropDownMenu() end
function CloseDropDownMenus() end

-- cvars / misc
local cvars = { minimapZoom = "0", minimapInsideZoom = "0" }
function GetCVar(k) return cvars[k] or "0" end
function SetCVar(k, v) cvars[k] = tostring(v) end
function GetCVarBool(k) return cvars[k] == "1" end
function InCombatLockdown() return nil end
function IsShiftKeyDown() return nil end
function IsControlKeyDown() return nil end
function IsAltKeyDown() return nil end
function GetFramerate() return 60 end
function PlaySound() end
function GetCursorPosition() return 0, 0 end
function MouseIsOver() return nil end
function GetMouseFocus() return nil end
function CreateFont() return mkTexture() end

-- unit / player
function UnitName(u) return "Testchar" end
function UnitLevel(u) return 25 end
function UnitClass(u) return "Shaman", "SHAMAN" end
function UnitFactionGroup(u) return "Horde", "Horde" end
function UnitRace() return "Orc", "Orc" end
function UnitXP() return 0 end
function UnitXPMax() return 100 end
function UnitOnTaxi() return nil end
function UnitIsDeadOrGhost() return nil end
function GetRealmName() return "TestRealm" end
function GetNumSkillLines() return 0 end
function GetSkillLineInfo() return nil end

-- map / zone
function GetRealZoneText() return "Ashenvale" end
function GetZoneText() return "Ashenvale" end
function GetSubZoneText() return "" end
function GetMinimapZoneText() return "Ashenvale" end
function SetMapToCurrentZone() end
function SetMapZoom() end
function GetCurrentMapContinent() return 1 end
function GetCurrentMapZone() return 4 end
function GetMapZones(c) return "Ashenvale" end
function GetMapContinents() return "Kalimdor" end
function GetPlayerMapPosition() return 0.5, 0.5 end
function GetCorpseMapPosition() return 0, 0 end
function QuestMapUpdateAllQuests() return 0 end
function QuestPOIUpdateIcons() end
function GetQuestLogQuestText() return "text", "obj" end
function GetTitleText() return "" end

-- quest log: driven by the harness via _G.FAKE_QUESTLOG
-- entry = { title, level, tag, group, isHeader, isCollapsed, isComplete, isDaily, questID, objectives = { {text, type, done} } }
FAKE_QUESTLOG = {}
function GetNumQuestLogEntries()
  local total, quests = 0, 0
  for _, e in ipairs(FAKE_QUESTLOG) do total = total + 1 if not e[5] then quests = quests + 1 end end
  -- harness knob: simulate a core transiently under-reporting the count
  -- during a QUEST_LOG_UPDATE burst (real 3.3.5a private-server quirk)
  if _G.FAKE_NUMQUESTS_OVERRIDE then return total, _G.FAKE_NUMQUESTS_OVERRIDE end
  return total, quests
end
function GetQuestLogTitle(i)
  local e = FAKE_QUESTLOG[i]
  if not e then return nil end
  return e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]
end
function GetNumQuestLeaderBoards(i)
  local e = FAKE_QUESTLOG[i]
  return e and e.objectives and getn(e.objectives) or 0
end
function GetQuestLogLeaderBoard(n, i)
  local e = FAKE_QUESTLOG[i]
  local o = e and e.objectives and e.objectives[n]
  if not o then return nil end
  return o[1], o[2], o[3]
end
function IsQuestWatched(i) return nil end
function GetNumQuestWatches() return 0 end
function GetQuestLogSelection() return 0 end
function SelectQuestLogEntry() end
function GetQuestGreenRange() return 8 end
function GetDifficultyColor(l) return { r = 1, g = 1, b = 0 } end
function GetQuestDifficultyColor(l) return { r = 1, g = 1, b = 0 } end
function AddQuestWatch() end
function RemoveQuestWatch() end
function CollapseQuestHeader() end
function ExpandQuestHeader() end

StaticPopupDialogs = {}
function StaticPopup_Show() end
function StaticPopup_Hide() end
function ReloadUI() end
GetQuestLogPushable = function() return nil end

function GetAddOnInfo(a) return a, a, nil, true, "MISSING" end
function GetNumAddOns() return 0 end
function IsAddOnLoaded() return nil end
function LoadAddOn() return nil end
function EnableAddOn() end
function DisableAddOn() end

function getglobal(n) return _G[n] end
function setglobal(n, v) _G[n] = v end

RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
RED_FONT_COLOR = { r = 1, g = 0.1, b = 0.1 }
ChatFrame1 = DEFAULT_CHAT_FRAME
NUM_CHAT_WINDOWS = 1

-- 3.3.5 client ships a bit library
bit = {
  band = function(a, b) local r, p = 0, 1 while a > 0 or b > 0 do local x, y = a % 2, b % 2 if x == 1 and y == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end,
  bor = function(a, b) local r, p = 0, 1 while a > 0 or b > 0 do local x, y = a % 2, b % 2 if x == 1 or y == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end,
  lshift = function(a, n) return a * 2 ^ n end,
  rshift = function(a, n) return math.floor(a / 2 ^ n) end,
}

function GetContainerNumSlots() return 0 end
function GetContainerItemLink() return nil end
function GetContainerItemInfo() return nil end
function GetBagName() return nil end

function GetInventoryItemLink() return nil end
ItemRefTooltip = CreateFrame("Frame", "ItemRefTooltip")
ItemRefTooltip.SetHyperlink = function() end

function SecondsToTime(s) return s .. "s" end

-- (pfUI created by compat at addon load)

WatchFrame = CreateFrame("Frame", "WatchFrame")
QuestWatchFrame = WatchFrame
function GetQuestIndexForWatch() return nil end
function GetQuestLogIndexByID() return 0 end
function ShiftQuestWatches() end
function SortQuestWatches() end

function GetMapInfo() return "Ashenvale" end
function UnitSex() return 2 end
