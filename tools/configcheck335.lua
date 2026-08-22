-- Settings-window check: load the REAL config.lua and BUILD the window.
--
-- Why this exists: the settings window was rebuilt in pfUI's idiom (flat nav,
-- one scroll frame per section, lazy layout, a search box). None of that is
-- reachable by a parse check, and a UI that fails to build is invisible until
-- someone opens it in-game -- which is how the ScrollBox-shaped bugs in this
-- project have always presented. The frame stub deliberately has NO catch-all
-- __index, so calling a widget method that does not exist errors here rather
-- than at the player.
--
-- Usage: lua5.1 tools/configcheck335.lua   (from the addon root)

local failures, checks = 0, 0
local function fail(f, ...) failures = failures + 1; print("  FAIL  " .. string.format(f, ...)) end
local function ok(f, ...) checks = checks + 1; print("  ok    " .. string.format(f, ...)) end
local function check(cond, f, ...) if cond then ok(f, ...) else fail(f, ...) end end

dofile("tools/framestub335.lua").install()

-- ---------------------------------------------------------------------------
-- the seams config.lua loads against
-- ---------------------------------------------------------------------------
_G.pfUI = { font_default = "Fonts\\FRIZQT__.TTF", api = {} }
-- a LARGER font than the default: the overlap bug only appears above the size
-- the layout was originally tuned for, so testing at 12 tested nothing
_G.pfUI_config = { global = { font_size = 16 } }
-- the standalone case: compat/pfUI.lua sets this when no real pfUI is present,
-- which is what most users run. The emulated backdrop is why inputs are scaled.
_G.pfUI.api.emulated = true
_G.pfUI.api.CreateBackdrop = function(f) if f then f.backdrop = true end end
_G.pfUI.api.SkinButton = function(f) if f then f.skinned = true end end
_G.pfUI.api.CreateScrollFrame = function(_, parent)
  local f = CreateFrame("ScrollFrame", nil, parent)
  f.isScrollFrame = true
  return f
end
_G.pfUI.api.CreateScrollChild = function(_, parent)
  local f = CreateFrame("Frame", nil, parent)
  f.isScrollChild = true
  parent.child = f
  return f
end

_G.pfQuestTheme = {
  accent = { 0.2, 1, 0.8 },
  SkinPanel = function() end,
  HeaderStrip = function(frame) return frame:CreateTexture() end,
}
_G.pfQuest_Loc = setmetatable({}, { __index = function(t, k) rawset(t, k, k) return k end })
_G.L = _G.pfQuest_Loc
_G.pfQuest_config = {}
_G.pfQuest = { ResetAll = function() end }
_G.pfMap = { ResizeNodes = function() end }
_G.pfDatabase = { GetIDByName = function() return {} end }
_G.UISpecialFrames = {}
_G.StaticPopupDialogs = {}
_G.GameFontNormal, _G.GameFontWhite = "GameFontNormal", "GameFontWhite"
_G.YES, _G.NO = "Yes", "No"
_G.GetAddOnInfo = function(n) return n, "pfQuest-Reforged" end
_G.GetAddOnMetadata = function() return "1.x-test" end
_G.debugstack = function() return "Interface\\AddOns\\pfQuest-Reforged\\config.lua:1" end
_G.ReloadUI = function() end
_G.OpenColorPicker = function() end
_G.ColorPickerFrame = { GetColorRGB = function() return 1, 1, 1 end }
_G.UnitXP = function() return 100 end
_G.UnitLevel = function() return 10 end
_G.GetLocale = function() return "enUS" end
_G.strlower = string.lower
_G.strfind = string.find
_G.strsub = string.sub
_G.strupper = string.upper
_G.strlen = string.len
_G.format = string.format
_G.getn = table.getn
_G.max, _G.min, _G.floor = math.max, math.min, math.floor

local okload, err = pcall(dofile, "config.lua")
if not okload then
  fail("config.lua did not load -> %s", tostring(err))
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
ok("config.lua loads under the 3.3.5a stub")

-- ---------------------------------------------------------------------------
-- build the window from a synthetic config carrying every widget type
-- ---------------------------------------------------------------------------
local cfg = {
  { text = "General", type = "header" },
  { text = "Harness Toggle", default = "1", type = "checkbox", config = "thing" },
  { text = "Harness Size", desc = "Percent, 100 is the default", tip = "A longer explanation of what this setting is actually for.", default = "100", type = "text", config = "thingsize" },
  { text = "Harness Wrap", desc = "A deliberately long hint line that has to wrap onto a second row because it does not fit beside the value box on the right", default = "1", type = "text", config = "thingwrap" },
  { text = "Harness Row With A Very Long Label Indeed", default = "1", type = "text", config = "thinglong" },
  { text = "Harness Group", type = "group" },
  { text = "Harness Beam Width", desc = "Percent", default = "100", type = "text", config = "thingbeam" },
  { text = "Second Section", type = "header" },
  { text = "Harness Color", default = "", type = "color", config = "thingcolor" },
  { text = "Harness Scale", default = "1", type = "slider", config = "thingscale",
    min = 0.5, max = 2, step = 0.1, format = "%.1fx" },
  { text = "Harness Button", type = "button", config = "thingbutton", func = function() end },
}
for i = 1, table.getn(cfg) do
  if cfg[i].config then pfQuest_config[cfg[i].config] = cfg[i].default end
end

local okbuild, berr = pcall(function() pfQuestConfig:CreateConfigEntries(cfg) end)
check(okbuild, "CreateConfigEntries builds the window%s", okbuild and "" or (" -> " .. tostring(berr)))
if not okbuild then
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end

-- ---------------------------------------------------------------------------
-- structure: a header opens a section, its rows land in that section's SCROLL
-- CHILD (not on the window), which is what makes a long section scroll instead
-- of forcing the window taller
-- ---------------------------------------------------------------------------
check(pfQuestConfig.activesection == 1, "the first section is selected on build")
check(pfQuestConfig.search ~= nil, "the search box exists")
check(pfQuestConfig.sectiontitle ~= nil and pfQuestConfig.separator ~= nil,
      "section title and sidebar rule exist")

-- every row's parent chain must reach a scroll child
local function parentIsScrollChild(frame)
  local p = frame and frame:GetParent()
  return p and p.isScrollChild == true
end

-- the sections table is a local, so reach the rows the way UpdateConfigEntries
-- does: through the frames the builder registered by caption
local built = 0
for _, name in ipairs({ "Harness Toggle", "Harness Size", "Harness Color", "Harness Scale", "Harness Button" }) do
  local f = pfQuestConfig:GetRow(name)
  if f then
    built = built + 1
    if not parentIsScrollChild(f) then
      fail("row %q is not parented to a scroll child", name)
    end
  end
end
check(built == 5, "all five widget types built a row (got %d)", built)

-- widgets carry the input they need
local function input(name)
  local f = pfQuestConfig:GetRow(name)
  return f and f.input
end
check(input("Harness Toggle") ~= nil, "checkbox row has an input")
-- the checked state must be the flat accent square, not Blizzard's yellow
-- tick: that tick was the one piece of 2006 art left on an otherwise flat row
do
  local box = input("Harness Toggle")
  local tick = box and box.GetCheckedTexture and box:GetCheckedTexture()
  -- NOT "tick and tick:GetVertexColor()": an `and` expression truncates a
  -- multi-value return to its first value, so g and b would read nil
  local r, g, b
  if tick then r, g, b = tick:GetVertexColor() end
  check(tick ~= nil and r == 0.2 and g == 1 and b == 0.8,
        "checkbox tick is tinted with the theme accent (got %s,%s,%s)",
        tostring(r), tostring(g), tostring(b))
end
check(input("Harness Size") ~= nil, "text row has an input")
check(input("Harness Color") ~= nil, "color row has a swatch button")
check(input("Harness Scale") ~= nil, "slider row has a slider")
check(input("Harness Button") ~= nil, "button row has a button")

-- the description line is what makes a row tall; the layout must reserve it
local sizerow = pfQuestConfig:GetRow("Harness Size")
local plainrow = pfQuestConfig:GetRow("Harness Toggle")
check(sizerow and plainrow and sizerow:GetHeight() > plainrow:GetHeight(),
      "a row with a hint line is taller than one without")

-- ---------------------------------------------------------------------------
-- ROWS MUST NOT OVERLAP.
--
-- The first build hardcoded 22/13 px and looked fine here while the rows ran
-- into each other on the maintainer's client, because pfUI's font size is a
-- user setting and the harness happened to use the size it was tuned for.
-- Two invariants, both independent of the font: a row's hint line has to fit
-- INSIDE the row that owns it, and each row has to start exactly where the
-- previous one ended.
-- ---------------------------------------------------------------------------
do
  local fs = pfUI_config.global.font_size
  local descrow = pfQuestConfig:GetRow("Harness Size")
  local descy = descrow and descrow.desc and descrow.desc.points
                and descrow.desc.points.TOPLEFT and descrow.desc.points.TOPLEFT.y
  check(descy ~= nil, "the hint line is anchored")
  if descy then
    -- the hint starts below the caption's own line, never on top of it
    check(-descy >= fs + 2,
          "the hint clears the caption line (offset %s, font %s)", tostring(-descy), tostring(fs))
    -- ...and ends inside the row, so it cannot bleed into the next one
    check(-descy + fs <= descrow:GetHeight(),
          "the hint fits inside its own row (needs %s, row is %s)",
          tostring(-descy + fs), tostring(descrow:GetHeight()))
  end

  -- consecutive rows stack exactly: gap == the previous row's height
  local order = { "Harness Toggle", "Harness Size" }
  local prev, prevy
  local stacked = true
  for _, name in ipairs(order) do
    local r = pfQuestConfig:GetRow(name)
    local y = r and r.points and r.points.TOPLEFT and r.points.TOPLEFT.y
    if prev and y and prevy then
      if math.abs((prevy - y) - prev:GetHeight()) > 0.5 then
        stacked = false
        fail("row %q starts %s below the previous row, which is %s tall",
             name, tostring(prevy - y), tostring(prev:GetHeight()))
      end
    end
    prev, prevy = r, y
  end
  if stacked then ok("rows stack with no overlap and no gap") end
end

-- a hint too long for the space beside its control WRAPS, and the row has to
-- grow to hold the wrap or the next row lands on top of it -- the overlap the
-- maintainer hit twice, in its remaining form
do
  local wraprow = pfQuestConfig:GetRow("Harness Wrap")
  local shortrow = pfQuestConfig:GetRow("Harness Size")
  check(wraprow and shortrow and wraprow:GetHeight() > shortrow:GetHeight(),
        "a wrapping hint makes its row taller (wrap %s, short %s)",
        tostring(wraprow and wraprow:GetHeight()), tostring(shortrow and shortrow:GetHeight()))
  -- and the text never reaches into the control gutter on the right
  if wraprow and wraprow.desc then
    check(wraprow.desc:GetWidth() > 0 and wraprow.desc:GetWidth() < wraprow:GetWidth(),
          "the hint is narrower than the row, leaving the control gutter clear (%s of %s)",
          tostring(wraprow.desc:GetWidth()), tostring(wraprow:GetWidth()))
  end
  local longrow = pfQuestConfig:GetRow("Harness Row With A Very Long Label Indeed")
  check(shortrow and longrow
        and shortrow.caption:GetWidth() == longrow.caption:GetWidth()
        and longrow.caption:GetWidth() < longrow:GetWidth(),
        "labels are constrained to the text column, short and long alike (%s vs %s, row %s)",
        tostring(shortrow and shortrow.caption:GetWidth()),
        tostring(longrow and longrow.caption:GetWidth()),
        tostring(longrow and longrow:GetWidth()))
end

-- tooltip: rows that carry one show it, rows that do not stay silent
do
  local shown = nil
  _G.GameTooltip = {
    SetOwner = function() end,
    SetText = function(_, t) shown = t end,
    AddLine = function() end,
    Show = function() end,
    Hide = function() shown = nil end,
  }
  local tiprow = pfQuestConfig:GetRow("Harness Size")
  local plainrow2 = pfQuestConfig:GetRow("Harness Toggle")
  _G.this = tiprow
  tiprow:Fire("OnEnter")
  check(shown == "Harness Size", "a row with a tooltip opens it on hover (got %s)", tostring(shown))
  tiprow:Fire("OnLeave")
  check(shown == nil, "the tooltip closes on leave")
  _G.this = plainrow2
  plainrow2:Fire("OnEnter")
  check(shown == nil, "a row without a tooltip opens nothing")
  plainrow2:Fire("OnLeave")
  _G.this = nil
end

-- the search box must get the SAME skinning as the value boxes in the pane.
-- It is built outside the row loop, so it silently missed the emulated-backdrop
-- scaling and wore a visibly heavier border than everything around it.
do
  local rowinput = input("Harness Size")
  check(pfQuestConfig.search.backdrop == true, "the search box has the panel backdrop")
  check(pfQuestConfig.search:GetScale() == rowinput:GetScale(),
        "the search box is scaled like the row inputs (search %s, row %s)",
        tostring(pfQuestConfig.search:GetScale()), tostring(rowinput:GetScale()))
  -- and it still occupies the sidebar it is anchored in: scaled widgets report
  -- their UNSCALED width, so the visual width is width * scale
  local visual = pfQuestConfig.search:GetWidth() * pfQuestConfig.search:GetScale()
  local tabwidth = _G.pfQuestConfigTab1:GetWidth()
  check(visual > 0 and math.abs(visual - (tabwidth + 12 - 14)) < 2,
        "the search box spans the sidebar (visual %s, sidebar %s)",
        tostring(visual), tostring(tabwidth + 12 - 14))
end

-- ---------------------------------------------------------------------------
-- search: filters across sections, and an empty result says so
-- ---------------------------------------------------------------------------
local oksearch = pcall(function() pfQuestConfig:ApplySearch("harness color") end)
check(oksearch, "ApplySearch runs")
if oksearch then
  check(pfQuestConfig.activesection == 2,
        "searching jumps to the section that still has a hit (got %s)",
        tostring(pfQuestConfig.activesection))
  local hidden = pfQuestConfig:GetRow("Harness Toggle")
  check(hidden and hidden.filtered == true, "a non-matching row is filtered out")
  local shown = pfQuestConfig:GetRow("Harness Color")
  check(shown and not shown.filtered, "the matching row survives the filter")

  -- the hint text matches too, not just the label
  pfQuestConfig:ApplySearch("percent")
  local byhint = pfQuestConfig:GetRow("Harness Size")
  check(byhint and not byhint.filtered, "search matches the hint line, not only the label")

  pfQuestConfig:ApplySearch("")
  check(pfQuestConfig:GetRow("Harness Toggle").filtered == nil, "clearing the search restores every row")
end

-- ---------------------------------------------------------------------------
-- section switching, and the refresh the window runs on every show
-- ---------------------------------------------------------------------------
local okshow = pcall(function() pfQuestConfig:ShowSection(2) end)
check(okshow and pfQuestConfig.activesection == 2, "ShowSection switches the active section")

-- the selected entry is marked by COLOUR and a bar, never by a button-shaped
-- block: the first attempt painted a solid white quad and modulated it with a
-- gradient, which rendered as a pale grey slab (QA screenshot)
do
  local t1, t2 = _G.pfQuestConfigTab1, _G.pfQuestConfigTab2
  check(t1 and t2 and t1.mark and t2.mark, "each nav entry owns a selection bar")
  if t1 and t2 and t1.mark and t2.mark then
    check(t2.mark:IsShown() == true and t1.mark:IsShown() == false,
          "only the active entry shows its selection bar")
    local r, g, b = t2.mark:GetVertexColor()
    check(t2.mark:GetTexture() ~= nil, "the selection bar is painted, not blank")
    pfQuestConfig:ShowSection(1)
    check(t1.mark:IsShown() == true and t2.mark:IsShown() == false,
          "the bar follows the selection")
    pfQuestConfig:ShowSection(2)
  end
end
local okupd, uerr = pcall(function() pfQuestConfig:UpdateConfigEntries() end)
check(okupd, "UpdateConfigEntries runs over every widget type%s", okupd and "" or (" -> " .. tostring(uerr)))

-- ---------------------------------------------------------------------------
-- Group labels, and the search feedback that goes with them.
--
-- In-world Pins carries 19 settings. Grouping is the change that makes that
-- navigable, and it brings two failure modes worth pinning: a group label
-- must not survive a search that filtered away everything under it (a lone
-- "BEAM" heading over nothing reads as a bug), and it must not be counted as
-- a setting, or "4 of 19 match" stops meaning anything.
-- ---------------------------------------------------------------------------
do
  local grp = pfQuestConfig:GetRow("Harness Group")
  check(grp == nil, "a group label is not registered as a settings row")

  -- it exists on the section though, between the rows it heads
  pfQuestConfig:ApplySearch("")
  local beam = pfQuestConfig:GetRow("Harness Beam Width")
  check(beam ~= nil, "the row under the group still builds")

  -- searching for something only the grouped row matches
  pfQuestConfig:ApplySearch("beam")
  check(beam.filtered == nil, "the matching row under a group survives")
  check(pfQuestConfig:GetRow("Harness Toggle").filtered == true,
        "a non-matching row elsewhere is filtered")

  -- the label rides along with its surviving row...
  local label = pfQuestConfig:GetGroup("Harness Group")
  check(label ~= nil and label.filtered == nil,
        "the group label stays while a row under it matches")

  -- ...and disappears when nothing under it does, so no lone heading is left
  pfQuestConfig:ApplySearch("zzzznomatch")
  check(beam.filtered == true, "a search with no hits filters the grouped row")
  check(label ~= nil and label.filtered == true,
        "the group label goes with it -- no heading left over nothing")

  -- the count is the whole reason group labels must not be counted: this
  -- section holds five SETTINGS plus one label, and one of them matches
  pfQuestConfig:ApplySearch("beam")
  local counted = pfQuestConfig.matchcount:GetText()
  check(counted == "1 of 5 settings match",
        "the match count excludes the group label (got %q)", tostring(counted))

  pfQuestConfig:ApplySearch("")
  check(beam.filtered == nil, "clearing the search restores it")
  check(label ~= nil and label.filtered == nil, "and the label comes back")
  check(pfQuestConfig.matchcount:GetText() == "",
        "clearing the search clears the count (got %q)",
        tostring(pfQuestConfig.matchcount:GetText()))
end

-- the matched run is picked out in the label, in the ORIGINAL case
do
  local beam = pfQuestConfig:GetRow("Harness Beam Width")
  pfQuestConfig:ApplySearch("beam")
  local painted = beam.caption:GetText()
  check(string.find(painted, "|cff", 1, true) ~= nil,
        "the matched word is colored in the label (got %s)", tostring(painted))
  check(string.find(painted, "Beam", 1, true) ~= nil,
        "the label keeps its original capitalisation, not the typed query")
  check(string.find(painted, "|r", 1, true) ~= nil, "the color is closed again")

  pfQuestConfig:ApplySearch("")
  check(beam.caption:GetText() == "Harness Beam Width",
        "clearing the search restores the plain label (got %s)",
        tostring(beam.caption:GetText()))
end

-- ---------------------------------------------------------------------------
-- Sidebar match badges. Dimming a section says "not here"; the count says
-- "three of them are over there", which is the half that was missing.
-- ---------------------------------------------------------------------------
do
  local t1, t2 = _G.pfQuestConfigTab1, _G.pfQuestConfigTab2
  check(t1 and t1.badge, "each nav entry owns a match badge")

  pfQuestConfig:ApplySearch("")
  check(t1.badge:GetText() == "", "no badge while the search is empty")

  -- "beam" appears once, in section one only
  pfQuestConfig:ApplySearch("beam")
  check(t1.badge:GetText() == "1",
        "the section with hits shows its count (got %q)", tostring(t1.badge:GetText()))
  check(t2.badge:GetText() == "",
        "a section with no hits shows no badge (got %q)", tostring(t2.badge:GetText()))

  pfQuestConfig:ApplySearch("")
  check(t1.badge:GetText() == "", "clearing the search clears the badges")

  -- the badge must not be counted as a section name when the sidebar is
  -- measured, or a long name plus a two-digit count runs off the entry
  check(t1:GetWidth() > 0, "nav entries are sized")
end

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
