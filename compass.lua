-- pfQuest Reforged -- HorizonCompass (stage 2)
-- Reforged: Skyrim-style horizontal compass strip at top-center. Cardinal
-- letters and 15-degree ticks scroll through a fixed 180-degree FOV as the
-- player turns; markers mirror the current zone's pfMap nodes (turn-ins,
-- active objectives, available quests, dungeon entrances), the route arrow's
-- current target and the player's corpse. Loads AFTER route.lua and only
-- READS its state. Strip chrome is procedural; markers sit on the generated
-- diamond plates (img/marker_fill + img/marker_edge, vertex-tinted to theme).

-- Reforged: standalone guard -- without pfQuest/route there is nothing to
-- mirror; bail before creating any frame so a partial install never errors.
if not pfQuest or not pfQuest.route then return end

-- cache per-frame globals once (tracker.lua idiom)
local floor, sqrt = math.floor, math.sqrt
-- math.atan2, NEVER the bare global atan2: the client's atan2 works in DEGREES
-- while GetPlayerFacing/math.sin are radians -- mixing them spun the route
-- arrow on any movement (route.lua:537).
local sin, cos, atan2 = math.sin, math.cos, math.atan2
local strfind = string.find
local GetTime = GetTime
local GetPlayerMapPosition = GetPlayerMapPosition
local GetRealZoneText = GetRealZoneText
local UnitOnTaxi = UnitOnTaxi
local UnitLevel = UnitLevel
-- corpse + difficulty APIs: all 3.3.5a-native (milkyway api-functions.ts:
-- GetCorpseMapPosition returns map fractions 0..1 or 0,0 when not on this map;
-- UnitIsDeadOrGhost; GetQuestDifficultyColor returns a {r,g,b} table)
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetCorpseMapPosition = GetCorpseMapPosition
local GetQuestDifficultyColor = GetQuestDifficultyColor
-- vanilla-era clients lack GetPlayerFacing; the compat shim derives it from the
-- minimap arrow (compat/client.lua:83). 3.3.5a has it natively (milkyway).
local GetFacing = pfQuestCompat and pfQuestCompat.GetPlayerFacing or GetPlayerFacing

local HALF_PI = math.pi / 2
local RAD2DEG = 180 / math.pi
local L = pfQuest_Loc

-- theme adapts to GW2_UI automatically (theme.lua swaps the accent when the
-- addon is loaded); fall back to pfQuest teal when running without theme.lua
local theme = pfQuestTheme
local accent = theme and theme.accent or { 0.2, 1.0, 0.8 }
local font = (pfUI and pfUI.font_default) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local PATH = (pfQuestConfig and pfQuestConfig.path) or "Interface\\AddOns\\pfQuest"

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
-- marker taxonomy (COMPASS-DESIGN.md "Stage 2: the marker taxonomy") --
-- ascending class number = higher importance; the cap drops the LOWEST class
-- (highest number) first, and label tie-breaks follow the same order.
-- ---------------------------------------------------------------------------

local CLASS_CORPSE   = 1 -- highest priority of all: nothing else matters mid-corpse-run
local CLASS_WAYPOINT = 2 -- the user's /way point (waypoint.lua), above the route target
local CLASS_ROUTE    = 3 -- the guidance anchor, stage 1's single marker
local CLASS_TURNIN   = 4 -- complete / complete_c (?)
local CLASS_ACTIVE   = 5 -- cluster_* objective nodes for questlog quests
local CLASS_AVAIL    = 6 -- available (!) quest givers
local CLASS_DUNGEON  = 7 -- meta DB meeting stones (instance portals), default off
local CLASS_RARE     = 8 -- rare spawns from the meta DB rares list, default off
local CLASS_PARTY    = 9 -- same-zone party members; PINS-ONLY (the strip never renders it)

-- classify a pfMap node by its minimap texture -- the node loop's own visual
-- language (map.lua layers table). Plain find, no patterns (perf idiom).
-- available_c is the giver of a quest ALREADY in the log -- not an offer, and
-- its objective already shows through cluster nodes, so it maps to nothing.
-- Ready turn-ins only (maintainer: the ender of a kill-quest still in
-- progress is clutter next to its objective pylon): pfDatabase paints the
-- ender complete_c (colored ?) once the log quest's complete flag is set and
-- plain complete (grey ?) while objectives are open (database.lua:1666-1675),
-- so the texture already encodes readiness -- a not-ready ender maps to
-- nothing here and thereby vanishes from every taxonomy consumer at once.
local function ClassifyNode(tex)
  if not tex then return nil end
  if strfind(tex, "complete_c", 1, true) then return CLASS_TURNIN end
  if strfind(tex, "complete", 1, true) then return nil end
  if strfind(tex, "cluster", 1, true) then return CLASS_ACTIVE end
  if strfind(tex, "available_c", 1, true) then return nil end
  if strfind(tex, "available", 1, true) then return CLASS_AVAIL end
  return nil
end

-- capped insertion keeping `list` sorted by (class asc, dist2 asc): nearest
-- first within a class, lowest class evicted first when over cap. Returns the
-- entry that fell out (for the caller to repool), or nil if all fit.
local function CapInsert(list, cap, entry)
  local n = list.n or 0
  local pos = n + 1
  for i = 1, n do
    local e = list[i]
    if entry.class < e.class or (entry.class == e.class and entry.dist2 < e.dist2) then
      pos = i
      break
    end
  end
  if pos > cap then return entry end
  for i = n, pos, -1 do
    list[i + 1] = list[i]
  end
  list[pos] = entry
  if n + 1 > cap then
    local evicted = list[n + 1]
    list[n + 1] = nil
    list.n = cap
    return evicted
  end
  list.n = n + 1
  return nil
end

-- view-driven label selection (COMPASS-DESIGN.md "Label policy"): the marker
-- nearest the center needle inside a ~ +/-15 degree window owns the label;
-- ties inside the window break by class priority (route > turn-in > active >
-- available). When NO marker is in the window the ROUTE TARGET keeps the
-- label even edge-clamped, so the strip is never guidance-free; the corpse
-- owns it unconditionally while dead. Hysteresis (the thrash hazard): the
-- incumbent keeps the label until a challenger is >= ~4 degrees closer to
-- center AND a ~0.5s minimum hold has passed -- two markers straddling the
-- center must not flicker-fight it. Pure over (slots, state, now): reads
-- each slot's class/rel/key, mutates only state {owner=key, since=time}.
local LABEL_WINDOW = 15 * math.pi / 180
local LABEL_MARGIN = 4 * math.pi / 180
local LABEL_HOLD = 0.5
local function SelectLabel(slots, state, now)
  local n = slots.n or 0
  for i = 1, n do
    if slots[i].class == CLASS_CORPSE then
      if state.owner ~= slots[i].key then
        state.owner, state.since = slots[i].key, now
      end
      return slots[i]
    end
  end
  local best, bestabs, inc, incabs, fallback
  for i = 1, n do
    local e = slots[i]
    local a = e.rel < 0 and -e.rel or e.rel
    if e.key == state.owner and not e.merged then
      inc, incabs = e, a
    end
    -- guidance anchors double as the empty-window fallback; the list is
    -- sorted class ascending, so a present WAYPOINT wins over the route
    if not fallback and (e.class == CLASS_WAYPOINT or e.class == CLASS_ROUTE) then
      fallback = e
    end
    if a <= LABEL_WINDOW and not e.merged then
      if not best then
        best, bestabs = e, a
      elseif a < bestabs - 1e-9 then
        best, bestabs = e, a
      elseif a < bestabs + 1e-9 and e.class < best.class then
        best, bestabs = e, a
      end
    end
  end
  local chosen
  if not best then
    chosen = fallback
  elseif inc and inc ~= best and incabs <= LABEL_WINDOW then
    -- incumbent still in the window: the challenger must clear both gates
    if now - (state.since or 0) >= LABEL_HOLD and bestabs <= incabs - LABEL_MARGIN then
      chosen = best
    else
      chosen = inc
    end
  else
    chosen = best
  end
  if chosen and chosen.key ~= state.owner then
    state.owner, state.since = chosen.key, now
  end
  return chosen
end

-- ---------------------------------------------------------------------------
-- strip frame + pooled elements (everything created ONCE here; the OnUpdate
-- only repositions/re-alphas -- zero allocations in the steady path)
-- ---------------------------------------------------------------------------

-- overlap collapse (maintainer QA: three turn-in plates stacked unreadably on
-- one camp). The slot list is already sorted by (class asc, dist asc), so the
-- FIRST marker at a screen position is the most important one; later markers
-- whose plate centers land within mergePx of a kept marker hide behind it --
-- several markers at one spot ARE one destination. Clamped stacks collapse to
-- one edge hint per side for free (shared off). Pure over slots: sets/clears
-- e.merged only.
local function MergeOverlaps(slots, mergePx)
  local n = slots.n or 0
  for i = 1, n do
    slots[i].merged = nil
  end
  for i = 2, n do
    local e = slots[i]
    for k = 1, i - 1 do
      local o = slots[k]
      if not o.merged then
        local d = e.off - o.off
        if d < 0 then d = -d end
        if d < mergePx then
          e.merged = true
          break
        end
      end
    end
  end
end
local MERGE_PX = 16

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

-- ---------------------------------------------------------------------------
-- marker pool: MAXCAP housed markers, built once. Each is a small frame (one
-- SetPoint moves plate+icon+badge together) carrying the diamond plate --
-- marker_fill tinted theme bg under marker_edge tinted theme accent, the type
-- icon (the node's own minimap texture) on top, and the daily/event badge
-- dot at the plate's top-right (COMPASS-DESIGN.md "Marker housing").
-- ---------------------------------------------------------------------------

local MAXCAP = 12
local ICON_FALLBACK = PATH .. "\\img\\node"
local markers = {}
for i = 1, MAXCAP do
  local m = CreateFrame("Frame", nil, compass)
  -- explicitly above the strip frame: cardinal LETTERS are fontstrings on the
  -- strip itself and fontstrings draw over sibling textures, so without this
  -- a cardinal renders across a plate (maintainer screenshot: SW over a ?)
  m:SetFrameLevel(compass:GetFrameLevel() + 3)
  m:SetWidth(20)
  m:SetHeight(20)
  m.fill = m:CreateTexture(nil, "ARTWORK")
  m.fill:SetTexture(PATH .. "\\img\\marker_fill")
  m.fill:SetAllPoints(m)
  m.fill:SetVertexColor(bgr, bgg, bgb, 0.9)
  -- created after fill in the same layer -> draws above it
  m.edge = m:CreateTexture(nil, "ARTWORK")
  m.edge:SetTexture(PATH .. "\\img\\marker_edge")
  m.edge:SetAllPoints(m)
  m.edge:SetVertexColor(accent[1], accent[2], accent[3], 1)
  m.icon = m:CreateTexture(nil, "OVERLAY")
  m.icon:SetWidth(12)
  m.icon:SetHeight(12)
  m.icon:SetPoint("CENTER", m, "CENTER", 0, 0)
  -- daily/event badge: a small accent-blue diamond, echoing the map's
  -- VERTEX_BLUE tint for event quests
  m.badge = m:CreateTexture(nil, "OVERLAY")
  m.badge:SetWidth(7)
  m.badge:SetHeight(7)
  m.badge:SetTexture(PATH .. "\\img\\marker_edge")
  m.badge:SetVertexColor(0.4, 0.7, 1.0, 1)
  m.badge:SetPoint("CENTER", m, "TOPRIGHT", -3, -3)
  m.badge:Hide()
  m:Hide()
  markers[i] = m
end

-- labels ride above the strip at the label owner's offset
local dist = compass:CreateFontString(nil, "OVERLAY")
dist:SetFont(font, 11, "OUTLINE")
dist:SetTextColor(0.9, 0.9, 0.9, 1)
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

-- objective description of the label owner (pfDatabase's precomputed
-- meta.description, the same line the route arrow prints, route.lua:628):
-- below the strip beside the degree readout -- spec layout preference (b).
-- Fixed box so a long line clips at the strip's scale instead of running
-- across the screen; sized in UpdateSettings.
local descText = compass:CreateFontString(nil, "OVERLAY")
descText:SetFont(font, 11, "OUTLINE")
descText:SetTextColor(0.9, 0.9, 0.9, 1)
descText:SetJustifyH("CENTER")
descText:SetHeight(12)
-- own line BELOW the degree readout (maintainer: beside it read as one run-on
-- string, and the narrow box truncated real descriptions); centered with the
-- full strip width available
descText:SetPoint("TOP", degreeText, "BOTTOM", 0, -2)
descText:Hide()

local LETTERS8 = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

-- ---------------------------------------------------------------------------
-- marker providers: fill `list` (the capped, class/distance-sorted selection)
-- from the corpse, the route target, the current zone's pfMap nodes and the
-- meta DB dungeon entrances. Runs on rebuild triggers (~1/s), never per frame.
-- ---------------------------------------------------------------------------

local list = { n = 0 }
local entrypool = {}
local poolsize = 0
local zoneName, zoneID

local function GetEntry()
  if poolsize > 0 then
    local e = entrypool[poolsize]
    entrypool[poolsize] = nil
    poolsize = poolsize - 1
    return e
  end
  return {}
end

local function Repool(e)
  poolsize = poolsize + 1
  entrypool[poolsize] = e
end

-- coord-key parse cache, the map.lua coord_cache idiom (map.lua:107): the
-- "x|y" keys are stable strings, so each is split exactly once
local coordcache = {}
local function ParseCoords(coords)
  local c = coordcache[coords]
  if not c then
    local _, _, strx, stry = strfind(coords, "(.*)|(.*)")
    c = { strx + 0, stry + 0 }
    coordcache[coords] = c
  end
  return c[1], c[2]
end

-- daily/event badge, cheap lookups only (design: no scans). The event flag
-- lives on the merged quest DB (db/quests-eventtags335.lua overlay applied in
-- database.lua:245); isDaily is GetQuestLogTitle slot 8 -- an AzerothCore
-- backport, guarded so stock cores (nil there) simply never badge dailies.
local function IsEventOrDaily(tab)
  local qid = tonumber(tab.questid)
  if qid and pfDB and pfDB["quests"] and pfDB["quests"]["data"]
     and pfDB["quests"]["data"][qid] and pfDB["quests"]["data"][qid]["event"] then
    return true
  end
  local qlogid = tonumber(tab.qlogid)
  if qlogid and GetQuestLogTitle then
    local qtitle, _, _, _, _, _, _, daily = GetQuestLogTitle(qlogid)
    -- only trust the slot while it still holds this quest (the log shifts on
    -- turn-in/abandon; quest.lua:417 uses the same verification)
    if qtitle == tab.title and daily then
      return true
    end
  end
  return nil
end

-- icon tint: available quests above the player's level show the difficulty
-- color (COMPASS-DESIGN.md taxonomy row); otherwise mirror the node's own
-- vertex tint like the route arrow does (route.lua:616), else untinted.
local function TintFor(class, tab, plevel)
  if class == CLASS_AVAIL then
    local qmin = tonumber(tab.qmin)
    if qmin and plevel and qmin > plevel then
      local c = GetQuestDifficultyColor(tonumber(tab.qlvl) or qmin)
      if c then return c.r, c.g, c.b end
    end
  end
  local v = tab.vertex
  if v and (v[1] > 0 or v[2] > 0 or v[3] > 0) then
    return v[1], v[2], v[3]
  end
  return 1, 1, 1
end

-- shared taxonomy walk (the strip AND the in-world multi-pins, pins.lua):
-- enumerate the zone's classified pfMap cells -- one candidate per coord cell
-- (the minimap shows one pin there too), the most important classified node
-- winning within a cell, the compassavail/compassturnin toggles honored --
-- and hand each to sink(x, y, class, tab). Selection POLICY (cap, ranking
-- metric, show radius) deliberately stays per-consumer: the strip ranks in
-- aspect-corrected map percent, the pins in world yards.
local function EachZoneNode(zid, sink)
  if not zid or not pfMap or not pfMap.nodes then return end
  local showAvail = pfQuest_config["compassavail"] ~= "0"
  local showTurnin = pfQuest_config["compassturnin"] ~= "0"
  for _, zones in pairs(pfMap.nodes) do
    local zone = zones[zid]
    if zone then
      for coords, cell in pairs(zone) do
        local best, bestclass
        for _, tab in pairs(cell) do
          local class = ClassifyNode(tab.texture)
          if class == CLASS_AVAIL and not showAvail then class = nil end
          if class == CLASS_TURNIN and not showTurnin then class = nil end
          if class and (not bestclass or class < bestclass) then
            best, bestclass = tab, class
          end
        end
        if best then
          local x, y = ParseCoords(coords)
          sink(x, y, bestclass, best)
        end
      end
    end
  end
end

-- BuildMarkers' sink for EachZoneNode: a fixed closure (zero rebuild
-- allocations) -- per-walk state travels in these upvalues, set right before
-- the walk
local walkPx, walkPy, walkPlevel, walkTarget, walkCap
local function StripSink(x, y, class, tab)
  -- the route-target marker already stands on this cell
  if walkTarget and x == walkTarget[1] and y == walkTarget[2] then return end
  local e = GetEntry()
  e.class, e.key, e.title = class, tab, tab.title
  e.x, e.y = x, y
  e.icon = tab.texture
  e.tr, e.tg, e.tb = TintFor(class, tab, walkPlevel)
  e.badge = IsEventOrDaily(tab)
  e.desc = tab.description
  e.qlvl = tab.qlvl
  local dx, dy = (x - walkPx) * 1.5, y - walkPy
  e.dist2 = dx * dx + dy * dy
  local ev = CapInsert(list, walkCap, e)
  if ev then Repool(ev) end
end

-- dungeon entrances: the meta DB's meeting stones stand at instance portals
-- (db/meta.lua "meetingstone", negative object ids). Static per zone, so the
-- object-coord scan runs once per zone change, never per rebuild.
local dungeons = { n = 0 }
local dungeonZone
local function BuildDungeonList(zone)
  if dungeonZone == zone then return end
  dungeonZone = zone
  local n = 0
  local stones = pfDB and pfDB["meta"] and pfDB["meta"]["meetingstone"]
  local objects = pfDB and pfDB["objects"] and pfDB["objects"]["data"]
  local loc = pfDB and pfDB["objects"] and pfDB["objects"]["loc"]
  if stones and objects then
    for entry in pairs(stones) do
      local id = entry < 0 and -entry or entry
      local obj = objects[id]
      if obj and obj["coords"] then
        for _, c in pairs(obj["coords"]) do
          if c[3] == zone then
            n = n + 1
            local d = dungeons[n] or {}
            dungeons[n] = d
            d.x, d.y = c[1], c[2]
            d.title = (loc and loc[id]) or L["Meeting Stone"]
          end
        end
      end
    end
  end
  dungeons.n = n
end

-- rare spawns: pfDB["meta"]["rares"] is the curated unit-id -> level list
-- (what /db track rares consults; the TBC overlay replaces it cumulatively,
-- no wotlk overlay ships one, so coverage is vanilla+TBC). Rares are NOT
-- pfMap nodes unless the user explicitly tracks them, and the units data
-- carries rank only as a stringly "rnk" field on the vanilla base with zero
-- consumers -- so the ambient toggle resolves the meta list through the
-- units DB coords ({x, y, zone, respawn} tuples) once per zone change,
-- never per rebuild (the BuildDungeonList idiom). Entries are node-shaped
-- (title/texture) so the pins extras can BindIcon them directly.
local rarelist = { n = 0 }
local rareZone
local function BuildRareList(zone)
  if rareZone == zone then return end
  rareZone = zone
  local n = 0
  local rares = pfDB and pfDB["meta"] and pfDB["meta"]["rares"]
  local units = pfDB and pfDB["units"] and pfDB["units"]["data"]
  local loc = pfDB and pfDB["units"] and pfDB["units"]["loc"]
  local tex = PATH .. "\\img\\tracking\\rares"
  if rares and units then
    for id in pairs(rares) do
      local unit = units[id]
      if unit and unit["coords"] then
        for _, c in pairs(unit["coords"]) do
          if c[3] == zone then
            n = n + 1
            local d = rarelist[n] or {}
            rarelist[n] = d
            d.x, d.y = c[1], c[2]
            d.title = (loc and loc[id]) or L["Rare"]
            d.texture = tex
          end
        end
      end
    end
  end
  rarelist.n = n
end

local function BuildMarkers(xp, yp, target, dead)
  for i = 1, list.n do
    Repool(list[i])
    list[i] = nil
  end
  list.n = 0

  local cap = tonumber(pfQuest_config["compasscap"]) or 8
  if cap < 4 then cap = 4 elseif cap > MAXCAP then cap = MAXCAP end

  local px, py = xp * 100, yp * 100
  local plevel = UnitLevel("player")

  -- corpse: ONLY while dead/ghost and only when the corpse is on this map
  -- (GetCorpseMapPosition returns 0,0 otherwise); class 1 so it can never be
  -- capped out (cap floor is 4)
  if dead then
    local cx, cy = GetCorpseMapPosition()
    if cx and cy and not (cx == 0 and cy == 0) then
      local e = GetEntry()
      e.class, e.key, e.title = CLASS_CORPSE, "corpse", L["Corpse"]
      e.x, e.y = cx * 100, cy * 100
      e.icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
      e.tr, e.tg, e.tb = 1, 1, 1
      e.badge, e.desc, e.qlvl = nil, nil, nil
      local dx, dy = (e.x - px) * 1.5, e.y - py
      e.dist2 = dx * dx + dy * dy
      local ev = CapInsert(list, cap, e)
      if ev then Repool(ev) end
    end
  end

  -- custom waypoint (waypoint.lua): the user's /way point, between the
  -- corpse and the route target; only in its own zone (a cross-zone bearing
  -- would lie). Star art in the accent tint, title = its label.
  local wp = pfQuest.waypoint and pfQuest.waypoint.Get and pfQuest.waypoint.Get()
  if wp and wp.zone ~= zoneID then wp = nil end
  if wp then
    local e = GetEntry()
    e.class, e.key, e.title = CLASS_WAYPOINT, "waypoint", wp.label or L["Waypoint"]
    e.x, e.y = wp.x, wp.y
    e.icon = PATH .. "\\img\\fav"
    e.tr, e.tg, e.tb = accent[1], accent[2], accent[3]
    e.badge, e.desc, e.qlvl = nil, nil, nil
    local dx, dy = (e.x - px) * 1.5, e.y - py
    e.dist2 = dx * dx + dy * dy
    local ev = CapInsert(list, cap, e)
    if ev then Repool(ev) end
  end

  -- route target: the same node the arrow points at (route.lua:491), kept as
  -- the guidance anchor and fallback label owner. When the route target IS
  -- the waypoint's own map node (waypoint.lua points the arrow at it), the
  -- WAYPOINT marker above already represents that cell -- skip the duplicate.
  if target and wp and target[1] == wp.x and target[2] == wp.y then target = nil end
  if target then
    local node = target[3]
    local e = GetEntry()
    e.class, e.key, e.title = CLASS_ROUTE, node, node.title
    e.x, e.y = target[1], target[2]
    e.icon = node.texture
    e.tr, e.tg, e.tb = TintFor(CLASS_ROUTE, node, plevel)
    e.badge = IsEventOrDaily(node)
    e.desc = node.description
    e.qlvl = node.qlvl
    local dx, dy = (e.x - px) * 1.5, e.y - py
    e.dist2 = dx * dx + dy * dy
    local ev = CapInsert(list, cap, e)
    if ev then Repool(ev) end
  end

  -- zone scan via the shared taxonomy walk (per-cell classification lives in
  -- EachZoneNode; the strip's ranking/pooling lives in StripSink)
  if zoneID then
    walkPx, walkPy, walkPlevel, walkTarget, walkCap = px, py, plevel, target, cap
    EachZoneNode(zoneID, StripSink)
  end

  -- dungeon entrances (default off: ambient info)
  if zoneID and pfQuest_config["compassdungeon"] == "1" then
    BuildDungeonList(zoneID)
    for i = 1, dungeons.n do
      local d = dungeons[i]
      local e = GetEntry()
      e.class, e.key, e.title = CLASS_DUNGEON, d, d.title
      e.x, e.y = d.x, d.y
      e.icon = PATH .. "\\img\\tracking\\meetingstone"
      e.tr, e.tg, e.tb = 1, 1, 1
      e.badge, e.desc, e.qlvl = nil, nil, nil
      local dx, dy = (d.x - px) * 1.5, d.y - py
      e.dist2 = dx * dx + dy * dy
      local ev = CapInsert(list, cap, e)
      if ev then Repool(ev) end
    end
  end

  -- rare spawns (default off: ambient info, lowest class -- capped out first)
  if zoneID and pfQuest_config["compassrares"] == "1" then
    BuildRareList(zoneID)
    for i = 1, rarelist.n do
      local d = rarelist[i]
      local e = GetEntry()
      e.class, e.key, e.title = CLASS_RARE, d, d.title
      e.x, e.y = d.x, d.y
      e.icon = d.texture
      e.tr, e.tg, e.tb = 1, 1, 1
      e.badge, e.desc, e.qlvl = nil, nil, nil
      local dx, dy = (d.x - px) * 1.5, d.y - py
      e.dist2 = dx * dx + dy * dy
      local ev = CapInsert(list, cap, e)
      if ev then Repool(ev) end
    end
  end

  -- widget bindings go stale on every rebuild
  list.rebind = true
end

-- ---------------------------------------------------------------------------
-- update loop
-- ---------------------------------------------------------------------------

local halfWidth = 210
local lastXP, lastYP, lastFacing
local lastDegree, lastYards, lastTitle
local lastTarget, lastDead, lastQueue
local nextRebuild = 0
local labelState = {}
local lastOwnerKey
local labelFade = 0 -- crossfade start; one label object, so the incoming side fades
local FADE_TIME = 0.2
local titleHalf, distHalf = 0, 0
local lastDesc

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
  local scaleCfg = pfQuest_config["compassscale"]
  if widthCfg ~= this.lastWidthCfg or scaleCfg ~= this.lastScaleCfg then
    this.lastWidthCfg, this.lastScaleCfg = widthCfg, scaleCfg
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

  -- GetMapIDByName is a linear scan over every zone name in the DB -- memoize
  -- by the raw zone-text string, same as the minimap loop (map.lua:1322)
  local rebuild
  local rz = GetRealZoneText()
  if rz ~= zoneName then
    zoneName = rz
    zoneID = pfMap and pfMap.GetMapIDByName and pfMap:GetMapIDByName(rz) or nil
    rebuild = true
  end

  -- rebuild triggers: the marker SET changes on node writes (pfMap.queue_update
  -- bumps on AddNode/DeleteNode), route-target identity change, death-state
  -- flips and zone change; a 1s heartbeat backstops anything missed. The
  -- steady cost is a handful of compares plus one UnitIsDeadOrGhost C call.
  local coords = pfQuest.route.coords
  local target = coords and coords[1] and coords[1][4] and coords[1] or nil
  local dead = UnitIsDeadOrGhost("player") and true or false
  if target ~= lastTarget or dead ~= lastDead then rebuild = true end
  if pfMap and pfMap.queue_update ~= lastQueue then rebuild = true end
  if now > nextRebuild then rebuild = true end
  if rebuild then
    lastTarget, lastDead = target, dead
    lastQueue = pfMap and pfMap.queue_update
    nextRebuild = now + 1
    BuildMarkers(xp, yp, target, dead)
    lastFacing = nil -- marker set may have changed: force a repaint
  end

  -- dirty-skip: everything below is a pure function of position, facing and
  -- the marker set -- standing still costs nothing beyond these compares.
  -- A running label crossfade keeps painting until it completes, else the
  -- fade would freeze mid-transition the moment the player stands still.
  if facing == lastFacing and xp == lastXP and yp == lastYP and now >= labelFade + FADE_TIME then
    return
  end
  lastXP, lastYP, lastFacing = xp, yp, facing

  -- scroll cardinals/ticks through the FOV; outside-FOV widgets hide (only
  -- markers clamp to the edge -- letters pinned there would just stack).
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

  -- markers: hide everything when GetPlayerMapPosition reports 0,0 (indoors/
  -- instance -- position unknown, every bearing would lie); cardinals stay up
  -- because facing is still valid there
  local owner
  if xp == 0 and yp == 0 then
    for i = 1, MAXCAP do
      markers[i]:Hide()
    end
  else
    local rebind = list.rebind
    list.rebind = nil
    for i = 1, list.n do
      local e = list[i]
      e.rel = BearingTo(xp, yp, e.x, e.y, facing)
      e.off, e.clamped = ProjectOffset(e.rel, halfWidth)
    end
    MergeOverlaps(list, MERGE_PX)
    for i = 1, list.n do
      local e = list[i]
      local m = markers[i]
      local off, clamped = e.off, e.clamped
      if e.merged then
        m:Hide()
      else

      -- rebind the widget only when the marker set changed under it
      if rebind or m.key ~= e.key then
        m.key = e.key
        if e.icon then
          m.icon:SetTexture(e.icon)
          m.icon:SetVertexColor(e.tr, e.tg, e.tb, 1)
        else
          -- unclassified art: pfQuest's colored dot, tinted by title like the
          -- arrow's fallback (route.lua:622)
          m.icon:SetTexture(ICON_FALLBACK)
          local r, g, b = pfMap.str2rgb(e.title)
          m.icon:SetVertexColor(r or 1, g or 1, b or 1, 1)
        end
        if e.badge then m.badge:Show() else m.badge:Hide() end
      end

      m:SetPoint("CENTER", compass, "CENTER", off, 0)
      -- beyond the FOV the marker pins to the edge at 40% alpha: still shows
      -- which way to turn without pretending to be on-screen. On-screen near
      -- the edge it fades 1 -> 0.4 over the same band the cardinals fade in,
      -- meeting the clamped value exactly -- no alpha pop at the boundary (the
      -- 0.4 floor keeps markers visible, never faded to nothing)
      local a = 1
      if clamped then
        a = 0.4
      else
        local absOff = off < 0 and -off or off
        if absOff > fadeStart then
          a = 1 - 0.6 * (absOff - fadeStart) / fadeSpan
        end
      end
      e.a = a
      m:SetAlpha(a)
      m:Show()
      end
    end
    for i = list.n + 1, MAXCAP do
      markers[i]:Hide()
    end

    -- view-driven label owner (needs every slot's rel from the loop above)
    owner = SelectLabel(list, labelState, now)

    -- the owning marker's plate grows to ~115% as the selection cue. Sizing
    -- the frame (fill/edge follow via SetAllPoints) instead of SetScale keeps
    -- the anchor offset in parent space -- SetScale would shift the rendered
    -- position by the scale factor.
    for i = 1, list.n do
      local m = markers[i]
      local size = (owner == list[i]) and 23 or 20
      if m.plateSize ~= size then
        m.plateSize = size
        m:SetWidth(size)
        m:SetHeight(size)
      end
    end
  end

  if owner and owner.key ~= lastOwnerKey then
    lastOwnerKey = owner.key
    labelFade = now -- restart the crossfade for the incoming owner
    lastTitle, lastYards = nil, nil -- force text repaint for the new owner
  elseif not owner then
    lastOwnerKey = nil
  end

  if not owner then
    dist:Hide()
    title:Hide()
    descText:Hide()
    lastYards, lastTitle, lastDesc = nil, nil, nil -- stale caches must not suppress the first repaint
  else
    if owner.title ~= lastTitle then
      lastTitle = owner.title
      title:SetText(lastTitle or "")
      titleHalf = (title:GetStringWidth() or 0) / 2
    end

    -- clamp the label inside the strip: a long title on an edge-clamped
    -- marker ran past the screen edge (maintainer screenshot); pin the text
    -- center so its half-width stays inside the strip bounds, dead-center
    -- when the title is wider than the strip itself
    local half = titleHalf > distHalf and titleHalf or distHalf
    local lo = owner.off
    if half >= halfWidth then
      lo = 0
    else
      if lo > halfWidth - half then lo = halfWidth - half end
      if lo < -halfWidth + half then lo = -halfWidth + half end
    end
    dist:SetPoint("BOTTOM", compass, "CENTER", lo, 14)

    local fadeMul = (now - labelFade) / FADE_TIME
    if fadeMul > 1 then fadeMul = 1 elseif fadeMul < 0 then fadeMul = 0 end
    dist:SetAlpha(owner.a * fadeMul)
    title:SetAlpha(owner.a * fadeMul)
    title:Show()

    -- objective description line, re-formatted only when the owner's text
    -- changes; the corpse and dungeon markers carry none and show none.
    -- Suppressed while the owner is edge-clamped: the player is not facing it,
    -- so "what to do there" is noise until they turn (maintainer direction);
    -- the clamped marker's own title/distance still show the way
    if pfQuest_config["compassdesc"] ~= "0" and owner.desc and owner.desc ~= "" and not owner.clamped then
      if owner.desc ~= lastDesc then
        lastDesc = owner.desc
        descText:SetText(owner.desc)
      end
      descText:SetAlpha(fadeMul)
      descText:Show()
    else
      descText:Hide()
      lastDesc = nil
    end

    local yards = YardsTo(xp, yp, owner.x, owner.y, zoneID)
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
        distHalf = (dist:GetStringWidth() or 0) / 2
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
compass.ClassifyNode = ClassifyNode
compass.CapInsert = CapInsert
compass.SelectLabel = SelectLabel
compass.MergeOverlaps = MergeOverlaps
compass.BuildMarkers = BuildMarkers
compass.EachZoneNode = EachZoneNode
compass.list = list
compass.markers = markers
compass.CLASS = {
  CORPSE = CLASS_CORPSE, WAYPOINT = CLASS_WAYPOINT, ROUTE = CLASS_ROUTE,
  TURNIN = CLASS_TURNIN, ACTIVE = CLASS_ACTIVE, AVAIL = CLASS_AVAIL,
  DUNGEON = CLASS_DUNGEON, RARE = CLASS_RARE, PARTY = CLASS_PARTY,
}

-- per-zone rare provider for the pins extras (the strip consumes rarelist
-- directly above): enumerate the cached zone rares as sink(x, y, class, tab).
-- Selection policy stays per-consumer, the EachZoneNode doctrine.
function compass.EachZoneRare(zid, sink)
  if not zid then return end
  BuildRareList(zid)
  for i = 1, rarelist.n do
    local d = rarelist[i]
    sink(d.x, d.y, CLASS_RARE, d)
  end
end

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
  -- description box rides the strip width so long lines clip with it
  descText:SetWidth(w)
  -- Reforged: overall scale, 0.5..2 -- the trackerscale pattern (tracker.lua:752)
  local s = tonumber(pfQuest_config and pfQuest_config["compassscale"]) or 1
  if s < 0.5 then s = 0.5 elseif s > 2 then s = 2 end
  if self:GetScale() ~= s then self:SetScale(s) end
  lastFacing = nil -- geometry changed: force a full reposition on the next tick
end

compass:UpdateSettings()
