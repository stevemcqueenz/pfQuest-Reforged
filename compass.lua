-- pfQuest Reforged -- HorizonCompass (stage 1)
-- Reforged: Skyrim-style horizontal compass strip at top-center. Cardinal
-- letters and 15-degree ticks scroll through a fixed 180-degree FOV as the
-- player turns; one marker mirrors the route arrow's current target. Loads
-- AFTER route.lua and only READS its state. All rendering is procedural
-- (solid-color textures + fontstrings) so no art files are needed.

-- Reforged: standalone guard -- without pfQuest/route there is nothing to
-- mirror; bail before creating any frame so a partial install never errors.
if not pfQuest or not pfQuest.route then return end

-- cache per-frame globals once (tracker.lua idiom)
local floor, sqrt = math.floor, math.sqrt
-- math.atan2, NEVER the bare global atan2: the client's atan2 works in DEGREES
-- while GetPlayerFacing/math.sin are radians -- mixing them spun the route
-- arrow on any movement (route.lua:537).
local sin, cos, atan2 = math.sin, math.cos, math.atan2
local GetTime = GetTime
local GetPlayerMapPosition = GetPlayerMapPosition
local GetRealZoneText = GetRealZoneText
local UnitOnTaxi = UnitOnTaxi
-- vanilla-era clients lack GetPlayerFacing; the compat shim derives it from the
-- minimap arrow (compat/client.lua:83). 3.3.5a has it natively (milkyway).
local GetFacing = pfQuestCompat and pfQuestCompat.GetPlayerFacing or GetPlayerFacing

local HALF_PI = math.pi / 2
local RAD2DEG = 180 / math.pi

-- theme adapts to GW2_UI automatically (theme.lua swaps the accent when the
-- addon is loaded); fall back to pfQuest teal when running without theme.lua
local theme = pfQuestTheme
local accent = theme and theme.accent or { 0.2, 1.0, 0.8 }
local font = (pfUI and pfUI.font_default) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- ---------------------------------------------------------------------------
-- pure math (exposed on pfQuest.compass for the harness)
-- ---------------------------------------------------------------------------

-- wrap any angle to [-pi, pi]; atan2(sin, cos) avoids branchy modulo wrapping
-- and matches the route arrow's normalization (route.lua:541)
local function Normalize(a)
  return atan2(sin(a), cos(a))
end

-- linear bearing -> pixel mapping across the 180-degree FOV. `clamped` marks a
-- target beyond the FOV so callers can pin it to the edge as a turn hint.
local function ProjectOffset(rel, halfWidth)
  local off = rel / HALF_PI * halfWidth
  if off > halfWidth then
    return halfWidth, true
  elseif off < -halfWidth then
    return -halfWidth, true
  end
  return off, false
end

-- relative clockwise bearing to a node, positive = to the player's RIGHT.
-- Same convention as the route arrow (route.lua:527-541): map coords are
-- x-east/y-south, GetPlayerFacing is 0=north increasing counterclockwise, and
-- the 1.5 factor is the map's x/y aspect. tx/ty are node percent (0..100),
-- xp/yp GetPlayerMapPosition fractions (0..1).
local function BearingTo(xp, yp, tx, ty, facing)
  local dx = (tx - xp * 100) * 1.5
  local dy = (ty - yp * 100)
  return Normalize(atan2(dx, -dy) + facing)
end

-- real-world distance via the zone's yard dimensions (pfMap.minimap_sizes,
-- map.lua:271). nil when the zone has no size data -- the caller hides the
-- distance text instead of fabricating a number. No 1.5 factor here: that is
-- a map-DISPLAY aspect correction; yard dimensions are already per-axis.
local function YardsTo(xp, yp, tx, ty, mapID)
  local size = pfMap and pfMap.minimap_sizes and pfMap.minimap_sizes[mapID]
  if not size or not size[1] or not size[2] then return nil end
  local dx = (tx / 100 - xp) * size[1]
  local dy = (ty / 100 - yp) * size[2]
  return sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------------------
-- strip frame + pooled elements (everything created ONCE here; the OnUpdate
-- only repositions/re-alphas -- zero allocations in the steady path)
-- ---------------------------------------------------------------------------

local compass = CreateFrame("Frame", nil, UIParent)
pfQuest.compass = compass
compass:SetPoint("TOP", UIParent, "TOP", 0, -24)
compass:SetHeight(22)
compass:Hide()

-- Background: not the standard hard-bordered panel (SkinPanel) -- a horizontal
-- fade, transparent at both ends and semi-transparent in the middle, so the
-- strip melts into the scene instead of sitting on it as a box. Three
-- textures: the side pieces carry the gradients (SetGradientAlpha is
-- 3.3.5a-native, milkyway widgets.ts:4144), the middle spans between them via
-- two-corner anchoring so only the sides need explicit widths (sized in
-- UpdateSettings, so they scale with compasswidth).
local BG_ALPHA = 0.45
local bgr, bgg, bgb = 0.05, 0.05, 0.06
if theme and theme.bg then
  bgr, bgg, bgb = theme.bg[1], theme.bg[2], theme.bg[3]
end
local bgLeft = compass:CreateTexture(nil, "BACKGROUND")
bgLeft:SetTexture("Interface\\BUTTONS\\WHITE8X8")
bgLeft:SetPoint("TOPLEFT", compass, "TOPLEFT", 0, 0)
bgLeft:SetPoint("BOTTOMLEFT", compass, "BOTTOMLEFT", 0, 0)
bgLeft:SetGradientAlpha("HORIZONTAL", bgr, bgg, bgb, 0, bgr, bgg, bgb, BG_ALPHA)
local bgRight = compass:CreateTexture(nil, "BACKGROUND")
bgRight:SetTexture("Interface\\BUTTONS\\WHITE8X8")
bgRight:SetPoint("TOPRIGHT", compass, "TOPRIGHT", 0, 0)
bgRight:SetPoint("BOTTOMRIGHT", compass, "BOTTOMRIGHT", 0, 0)
bgRight:SetGradientAlpha("HORIZONTAL", bgr, bgg, bgb, BG_ALPHA, bgr, bgg, bgb, 0)
local bgMid = compass:CreateTexture(nil, "BACKGROUND")
bgMid:SetTexture(bgr, bgg, bgb, BG_ALPHA)
bgMid:SetPoint("TOPLEFT", bgLeft, "TOPRIGHT", 0, 0)
bgMid:SetPoint("BOTTOMRIGHT", bgRight, "BOTTOMLEFT", 0, 0)

-- Movable like the route arrow: hold SHIFT and drag (route.lua:441-465 is the
-- template). One deliberate difference: the arrow keeps EnableMouse(true)
-- permanently, but a 420px strip across the screen top would eat world clicks
-- and camera drags over its whole rectangle -- so the mouse is enabled only
-- while shift is held (MODIFIER_STATE_CHANGED + IsShiftKeyDown, both
-- 3.3.5a-native per milkyway events.ts:3777 / api-functions.ts).
compass:SetMovable(true)
compass:SetClampedToScreen(true)
compass:RegisterForDrag("LeftButton")
compass:EnableMouse(false)
compass:RegisterEvent("MODIFIER_STATE_CHANGED")
compass:SetScript("OnEvent", function()
  -- never drop the mouse mid-drag: releasing shift first would strand the
  -- frame on the cursor with no OnDragStop to finish the move
  if not compass.moving then
    compass:EnableMouse(IsShiftKeyDown())
  end
end)

compass:SetScript("OnDragStart", function()
  if IsShiftKeyDown() then
    compass.moving = true
    this:StartMoving()
  end
end)

compass:SetScript("OnDragStop", function()
  compass.moving = nil
  this:StopMovingOrSizing()
  local anchor, x, y = pfUI.api.ConvertFrameAnchor(this, pfUI.api.GetBestAnchor(this))
  this:ClearAllPoints()
  this:SetPoint(anchor, x, y)

  -- save position
  pfQuest_config.compasspos = { anchor, x, y }
  compass:EnableMouse(IsShiftKeyDown())
end)

compass:SetScript("OnShow", function()
  if pfQuest_config.compasspos then
    this:ClearAllPoints()
    this:SetPoint(unpack(pfQuest_config.compasspos))
  end
end)

local CARDINALS = {
  [0] = "N", [45] = "NE", [90] = "E", [135] = "SE",
  [180] = "S", [225] = "SW", [270] = "W", [315] = "NW",
}

-- one pooled widget per 15-degree world bearing (24 total): fontstrings for
-- the 8 cardinals, thin tick textures for the rest. At most ~13 are inside
-- the FOV at once, but pooling all 24 keeps the per-frame loop branch-free.
local elements = {}
local numElements = 0
for deg = 0, 345, 15 do
  local e = { rad = math.rad(deg) }
  local label = CARDINALS[deg]
  if label then
    local fs = compass:CreateFontString(nil, "OVERLAY")
    -- primary cardinals pop in the accent color; intercardinals stay dim so
    -- the strip reads at a glance (fonts capped well under the 32pt limit)
    if math.fmod(deg, 90) == 0 then
      fs:SetFont(font, 15, "OUTLINE")
      fs:SetTextColor(accent[1], accent[2], accent[3], 1)
    else
      fs:SetFont(font, 11, "OUTLINE")
      fs:SetTextColor(0.8, 0.8, 0.8, 1)
    end
    fs:SetText(label)
    e.widget = fs
  else
    local t = compass:CreateTexture(nil, "ARTWORK")
    t:SetTexture(1, 1, 1, 0.25)
    t:SetWidth(1)
    t:SetHeight(6)
    e.widget = t
  end
  e.widget:Hide()
  numElements = numElements + 1
  elements[numElements] = e
end

-- center needle: the player's current heading reference line
local needle = compass:CreateTexture(nil, "OVERLAY")
needle:SetTexture(accent[1], accent[2], accent[3], 0.9)
needle:SetWidth(2)
needle:SetPoint("TOP", compass, "TOP", 0, -1)
needle:SetPoint("BOTTOM", compass, "BOTTOM", 0, 1)

-- the ONE marker: the route arrow's current target
local marker = compass:CreateTexture(nil, "OVERLAY")
marker:SetTexture(accent[1], accent[2], accent[3], 1)
marker:SetWidth(6)
marker:SetHeight(6)
marker:Hide()

-- labels ride the marker via anchors, so only the marker moves per frame
local dist = compass:CreateFontString(nil, "OVERLAY")
dist:SetFont(font, 11, "OUTLINE")
dist:SetTextColor(0.9, 0.9, 0.9, 1)
dist:SetPoint("BOTTOM", marker, "TOP", 0, 10)
dist:Hide()

local title = compass:CreateFontString(nil, "OVERLAY")
title:SetFont(font, 12, "OUTLINE")
title:SetTextColor(accent[1], accent[2], accent[3], 1)
title:SetPoint("BOTTOM", dist, "TOP", 0, 1)
title:Hide()

-- degree readout under the strip ("107 E")
local degreeText = compass:CreateFontString(nil, "OVERLAY")
degreeText:SetFont(font, 11, "OUTLINE")
degreeText:SetTextColor(0.85, 0.85, 0.85, 1)
degreeText:SetPoint("TOP", compass, "BOTTOM", 0, -3)

local LETTERS8 = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- ---------------------------------------------------------------------------
-- update loop
-- ---------------------------------------------------------------------------

local halfWidth = 210
local lastXP, lastYP, lastFacing, lastTarget
local lastDegree, lastYards, lastTitle
local zoneName, zoneID

-- Reforged: the OnUpdate lives on a separate always-shown driver, not on the
-- strip itself -- Hide()ing the strip (taxi/disable) would stop its own
-- OnUpdate and it could never wake back up. The driver's disabled path is a
-- single table index per frame (class-B).
local driver = CreateFrame("Frame", nil, UIParent)
compass.driver = driver

driver:SetScript("OnUpdate", function()
  if not pfQuest_config or pfQuest_config["compass"] ~= "1" then
    if compass.on then
      compass.on = nil
      compass:Hide()
    end
    return
  end

  -- perf cap identical to the route arrow (route.lua:515): ~50/sec is
  -- indistinguishable for a heading strip
  local now = GetTime()
  if this.perfTick and now < this.perfTick then return end
  this.perfTick = now + 0.02

  -- Reforged: width is applied only in UpdateSettings and nothing in the config
  -- UI calls it, so without this check a compasswidth change needs a /reload.
  -- One hash lookup + compare inside the 0.02s cap; UpdateSettings runs only on
  -- an actual change.
  local widthCfg = pfQuest_config["compasswidth"]
  if widthCfg ~= this.lastWidthCfg then
    this.lastWidthCfg = widthCfg
    compass:UpdateSettings()
  end

  -- facing/position race along the flight path on a taxi and the bearing is
  -- useless -- the arrow shipped this exact bug (route.lua:495)
  if UnitOnTaxi("player") then
    if compass.on then
      compass.on = nil
      compass:Hide()
    end
    return
  end

  if not compass.on then
    compass.on = true
    compass:Show()
    lastFacing = nil -- force a full repaint after any hidden stretch
  end

  local xp, yp = GetPlayerMapPosition("player")
  local facing = GetFacing()

  -- the SAME target the route arrow points at (route.lua:491): the route head,
  -- valid only once its distance (slot 4) has been computed
  local coords = pfQuest.route.coords
  local target = coords and coords[1] and coords[1][4] and coords[1] or nil

  -- dirty-skip: everything below is a pure function of position, facing and
  -- target -- standing still costs nothing beyond these compares
  if facing == lastFacing and xp == lastXP and yp == lastYP and target == lastTarget then
    return
  end
  lastXP, lastYP, lastFacing = xp, yp, facing
  local targetChanged = target ~= lastTarget
  lastTarget = target

  -- scroll cardinals/ticks through the FOV; outside-FOV widgets hide (only
  -- the marker clamps to the edge -- letters pinned there would just stack).
  -- Edge fade: full strength inside 70% of the half-width, then linear to 0
  -- at the edge, so letters dissolve into the background gradient instead of
  -- popping out at the FOV boundary.
  local fadeStart = halfWidth * 0.7
  local fadeSpan = halfWidth - fadeStart
  for i = 1, numElements do
    local e = elements[i]
    local rel = Normalize(e.rad + facing)
    local off, clamped = ProjectOffset(rel, halfWidth)
    if clamped then
      e.widget:Hide()
    else
      local absOff = off < 0 and -off or off
      e.widget:SetAlpha(absOff > fadeStart and (1 - (absOff - fadeStart) / fadeSpan) or 1)
      e.widget:SetPoint("CENTER", compass, "CENTER", off, 0)
      e.widget:Show()
    end
  end

  -- degree readout: heading is clockwise-from-north = -facing; re-format the
  -- string only when the rounded degree actually changes
  local degree = floor(-facing * RAD2DEG + 0.5) % 360
  if degree ~= lastDegree then
    lastDegree = degree
    degreeText:SetText(degree .. " " .. LETTERS8[floor(degree / 45 + 0.5) % 8 + 1])
  end

  -- marker: hide when there is no route target, or when GetPlayerMapPosition
  -- reports 0,0 (indoors/instance -- position unknown, bearing would lie);
  -- cardinals stay up because facing is still valid there
  if not target or (xp == 0 and yp == 0) then
    marker:Hide()
    dist:Hide()
    title:Hide()
    lastYards, lastTitle = nil, nil -- stale caches must not suppress the first repaint
  else
    local rel = BearingTo(xp, yp, target[1], target[2], facing)
    local off, clamped = ProjectOffset(rel, halfWidth)
    marker:SetPoint("CENTER", compass, "CENTER", off, 0)
    -- beyond the FOV the marker pins to the edge at 40% alpha: still shows
    -- which way to turn without pretending to be on-screen. On-screen near
    -- the edge it fades 1 -> 0.4 over the same band the cardinals fade in,
    -- meeting the clamped value exactly -- no alpha pop at the boundary (the
    -- 0.4 floor keeps the guidance anchor visible, never faded to nothing)
    local a = 1
    if clamped then
      a = 0.4
    else
      local absOff = off < 0 and -off or off
      if absOff > fadeStart then
        a = 1 - 0.6 * (absOff - fadeStart) / fadeSpan
      end
    end
    marker:SetAlpha(a)
    dist:SetAlpha(a)
    title:SetAlpha(a)
    marker:Show()

    if targetChanged or target[3].title ~= lastTitle then
      lastTitle = target[3].title
      title:SetText(lastTitle or "")
    end
    title:Show()

    -- GetMapIDByName is a linear scan over every zone name in the DB -- memoize
    -- by the raw zone-text string, same as the minimap loop (map.lua:1322)
    local rz = GetRealZoneText()
    if rz ~= zoneName then
      zoneName = rz
      zoneID = pfMap and pfMap.GetMapIDByName and pfMap:GetMapIDByName(rz) or nil
    end

    local yards = YardsTo(xp, yp, target[1], target[2], zoneID)
    if not yards then
      -- no size data for this zone: show no distance rather than a wrong one
      dist:Hide()
      lastYards = nil
    else
      -- Reforged: metric option. WoW's world unit is the yard; meters = yd * 0.9144.
      -- Converted at DISPLAY time only -- everything internal stays in yards, so no
      -- other consumer can be poisoned by a unit mixup. Dirty-check includes the
      -- unit so flipping the option repaints without a target change.
      local metric = pfQuest_config["compassmetric"] == "1"
      local shown = metric and (yards * 0.9144) or yards
      local rounded = floor(shown + 0.5)
      local key = metric and -rounded or rounded
      if key ~= lastYards then
        lastYards = key
        dist:SetText(rounded .. (metric and " m" or " yd"))
      end
      dist:Show()
    end
  end
end)

-- ---------------------------------------------------------------------------
-- public surface
-- ---------------------------------------------------------------------------

compass.ProjectOffset = ProjectOffset
compass.BearingTo = BearingTo
compass.YardsTo = YardsTo

-- re-read pfQuest_config and resize; safe before saved variables exist
-- (defaults apply until the config module calls this again)
function compass:UpdateSettings()
  local w = tonumber(pfQuest_config and pfQuest_config["compasswidth"]) or 420
  if w < 240 then
    w = 240
  elseif w > 800 then
    w = 800
  end
  self:SetWidth(w)
  halfWidth = w / 2
  -- gradient side pieces scale with the strip (30% each; the middle spans
  -- between them by anchoring, no explicit width needed)
  bgLeft:SetWidth(w * 0.3)
  bgRight:SetWidth(w * 0.3)
  lastFacing = nil -- geometry changed: force a full reposition on the next tick
end

compass:UpdateSettings()
