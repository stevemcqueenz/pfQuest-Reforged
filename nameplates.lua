-- pfQuest Reforged -- Quest icons on nameplates (issue #14)
-- Reforged-authored module, no upstream counterpart. Shows pfQuest's map icon
-- language beside enemy nameplates: kill/loot/interact objective units of the
-- log quests, ready turn-in enders (?) and available quest givers (!). No
-- progress text on the plates: the compass, arrow and tracker own progress
-- (maintainer decision on the issue).
--
-- Matching is by NAME, not tooltip scanning: pfQuest already knows every
-- quest-relevant unit by name through pfMap.tooltips (the spawn-keyed index
-- AddNode maintains and DeleteNode cleans, map.lua:774), and objective
-- progress on 3.3.5a is quest-level anyway, so one hash lookup per plate is
-- exact and free. The index mirrors the map's node set: what the map shows
-- (tracking method, giver filters) is what the plates badge.
--
-- Plate access has two tiers, detected at load:
--   * native: an AwesomeWotLK-class client mod provides C_NamePlate plus the
--     NAME_PLATE_UNIT_ADDED/REMOVED events with real "nameplateN" unit
--     tokens (the same feature-detect GW2 UI Reforged uses); names come from
--     UnitName(token).
--   * stock: throttled WorldFrame child scan, child-count gated -- the
--     standard 3.3.5a technique. Plate recognition and the name region
--     follow Questie-335's findings (Compat/Nameplate.lua: border texture
--     "Interface\Tooltips\Nameplate-Border", the UnitFrame/extended/
--     aloftData/kui skinned-plate fields, name fontstring =
--     select(7, GetRegions())); the implementation is our own.
--
-- GW2 UI dedupe -- the rule as shipped: when GW2 UI's own quest plate icons
-- are active (see Gw2QuestPlatesActive), plateicons "1" is treated as off and
-- the settings row hints "GW2 UI quest icons are active". No double icons.

-- Reforged: standalone guard -- without the pfQuest core there is no name
-- source; bail before creating any frame so a partial install never errors.
if not pfQuest or not pfMap or not pfDatabase then return end

-- cache per-frame globals once (tracker.lua idiom)
local pairs, type, tonumber, select = pairs, type, tonumber, select
local strfind = string.find
local GetTime = GetTime
local PATH = (pfQuestConfig and pfQuestConfig.path) or "Interface\\AddOns\\pfQuest"

-- ---------------------------------------------------------------------------
-- name index: [unit name] = kind. Lower kind = higher priority when one name
-- serves several roles; the order mirrors the cluster classifier's precedence
-- (database.lua:1899-1913 checks item, then Unit spawns, then misc) with the
-- ready turn-in on top and the ambient giver at the bottom.
-- ---------------------------------------------------------------------------
local KIND_TURNIN, KIND_LOOT, KIND_KILL, KIND_INTERACT, KIND_AVAIL = 1, 2, 3, 4, 5

-- pfQuest's existing icon set -- the same textures the map and compass use
local ICONS = {
  [KIND_TURNIN] = PATH .. "\\img\\complete_c",
  [KIND_LOOT] = PATH .. "\\img\\cluster_item",
  [KIND_KILL] = PATH .. "\\img\\cluster_mob",
  [KIND_INTERACT] = PATH .. "\\img\\cluster_misc",
  [KIND_AVAIL] = PATH .. "\\img\\available",
}
-- clustermono variants for the three cluster kinds (map parity)
local ICONS_MONO = {
  [KIND_TURNIN] = ICONS[KIND_TURNIN],
  [KIND_LOOT] = PATH .. "\\img\\cluster_item_mono",
  [KIND_KILL] = PATH .. "\\img\\cluster_mob_mono",
  [KIND_INTERACT] = PATH .. "\\img\\cluster_misc_mono",
  [KIND_AVAIL] = ICONS[KIND_AVAIL],
}

-- classify one stored pfMap node meta by the same visual language the map and
-- compass read (compass.lua ClassifyNode texture order). Only quest-driven
-- nodes count (addon PFQUEST): a /db-tracked browser result must not badge
-- plates. `inzone` gates ONLY the available giver (maintainer: givers in the
-- current zone); objectives and ready enders show wherever the unit stands.
-- A plain `complete` ender (quest not ready) maps to nothing -- same rule as
-- the compass (a not-ready ender is clutter next to its objective icons).
local function ClassifyMeta(meta, inzone)
  if meta.addon ~= "PFQUEST" then return nil end
  local tex = meta.texture
  if tex then
    if strfind(tex, "complete_c", 1, true) then return KIND_TURNIN end
    if strfind(tex, "complete", 1, true) then return nil end
    if strfind(tex, "cluster_item", 1, true) then return KIND_LOOT end
    if strfind(tex, "cluster_mob", 1, true) then return KIND_KILL end
    if strfind(tex, "cluster_misc", 1, true) then return KIND_INTERACT end
    if strfind(tex, "available_c", 1, true) then return nil end
    if strfind(tex, "available", 1, true) then return inzone and KIND_AVAIL or nil end
    return nil
  end
  -- untextured spawn node: kill vs loot vs interact via the same meta fields
  -- the cluster pass keys on. AddNode wraps meta.item into a table (map.lua:
  -- 727), raw metas carry it as a string -- accept both shapes.
  local it = meta.item
  if meta.itemid or (type(it) == "table" and it[1]) or type(it) == "string" then
    return KIND_LOOT
  end
  if meta.spawntype == pfQuest_Loc["Unit"] then return KIND_KILL end
  return KIND_INTERACT
end

-- the index table is reused across rebuilds (wiped in place, no allocation);
-- rebuilds run at the driver tick only when pfMap.queue_update moved, so a
-- whole QUEST_LOG_UPDATE burst (delete + re-add per quest) costs ONE walk
local index = {}
local function BuildIndex()
  for k in pairs(index) do index[k] = nil end
  local tips = pfMap.tooltips
  if not tips then return end
  local zid = pfMap.PlayerZoneID and pfMap:PlayerZoneID() or nil
  for name, titles in pairs(tips) do
    local best
    for _, maps in pairs(titles) do
      for map, meta in pairs(maps) do
        local kind = ClassifyMeta(meta, zid ~= nil and map == zid)
        if kind and (not best or kind < best) then best = kind end
      end
    end
    if best then index[name] = best end
  end
end

-- ---------------------------------------------------------------------------
-- GW2 UI dedupe. Presence probe: GW2 UI Reforged's quest plate module creates
-- the named frame GwQuestPlateScanTip at load (questPlate335.lua) -- OptionalDeps
-- orders GW2_UI before us, so it exists by the time this file runs. Setting
-- probe (best effort): GW2 stores its profile in the AceDB saved variable
-- GW2UI_DATABASE; AceDB copies plain defaults into the live profile table, so
-- an explicit false on NAMEPLATES_ENABLED or NAMEPLATES_QUEST_ICON means the
-- user turned GW2's icons off and pfQuest's may run. Unreadable state defers
-- to GW2 (module present -> active) -- never two icon sets on one plate.
-- ---------------------------------------------------------------------------
local gw2CharKey
local function Gw2QuestPlatesActive()
  if not GwQuestPlateScanTip then return nil end
  local db = GW2UI_DATABASE
  if db and db.profileKeys and db.profiles then
    if not gw2CharKey then
      local n, r = UnitName("player"), GetRealmName()
      if n and r then
        gw2CharKey = n .. " - " .. r -- AceDB's character key format
      else
        return true -- identity not readable yet: defer to GW2
      end
    end
    local prof = db.profiles[db.profileKeys[gw2CharKey]]
    if prof and (prof.NAMEPLATES_ENABLED == false or prof.NAMEPLATES_QUEST_ICON == false) then
      return nil
    end
  end
  return true
end

-- settings-row hint: swap the checkbox row's caption hint when GW2's icons
-- are detected. This file loads before ADDON_LOADED builds the config rows
-- (init\addon.xml order), so mutating the default table here lands in time.
if pfQuest_defconfig and Gw2QuestPlatesActive() then
  for i = 1, table.getn(pfQuest_defconfig) do
    local row = pfQuest_defconfig[i]
    if row.config == "plateicons" then
      row.desc = pfQuest_Loc["GW2 UI quest icons are active"]
      break
    end
  end
end

-- ---------------------------------------------------------------------------
-- icon frames: one per plate, created lazily on first match and reused across
-- the client's plate recycling (plates are never destroyed, so this pool is
-- bounded by the most plates ever simultaneously registered). Hidden, never
-- destroyed.
-- ---------------------------------------------------------------------------
local active = false -- effective enable (plateicons setting + GW2 dedupe)
local icons = {} -- [plate frame] = icon frame

local function Clamp(v, lo, hi, fallback)
  v = tonumber(v) or fallback
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

-- 16px base at LEFT of the plate rect, Questie's default footprint (x -17
-- puts the icon just outside the plate's left edge, y -7 rides the bar line)
local function ApplyLayout(icon, plate)
  local scale = Clamp(pfQuest_config["plateiconscale"], 50, 200, 100) / 100
  local x = Clamp(pfQuest_config["plateiconx"], -100, 100, -17)
  local y = Clamp(pfQuest_config["plateicony"], -100, 100, -7)
  local size = 16 * scale
  icon:SetWidth(size)
  icon:SetHeight(size)
  icon:ClearAllPoints()
  icon:SetPoint("LEFT", plate, "LEFT", x, y)
end

local function GetIcon(plate)
  local icon = icons[plate]
  if not icon then
    icon = CreateFrame("Frame", nil, plate)
    icon:SetFrameStrata("LOW")
    icon:SetFrameLevel(10)
    icon:EnableMouse(false)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints(icon)
    ApplyLayout(icon, plate)
    icons[plate] = icon
  end
  return icon
end

local function HideAllIcons()
  for _, icon in pairs(icons) do
    icon:Hide()
  end
end

-- one hash lookup per plate; texture only re-set when the kind changed
local function ApplyPlate(plate, name)
  local kind = name and index[name]
  if kind then
    local icon = GetIcon(plate)
    local tex = pfQuest_config["clustermono"] == "1" and ICONS_MONO[kind] or ICONS[kind]
    if icon.lasttex ~= tex then
      icon.lasttex = tex
      icon.tex:SetTexture(tex)
    end
    icon:Show()
  else
    local icon = icons[plate]
    if icon then icon:Hide() end
  end
end

-- ---------------------------------------------------------------------------
-- tier detection + plate stores. hasNativeNP is non-nil only under a client
-- mod (AwesomeWotLK/ConsoleXP-class); stock 3.3.5a has no C_NamePlate.
-- ---------------------------------------------------------------------------
local hasNativeNP = type(C_NamePlate) == "table" and type(C_NamePlate.GetNamePlateForUnit) == "function"
local nativePlates = {} -- native tier: [unit token] = plate frame
local plates = {} -- stock tier: [plate frame] = name fontstring

local function RefreshPlates()
  if hasNativeNP then
    for unit, plate in pairs(nativePlates) do
      local name = active and not UnitIsPlayer(unit) and UnitName(unit) or nil
      ApplyPlate(plate, name)
    end
  else
    for plate, fs in pairs(plates) do
      if plate:IsShown() then
        ApplyPlate(plate, active and fs and fs:GetText() or nil)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- native tier (AwesomeWotLK-class): the real events carry the unit token.
-- Registered ONLY behind the feature-detect; stock clients never reach this.
-- ---------------------------------------------------------------------------
local nativeDriver
if hasNativeNP then
  nativeDriver = CreateFrame("Frame", nil, UIParent)
  nativeDriver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  nativeDriver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  -- dual-read the handler payload: the stock dispatcher sets the legacy
  -- this/event/arg globals (house idiom), but these events come from a client
  -- mod, so also accept the modern (self, event, unit) argument form
  nativeDriver:SetScript("OnEvent", function(_, e, u)
    local ev = e or event
    local unit = u or arg1
    if not unit then return end
    if ev == "NAME_PLATE_UNIT_ADDED" then
      local plate = C_NamePlate.GetNamePlateForUnit(unit)
      if plate then
        nativePlates[unit] = plate
        if active and not UnitIsPlayer(unit) then
          ApplyPlate(plate, UnitName(unit))
        end
      end
    elseif ev == "NAME_PLATE_UNIT_REMOVED" then
      local plate = nativePlates[unit]
      nativePlates[unit] = nil
      if plate then
        local icon = icons[plate]
        if icon then icon:Hide() end
      end
    end
  end)
end

-- ---------------------------------------------------------------------------
-- stock tier: WorldFrame child scan (child-count gated, 0.25s throttle)
-- ---------------------------------------------------------------------------
local NP_BORDER = "Interface\\Tooltips\\Nameplate-Border"

-- skinned-plate signatures first (ElvUI/TidyPlates/Aloft/KUI, the Questie-335
-- field list), then the stock plate's border texture in region slot 2
local function IsNamePlate(frame)
  if frame.UnitFrame or frame.extended or frame.aloftData or frame.kui then
    return true
  end
  local _, border = frame:GetRegions()
  if border and border.GetObjectType and border:GetObjectType() == "Texture" then
    return border:GetTexture() == NP_BORDER
  end
  return nil
end

local function PlateOnShow()
  if not active then return end
  local fs = plates[this]
  ApplyPlate(this, fs and fs:GetText())
end

local function PlateOnHide()
  local icon = icons[this]
  if icon then icon:Hide() end
end

local function ScanChildren(...)
  for i = 1, select("#", ...) do
    local frame = select(i, ...)
    if frame and not plates[frame] and IsNamePlate(frame) then
      -- name fontstring lives in region slot 7 on the Blizzard plate
      -- (Questie-335, Compat/Nameplate.lua:34); skinned plates keep the
      -- underlying Blizzard regions, so the same slot serves them
      plates[frame] = select(7, frame:GetRegions())
      frame:HookScript("OnShow", PlateOnShow)
      frame:HookScript("OnHide", PlateOnHide)
      if active and frame:IsShown() then
        local fs = plates[frame]
        ApplyPlate(frame, fs and fs:GetText())
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- driver: one 0.25s ticker for both tiers -- enable/dedupe gate, live
-- settings, index rebuild trigger and (stock only) the child scan. Disabled
-- path is a config read plus a compare per tick, no allocations anywhere.
-- ---------------------------------------------------------------------------
local driver = CreateFrame("Frame", nil, UIParent)
local lastQueue, lastZone = false, false
local lastScale, lastX, lastY, lastMono
local lastChildren

driver:SetScript("OnUpdate", function()
  local now = GetTime()
  if this.tick and now < this.tick then return end
  this.tick = now + 0.25

  local want = pfQuest_config and pfQuest_config["plateicons"] == "1"
    and not Gw2QuestPlatesActive() and true or false
  if want ~= active then
    active = want
    if not active then
      HideAllIcons()
      return
    end
    -- (re)activation: force a rebuild, a refresh and a fresh stock scan
    lastQueue, lastChildren = false, nil
  end
  if not active then return end

  local dirty

  -- live settings: re-layout on any raw config change (compass driver idiom)
  local s = pfQuest_config["plateiconscale"]
  local x = pfQuest_config["plateiconx"]
  local y = pfQuest_config["plateicony"]
  local m = pfQuest_config["clustermono"]
  if s ~= lastScale or x ~= lastX or y ~= lastY or m ~= lastMono then
    lastScale, lastX, lastY, lastMono = s, x, y, m
    for plate, icon in pairs(icons) do
      ApplyLayout(icon, plate)
      icon.lasttex = nil -- clustermono may have flipped the texture set
    end
    dirty = true
  end

  -- the index follows the map's node set: pfMap.queue_update bumps on every
  -- AddNode/DeleteNode, so one compare per tick coalesces a whole quest
  -- refresh burst into a single rebuild; a zone change re-gates the givers
  local zname
  if pfMap.PlayerZoneID then
    local _, zn = pfMap:PlayerZoneID()
    zname = zn
  end
  if pfMap.queue_update ~= lastQueue or zname ~= lastZone then
    lastQueue, lastZone = pfMap.queue_update, zname
    BuildIndex()
    dirty = true
  end

  -- stock tier: scan only when the WorldFrame child count moved
  if not hasNativeNP then
    local n = WorldFrame:GetNumChildren()
    if n ~= lastChildren then
      lastChildren = n
      ScanChildren(WorldFrame:GetChildren())
    end
  end

  if dirty then RefreshPlates() end
end)

-- ---------------------------------------------------------------------------
-- public surface (the platecheck335 harness drives these)
-- ---------------------------------------------------------------------------
pfQuest.nameplates = {
  KIND = {
    TURNIN = KIND_TURNIN, LOOT = KIND_LOOT, KILL = KIND_KILL,
    INTERACT = KIND_INTERACT, AVAIL = KIND_AVAIL,
  },
  ICONS = ICONS,
  ICONS_MONO = ICONS_MONO,
  ClassifyMeta = ClassifyMeta,
  BuildIndex = BuildIndex,
  index = index,
  Gw2QuestPlatesActive = Gw2QuestPlatesActive,
  IsNamePlate = IsNamePlate,
  ScanChildren = ScanChildren,
  RefreshPlates = RefreshPlates,
  icons = icons,
  plates = plates,
  nativePlates = nativePlates,
  driver = driver,
  nativeDriver = nativeDriver,
  HasNativeAPI = hasNativeNP or false,
}
