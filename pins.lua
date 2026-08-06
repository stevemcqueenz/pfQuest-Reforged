-- pfQuest Reforged -- in-world pins, stage 1 (docs/PINS-DESIGN.md)
-- The WorldAPI DLL tier: markers rendered AT world positions. Stage 1 draws
-- the ROUTE TARGET only, as two cooperating elements switched by the
-- WorldToScreen visibility flag:
--   Waypoint  (target in the camera frustum): diamond plate + vertical light
--             beam + distance/ETA text at the projected screen position.
--   Navigator (target off-screen): a small plate with a direction chevron
--             orbiting the screen center, pointing toward the target.
-- Pinpoint handoff, objective text and the full settings surface are stage 2.
-- The compass strip is the degrade path and never depends on this file.

-- standalone guard (compass.lua idiom): without pfQuest/route there is no
-- target to mirror; bail before creating any frame
if not pfQuest or not pfQuest.route then return end

-- Feature-detect the DLL exports by TYPE, never a version global (spec).
-- Without them this file is fully inert: zero frames, zero handlers -- return
-- before anything is created. NOTE: this UnitPosition is the DLL's
-- (x, y, z world yards), NOT retail's (posY, posX, posZ, mapID).
if type(WorldToScreen) ~= "function" or type(UnitPosition) ~= "function" then return end

-- cache per-frame globals once (compass.lua idiom)
local floor, sqrt, fmod = math.floor, math.sqrt, math.fmod
-- math.atan2, NEVER the bare global atan2: the client's atan2 works in
-- DEGREES while math.sin/cos are radians (route.lua:537 shipped that spin)
local sin, cos, atan2 = math.sin, math.cos, math.atan2
local format = string.format
local GetTime = GetTime
local GetPlayerMapPosition = GetPlayerMapPosition
local GetRealZoneText = GetRealZoneText
-- GetUnitSpeed: 3.3.5a-native, ONE return -- current speed in yards/second
-- (milkyway api-functions.ts:29344; run = 7, standing = 0)
local GetUnitSpeed = GetUnitSpeed
local WorldToScreen, UnitPosition = WorldToScreen, UnitPosition
local HUGE = math.huge

local theme = pfQuestTheme
local accent = theme and theme.accent or { 0.2, 1.0, 0.8 }
local bg = theme and theme.bg or { 0.07, 0.07, 0.09 }
local font = (pfUI and pfUI.font_default) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local PATH = (pfQuestConfig and pfQuestConfig.path) or "Interface\\AddOns\\pfQuest"
local ICON_FALLBACK = PATH .. "\\img\\node"

-- ---------------------------------------------------------------------------
-- constants (spec defaults; the min/max scale clamps mirror Waypoint-UI's
-- proven 50%/150% values, PINS-DESIGN.md settings section)
-- ---------------------------------------------------------------------------

local BASE_SIZE = 28 -- waypoint plate px at pinssize 100 and neutral distance
local SCALE_MIN, SCALE_MAX = 0.5, 1.5 -- distance-scale clamps (far/close)
local SCALE_NEAR, SCALE_FAR = 40, 400 -- yards: <=near -> max, >=far -> min
local NAV_RADIUS = 140 -- navigator orbit radius (UI units; configurable in stage 2)
local NAV_SIZE = 22
local PIN_HOLD = 0.25 -- visible/invisible hysteresis hold (spec)
local BEAM_MIN, BEAM_MAX = 60, 300 -- beam height clamp (UI units)

-- ---------------------------------------------------------------------------
-- pure helpers (exposed on pfQuest.pins for the harness)
-- ---------------------------------------------------------------------------

-- DLL screen space -> UIParent BOTTOMLEFT offsets. THE calibration lives here
-- and nowhere else, so an in-game correction is a one-line fix. Conclusion
-- from the live sample (UnitPosition("player") -7188.48,-3803.71,9.08 ->
-- WorldToScreen 614.40, 343.49 with 614.40 = 0.6 * 1024 exactly):
-- CGWorldFrame::PercToScreenPos yields screen PERCENT scaled by a fixed
-- 1024x768 base. Dividing by that base and multiplying by UIParent's actual
-- dimensions lands the point in UI units at any resolution/uiScale. If the
-- in-game QA pass shows a horizontal drift on widescreen, the base is
-- height-anchored instead: swap 1024 for uih * (4 / 3) here.
local function ToUiCoords(sx, sy, uiw, uih)
  return sx / 1024 * uiw, sy / 768 * uih
end

-- map-percent -> world yards, the delta form: pfQuest has zone SIZES
-- (pfMap.minimap_sizes, world yards per axis) but no world-space origins, so
-- the player's own paired sample (UnitPosition + GetPlayerMapPosition) anchors
-- the conversion every tick -- no per-zone calibration state, correct
-- immediately. Axis pairing: world +X is north, +Y is west (client/AC
-- convention); map-x grows EAST so worldY falls with it, map-y grows SOUTH so
-- worldX falls with it. The db/minimap-wotlk335.lua fit derivation pins the
-- same pairing (its zone width comes from d(pctX)/d(worldY)). nil when the
-- zone has no size data -- the caller hides the pins, never fabricates.
local function PercentToWorld(pxf, pyf, tx, ty, wx, wy, mapID)
  local size = pfMap and pfMap.minimap_sizes and pfMap.minimap_sizes[mapID]
  if not size or not size[1] or not size[2] then return nil end
  return wx - (ty / 100 - pyf) * size[2], wy - (tx / 100 - pxf) * size[1]
end

-- distance -> plate scale factor: max at close range, min at far range,
-- linear ramp between (spec: "base size, clamped by a minimum % at max
-- distance and maximum % at min distance")
local function ScaleForDistance(dist)
  if dist <= SCALE_NEAR then return SCALE_MAX end
  if dist >= SCALE_FAR then return SCALE_MIN end
  return SCALE_MAX + (SCALE_MIN - SCALE_MAX) * (dist - SCALE_NEAR) / (SCALE_FAR - SCALE_NEAR)
end

-- ETA seconds, or nil when no honest number exists: standing still (speed 0),
-- or a nonsense speed (negative/nan/inf from a misreporting core). The spec
-- rule is NEVER show infinity -- the caller hides the line on nil.
local function EtaFor(dist, speed)
  if not speed or speed <= 0 or speed ~= speed or speed == HUGE then return nil end
  return dist / speed
end

-- "mm:ss" from a minute up, plain "Ns" below it
local function FormatEta(sec)
  sec = floor(sec + 0.5)
  if sec >= 60 then
    return format("%d:%02d", floor(sec / 60), fmod(sec, 60))
  end
  return sec .. "s"
end

-- direction of the target from the screen center, counterclockwise from
-- screen-right. WorldToScreen keeps updating sx/sy while the visible flag is
-- nil, which is exactly what gives the Navigator its bearing for free (spec).
local function NavigatorAngle(sx, sy, cx, cy)
  return atan2(sy - cy, sx - cx)
end

-- Waypoint/Navigator state machine with the spec's ~0.25s hysteresis: the raw
-- visible flag flaps at screen edges as the camera bobs, and the pair must not
-- flicker-swap there. Debounce form: the CURRENT mode holds until the other
-- has been the raw desire CONTINUOUSLY for PIN_HOLD seconds -- a flapping
-- input therefore never switches at all, a real transition follows 0.25s
-- late. Pure over (state, visible, now); mutates only state{mode,pending,since}.
local function StepMode(state, visible, now)
  local want = visible and "waypoint" or "navigator"
  if not state.mode then
    state.mode, state.pending = want, nil
  elseif want == state.mode then
    state.pending = nil
  elseif state.pending ~= want then
    state.pending, state.since = want, now
  elseif now - state.since >= PIN_HOLD then
    state.mode, state.pending = want, nil
  end
  return state.mode
end

-- ---------------------------------------------------------------------------
-- widgets, created once at load (zero allocations in the steady path).
-- BACKGROUND strata: these are world-attached visuals and must never cover
-- interactive UI. Housing = the compass marker plates (marker_fill under
-- marker_edge, white art vertex-tinted by pfQuestTheme) so the tier reads as
-- one family with the strip (spec "Visual identity").
-- ---------------------------------------------------------------------------

local pins = {}
pfQuest.pins = pins

local waypoint = CreateFrame("Frame", nil, UIParent)
pins.waypoint = waypoint
waypoint:SetFrameStrata("BACKGROUND")
waypoint:SetWidth(BASE_SIZE)
waypoint:SetHeight(BASE_SIZE)

-- light beam: a solid WHITE8X8 stretched tall, vertical alpha gradient fading
-- upward from the plate (SetGradientAlpha is 3.3.5a-native and VERTICAL runs
-- bottom->top, milkyway widgets.ts:4144); BORDER layer so the plate draws over
-- its base. TGA gradient strip is the spec's fallback if this proves
-- unreliable on untextured solids in-game.
waypoint.beam = waypoint:CreateTexture(nil, "BORDER")
waypoint.beam:SetTexture("Interface\\BUTTONS\\WHITE8X8")
waypoint.beam:SetWidth(6)
waypoint.beam:SetHeight(120)
waypoint.beam:SetPoint("BOTTOM", waypoint, "CENTER", 0, 0)
waypoint.beam:SetGradientAlpha("VERTICAL", accent[1], accent[2], accent[3], 0.75,
                               accent[1], accent[2], accent[3], 0)
-- born hidden: the .on dirty-flags below only HIDE what they have shown, so a
-- region that starts shown with pinsbeam off would never be put away
waypoint.beam:Hide()

waypoint.fill = waypoint:CreateTexture(nil, "ARTWORK")
waypoint.fill:SetTexture(PATH .. "\\img\\marker_fill")
waypoint.fill:SetAllPoints(waypoint)
waypoint.fill:SetVertexColor(bg[1], bg[2], bg[3], 0.9)
-- created after fill in the same layer -> draws above it (compass idiom)
waypoint.edge = waypoint:CreateTexture(nil, "ARTWORK")
waypoint.edge:SetTexture(PATH .. "\\img\\marker_edge")
waypoint.edge:SetAllPoints(waypoint)
waypoint.edge:SetVertexColor(accent[1], accent[2], accent[3], 1)

waypoint.icon = waypoint:CreateTexture(nil, "OVERLAY")
waypoint.icon:SetWidth(16)
waypoint.icon:SetHeight(16)
waypoint.icon:SetPoint("CENTER", waypoint, "CENTER", 0, 0)

waypoint.dist = waypoint:CreateFontString(nil, "OVERLAY")
waypoint.dist:SetFont(font, 12, "OUTLINE")
waypoint.dist:SetTextColor(0.9, 0.9, 0.9, 1)
waypoint.dist:SetPoint("TOP", waypoint, "BOTTOM", 0, -3)

waypoint.eta = waypoint:CreateFontString(nil, "OVERLAY")
waypoint.eta:SetFont(font, 11, "OUTLINE")
waypoint.eta:SetTextColor(0.75, 0.75, 0.75, 1)
waypoint.eta:SetPoint("TOP", waypoint.dist, "BOTTOM", 0, -1)
waypoint.eta:Hide() -- same born-hidden rule: shown only once an ETA exists
waypoint:Hide()

local navigator = CreateFrame("Frame", nil, UIParent)
pins.navigator = navigator
navigator:SetFrameStrata("BACKGROUND")
navigator:SetWidth(NAV_SIZE)
navigator:SetHeight(NAV_SIZE)
navigator.fill = navigator:CreateTexture(nil, "ARTWORK")
navigator.fill:SetTexture(PATH .. "\\img\\marker_fill")
navigator.fill:SetAllPoints(navigator)
navigator.fill:SetVertexColor(bg[1], bg[2], bg[3], 0.9)
navigator.edge = navigator:CreateTexture(nil, "ARTWORK")
navigator.edge:SetTexture(PATH .. "\\img\\marker_edge")
navigator.edge:SetAllPoints(navigator)
navigator.edge:SetVertexColor(accent[1], accent[2], accent[3], 1)
-- direction chevron: our arrow art free-rotated via the 8-corner SetTexCoord
-- (route.lua:582-591 idiom -- the art stays inside the inscribed circle so
-- the rotated sample never clips), accent-tinted like the plate edge
navigator.chevron = navigator:CreateTexture(nil, "OVERLAY")
navigator.chevron:SetTexture(PATH .. "\\img\\arrow-gw2")
navigator.chevron:SetWidth(16)
navigator.chevron:SetHeight(16)
navigator.chevron:SetPoint("CENTER", navigator, "CENTER", 0, 0)
navigator.chevron:SetVertexColor(accent[1], accent[2], accent[3], 1)
navigator:Hide()

-- point the chevron art along screen angle `a` (ccw from screen-right). The
-- arrow art renders pointing UP at phi = 3pi/4 under this corner mapping
-- (verified offline for route.lua:583); screen-up is a = pi/2, so
-- phi = 3pi/4 - (pi/2 - a) = pi/4 + a.
local function AimChevron(tex, a)
  local phi = 0.78539816339745 + a
  local s = sin(phi) * 0.70710678118655
  local c = cos(phi) * 0.70710678118655
  tex:SetTexCoord(0.5 - s, 0.5 + c, 0.5 + c, 0.5 + s, 0.5 - c, 0.5 - s, 0.5 + s, 0.5 - c)
end

-- ---------------------------------------------------------------------------
-- update loop: one driver frame, 0.02s perf cap (route.lua:515 idiom). The
-- screen position is a function of the CAMERA, which moves every frame, so
-- the projected point cannot be dirty-skipped -- but everything expensive
-- (strings, sizes, texcoords) only reruns on an actual value change.
-- ---------------------------------------------------------------------------

local zoneName, zoneID
local state = {}
local shownMode
local speedAvg
local lastNode, lastWaySize, lastBeamH, lastDistKey, lastEtaKey, lastNavAngle
local sizeMul, lastSizeCfg = 1, nil

local driver = CreateFrame("Frame", nil, UIParent)
pins.driver = driver

local function Sleep()
  if not pins.on then return end
  pins.on = nil
  shownMode = nil
  state.mode, state.pending = nil, nil -- wake adopts the raw flag instantly
  speedAvg = nil
  waypoint:Hide()
  navigator:Hide()
end

driver:SetScript("OnUpdate", function()
  -- disabled path: one table index + compare per frame (class-B driver)
  if not pfQuest_config or pfQuest_config["pins"] ~= "1" then
    Sleep()
    return
  end

  local now = GetTime()
  if this.perfTick and now < this.perfTick then return end
  this.perfTick = now + 0.02

  -- live size option: dirty-check inside the cap (compass width idiom)
  local sizeCfg = pfQuest_config["pinssize"]
  if sizeCfg ~= lastSizeCfg then
    lastSizeCfg = sizeCfg
    local s = tonumber(sizeCfg) or 100
    if s < 25 then s = 25 elseif s > 300 then s = 300 end
    sizeMul = s / 100
  end

  -- route target: the arrow's current destination -- coords[1] is only a
  -- valid target while its distance slot [4] is set (route.lua:491)
  local coords = pfQuest.route.coords
  local target = coords and coords[1] and coords[1][4] and coords[1] or nil
  local pxf, pyf = GetPlayerMapPosition("player")
  -- 0,0 = indoors/instance/other map viewed: the percent->world anchor pair
  -- is invalid, so every pin position would lie (compass indoor rule)
  if not target or (pxf == 0 and pyf == 0) then
    Sleep()
    return
  end

  -- GetMapIDByName is a linear DB scan -- memoize by zone text (map.lua:1322)
  local rz = GetRealZoneText()
  if rz ~= zoneName then
    zoneName = rz
    zoneID = pfMap and pfMap.GetMapIDByName and pfMap:GetMapIDByName(rz) or nil
  end

  local wx, wy, wz = UnitPosition("player")
  if not wx then
    Sleep()
    return
  end
  local tX, tY = PercentToWorld(pxf, pyf, target[1], target[2], wx, wy, zoneID)
  if not tX then
    Sleep()
    return
  end

  -- stage-1 limitation (spec): the target's z is the player's own z -- the
  -- marker sits at eye level; a ground-height query is a later DLL addition
  local sx, sy, vis = WorldToScreen(tX, tY, wz)
  if not sx then
    Sleep()
    return
  end

  -- world-space distance: exact yards, no map aspect factor needed
  local dxw, dyw = tX - wx, tY - wy
  local dist = sqrt(dxw * dxw + dyw * dyw)

  pins.on = true
  local mode = StepMode(state, vis and true or false, now)
  if mode ~= shownMode then
    shownMode = mode
    if mode == "waypoint" then
      navigator:Hide()
      waypoint:Show()
    else
      waypoint:Hide()
      navigator:Show()
    end
  end

  local uiw, uih = UIParent:GetWidth(), UIParent:GetHeight()

  if mode == "waypoint" then
    local ux, uy = ToUiCoords(sx, sy, uiw, uih)
    waypoint:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ux, uy)

    -- distance-based plate scale, dirty on the rounded pixel size
    local size = floor(BASE_SIZE * sizeMul * ScaleForDistance(dist) + 0.5)
    if size ~= lastWaySize then
      lastWaySize = size
      waypoint:SetWidth(size)
      waypoint:SetHeight(size)
      local isz = floor(size * 0.6 + 0.5)
      waypoint.icon:SetWidth(isz)
      waypoint.icon:SetHeight(isz)
    end

    -- icon rebind on target change only (compass rebind idiom)
    local node = target[3]
    if node ~= lastNode then
      lastNode = node
      if node and node.texture then
        waypoint.icon:SetTexture(node.texture)
        local v = node.vertex
        if v and (v[1] > 0 or v[2] > 0 or v[3] > 0) then
          waypoint.icon:SetVertexColor(v[1], v[2], v[3], 1)
        else
          waypoint.icon:SetVertexColor(1, 1, 1, 1)
        end
      else
        waypoint.icon:SetTexture(ICON_FALLBACK)
        local r, g, b = pfMap.str2rgb(node and node.title or "")
        waypoint.icon:SetVertexColor(r or 1, g or 1, b or 1, 1)
      end
    end

    -- beam: height scales with distance (tall from afar, short up close),
    -- dirty on the rounded clamp
    if pfQuest_config["pinsbeam"] ~= "0" then
      local bh = floor(dist + 0.5)
      if bh < BEAM_MIN then bh = BEAM_MIN elseif bh > BEAM_MAX then bh = BEAM_MAX end
      if bh ~= lastBeamH then
        lastBeamH = bh
        waypoint.beam:SetHeight(bh)
      end
      if not waypoint.beam.on then
        waypoint.beam.on = true
        waypoint.beam:Show()
      end
    elseif waypoint.beam.on then
      waypoint.beam.on = nil
      waypoint.beam:Hide()
    end

    -- distance text: yards, or meters when compassmetric is on -- the same
    -- display-time-only conversion as the strip (compass.lua:909)
    local metric = pfQuest_config["compassmetric"] == "1"
    local shownD = metric and (dist * 0.9144) or dist
    local rounded = floor(shownD + 0.5)
    local key = metric and -rounded or rounded
    if key ~= lastDistKey then
      lastDistKey = key
      waypoint.dist:SetText(rounded .. (metric and " m" or " yd"))
    end

    -- ETA: distance over a short running average of GetUnitSpeed, so brief
    -- speed jitters do not flicker the number. Standing still (raw speed 0)
    -- hides the line ENTIRELY and drops the average, so movement restarts
    -- from the fresh speed instead of a stale one.
    local speed = GetUnitSpeed("player")
    if not speed or speed <= 0 then
      speedAvg = nil
    else
      speedAvg = speedAvg and (speedAvg + (speed - speedAvg) * 0.15) or speed
    end
    local eta = speedAvg and EtaFor(dist, speedAvg) or nil
    if eta then
      local r = floor(eta + 0.5)
      if r ~= lastEtaKey then
        lastEtaKey = r
        waypoint.eta:SetText(FormatEta(eta))
      end
      if not waypoint.eta.on then
        waypoint.eta.on = true
        waypoint.eta:Show()
      end
    elseif waypoint.eta.on then
      waypoint.eta.on = nil
      waypoint.eta:Hide()
      lastEtaKey = nil
    end
  else
    -- navigator: orbit the screen center at a fixed radius along the target's
    -- screen direction -- the invisible-but-updating WorldToScreen coords ARE
    -- the bearing (spec)
    local ux, uy = ToUiCoords(sx, sy, uiw, uih)
    local a = NavigatorAngle(ux, uy, uiw * 0.5, uih * 0.5)
    navigator:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
                       uiw * 0.5 + cos(a) * NAV_RADIUS, uih * 0.5 + sin(a) * NAV_RADIUS)
    -- re-aim only on a real angular change (~0.6 deg) -- SetTexCoord is not free
    if not lastNavAngle or a - lastNavAngle > 0.01 or lastNavAngle - a > 0.01 then
      lastNavAngle = a
      AimChevron(navigator.chevron, a)
    end
  end
end)

-- ---------------------------------------------------------------------------
-- public surface (the harness drives exactly these)
-- ---------------------------------------------------------------------------

pins.ToUiCoords = ToUiCoords
pins.PercentToWorld = PercentToWorld
pins.ScaleForDistance = ScaleForDistance
pins.EtaFor = EtaFor
pins.FormatEta = FormatEta
pins.NavigatorAngle = NavigatorAngle
pins.StepMode = StepMode
