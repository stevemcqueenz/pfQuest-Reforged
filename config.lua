-- multi api compat
local compat = pfQuestCompat
local L = pfQuest_Loc

-- Performance: cache frequently-used globals
local pairs = pairs
local getn = table.getn

pfQuest_history = {}
pfQuest_colors = {}
pfQuest_config = {}

local reset = {
  config = function()
    local dialog = StaticPopupDialogs["PFQUEST_RESET"]
    dialog.text = L["Do you really want to reset the configuration?"]
    dialog.OnAccept = function()
      pfQuest_config = nil
      ReloadUI()
    end

    StaticPopup_Show("PFQUEST_RESET")
  end,
  history = function()
    local dialog = StaticPopupDialogs["PFQUEST_RESET"]
    dialog.text = L["Do you really want to reset the quest history?"]
    dialog.OnAccept = function()
      pfQuest_history = nil
      ReloadUI()
    end

    StaticPopup_Show("PFQUEST_RESET")
  end,
  cache = function()
    local dialog = StaticPopupDialogs["PFQUEST_RESET"]
    dialog.text = L["Do you really want to reset the caches?"]
    dialog.OnAccept = function()
      pfQuest_questcache = nil
      ReloadUI()
    end

    StaticPopup_Show("PFQUEST_RESET")
  end,
  everything = function()
    local dialog = StaticPopupDialogs["PFQUEST_RESET"]
    dialog.text = L["Do you really want to reset everything?"]
    dialog.OnAccept = function()
      pfQuest_config, pfBrowser_fav, pfQuest_history, pfQuest_colors, pfQuest_server, pfQuest_questcache = nil
      ReloadUI()
    end

    StaticPopup_Show("PFQUEST_RESET")
  end,
}

-- default config
-- Reforged: the flat option list outgrew a single column (60+ rows once the
-- tracker, compass and pins landed), so rows are grouped into sections by the
-- "header" entries and the config window shows ONE section at a time behind a
-- sidebar (see CreateConfigEntries). Only ORDER and header placement changed
-- here -- every config key, default and widget type is identical to the old
-- flat list, so saved variables stay compatible. `desc` is an optional
-- one-line hint rendered under the caption of a non-obvious row.
pfQuest_defconfig = {
  { -- 1: All Quests; 2: Tracked; 3: Manual; 4: Hide
    config = "trackingmethod",
    text = nil,
    default = 1,
    type = nil,
  },
  {
    config = "trackerquestsort",
    text = nil,
    default = "level",
    type = nil,
  },

  { text = L["General"], default = nil, type = "header" },
  { text = L["Enable World Map Menu"], default = "1", type = "checkbox", config = "worldmapmenu" },
  { text = L["Enable Minimap Button"], default = "1", type = "checkbox", config = "minimapbutton" },
  { text = L["Enable Quest Log Buttons"], default = "1", type = "checkbox", config = "questlogbuttons" },
  { text = L["Enable Quest Link Support"], default = "1", type = "checkbox", config = "questlinks" },
  { text = L["Show Level On Quest Log"], default = "0", type = "checkbox", config = "questloglevel" },

  { text = L["Quest Tracker"], default = nil, type = "header" },
  -- Default the pfQuest tracker OFF when GW2 UI is present -- GW2 UI has its
  -- own quest tracker and the maintainer wants that one used instead. Only a
  -- NEW/never-set value picks this up (existing saved configs keep their
  -- choice), and standalone installs still default it ON.
  { text = L["Enable Quest Tracker"], default = (pfQuestTheme and pfQuestTheme.gw2) and "0" or "1", type = "checkbox", config = "showtracker" },
  { text = L["Show Level On Quest Tracker"], default = "1", type = "checkbox", config = "trackerlevel" },
  { text = L["Quest Tracker Visibility"], desc = L["Row background opacity from 0 to 1"], default = "0", type = "text", config = "trackeralpha" },
  { text = L["Quest Tracker Font Size"], default = "12", type = "text", config = "trackerfontsize" },
  { text = L["Quest Tracker Max Width"], default = "300", type = "text", config = "trackerwidth" },
  { text = L["Quest Tracker Scale"], default = "1", type = "text", config = "trackerscale" },
  { text = L["Quest Tracker Progress Bars"], default = "1", type = "checkbox", config = "trackerbars" },
  { text = L["Quest Tracker Unfold Objectives"], default = "0", type = "checkbox", config = "trackerexpand" },

  { text = L["Map & Minimap"], default = nil, type = "header" },
  { text = L["Quest Objective Spawn Points (World Map)"], default = "1", type = "checkbox", config = "showspawn" },
  {
    text = L["Quest Objective Spawn Points (Mini Map)"],
    default = "1",
    type = "checkbox",
    config = "showspawnmini",
  },
  { text = L["Quest Objective Icons (World Map)"], default = "1", type = "checkbox", config = "showcluster" },
  { text = L["Quest Objective Icons (Mini Map)"], default = "0", type = "checkbox", config = "showclustermini" },
  { text = L["Enable Minimap Nodes"], default = "1", type = "checkbox", config = "minimapnodes" },
  { text = L["Display Available Quest Givers"], default = "1", type = "checkbox", config = "allquestgivers" },
  { text = L["Display Current Quest Givers"], default = "1", type = "checkbox", config = "currentquestgivers" },
  { text = L["Display Low Level Quest Givers"], default = "0", type = "checkbox", config = "showlowlevel" },
  { text = L["Display Level+3 Quest Givers"], default = "0", type = "checkbox", config = "showhighlevel" },
  { text = L["Display Event & Daily Quests"], default = "0", type = "checkbox", config = "showfestival" },

  { text = L["Node Appearance"], default = nil, type = "header" },
  { text = L["Use Icons For Tracking Nodes"], default = "1", type = "checkbox", config = "trackingicons" },
  { text = L["Use Monochrome Cluster Icons"], default = "0", type = "checkbox", config = "clustermono" },
  { text = L["Use Cut-Out Minimap Node Icons"], default = "1", type = "checkbox", config = "cutoutminimap" },
  { text = L["Use Cut-Out World Map Node Icons"], default = "0", type = "checkbox", config = "cutoutworldmap" },
  { text = L["Color Map Nodes By Spawn"], default = "0", type = "checkbox", config = "spawncolors" },
  { text = L["World Map Node Transparency"], default = "1.0", type = "text", config = "worldmaptransp" },
  { text = L["Minimap Node Transparency"], default = "1.0", type = "text", config = "minimaptransp" },
  { text = L["World Map Node Size"], default = "14", type = "slider", config = "worldmapNodeSize", min = 8, max = 24, step = 1, format = "%dpx" },
  { text = L["Minimap Node Size"], default = "14", type = "slider", config = "minimapNodeSize", min = 8, max = 24, step = 1, format = "%dpx" },
  { text = L["Node Fade Transparency"], desc = L["Node opacity while faded, 0 to 1"], default = "0.3", type = "text", config = "nodefade" },
  { text = L["Highlight Nodes On Mouseover"], default = "1", type = "checkbox", config = "mouseover" },

  { text = L["Tooltips"], default = nil, type = "header" },
  { text = L["Show Tooltips"], default = "1", type = "checkbox", config = "showtooltips" },
  { text = L["Show Help On Tooltips"], default = "1", type = "checkbox", config = "tooltiphelp" },
  { text = L["Show Database IDs"], default = "0", type = "checkbox", config = "showids" },

  { text = L["Compass Bar"], default = nil, type = "header" },
  { text = L["Enable Compass Bar"], desc = L["Quest directions on a bar at the top of the screen"], default = "0", type = "checkbox", config = "compass" },
  { text = L["Bar Width"], default = "420", type = "text", config = "compasswidth" },
  { text = L["Bar Scale"], default = "1", type = "text", config = "compassscale" },
  { text = L["Metric Distances (meters)"], default = "0", type = "checkbox", config = "compassmetric" },
  { text = L["Show Available Quests"], default = "1", type = "checkbox", config = "compassavail" },
  { text = L["Show Quest Turn-Ins"], default = "1", type = "checkbox", config = "compassturnin" },
  { text = L["Show Dungeon Entrances"], default = "0", type = "checkbox", config = "compassdungeon" },
  { text = L["Show Objective Description"], default = "1", type = "checkbox", config = "compassdesc" },
  { text = L["Marker Cap"], desc = L["4 to 12 markers, default 8"], default = "8", type = "text", config = "compasscap" },

  { text = L["Routes"], default = nil, type = "header" },
  { text = L["Show Route Between Objects"], default = "1", type = "checkbox", config = "routes" },
  { text = L["Include Unified Quest Locations"], default = "1", type = "checkbox", config = "routecluster" },
  { text = L["Include Quest Enders"], default = "1", type = "checkbox", config = "routeender" },
  { text = L["Include Quest Starters"], default = "0", type = "checkbox", config = "routestarter" },
  { text = L["Show Route On Minimap"], default = "0", type = "checkbox", config = "routeminimap" },
  { text = L["Show Arrow Along Routes"], default = "1", type = "checkbox", config = "arrow" },
  { text = L["Arrow Scale"], default = "1.0", type = "slider", config = "arrowscale", min = 0.5, max = 3.0, step = 0.1 },

  { text = L["Database & Advanced"], default = nil, type = "header" },
  { text = L["Draw Favorites On Login"], default = "0", type = "checkbox", config = "favonlogin" },
  { text = L["Minimum Item Drop Chance"], desc = L["Hide drops below this percent chance"], default = "1", type = "text", config = "mindropchance" },
  { text = L["Reset Configuration"], default = "1", type = "button", func = reset.config },
  { text = L["Reset Quest History"], default = "1", type = "button", func = reset.history },
  { text = L["Reset Cache"], default = "1", type = "button", func = reset.cache },
  { text = L["Reset Everything"], default = "1", type = "button", func = reset.everything },
}

-- In-world pins (docs/PINS-DESIGN.md, stage 2): the tier is hidden ENTIRELY
-- without the WorldAPI DLL, settings rows AND its sidebar section included --
-- feature-detect by type, never a version global. Inserted after the compass
-- section (its rows end at compasscap); reverse-order inserts land in reading
-- order header/pins/size/minscale/maxscale/opacity/pointsize/beam/navradius/
-- navsize, so the section header comes first.
if type(WorldToScreen) == "function" then
  for i = 1, getn(pfQuest_defconfig) do
    if pfQuest_defconfig[i].config == "compasscap" then
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Navigator Size"], default = "100", type = "text", config = "pinsnavsize" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Navigator Orbit Radius"], default = "140", type = "text", config = "pinsnavradius" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pin Light Beam"], default = "1", type = "checkbox", config = "pinsbeam" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pinpoint Size"], default = "100", type = "text", config = "pinspointsize" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pin Opacity"], default = "100", type = "text", config = "pinsopacity" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Maximum Pin Scale"], default = "150", type = "text", config = "pinsmaxscale" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Minimum Pin Scale"], default = "50", type = "text", config = "pinsminscale" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pin Size"], desc = L["Percent, 100 is the default size"], default = "100", type = "text", config = "pinssize" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Enable Waypoint Pins"], desc = L["Needs the WorldAPI DLL (WorldToScreen)"], default = "0", type = "checkbox", config = "pins" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["In-world Pins"], default = nil, type = "header" })
      break
    end
  end
end

StaticPopupDialogs["PFQUEST_RESET"] = {
  button1 = YES,
  button2 = NO,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

pfQuestConfig = CreateFrame("Frame", "pfQuestConfig", UIParent)
pfQuestConfig:Hide()
pfQuestConfig:SetWidth(280)
pfQuestConfig:SetHeight(550)
pfQuestConfig:SetPoint("CENTER", 0, 0)
pfQuestConfig:SetFrameStrata("HIGH")
pfQuestConfig:SetMovable(true)
pfQuestConfig:EnableMouse(true)
pfQuestConfig:SetClampedToScreen(true)

pfQuestConfig:SetScript("OnMouseDown", function()
  this:StartMoving()
end)

pfQuestConfig:SetScript("OnMouseUp", function()
  this:StopMovingOrSizing()
end)

pfQuestConfig:SetScript("OnShow", function()
  this:UpdateConfigEntries()
end)

pfQuestConfig.vpos = 40

-- Reforged: route the config window through the shared theme (flat panel +
-- accent header strip) like the browser/journal, instead of the bare pfUI
-- backdrop that left it looking unstyled and near-transparent (QA: the
-- settings window showed the game world through it). Picks up the GW2
-- palette automatically when GW2 UI is installed.
if pfQuestTheme and pfQuestTheme.SkinPanel then
  pfQuestTheme.SkinPanel(pfQuestConfig)
  pfQuestTheme.HeaderStrip(pfQuestConfig, 26)
else
  pfUI.api.CreateBackdrop(pfQuestConfig, nil, true, 0.75)
end
table.insert(UISpecialFrames, "pfQuestConfig")

-- detect current addon path. Reforged: try the REAL folder name first,
-- parsed from this file's load path -- it works for ANY folder name (zip
-- extractors love to append version suffixes); the known-name probe stays
-- as the fallback.
local candidates = {}
local real = debugstack and string.match(debugstack(1) or "", "AddOns\\(.-)\\")
if real then table.insert(candidates, real) end
for _, name in pairs({ "", "-Reforged", "-master", "-tbc", "-wotlk", "-turtle" }) do
  table.insert(candidates, string.format("pfQuest%s", name))
end
for _, current in pairs(candidates) do
  local _, title = GetAddOnInfo(current)
  if title then
    pfQuestConfig.path = "Interface\\AddOns\\" .. current
    pfQuestConfig.version = tostring(GetAddOnMetadata(current, "Version"))
    break
  end
end

-- fallback if no matching addon found
if not pfQuestConfig.path then
  pfQuestConfig.path = "Interface\\AddOns\\pfQuest"
  pfQuestConfig.version = "unknown"
end

pfQuestConfig.title = pfQuestConfig:CreateFontString("Status", "LOW", "GameFontNormal")
pfQuestConfig.title:SetFontObject(GameFontWhite)
pfQuestConfig.title:SetPoint("TOP", pfQuestConfig, "TOP", 0, -8)
pfQuestConfig.title:SetJustifyH("LEFT")
pfQuestConfig.title:SetFont(pfUI.font_default, 14)
pfQuestConfig.title:SetText("|cff33ffccpf|rQuest " .. L["Config"])

pfQuestConfig.close = CreateFrame("Button", "pfQuestConfigClose", pfQuestConfig)
pfQuestConfig.close:SetPoint("TOPRIGHT", -5, -5)
pfQuestConfig.close:SetHeight(20)
pfQuestConfig.close:SetWidth(20)
pfQuestConfig.close.texture = pfQuestConfig.close:CreateTexture("pfQuestionDialogCloseTex")
pfQuestConfig.close.texture:SetTexture(pfQuestConfig.path .. "\\compat\\close")
pfQuestConfig.close.texture:ClearAllPoints()
pfQuestConfig.close.texture:SetPoint("TOPLEFT", pfQuestConfig.close, "TOPLEFT", 4, -4)
pfQuestConfig.close.texture:SetPoint("BOTTOMRIGHT", pfQuestConfig.close, "BOTTOMRIGHT", -4, 4)

pfQuestConfig.close.texture:SetVertexColor(1, 0.25, 0.25, 1)
pfUI.api.SkinButton(pfQuestConfig.close, 1, 0.5, 0.5)
pfQuestConfig.close:SetScript("OnClick", function()
  this:GetParent():Hide()
end)

pfQuestConfig.welcome = CreateFrame("Button", "pfQuestConfigWelcome", pfQuestConfig)
pfQuestConfig.welcome:SetWidth(160)
pfQuestConfig.welcome:SetHeight(28)
pfQuestConfig.welcome:SetPoint("BOTTOMLEFT", 10, 10)
pfQuestConfig.welcome:SetScript("OnClick", function()
  pfQuestConfig:Hide()
  pfQuestInit:Show()
end)
pfQuestConfig.welcome.text = pfQuestConfig.welcome:CreateFontString("Caption", "LOW", "GameFontWhite")
pfQuestConfig.welcome.text:SetAllPoints(pfQuestConfig.welcome)
pfQuestConfig.welcome.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
pfQuestConfig.welcome.text:SetText(L["Welcome Screen"])
pfUI.api.SkinButton(pfQuestConfig.welcome)

pfQuestConfig.save = CreateFrame("Button", "pfQuestConfigReload", pfQuestConfig)
pfQuestConfig.save:SetWidth(160)
pfQuestConfig.save:SetHeight(28)
pfQuestConfig.save:SetPoint("BOTTOMRIGHT", -10, 10)
pfQuestConfig.save:SetScript("OnClick", ReloadUI)
pfQuestConfig.save.text = pfQuestConfig.save:CreateFontString("Caption", "LOW", "GameFontWhite")
pfQuestConfig.save.text:SetAllPoints(pfQuestConfig.save)
pfQuestConfig.save.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
pfQuestConfig.save.text:SetText(L["Save & Close"])
pfUI.api.SkinButton(pfQuestConfig.save)

function pfQuestConfig:LoadConfig()
  if not pfQuest_config then
    pfQuest_config = {}
  end
  for id, data in pairs(pfQuest_defconfig) do
    if data.config and not pfQuest_config[data.config] then
      pfQuest_config[data.config] = data.default
    end
  end
end

function pfQuestConfig:MigrateHistory()
  if not pfQuest_history then
    return
  end

  local match = false

  for entry, data in pairs(pfQuest_history) do
    if type(entry) == "string" then
      for id in pairs(pfDatabase:GetIDByName(entry, "quests")) do
        pfQuest_history[id] = { 0, 0 }
        pfQuest_history[entry] = nil
        match = true
      end
    elseif data == true then
      pfQuest_history[entry] = { 0, 0 }
    elseif type(data) == "table" and not data[1] then
      pfQuest_history[entry] = { 0, 0 }
    end
  end

  if match == true then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest|r: " .. L["Quest history migration completed."])
  end
end

-- Reforged: sectioned layout. The old renderer flowed ALL rows into 22-row
-- columns, which stopped scaling once the tracker/compass/pins options landed
-- (60+ rows, three dense columns). Headers now define sections; each section
-- gets a sidebar button on the left and its rows render in a single pane on
-- the right, one section visible at a time. Plain frames and buttons only --
-- no scroll frames, no templates beyond UICheckButtonTemplate (as before).
local rowheight = 24
local descheight = 14
local maxtext = 130
local configframes = {}
local sections = {}

function pfQuestConfig:ShowSection(index)
  local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }
  for i = 1, getn(sections) do
    local active = (i == index)
    local rows = sections[i].rows
    for j = 1, getn(rows) do
      if active then
        rows[j]:Show()
      else
        rows[j]:Hide()
      end
    end
    if sections[i].tab then
      if active then
        sections[i].tab.text:SetTextColor(a[1], a[2], a[3], 1)
      else
        sections[i].tab.text:SetTextColor(1, 1, 1, 1)
      end
    end
  end

  if sections[index] then
    pfQuestConfig.sectiontitle:SetText(sections[index].name)
    pfQuestConfig.activesection = index
  end
end

function pfQuestConfig:CreateConfigEntries(config)
  local count = 1
  local hasSlider = false
  local section = nil

  for _, data in pairs(config) do
    -- header: opens a new section instead of rendering a row
    if data.type == "header" then
      section = { name = data.text, rows = {} }
      table.insert(sections, section)

    elseif data.type then
      -- basic frame
      local frame = CreateFrame("Frame", "pfQuestConfig" .. count, pfQuestConfig)
      frame:Hide()
      configframes[data.text] = frame
      if section then
        table.insert(section.rows, frame)
      end

      -- caption
      frame.caption = frame:CreateFontString("Status", "LOW", "GameFontWhite")
      frame.caption:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
      frame.caption:SetJustifyH("LEFT")
      frame.caption:SetText(data.text)
      maxtext = max(maxtext, frame.caption:GetStringWidth())

      -- optional hint line below the caption for non-obvious rows
      if data.desc then
        frame.tall = true
        frame.caption:SetPoint("TOPLEFT", 8, -4)
        frame.desc = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
        frame.desc:SetFont(pfUI.font_default, pfUI_config.global.font_size - 2, "OUTLINE")
        frame.desc:SetPoint("TOPLEFT", 8, -19)
        frame.desc:SetJustifyH("LEFT")
        frame.desc:SetTextColor(0.6, 0.6, 0.6, 1)
        frame.desc:SetText(data.desc)
        maxtext = max(maxtext, frame.desc:GetStringWidth())
      else
        frame.caption:SetPoint("LEFT", 8, 0)
      end

      -- checkbox
      if data.type == "checkbox" then
        frame.input = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        frame.input:SetNormalTexture("")
        frame.input:SetPushedTexture("")
        frame.input:SetHighlightTexture("")
        pfUI.api.CreateBackdrop(frame.input, nil, true)

        frame.input:SetWidth(16)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -8, 0)

        frame.input.config = data.config
        if pfQuest_config[data.config] == "1" then
          frame.input:SetChecked()
        end

        frame.input:SetScript("OnClick", function()
          if this:GetChecked() then
            pfQuest_config[this.config] = "1"
          else
            pfQuest_config[this.config] = "0"
          end

          pfQuest:ResetAll()
        end)

        -- Reforged: the whole row is the hit target, not just the 16px box.
        -- An overlay button above the checkbox forwards clicks via :Click()
        -- (native Button method, 1.12+), so the label toggles too and the
        -- caption lights up in the accent color on hover.
        frame.hit = CreateFrame("Button", nil, frame)
        frame.hit:SetAllPoints(frame)
        frame.hit:SetFrameLevel(frame.input:GetFrameLevel() + 1)
        frame.hit.input = frame.input
        frame.hit.caption = frame.caption
        frame.hit:SetScript("OnClick", function()
          this.input:Click()
        end)
        frame.hit:SetScript("OnEnter", function()
          local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }
          this.caption:SetTextColor(a[1], a[2], a[3], 1)
        end)
        frame.hit:SetScript("OnLeave", function()
          this.caption:SetTextColor(1, 1, 1, 1)
        end)
      elseif data.type == "text" then
        -- input field
        frame.input = CreateFrame("EditBox", nil, frame)
        local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }; frame.input:SetTextColor(a[1], a[2], a[3], 1)
        frame.input:SetJustifyH("RIGHT")
        frame.input:SetTextInsets(5, 5, 5, 5)
        -- Reforged: 50px instead of 32 -- three-digit values (compass width
        -- 420, pin percents) did not fit the old box.
        frame.input:SetWidth(50)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -8, 0)
        frame.input:SetFontObject(GameFontNormal)
        frame.input:SetAutoFocus(false)
        frame.input:SetScript("OnEscapePressed", function(self)
          this:ClearFocus()
        end)

        frame.input.config = data.config
        frame.input:SetText(pfQuest_config[data.config])

        frame.input:SetScript("OnTextChanged", function(self)
          pfQuest_config[this.config] = this:GetText()
        end)

        pfUI.api.CreateBackdrop(frame.input, nil, true)
      elseif data.type == "slider" then
        -- Copy slider-specific values out of the loop table so the callback
        -- keeps stable bounds/config even after CreateConfigEntries continues.
        local minval = data.min
        local maxval = data.max
        local config = data.config
        local default = data.default
        local step = data.step or 0.1
        local fmt = data.format or "%.1fx"

        frame.input = CreateFrame("Slider", nil, frame)
        frame.input:SetOrientation("HORIZONTAL")
        frame.input:SetWidth(60)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -8, 0)
        frame.input:EnableMouse(true)
        frame.input:SetMinMaxValues(minval, maxval)
        frame.input:SetValueStep(data.step)
        frame.input:SetThumbTexture("Interface\\BUTTONS\\WHITE8X8")
        frame.input.thumb = frame.input:GetThumbTexture()
        frame.input.thumb:SetHeight(14)
        frame.input.thumb:SetWidth(8)
        -- Reforged: thumb follows the theme accent (gold under GW2 UI)
        -- instead of hardcoded teal.
        local ta = pfQuestTheme and pfQuestTheme.accent or { 0.3, 1, 0.8 }
        frame.input.thumb:SetTexture(ta[1], ta[2], ta[3], 0.5)
        pfUI.api.CreateBackdrop(frame.input, nil, true)

        frame.input.config = config

        -- value label to the left of the slider
        frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
        frame.value:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
        frame.value:SetPoint("RIGHT", frame.input, "LEFT", -4, 0)
        local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }; frame.value:SetTextColor(a[1], a[2], a[3], 1)

        local val = tonumber(pfQuest_config[config]) or tonumber(default) or 1
        frame.input:SetValue(val)
        frame.value:SetText(string.format(fmt, val))

        frame.input.updating = false
        frame.input:SetScript("OnValueChanged", function()
          if this.updating then return end
          this.updating = true

          local val = this:GetValue()
          val = max(minval, min(maxval, val))
          val = floor(val / step + 0.5) * step

          -- Snap the thumb back onto the stored step so slider position,
          -- label text, and saved config all stay visually in sync.
          this:SetValue(val)

          pfQuest_config[this.config] = tostring(val)
          frame.value:SetText(string.format(fmt, val))

          -- live-apply: the arrow reads its scale, the world-map pins their
          -- size (minimap pins pick the new size up on their next update)
          if pfQuest and pfQuest.route and pfQuest.route.arrow then
            pfQuest.route.arrow:ApplyScale()
          end
          if pfMap and pfMap.ResizeNodes then
            pfMap:ResizeNodes()
          end

          this.updating = false
        end)

        hasSlider = true
      elseif data.type == "button" and data.func then
        frame.input = CreateFrame("Button", nil, frame)
        frame.input:SetWidth(44)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -8, 0)
        frame.input:SetScript("OnClick", data.func)
        frame.input.text = frame.input:CreateFontString("Caption", "LOW", "GameFontWhite")
        frame.input.text:SetAllPoints(frame.input)
        frame.input.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
        frame.input.text:SetText("OK")
        pfUI.api.SkinButton(frame.input)
      end

      -- increase size and zoom back due to blizzard backdrop reasons...
      if frame.input and pfUI.api.emulated and data.type ~= "slider" then
        frame.input:SetWidth(frame.input:GetWidth() / 0.6)
        frame.input:SetHeight(frame.input:GetHeight() / 0.6)
        frame.input:SetScale(0.8)
        if frame.input.SetTextInsets then
          frame.input:SetTextInsets(8, 8, 8, 8)
        end
      end

      count = count + 1
    end
  end

  -- sidebar: one button per section
  local a = pfQuestTheme and pfQuestTheme.accent or { 0.2, 1, 0.8 }
  local sidebarwidth = 110
  for i = 1, getn(sections) do
    local tab = CreateFrame("Button", "pfQuestConfigTab" .. i, pfQuestConfig)
    tab:SetHeight(24)
    tab:SetID(i)
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    tab.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
    tab.text:SetPoint("LEFT", 8, 0)
    tab.text:SetJustifyH("LEFT")
    tab.text:SetText(sections[i].name)
    sidebarwidth = max(sidebarwidth, tab.text:GetStringWidth() + 24)
    pfUI.api.SkinButton(tab, a[1], a[2], a[3])
    tab:SetScript("OnClick", function()
      pfQuestConfig:ShowSection(this:GetID())
    end)
    sections[i].tab = tab
  end

  for i = 1, getn(sections) do
    sections[i].tab:SetWidth(sidebarwidth)
    sections[i].tab:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 26)
  end

  -- pane geometry: sidebar left, section title + rows right
  local panewidth = maxtext + (hasSlider and 150 or 110)
  local paneleft = 10 + sidebarwidth + 14

  -- vertical separator between sidebar and pane
  pfQuestConfig.separator = pfQuestConfig:CreateTexture(nil, "BORDER")
  pfQuestConfig.separator:SetTexture(a[1], a[2], a[3], 0.15)
  pfQuestConfig.separator:SetWidth(1)
  pfQuestConfig.separator:SetPoint("TOPLEFT", 10 + sidebarwidth + 7, -36)

  -- active section title above the rows, underlined in the accent color
  pfQuestConfig.sectiontitle = pfQuestConfig:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  pfQuestConfig.sectiontitle:SetFont(pfUI.font_default, pfUI_config.global.font_size + 2, "OUTLINE")
  pfQuestConfig.sectiontitle:SetPoint("TOPLEFT", paneleft + 8, -42)
  pfQuestConfig.sectiontitle:SetJustifyH("LEFT")
  pfQuestConfig.sectiontitle:SetTextColor(a[1], a[2], a[3], 1)

  pfQuestConfig.sectionline = pfQuestConfig:CreateTexture(nil, "BORDER")
  pfQuestConfig.sectionline:SetTexture(a[1], a[2], a[3], 0.35)
  pfQuestConfig.sectionline:SetHeight(1)
  pfQuestConfig.sectionline:SetPoint("TOPLEFT", paneleft, -60)
  pfQuestConfig.sectionline:SetWidth(panewidth)

  -- lay out each section's rows from the pane top; sections overlap, only
  -- the active one is shown (ShowSection)
  local contentheight = 0
  for i = 1, getn(sections) do
    local y = 0
    local rows = sections[i].rows
    for j = 1, getn(rows) do
      local h = rows[j].tall and (rowheight + descheight) or rowheight
      rows[j]:SetWidth(panewidth)
      rows[j]:SetHeight(h)
      rows[j]:SetPoint("TOPLEFT", pfQuestConfig, "TOPLEFT", paneleft, -68 - y)
      y = y + h
    end
    contentheight = max(contentheight, y)
  end

  -- window size: fixed, driven by the tallest section and the sidebar
  local body = max(68 + contentheight, 36 + getn(sections) * 26)
  pfQuestConfig:SetWidth(max(paneleft + panewidth + 14, 360))
  pfQuestConfig:SetHeight(body + 52)
  pfQuestConfig.separator:SetHeight(body - 30)

  pfQuestConfig:ShowSection(1)
end

function pfQuestConfig:UpdateConfigEntries()
  for _, data in pairs(pfQuest_defconfig) do
    if data.type and configframes[data.text] then
      if data.type == "checkbox" then
        configframes[data.text].input:SetChecked((pfQuest_config[data.config] == "1" and true or nil))
      elseif data.type == "text" then
        configframes[data.text].input:SetText(pfQuest_config[data.config])
      elseif data.type == "slider" then
        local newval = tonumber(pfQuest_config[data.config]) or tonumber(data.default) or 1
        newval = floor(newval * 10 + 0.5) / 10
        local oldval = floor(configframes[data.text].input:GetValue() * 10 + 0.5) / 10
        -- Avoid bouncing the slider callback when the UI is already showing
        -- the same rounded value that the config stores.
        if oldval ~= newval then
          configframes[data.text].input:SetValue(newval)
        end
      end
    end
  end
end

-- Register ADDON_LOADED event handler after all methods are defined
-- This ensures LoadConfig, MigrateHistory, CreateConfigEntries exist when called
pfQuestConfig:RegisterEvent("ADDON_LOADED")
pfQuestConfig:SetScript("OnEvent", function()
  -- Reforged: prefix-match the addon folder name. The old equality list
  -- (pfQuest/-tbc/-wotlk) silently skipped ALL of this init for any other
  -- install folder -- the canonical pfQuest-Reforged folder loaded with no
  -- config defaults, no settings entries and a nil pfQuest_track (QA: empty
  -- config window, dead arrow, menu.lua crash on fresh installs). The
  -- run-once flag keeps a second pfQuest*-named addon from double-building
  -- the settings entries.
  if not pfQuestConfig.initialized and strsub(tostring(arg1), 1, 7) == "pfQuest" then
    pfQuestConfig.initialized = true
    pfQuestConfig:LoadConfig()
    pfQuestConfig:MigrateHistory()
    pfQuestConfig:CreateConfigEntries(pfQuest_defconfig)

    pfQuest_questcache = pfQuest_questcache or {}
    pfQuest_history = pfQuest_history or {}
    pfQuest_colors = pfQuest_colors or {}
    pfQuest_config = pfQuest_config or {}
    pfQuest_track = pfQuest_track or {}
    pfBrowser_fav = pfBrowser_fav or { ["units"] = {}, ["objects"] = {}, ["items"] = {}, ["quests"] = {} }

    -- clear quest history on new characters
    if UnitXP("player") == 0 and UnitLevel("player") == 1 then
      pfQuest_history = {}
    end

    if pfBrowserIcon and pfQuest_config["minimapbutton"] == "0" then
      pfBrowserIcon:Hide()
    end

    if pfQuest and pfQuest.route and pfQuest.route.arrow then
      pfQuest.route.arrow:ApplyScale()
    end
  end
end)

do -- welcome/init popup dialog
  local config_stage = {
    arrow = 1,
    mode = 2,
  }

  local desaturate = function(texture, state)
    local supported = texture:SetDesaturated(state)
    if not supported then
      if state then
        texture:SetVertexColor(0.5, 0.5, 0.5)
      else
        texture:SetVertexColor(1.0, 1.0, 1.0)
      end
    end
  end

  -- create welcome/init window
  pfQuestInit = CreateFrame("Frame", "pfQuestInit", UIParent)
  pfQuestInit:Hide()
  pfQuestInit:SetWidth(400)
  pfQuestInit:SetHeight(270)
  pfQuestInit:SetMovable(true)
  pfQuestInit:EnableMouse(true)
  pfQuestInit:SetPoint("CENTER", 0, 0)
  pfQuestInit:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfQuestInit:SetScript("OnMouseDown", function()
    this:StartMoving()
  end)

  pfQuestInit:SetScript("OnMouseUp", function()
    this:StopMovingOrSizing()
  end)

  pfQuestInit:SetScript("OnEvent", function()
    if pfQuest_config.welcome ~= "1" then
      -- parse current config
      if pfQuest_config["showspawn"] == "0" and pfQuest_config["showcluster"] == "1" then
        config_stage.mode = 1
      elseif pfQuest_config["showspawn"] == "1" and pfQuest_config["showcluster"] == "0" then
        config_stage.mode = 3
      end

      if pfQuest_config["arrow"] == "0" then
        config_stage.arrow = nil
      end

      pfQuestInit:Show()
    end
    this:UnregisterAllEvents()
  end)

  pfQuestInit:SetScript("OnShow", function()
    -- reload ui elements
    desaturate(pfQuestInit[1].bg, true)
    desaturate(pfQuestInit[2].bg, true)
    desaturate(pfQuestInit[3].bg, true)
    desaturate(pfQuestInit[config_stage.mode].bg, false)
    pfQuestInit.checkbox:SetChecked(config_stage.arrow)
  end)

  if pfQuestTheme and pfQuestTheme.SkinPanel then
    pfQuestTheme.SkinPanel(pfQuestInit)
  else
    pfUI.api.CreateBackdrop(pfQuestInit, nil, true, 0.85)
  end

  -- welcome title
  pfQuestInit.title = pfQuestInit:CreateFontString("Status", "LOW", "GameFontWhite")
  pfQuestInit.title:SetPoint("TOP", pfQuestInit, "TOP", 0, -17)
  pfQuestInit.title:SetJustifyH("LEFT")
  pfQuestInit.title:SetText(L["Please select your preferred |cff33ffccpf|cffffffffQuest|r mode:"])

  -- questing mode
  local buttons = {
    {
      caption = L["Simple Markers"],
      texture = "\\img\\init\\simple",
      position = { "TOPLEFT", 10, -40 },
      tooltip = L["Only show cluster icons with summarized objective locations based on spawn points"],
    },
    {
      caption = L["Combined"],
      texture = "\\img\\init\\combined",
      position = { "TOP", 0, -40 },
      tooltip = L["Show cluster icons with summarized locations and also display all spawn points of each quest objective"],
    },
    {
      caption = L["Spawn Points"],
      texture = "\\img\\init\\spawns",
      position = { "TOPRIGHT", -10, -40 },
      tooltip = L["Display all spawn points of each quest objective and hide summarized cluster icons."],
    },
  }

  for i, button in pairs(buttons) do
    pfQuestInit[i] = CreateFrame("Button", "pfQuestInitLeft", pfQuestInit)
    pfQuestInit[i]:SetWidth(120)
    pfQuestInit[i]:SetHeight(160)
    pfQuestInit[i]:SetPoint(unpack(button.position))
    pfQuestInit[i]:SetID(i)

    pfQuestInit[i].bg = pfQuestInit[i]:CreateTexture(nil, "NORMAL")
    pfQuestInit[i].bg:SetWidth(200)
    pfQuestInit[i].bg:SetHeight(200)
    pfQuestInit[i].bg:SetPoint("CENTER", 0, 0)
    pfQuestInit[i].bg:SetTexture(pfQuestConfig.path .. button.texture)

    pfQuestInit[i].caption = pfQuestInit:CreateFontString("Status", "LOW", "GameFontWhite")
    pfQuestInit[i].caption:SetPoint("TOP", pfQuestInit[i], "BOTTOM", 0, -5)
    pfQuestInit[i].caption:SetJustifyH("LEFT")
    pfQuestInit[i].caption:SetText(button.caption)

    pfUI.api.SkinButton(pfQuestInit[i])

    pfQuestInit[i]:SetScript("OnClick", function()
      desaturate(pfQuestInit[1].bg, true)
      desaturate(pfQuestInit[2].bg, true)
      desaturate(pfQuestInit[3].bg, true)
      desaturate(pfQuestInit[this:GetID()].bg, false)
      config_stage.mode = this:GetID()
    end)

    local OnEnter = pfQuestInit[i]:GetScript("OnEnter")
    pfQuestInit[i]:SetScript("OnEnter", function()
      if OnEnter then
        OnEnter()
      end
      GameTooltip_SetDefaultAnchor(GameTooltip, this)

      GameTooltip:SetText(this.caption:GetText())
      GameTooltip:AddLine(buttons[this:GetID()].tooltip, 1, 1, 1, true)
      GameTooltip:SetWidth(100)
      GameTooltip:Show()
    end)

    local OnLeave = pfQuestInit[i]:GetScript("OnLeave")
    pfQuestInit[i]:SetScript("OnLeave", function()
      if OnLeave then
        OnLeave()
      end
      GameTooltip:Hide()
    end)
  end

  -- show arrows
  pfQuestInit.checkbox = CreateFrame("CheckButton", nil, pfQuestInit, "UICheckButtonTemplate")
  pfQuestInit.checkbox:SetPoint("BOTTOMLEFT", 10, 10)
  pfQuestInit.checkbox:SetNormalTexture("")
  pfQuestInit.checkbox:SetPushedTexture("")
  pfQuestInit.checkbox:SetHighlightTexture("")
  pfQuestInit.checkbox:SetWidth(22)
  pfQuestInit.checkbox:SetHeight(22)
  pfUI.api.CreateBackdrop(pfQuestInit.checkbox, nil, true)

  pfQuestInit.checkbox.caption = pfQuestInit:CreateFontString("Status", "LOW", "GameFontWhite")
  pfQuestInit.checkbox.caption:SetPoint("LEFT", pfQuestInit.checkbox, "RIGHT", 5, 0)
  pfQuestInit.checkbox.caption:SetJustifyH("LEFT")
  pfQuestInit.checkbox.caption:SetText(L["Show Navigation Arrow"])
  pfQuestInit.checkbox:SetScript("OnClick", function()
    config_stage.arrow = this:GetChecked()
  end)

  pfQuestInit.checkbox:SetScript("OnEnter", function()
    GameTooltip_SetDefaultAnchor(GameTooltip, this)
    GameTooltip:SetText(L["Navigation Arrow"])
    GameTooltip:AddLine(L["Show navigation arrow that points you to the nearest quest location."], 1, 1, 1, true)
    GameTooltip:SetWidth(100)
    GameTooltip:Show()
  end)

  pfQuestInit.checkbox:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- save button
  pfQuestInit.save = CreateFrame("Button", nil, pfQuestInit)
  pfQuestInit.save:SetWidth(100)
  pfQuestInit.save:SetHeight(24)
  pfQuestInit.save:SetPoint("BOTTOMRIGHT", -10, 10)
  pfQuestInit.save.text = pfQuestInit.save:CreateFontString("Caption", "LOW", "GameFontWhite")
  pfQuestInit.save.text:SetAllPoints(pfQuestInit.save)
  pfQuestInit.save.text:SetText(L["Save & Close"])

  pfUI.api.SkinButton(pfQuestInit.save)

  pfQuestInit.save:SetScript("OnClick", function()
    -- write current config
    if config_stage.mode == 1 then
      pfQuest_config["showspawn"] = "0"
      pfQuest_config["showspawnmini"] = "0"
      pfQuest_config["showcluster"] = "1"
      pfQuest_config["showclustermini"] = "1"
    elseif config_stage.mode == 2 then
      pfQuest_config["showspawn"] = "1"
      pfQuest_config["showspawnmini"] = "1"
      pfQuest_config["showcluster"] = "1"
      pfQuest_config["showclustermini"] = "0"
    elseif config_stage.mode == 3 then
      pfQuest_config["showspawn"] = "1"
      pfQuest_config["showspawnmini"] = "1"
      pfQuest_config["showcluster"] = "0"
      pfQuest_config["showclustermini"] = "0"
    end

    if config_stage.arrow then
      pfQuest_config["arrow"] = "1"
    else
      pfQuest_config["arrow"] = "0"
    end

    -- save welcome flag and reload
    pfQuest_config["welcome"] = "1"
    pfQuest:ResetAll()
    pfQuestInit:Hide()
  end)
end
