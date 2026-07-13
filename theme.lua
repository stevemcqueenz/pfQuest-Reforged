-- pfQuest Reforged -- shared visual system
-- One place for the flat dark look: panel chrome, fonts, accent colors and the
-- progress-bar factory used by the tracker. Pure presentation helpers -- no
-- game logic, no saved variables beyond reading pfQuest_config font size.
-- 3.3.5a-safe API surface only: SetBackdrop, CreateTexture, SetTexture(r,g,b,a).

pfQuestTheme = {
  -- pfQuest's signature teal, used as the single accent
  accent  = { 0.2, 1.0, 0.8 },
  -- panel body / border (flat dark, GW2-style)
  bg      = { 0.07, 0.07, 0.09 },
  border  = { 0, 0, 0 },
  -- progress ramp (red -> yellow -> green handled by callers via GetColor)
  dim     = { 0.55, 0.55, 0.55 },
}

local T = pfQuestTheme

-- When GW2 UI (WotLK Reforged) is installed, adopt its look instead of the
-- standalone teal: GW2's warm parchment-gold accent and its darker, more
-- opaque panel body, so every pfQuest window (tracker, browser, journal,
-- config, welcome) reads as part of the GW2 UI rather than a foreign teal
-- box. Standalone (no GW2) keeps the teal identity. Detection is a plain
-- addon-loaded check -- no dependency, no coupling to GW2 internals.
if IsAddOnLoaded and (IsAddOnLoaded("GW2_UI") or IsAddOnLoaded("GW2-UI")) then
  T.accent   = { 1.0, 0.93, 0.73 } -- GW2 parchment gold
  T.bg       = { 0.04, 0.04, 0.045 }
  T.gw2       = true
  T.panelAlpha = 0.92             -- GW2 panels are near-opaque
end
T.panelAlpha = T.panelAlpha or 0.85

-- 1px flat border + dark body. `alpha` is the BODY alpha (border stays solid).
function T.SkinPanel(frame, alpha)
  frame:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(T.bg[1], T.bg[2], T.bg[3], alpha or T.panelAlpha)
  frame:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.9)
end

-- Accent-tinted header strip texture for a panel's top bar.
function T.HeaderStrip(frame, height)
  local strip = frame:CreateTexture(nil, "BORDER")
  strip:SetTexture(T.bg[1] * 1.6, T.bg[2] * 1.6, T.bg[3] * 1.6, 0.9)
  strip:SetPoint("TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", -1, -1)
  strip:SetHeight(height - 2)
  local line = frame:CreateTexture(nil, "BORDER")
  line:SetTexture(T.accent[1], T.accent[2], T.accent[3], 0.35)
  line:SetPoint("TOPLEFT", 1, -(height - 1))
  line:SetPoint("TOPRIGHT", -1, -(height - 1))
  line:SetHeight(1)
  return strip
end

-- Thin progress bar: dark track + colored fill. The caller drives it with
-- bar.SetProgress(pct01, r, g, b); width follows the parent automatically.
function T.CreateProgressBar(parent, height)
  local bar = { height = height or 3 }

  bar.track = parent:CreateTexture(nil, "BORDER")
  bar.track:SetTexture(1, 1, 1, 0.10)
  bar.track:SetHeight(bar.height)

  bar.fill = parent:CreateTexture(nil, "ARTWORK")
  bar.fill:SetTexture(T.accent[1], T.accent[2], T.accent[3], 0.9)
  bar.fill:SetHeight(bar.height)
  bar.fill:SetPoint("LEFT", bar.track, "LEFT", 0, 0)
  bar.fill:SetWidth(0.01)

  function bar.SetPoint(_, a, b, c, d, e)
    bar.track:SetPoint(a, b, c, d, e)
  end

  function bar.SetProgress(_, pct, r, g, b)
    if pct == nil then
      bar.track:Hide()
      bar.fill:Hide()
      return
    end
    bar.track:Show()
    pct = pct < 0 and 0 or pct > 1 and 1 or pct
    local width = bar.track:GetWidth()
    if not width or width <= 0 then width = 1 end
    if pct <= 0.001 then
      bar.fill:Hide()
    else
      bar.fill:Show()
      bar.fill:SetWidth(width * pct)
    end
    if r then
      bar.fill:SetTexture(r, g, b, 0.9)
    end
  end

  function bar.Hide(_)
    bar.track:Hide()
    bar.fill:Hide()
  end

  return bar
end

-- Uniform hover behavior for icon buttons: dim by default, accent on hover.
function T.HoverIcon(button)
  if not button.icon then return end
  button.icon:SetVertexColor(0.75, 0.75, 0.75)
  local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
  button:SetScript("OnEnter", function()
    this.icon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3])
    if enter then enter() end
  end)
  button:SetScript("OnLeave", function()
    if not this.gwActive then
      this.icon:SetVertexColor(0.75, 0.75, 0.75)
    end
    if leave then leave() end
  end)
end
