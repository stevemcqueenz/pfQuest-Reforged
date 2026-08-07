-- Frame-shaped 3.3.5a stub: enough of the widget API that our real UI files can be
-- loaded and DRIVEN, not just parsed. Textures and fontstrings track their own size so
-- layout arithmetic is genuinely exercised.
--
-- Deliberately not a full client. It fakes shape, not behaviour -- see tools/README.md
-- on the tradeoff. Anything a test asserts on must be modelled here honestly.

local M = {}
local noop = function() end

-- CRITICAL: this stub must NOT hand back a function for every unknown key.
-- A catch-all __index that returns noop makes `if not frame.someField` always false
-- (a function is truthy), silently inverting the addon's own logic -- and, worse, it
-- makes a call to a method that does not exist SUCCEED. That is precisely the v1.0.30
-- bug (bar:Show(), nil), so a catch-all would mask the one class of failure this
-- harness exists to catch. Unknown keys therefore stay nil, exactly as on a real
-- frame: reading a field gives nil, and calling a method that is not there errors.
-- Widening the stub means adding a name to the lists below, on purpose.
local FRAME_NOOPS = [[SetMovable
EnableMouse EnableMouseWheel SetClampedToScreen SetFrameStrata
SetBackdrop SetBackdropColor SetBackdropBorderColor StartMoving StopMovingOrSizing
SetUserPlaced RegisterForClicks RegisterForDrag SetID GetID SetToplevel Raise Lower
SetHitRectInsets SetResizable SetMinResize SetMaxResize UnregisterAllEvents SetOwner
AddLine AddDoubleLine ClearLines SetText SetNormalTexture SetHighlightTexture
SetPushedTexture SetDisabledTexture GetNormalTexture GetHighlightTexture SetChecked
GetChecked SetValue GetValue SetMinMaxValues SetStatusBarTexture SetStatusBarColor
SetJustifyH SetJustifyV SetFont SetTextColor SetShadowOffset SetShadowColor SetSpacing
SetNonSpaceWrap SetWordWrap SetIndentedWordWrap SetMultiLine SetAutoFocus SetMaxLetters
ClearFocus SetFocus HighlightText SetCursorPosition SetPropagateKeyboardInput
SetParent GetObjectType IsObjectType SetSize GetEffectiveScale SetDrawLayer
SetVertexColor GetVertexColor SetTexCoord SetBlendMode SetDesaturated SetGradientAlpha]]

local function methodTable(names, extra)
  local t = {}
  for w in string.gmatch(names, "%S+") do t[w] = noop end
  if extra then for k, v in pairs(extra) do t[k] = v end end
  return t
end

-- Two-point anchoring is modelled, not stubbed away: a region anchored LEFT and RIGHT
-- derives its width from its parent. That is the whole mechanism behind the v1.0.30
-- fill bug (the bar read its width before the tracker had one), so a no-op SetPoint
-- would make the harness unable to tell a working bar from a broken one.
local function applySize(o)
  o.points = {}
  -- frame level modelled, not noop'd: compass.lua does arithmetic on
  -- GetFrameLevel() (plate layering above cardinal fontstrings) and a nil
  -- return would mask exactly that class of bug in-game
  o.frameLevel = 1
  function o.SetFrameLevel(s, lvl) s.frameLevel = tonumber(lvl) or 1 end
  function o.GetFrameLevel(s) return s.frameLevel end
  function o.SetPoint(s, point, rel, relPoint, x, y)
    if type(point) ~= "string" then return end
    s.points[point] = { rel = rel, x = tonumber(x) or 0, y = tonumber(y) or 0 }
    if rel and type(rel) == "table" then s.anchorTo = rel end
  end
  -- alpha modelled, not noop'd: the pins opacity setting is asserted on
  -- GetAlpha, and a nil return would mask a SetAlpha that never ran
  o.alpha = 1
  function o.SetAlpha(s, a) s.alpha = a end
  function o.GetAlpha(s) return s.alpha or 1 end
  function o.ClearAllPoints(s) s.points = {} end
  function o.SetAllPoints(s, rel) s.anchorTo = rel; s.fullWidth = true end
  -- 3.3.5a fact: a region whose size derives from two-point anchors does NOT
  -- resolve while its frame hierarchy is hidden -- GetWidth() lies (0/stale)
  -- until the frame is actually shown. That is the mechanism behind the
  -- enable-mid-session sliver bug (bars refreshed while the tracker was
  -- hidden), so the stub models it instead of resolving anchors regardless.
  local function effectivelyShown(o)
    while o do
      if o.shown == false then return false end
      o = o.parent
    end
    return true
  end
  local function anchoredWidth(s)
    local p = s.points
    local left = p.LEFT or p.TOPLEFT or p.BOTTOMLEFT
    local right = p.RIGHT or p.TOPRIGHT or p.BOTTOMRIGHT
    if not (left and right) then return nil end
    if not effectivelyShown(s) then return nil end
    local host = s.anchorTo
    local hw = host and host.GetWidth and host:GetWidth() or 0
    if hw <= 0 then return nil end
    return hw - left.x + right.x
  end
  function o.SetWidth(s, v) s.explicitW = v; s.w = v end
  function o.GetWidth(s)
    if s.fullWidth and s.anchorTo and s.anchorTo.GetWidth then return s.anchorTo:GetWidth() end
    local a = anchoredWidth(s)
    if a then return a end
    return s.explicitW or s.w or 0
  end
  function o.SetHeight(s, v) s.h = v end
  function o.GetHeight(s) return s.h or 0 end
  function o.Show(s) s.shown = true end
  function o.Hide(s) s.shown = false end
  function o.IsShown(s) return s.shown and true or false end
  function o.IsVisible(s) return s.shown and true or false end
end

local function mkFontString(parent)
  -- parent kept: effective visibility (and thus anchor resolution) walks it
  local fs = { w = 0, h = 12, shown = true, text = "", parent = parent }
  applySize(fs)
  function fs.SetText(s, t) s.text = t or ""
    -- width proportional to text length: the tracker sizes itself from this
    s.w = string.len(tostring(s.text)) * 6 end
  function fs.GetText(s) return s.text end
  function fs.GetStringWidth(s) return s.w end
  return setmetatable(fs, { __index = methodTable(FRAME_NOOPS) })
end

local function mkTexture(parent)
  local t = { w = 0, h = 0, shown = true, parent = parent }
  applySize(t)
  function t.SetTexture(s, ...) s.tex = ... end
  function t.GetTexture(s) return s.tex end
  -- vertex color / gradient / blend modelled, not noop'd: the pins polish
  -- checks assert the pylon color override actually re-tints widgets, the
  -- beam gradient endpoints, and the ADD blend on glows/beams/chevrons.
  -- Widened deliberately (the no-catch-all rule above still holds).
  function t.SetVertexColor(s, r, g, b, a) s.vr, s.vg, s.vb, s.va = r, g, b, a end
  function t.GetVertexColor(s) return s.vr or 1, s.vg or 1, s.vb or 1, s.va or 1 end
  function t.SetGradientAlpha(s, o, r1, g1, b1, a1, r2, g2, b2, a2)
    s.grad = { o, r1, g1, b1, a1, r2, g2, b2, a2 }
  end
  function t.SetBlendMode(s, m) s.blend = m end
  return setmetatable(t, { __index = methodTable(FRAME_NOOPS) })
end

function M.CreateFrame(ftype, name, parent, template)
  local f = { w = 0, h = 0, shown = true, scale = 1, ftype = ftype, name = name,
              parent = parent, scripts = {}, events = {}, children = {} }
  applySize(f)
  function f.SetScript(s, k, fn) s.scripts[k] = fn end
  function f.GetScript(s, k) return s.scripts[k] end
  function f.HookScript(s, k, fn) local o = s.scripts[k]
    s.scripts[k] = function(...) if o then o(...) end return fn(...) end end
  function f.RegisterEvent(s, e) s.events[e] = true end
  function f.UnregisterEvent(s, e) s.events[e] = nil end
  function f.IsEventRegistered(s, e) return s.events[e] or false end
  function f.SetScale(s, v) s.scale = v end
  function f.GetScale(s) return s.scale or 1 end
  function f.CreateFontString(s, ...) local fs = mkFontString(s)
    s.children[#s.children + 1] = fs; return fs end
  function f.CreateTexture(s, ...) local t = mkTexture(s)
    s.children[#s.children + 1] = t; return t end
  function f.GetName(s) return s.name end
  function f.GetParent(s) return s.parent end
  function f.Fire(s, script, ...) local fn = s.scripts[script]
    if fn then return fn(s, ...) end end
  if name then _G[name] = f end
  return setmetatable(f, { __index = methodTable(FRAME_NOOPS) })
end

function M.install()
  _G.CreateFrame = M.CreateFrame
  _G.UIParent = M.CreateFrame("Frame", "UIParent")
  _G.WorldFrame = M.CreateFrame("Frame", "WorldFrame")
  _G.GameTooltip = M.CreateFrame("GameTooltip", "GameTooltip")
  _G.GetLocale = function() return "enUS" end
  _G.IsAddOnLoaded = function() return nil end
  _G.GetTime = function() return 1000 end
  _G.UnitLevel = function() return 71 end
  _G.UnitName = function() return "Tester" end
  _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  _G.NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
  _G.GetQuestGreenRange = function() return 7 end
  -- WoW exposes the string/table library as globals; addon code uses them bare.
  _G.gsub, _G.strfind, _G.strsub, _G.strlen = string.gsub, string.find, string.sub, string.len
  _G.strupper, _G.strlower, _G.strrep = string.upper, string.lower, string.rep
  _G.format, _G.strmatch, _G.gmatch = string.format, string.match, string.gmatch
  _G.tinsert, _G.tremove, _G.sort, _G.getn = table.insert, table.remove, table.sort, table.getn
  _G.abs, _G.ceil, _G.floor, _G.min, _G.max, _G.sqrt =
    math.abs, math.ceil, math.floor, math.min, math.max, math.sqrt
  _G.mod = math.fmod
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  _G.strsplit = function(d, str)
    local out = {} for tok in string.gmatch(str, "([^" .. d .. "]+)") do out[#out+1] = tok end
    return unpack(out)
  end
  return M
end

return M
