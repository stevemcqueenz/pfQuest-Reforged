-- pfQuest Reforged -- in-world pins, stage 2 (docs/PINS-DESIGN.md)
-- The WorldAPI DLL tier: markers rendered AT world positions. The route
-- target is drawn as THREE cooperating elements, switched by the
-- WorldToScreen visibility flag and the near-range distance:
--   Waypoint  (far, in the camera frustum): diamond plate + vertical light
--             beam + distance/ETA text at the projected screen position.
--   Pinpoint  (near, in the camera frustum): a smaller plate at the exact
--             spot; the info text switches to the OBJECTIVE line.
--   Navigator (target off-screen): a small plate with a direction chevron
--             orbiting the screen center, pointing toward the target.
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
local PINPOINT_BASE = 20 -- pinpoint plate px at pinspointsize 100
local SCALE_MIN, SCALE_MAX = 0.5, 1.5 -- distance-scale clamp defaults (far/close)
local SCALE_NEAR, SCALE_FAR = 40, 400 -- yards: <=near -> max, >=far -> min
local NAV_RADIUS = 140 -- navigator orbit radius default (UI units)
local NAV_SIZE = 22 -- navigator plate px at pinsnavsize 100
local PIN_HOLD = 0.25 -- mode hysteresis hold (spec; all three boundaries)
-- near-range handoff (stage 2): Waypoint -> Pinpoint around ~30 yards, with a
-- distance hysteresis BAND on top of the hold -- enter below 28, leave above
-- 33 -- so walking along the threshold cannot flicker-swap the pair
local NEAR_ENTER, NEAR_LEAVE = 28, 33
-- beam height clamp (UI units). First in-game contact showed 300 at max
-- distance renders as a screen-tall pillar on a scaled UI -- the beam is a
-- subtle locator shaft, not the dominant object; shorter and dimmer reads far
-- better against the sky (maintainer screenshots, Barrens night).
local BEAM_MIN, BEAM_MAX = 40, 170
-- 0.35 base alpha: at 0.75 the first in-game shots read as a solid column
local BEAM_ALPHA = 0.35

-- multi-pin exploration (pinsmulti, experimental): every tunable of the
-- ambient extras layer lives HERE so the in-game QA round-trip is a
-- one-line-per-knob affair. Extras are plates only (no navigator, no state
-- machine) drawn from the compass taxonomy; the route target keeps the full
-- waypoint/pinpoint/navigator treatment.
local MULTI_MAX = 8            -- widget pool ceiling; pinsmulticap clamps 1..this
local MULTI_RADIUS = 300       -- yd: extras beyond this never show
local MULTI_SOLID = 40         -- yd: full alpha inside this
local MULTI_FLOOR = 0.35       -- alpha floor reached at MULTI_RADIUS
local MULTI_MERGE = 28         -- UI units: screen-space overlap merge radius
local MULTI_BASE = 20          -- extra plate px (pinpoint-sized: ambient, not dominant)
local MULTI_NEAREST_DIST = true -- the single nearest extra shows a distance line
-- subordinate beams (pinsmultibeam): same construction as the main beam but
-- visually secondary so the route target keeps dominance -- ~60 percent of
-- its base alpha, ~70 percent of its height clamp; the extra's distance-fade
-- alpha multiplies in on top via frame-alpha inheritance
local MULTI_BEAM_ALPHA = 0.2
local MULTI_BEAM_MIN, MULTI_BEAM_MAX = 28, 119

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
-- distance and maximum % at min distance"). The clamps are the pinsminscale/
-- pinsmaxscale settings (stage 2); nil falls back to the spec defaults.
local function ScaleForDistance(dist, smin, smax)
  smin, smax = smin or SCALE_MIN, smax or SCALE_MAX
  if dist <= SCALE_NEAR then return smax end
  if dist >= SCALE_FAR then return smin end
  return smax + (smin - smax) * (dist - SCALE_NEAR) / (SCALE_FAR - SCALE_NEAR)
end

-- defensive settings parse (compass width idiom): a garbage string falls to
-- the default, a number outside [lo, hi] clamps to the edge
local function Clamp(v, lo, hi, def)
  v = tonumber(v) or def
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

-- Pinpoint info line (stage 2): the OBJECTIVE text -- the route target's
-- precomputed description (meta.description, the same field the compass label
-- owner and the route arrow print), falling back to the quest/node title.
-- nil when the node carries neither; the CALLER then falls back to the
-- distance line, so the text is never empty (spec fallback chain).
local function PinpointText(node)
  if not node then return nil end
  local d = node.description
  if d and d ~= "" then return d end
  local t = node.title
  if t and t ~= "" then return t end
  return nil
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

-- The three-state machine (stage 2): invisible -> navigator; visible+near ->
-- pinpoint; visible+far -> waypoint. Two hysteresis layers, because both raw
-- inputs flap: the visible flag at screen edges as the camera bobs, and the
-- distance at the near threshold as the player walks along it.
--   1. Distance band (Schmitt trigger keyed on the COMMITTED mode): pinpoint
--      is desired below NEAR_ENTER, and once committed it stays desired until
--      the distance clears NEAR_LEAVE -- inside the band the incumbent side
--      wins, so oscillating across ~30 yd never even changes the desire.
--   2. The stage-1 debounce hold: the current mode holds until another has
--      been the raw desire CONTINUOUSLY for PIN_HOLD seconds -- a flapping
--      input never switches at all, a real transition follows 0.25s late.
-- Pure over (state, visible, dist, now); mutates only state{mode,pending,since}.
local function StepMode(state, visible, dist, now)
  local want
  if not visible then
    want = "navigator"
  elseif state.mode == "pinpoint" then
    want = dist <= NEAR_LEAVE and "pinpoint" or "waypoint"
  else
    want = dist < NEAR_ENTER and "pinpoint" or "waypoint"
  end
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

-- extras fade ramp: solid inside MULTI_SOLID, linear down to the MULTI_FLOOR
-- at MULTI_RADIUS (never to zero -- an invisible pin that still occupies a
-- cap slot would be a bug, not a fade). pinsopacity multiplies at apply time.
local function MultiAlpha(dist)
  if dist <= MULTI_SOLID then return 1 end
  if dist >= MULTI_RADIUS then return MULTI_FLOOR end
  return 1 + (MULTI_FLOOR - 1) * (dist - MULTI_SOLID) / (MULTI_RADIUS - MULTI_SOLID)
end

-- screen-space overlap collapse for the extras (compass MergeOverlaps adapted
-- to 2D): an extra whose plate center lands within mergeR of the ROUTE
-- TARGET's drawn plate (rx/ry; nil while the navigator holds the target --
-- extras near the orbit point are not actually overlapping anything) or of an
-- earlier KEPT extra hides behind it. The list arrives sorted (class asc,
-- dist asc, CapInsert semantics), so earlier = more important: route always
-- wins, then priority/nearness. Merged or hidden extras suppress nothing
-- (several markers at one spot ARE one destination -- the survivor marks it).
-- Pure over slots: reads show/ux/uy, sets e.merged only.
local function MergeScreenOverlaps(slots, rx, ry, mergeR)
  local n = slots.n or 0
  local r2 = mergeR * mergeR
  for i = 1, n do
    local e = slots[i]
    e.merged = nil
    if e.show then
      if rx then
        local dx, dy = e.ux - rx, e.uy - ry
        if dx * dx + dy * dy < r2 then e.merged = true end
      end
      if not e.merged then
        for k = 1, i - 1 do
          local o = slots[k]
          if o.show and not o.merged then
            local dx, dy = e.ux - o.ux, e.uy - o.uy
            if dx * dx + dy * dy < r2 then
              e.merged = true
              break
            end
          end
        end
      end
    end
  end
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
waypoint.beam:SetWidth(4)
waypoint.beam:SetHeight(120)
waypoint.beam:SetPoint("BOTTOM", waypoint, "CENTER", 0, 0)
waypoint.beam:SetGradientAlpha("VERTICAL", accent[1], accent[2], accent[3], BEAM_ALPHA,
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

-- Pinpoint (stage 2): the near-range element -- a smaller plate in the same
-- housing at the exact spot, objective text below it. No beam: up close the
-- locator shaft is the dominant object it must not be; the plate itself marks
-- the spot.
local pinpoint = CreateFrame("Frame", nil, UIParent)
pins.pinpoint = pinpoint
pinpoint:SetFrameStrata("BACKGROUND")
pinpoint:SetWidth(PINPOINT_BASE)
pinpoint:SetHeight(PINPOINT_BASE)
pinpoint.fill = pinpoint:CreateTexture(nil, "ARTWORK")
pinpoint.fill:SetTexture(PATH .. "\\img\\marker_fill")
pinpoint.fill:SetAllPoints(pinpoint)
pinpoint.fill:SetVertexColor(bg[1], bg[2], bg[3], 0.9)
pinpoint.edge = pinpoint:CreateTexture(nil, "ARTWORK")
pinpoint.edge:SetTexture(PATH .. "\\img\\marker_edge")
pinpoint.edge:SetAllPoints(pinpoint)
pinpoint.edge:SetVertexColor(accent[1], accent[2], accent[3], 1)
pinpoint.icon = pinpoint:CreateTexture(nil, "OVERLAY")
pinpoint.icon:SetWidth(12)
pinpoint.icon:SetHeight(12)
pinpoint.icon:SetPoint("CENTER", pinpoint, "CENTER", 0, 0)
-- objective text rides in a themed panel (Waypoint-UI video reference: bare
-- text floats unreadably over world clutter; the box is what makes it legible)
pinpoint.panel = CreateFrame("Frame", nil, pinpoint)
if theme and theme.SkinPanel then theme.SkinPanel(pinpoint.panel) end
pinpoint.panel:SetPoint("TOP", pinpoint, "BOTTOM", 0, -4)
pinpoint.panel:SetHeight(20)
pinpoint.panel:SetWidth(60)
pinpoint.text = pinpoint.panel:CreateFontString(nil, "OVERLAY")
pinpoint.text:SetFont(font, 12, "OUTLINE")
pinpoint.text:SetTextColor(0.9, 0.9, 0.9, 1)
pinpoint.text:SetPoint("CENTER", pinpoint.panel, "CENTER", 0, 0)
-- panel hugs whatever the text currently says (+padding); called from every
-- SetText site so the box never lags the string
local function FitPinPanel()
  local w = pinpoint.text:GetStringWidth() or 40
  pinpoint.panel:SetWidth(w + 16)
end
pinpoint.FitPanel = FitPinPanel
-- animated go-here chevrons (Waypoint-UI video reference, rendered with OUR
-- arrow art): two marks pointing DOWN above the plate, descending and fading
-- on staggered phases. Cost: two SetPoint + two SetAlpha per tick, and only
-- while pinpoint is the committed mode.
pinpoint.chev1 = pinpoint:CreateTexture(nil, "OVERLAY")
pinpoint.chev2 = pinpoint:CreateTexture(nil, "OVERLAY")
for _, t in pairs({ pinpoint.chev1, pinpoint.chev2 }) do
  t:SetTexture(PATH .. "\\img\\arrow-gw2")
  t:SetWidth(14)
  t:SetHeight(14)
  t:SetVertexColor(accent[1], accent[2], accent[3], 1)
end
pinpoint:Hide()

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

-- pinpoint chevrons always point straight down at the spot (screen angle
-- -pi/2 in AimChevron's ccw-from-right convention); aimed once, never re-set
AimChevron(pinpoint.chev1, -math.pi / 2)
AimChevron(pinpoint.chev2, -math.pi / 2)

-- node -> plate icon (compass rebind idiom); shared by Waypoint and Pinpoint
-- so a target change restyles both the same way
local function BindIcon(tex, node)
  if node and node.texture then
    tex:SetTexture(node.texture)
    local v = node.vertex
    if v and (v[1] > 0 or v[2] > 0 or v[3] > 0) then
      tex:SetVertexColor(v[1], v[2], v[3], 1)
    else
      tex:SetVertexColor(1, 1, 1, 1)
    end
  else
    tex:SetTexture(ICON_FALLBACK)
    local r, g, b = pfMap.str2rgb(node and node.title or "")
    tex:SetVertexColor(r or 1, g or 1, b or 1, 1)
  end
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
-- corpse override target (A1, docs/PINS-DESIGN.md): ONE persistent tuple in
-- the route target's {x, y, node} shape, coords rewritten in place per tick --
-- the identity stays stable so the icon/text rebinds fire once, not per
-- frame. The node mirrors the compass corpse marker (the same skull art,
-- compass.lua:640); PinpointText falls through to the title, so the pinpoint
-- reads "Your corpse" at near range. Carried on the pins table, NOT a new
-- local: the OnUpdate closure sits at Lua 5.1's 60-upvalue limit and pins is
-- already captured.
pins.corpseTarget = { 0, 0, {
  title = pfQuest_Loc and pfQuest_Loc["Your corpse"] or "Your corpse",
  texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
} }
local lastNode, lastWaySize, lastBeamH, lastDistKey, lastEtaKey, lastNavAngle
local lastPinNode, pinText, lastPinDistKey
-- parsed settings snapshot, refreshed only when a raw config string changes
-- (compass width idiom); the per-frame path reads these plain locals
local sizeMul, scaleMin, scaleMax, navRadius = 1, SCALE_MIN, SCALE_MAX, NAV_RADIUS
local lastCfgSize, lastCfgPoint, lastCfgMin, lastCfgMax, lastCfgOp, lastCfgNavR, lastCfgNavS

-- multi settings + driver state in ONE table: the OnUpdate closure brushes
-- Lua 5.1's 60-upvalue limit, so the multi layer contributes three upvalues
-- (ms, MultiTick, MultiSleep) instead of eleven scattered locals
local ms = {
  MAX = MULTI_MAX,
  on = false, cap = 4, beam = true, active = nil,
  op = 1, -- pinsopacity snapshot, multiplied into the extras' distance fade
  cfgOn = nil, cfgCap = nil, cfgBeam = nil, -- raw-string dirty keys
  lastTarget = nil, lastQueue = nil, lastZone = nil, lastCap = nil,
  nextRebuild = 0,
}

-- ---------------------------------------------------------------------------
-- multi-pin extras (pinsmulti, experimental): an AMBIENT layer of up to
-- pinsmulticap additional plates beyond the route target, drawn from the
-- compass taxonomy via the shared pfQuest.compass.EachZoneNode walk --
-- turn-ins (ready only), active objectives and available givers, honoring the
-- compass's per-class toggles; dungeon entrances and the corpse never reach
-- this layer (the walk yields neither, and the route already follows the
-- corpse while dead). Plain conditions, no per-extra state machine, no
-- navigator: an off-screen or out-of-radius extra simply hides.
-- ---------------------------------------------------------------------------

local mlist = { n = 0 }
local mpool, mpoolsize = {}, 0
local mframes = {}

local function GetMEntry()
  if mpoolsize > 0 then
    local e = mpool[mpoolsize]
    mpool[mpoolsize] = nil
    mpoolsize = mpoolsize - 1
    return e
  end
  return {}
end

local function RepoolM(e)
  mpoolsize = mpoolsize + 1
  mpool[mpoolsize] = e
end

-- pooled widgets, created ONCE on the first enabled tick (pinsmulti off costs
-- zero frames): the compass plate housing, a subordinate beam and a distance
-- fontstring only the nearest extra ever shows. Beam gradient base is
-- MULTI_BEAM_ALPHA set once here -- the per-extra distance fade rides the
-- FRAME's alpha, which children inherit, so the steady path never re-issues
-- SetGradientAlpha.
local function BuildMultiPool()
  for i = 1, MULTI_MAX do
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("BACKGROUND")
    f:SetWidth(MULTI_BASE)
    f:SetHeight(MULTI_BASE)
    f.beam = f:CreateTexture(nil, "BORDER")
    f.beam:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    f.beam:SetWidth(3)
    f.beam:SetHeight(MULTI_BEAM_MIN)
    f.beam:SetPoint("BOTTOM", f, "CENTER", 0, 0)
    f.beam:SetGradientAlpha("VERTICAL", accent[1], accent[2], accent[3], MULTI_BEAM_ALPHA,
                            accent[1], accent[2], accent[3], 0)
    f.beam:Hide() -- born hidden (the .on dirty-flag rule)
    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetTexture(PATH .. "\\img\\marker_fill")
    f.fill:SetAllPoints(f)
    f.fill:SetVertexColor(bg[1], bg[2], bg[3], 0.9)
    f.edge = f:CreateTexture(nil, "ARTWORK")
    f.edge:SetTexture(PATH .. "\\img\\marker_edge")
    f.edge:SetAllPoints(f)
    f.edge:SetVertexColor(accent[1], accent[2], accent[3], 1)
    f.icon = f:CreateTexture(nil, "OVERLAY")
    f.icon:SetWidth(12)
    f.icon:SetHeight(12)
    f.icon:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.dtext = f:CreateFontString(nil, "OVERLAY")
    f.dtext:SetFont(font, 11, "OUTLINE")
    f.dtext:SetTextColor(0.9, 0.9, 0.9, 1)
    f.dtext:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.dtext:Hide()
    f:Hide()
    mframes[i] = f
  end
end

-- rebuild sink for EachZoneNode, a fixed closure (zero rebuild allocations);
-- ranking is CapInsert semantics (class asc, dist asc) in WORLD YARDS, and
-- the show radius culls here so cap slots never go to unreachable extras
local sinkPx, sinkPy, sinkW, sinkH, sinkSkipX, sinkSkipY, sinkCapInsert
local MULTI_RADIUS2 = MULTI_RADIUS * MULTI_RADIUS
local function MultiSink(x, y, class, tab)
  -- the route target's own cell already wears the full waypoint treatment
  if sinkSkipX and x == sinkSkipX and y == sinkSkipY then return end
  local dx = (x / 100 - sinkPx) * sinkW
  local dy = (y / 100 - sinkPy) * sinkH
  local d2 = dx * dx + dy * dy
  if d2 > MULTI_RADIUS2 then return end
  local e = GetMEntry()
  e.class, e.key, e.x, e.y, e.dist2 = class, tab, x, y, d2
  e.show = nil
  local ev = sinkCapInsert(mlist, ms.cap, e)
  if ev then RepoolM(ev) end
end

local function RebuildMulti(pxf, pyf, target)
  for i = 1, mlist.n do
    RepoolM(mlist[i])
    mlist[i] = nil
  end
  mlist.n = 0
  mlist.rebind = true
  -- the provider lives in compass.lua (the module, NOT the compass setting:
  -- EachZoneNode is a plain function, live whether the strip is enabled or
  -- not); without it, or without zone size data, extras honestly stay empty
  local api = pfQuest.compass
  if not api or not api.EachZoneNode then return end
  local size = pfMap and pfMap.minimap_sizes and pfMap.minimap_sizes[zoneID]
  if not size or not size[1] or not size[2] then return end
  sinkCapInsert = api.CapInsert
  sinkPx, sinkPy, sinkW, sinkH = pxf, pyf, size[1], size[2]
  sinkSkipX = target and target[1] or nil
  sinkSkipY = target and target[2] or nil
  api.EachZoneNode(zoneID, MultiSink)
end

local function MultiSleep()
  if not ms.active then return end
  ms.active = nil
  ms.nextRebuild = 0 -- wake rebuilds immediately
  ms.lastTarget, ms.lastQueue, ms.lastZone = nil, nil, nil
  for i = 1, MULTI_MAX do
    local f = mframes[i]
    if f then
      if f.on then
        f.on = nil
        f:Hide()
      end
      if f.dtext.on then
        f.dtext.on = nil
        f.dtext:Hide()
      end
    end
  end
end

-- per-tick extras pass: project + fade + merge + apply for at most MULTI_MAX
-- plates inside the existing 0.02s cap. rx/ry is the route pin's drawn plate
-- position (nil in navigator mode). Strings/sizes/show-hide all dirty-keyed;
-- the SetPoint cannot be (the camera moves every frame).
local function MultiTick(now, wx, wy, wz, pxf, pyf, uiw, uih, target, rx, ry)
  if not mframes[1] then BuildMultiPool() end
  ms.active = true

  -- rebuild triggers, the compass driver's set: route-target identity, node
  -- writes (pfMap.queue_update), zone change, cap change, 1s heartbeat
  local queue = pfMap and pfMap.queue_update
  if target ~= ms.lastTarget or queue ~= ms.lastQueue
     or zoneID ~= ms.lastZone or ms.cap ~= ms.lastCap
     or now > ms.nextRebuild then
    ms.lastTarget, ms.lastQueue = target, queue
    ms.lastZone, ms.lastCap = zoneID, ms.cap
    ms.nextRebuild = now + 1
    RebuildMulti(pxf, pyf, target)
  end

  local n = mlist.n
  for i = 1, n do
    local e = mlist[i]
    e.show = nil
    local ex, ey = PercentToWorld(pxf, pyf, e.x, e.y, wx, wy, zoneID)
    if ex then
      local sx, sy, vis = WorldToScreen(ex, ey, wz)
      if sx and vis then
        local dxw, dyw = ex - wx, ey - wy
        local d = sqrt(dxw * dxw + dyw * dyw)
        -- the player moves between rebuilds: re-check the show radius live
        if d <= MULTI_RADIUS then
          e.show = true
          e.dist = d
          e.ux, e.uy = ToUiCoords(sx, sy, uiw, uih)
        end
      end
    end
  end
  MergeScreenOverlaps(mlist, rx, ry, MULTI_MERGE)

  local rebind = mlist.rebind
  mlist.rebind = nil
  local nearestIdx, nearestDist
  for i = 1, MULTI_MAX do
    local f = mframes[i]
    local e = i <= n and mlist[i] or nil
    if e and e.show and not e.merged then
      if rebind or f.key ~= e.key then
        f.key = e.key
        BindIcon(f.icon, e.key)
      end
      f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", e.ux, e.uy)
      -- extras shrink with range exactly like the main pin (same clamps)
      local size = floor(MULTI_BASE * sizeMul * ScaleForDistance(e.dist, scaleMin, scaleMax) + 0.5)
      if size ~= f.lastSize then
        f.lastSize = size
        f:SetWidth(size)
        f:SetHeight(size)
        local isz = floor(size * 0.6 + 0.5)
        f.icon:SetWidth(isz)
        f.icon:SetHeight(isz)
      end
      local a = MultiAlpha(e.dist) * ms.op
      if a ~= f.lastA then
        f.lastA = a
        f:SetAlpha(a)
      end
      -- subordinate beam: distance-driven height like the main beam, tighter
      -- clamp; its alpha = MULTI_BEAM_ALPHA * frame fade via inheritance
      if ms.beam then
        local bh = floor(e.dist + 0.5)
        if bh < MULTI_BEAM_MIN then bh = MULTI_BEAM_MIN
        elseif bh > MULTI_BEAM_MAX then bh = MULTI_BEAM_MAX end
        if bh ~= f.lastBeamH then
          f.lastBeamH = bh
          f.beam:SetHeight(bh)
        end
        if not f.beam.on then
          f.beam.on = true
          f.beam:Show()
        end
      elseif f.beam.on then
        f.beam.on = nil
        f.beam:Hide()
      end
      if not f.on then
        f.on = true
        f:Show()
      end
      if MULTI_NEAREST_DIST and (not nearestDist or e.dist < nearestDist) then
        nearestDist, nearestIdx = e.dist, i
      end
    elseif f.on then
      f.on = nil
      f:Hide()
    end
  end

  -- the single nearest shown extra gets a small distance line (exploration
  -- knob MULTI_NEAREST_DIST); everything else is plate+icon only
  for i = 1, MULTI_MAX do
    local f = mframes[i]
    if i == nearestIdx then
      local metric = pfQuest_config["compassmetric"] == "1"
      local shownD = metric and (nearestDist * 0.9144) or nearestDist
      local rounded = floor(shownD + 0.5)
      local key = metric and -rounded or rounded
      if key ~= f.lastDistKey then
        f.lastDistKey = key
        f.dtext:SetText(rounded .. (metric and " m" or " yd"))
      end
      if not f.dtext.on then
        f.dtext.on = true
        f.dtext:Show()
      end
    elseif f.dtext and f.dtext.on then
      f.dtext.on = nil
      f.dtext:Hide()
    end
  end
end

local driver = CreateFrame("Frame", nil, UIParent)
pins.driver = driver

local function Sleep()
  if not pins.on then return end
  pins.on = nil
  shownMode = nil
  state.mode, state.pending = nil, nil -- wake adopts the raw flag instantly
  speedAvg = nil
  waypoint:Hide()
  pinpoint:Hide()
  navigator:Hide()
  MultiSleep()
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

  -- live settings: dirty-check the raw strings inside the cap (compass width
  -- idiom) -- seven table reads + compares per capped tick; the parse and the
  -- widget writes run only on an actual change
  local cfgSize = pfQuest_config["pinssize"]
  local cfgPoint = pfQuest_config["pinspointsize"]
  local cfgMin = pfQuest_config["pinsminscale"]
  local cfgMax = pfQuest_config["pinsmaxscale"]
  local cfgOp = pfQuest_config["pinsopacity"]
  local cfgNavR = pfQuest_config["pinsnavradius"]
  local cfgNavS = pfQuest_config["pinsnavsize"]
  local cfgMulti = pfQuest_config["pinsmulti"]
  local cfgMultiCap = pfQuest_config["pinsmulticap"]
  local cfgMultiBeam = pfQuest_config["pinsmultibeam"]
  if cfgSize ~= lastCfgSize or cfgPoint ~= lastCfgPoint
     or cfgMin ~= lastCfgMin or cfgMax ~= lastCfgMax or cfgOp ~= lastCfgOp
     or cfgNavR ~= lastCfgNavR or cfgNavS ~= lastCfgNavS
     or cfgMulti ~= ms.cfgOn or cfgMultiCap ~= ms.cfgCap
     or cfgMultiBeam ~= ms.cfgBeam then
    lastCfgSize, lastCfgPoint, lastCfgMin, lastCfgMax = cfgSize, cfgPoint, cfgMin, cfgMax
    lastCfgOp, lastCfgNavR, lastCfgNavS = cfgOp, cfgNavR, cfgNavS
    ms.cfgOn, ms.cfgCap, ms.cfgBeam = cfgMulti, cfgMultiCap, cfgMultiBeam
    sizeMul = Clamp(cfgSize, 25, 300, 100) / 100
    scaleMin = Clamp(cfgMin, 10, 300, 50) / 100
    scaleMax = Clamp(cfgMax, 10, 300, 150) / 100
    -- a crossed pair collapses to the max value instead of inverting the ramp
    if scaleMin > scaleMax then scaleMin = scaleMax end
    navRadius = Clamp(cfgNavR, 50, 400, 140)
    ms.on = cfgMulti == "1"
    ms.cap = Clamp(cfgMultiCap, 1, ms.MAX, 4)
    ms.beam = cfgMultiBeam ~= "0"
    -- whole-tier opacity: one SetAlpha per element, every child rides along;
    -- the extras multiply it into their distance fade per tick instead
    local a = Clamp(cfgOp, 10, 100, 100) / 100
    ms.op = a
    waypoint:SetAlpha(a)
    pinpoint:SetAlpha(a)
    navigator:SetAlpha(a)
    -- pinpoint and navigator sizes are distance-independent: apply once here,
    -- not per frame
    local psz = floor(PINPOINT_BASE * Clamp(cfgPoint, 25, 300, 100) / 100 + 0.5)
    pinpoint:SetWidth(psz)
    pinpoint:SetHeight(psz)
    local pisz = floor(psz * 0.6 + 0.5)
    pinpoint.icon:SetWidth(pisz)
    pinpoint.icon:SetHeight(pisz)
    local nsz = floor(NAV_SIZE * Clamp(cfgNavS, 25, 300, 100) / 100 + 0.5)
    navigator:SetWidth(nsz)
    navigator:SetHeight(nsz)
    local csz = floor(nsz * 0.72 + 0.5)
    navigator.chevron:SetWidth(csz)
    navigator.chevron:SetHeight(csz)
    lastWaySize = nil -- the waypoint's distance-scaled size re-derives next pass
  end

  -- route target: the arrow's current destination -- coords[1] is only a
  -- valid target while its distance slot [4] is set (route.lua:491)
  local coords = pfQuest.route.coords
  local target = coords and coords[1] and coords[1][4] and coords[1] or nil
  local pxf, pyf = GetPlayerMapPosition("player")
  -- 0,0 = indoors/instance/other map viewed: the percent->world anchor pair
  -- is invalid, so every pin position would lie (compass indoor rule)
  if pxf == 0 and pyf == 0 then
    Sleep()
    return
  end

  -- corpse pylon (A1): while dead/ghost the tier targets the CORPSE with
  -- absolute priority (the compass CLASS_CORPSE rule), unconditional while
  -- pins are on -- nothing else matters mid-corpse-run, so the extras hide
  -- too (the corpseRun gate below). GetCorpseMapPosition returns map
  -- fractions and 0,0 when the corpse is on another map (both 3.3.5a-native,
  -- the compass.lua:635 seam); read as globals, not upvalue-cached locals --
  -- this OnUpdate closure brushes Lua 5.1's 60-upvalue limit.
  local corpseRun
  if UnitIsDeadOrGhost("player") then
    corpseRun = true
    local cx, cy = GetCorpseMapPosition()
    if cx and cy and not (cx == 0 and cy == 0) then
      local ct = pins.corpseTarget
      ct[1], ct[2] = cx * 100, cy * 100
      target = ct
    end
  end

  if not target then
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
  local mode = StepMode(state, vis and true or false, dist, now)
  if mode ~= shownMode then
    shownMode = mode
    if mode == "waypoint" then
      pinpoint:Hide()
      navigator:Hide()
      waypoint:Show()
    elseif mode == "pinpoint" then
      waypoint:Hide()
      navigator:Hide()
      pinpoint:Show()
    else
      waypoint:Hide()
      pinpoint:Hide()
      navigator:Show()
    end
  end

  local uiw, uih = UIParent:GetWidth(), UIParent:GetHeight()
  -- the projected target point in UI units, shared by all three modes (and
  -- by the extras' merge pass as the route pin's drawn position)
  local ux, uy = ToUiCoords(sx, sy, uiw, uih)

  if mode == "waypoint" then
    waypoint:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ux, uy)

    -- distance-based plate scale, dirty on the rounded pixel size
    local size = floor(BASE_SIZE * sizeMul * ScaleForDistance(dist, scaleMin, scaleMax) + 0.5)
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
      BindIcon(waypoint.icon, node)
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
  elseif mode == "pinpoint" then
    pinpoint:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ux, uy)

    -- descending chevron animation: linear fall over ~1.1s, staggered half a
    -- phase apart, fading in over the first 15 percent and out over the last
    -- 25 so the loop point never pops
    local ph = (now % 1.1) / 1.1
    local ph2 = ph + 0.5
    if ph2 >= 1 then ph2 = ph2 - 1 end
    local a1 = (ph < 0.15 and ph / 0.15 or 1) * (ph > 0.75 and (1 - ph) / 0.25 or 1)
    local a2 = (ph2 < 0.15 and ph2 / 0.15 or 1) * (ph2 > 0.75 and (1 - ph2) / 0.25 or 1)
    pinpoint.chev1:SetPoint("BOTTOM", pinpoint, "TOP", 0, 26 - ph * 12)
    pinpoint.chev2:SetPoint("BOTTOM", pinpoint, "TOP", 0, 26 - ph2 * 12)
    pinpoint.chev1:SetAlpha(a1)
    pinpoint.chev2:SetAlpha(a2)

    -- objective line + icon, rebound on target change only. The text is the
    -- spec fallback chain: description -> title -> distance (never empty)
    local node = target[3]
    if node ~= lastPinNode then
      lastPinNode = node
      BindIcon(pinpoint.icon, node)
      pinText = PinpointText(node)
      if pinText then
        pinpoint.text:SetText(pinText)
        FitPinPanel()
      end
      lastPinDistKey = nil
    end
    if not pinText then
      -- last fallback: the same distance line as the waypoint (display-time
      -- metric conversion, compass.lua:909), dirty on the rounded key
      local metric = pfQuest_config["compassmetric"] == "1"
      local shownD = metric and (dist * 0.9144) or dist
      local rounded = floor(shownD + 0.5)
      local key = metric and -rounded or rounded
      if key ~= lastPinDistKey then
        lastPinDistKey = key
        pinpoint.text:SetText(rounded .. (metric and " m" or " yd"))
        FitPinPanel()
      end
    end
  else
    -- navigator: orbit the screen center at a fixed radius along the target's
    -- screen direction -- the invisible-but-updating WorldToScreen coords ARE
    -- the bearing (spec)
    local a = NavigatorAngle(ux, uy, uiw * 0.5, uih * 0.5)
    navigator:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
                       uiw * 0.5 + cos(a) * navRadius, uih * 0.5 + sin(a) * navRadius)
    -- re-aim only on a real angular change (~0.6 deg) -- SetTexCoord is not free
    if not lastNavAngle or a - lastNavAngle > 0.01 or lastNavAngle - a > 0.01 then
      lastNavAngle = a
      AimChevron(navigator.chevron, a)
    end
  end

  -- multi-pin extras (experimental ambient layer): in navigator mode the
  -- route pin is drawn at the orbit point, not at ux/uy, so no merge ref.
  -- While dead the extras hide ENTIRELY (A1 corpse-run rule): the corpse is
  -- the only thing that matters, ambient plates are noise next to it.
  if corpseRun then
    if ms.active then MultiSleep() end
  elseif ms.on then
    if mode == "navigator" then
      MultiTick(now, wx, wy, wz, pxf, pyf, uiw, uih, target, nil, nil)
    else
      MultiTick(now, wx, wy, wz, pxf, pyf, uiw, uih, target, ux, uy)
    end
  elseif ms.active then
    MultiSleep()
  end
end)

-- ---------------------------------------------------------------------------
-- public surface (the harness drives exactly these)
-- ---------------------------------------------------------------------------

pins.ToUiCoords = ToUiCoords
pins.PercentToWorld = PercentToWorld
pins.ScaleForDistance = ScaleForDistance
pins.Clamp = Clamp
pins.PinpointText = PinpointText
pins.EtaFor = EtaFor
pins.FormatEta = FormatEta
pins.NavigatorAngle = NavigatorAngle
pins.StepMode = StepMode
pins.MultiAlpha = MultiAlpha
pins.MergeScreenOverlaps = MergeScreenOverlaps
pins.multilist = mlist
pins.multiframes = mframes
-- the tunables, exposed so the harness can pin relationships (extras beams
-- subordinate to the main beam) without transcribing constants
pins.tunables = {
  BEAM_ALPHA = BEAM_ALPHA, BEAM_MIN = BEAM_MIN, BEAM_MAX = BEAM_MAX,
  MULTI_MAX = MULTI_MAX, MULTI_RADIUS = MULTI_RADIUS, MULTI_SOLID = MULTI_SOLID,
  MULTI_FLOOR = MULTI_FLOOR, MULTI_MERGE = MULTI_MERGE, MULTI_BASE = MULTI_BASE,
  MULTI_NEAREST_DIST = MULTI_NEAREST_DIST, MULTI_BEAM_ALPHA = MULTI_BEAM_ALPHA,
  MULTI_BEAM_MIN = MULTI_BEAM_MIN, MULTI_BEAM_MAX = MULTI_BEAM_MAX,
}
