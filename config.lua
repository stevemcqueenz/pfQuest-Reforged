-- multi api compat
local compat = pfQuestCompat
local L = pfQuest_Loc

-- Performance: cache frequently-used globals
local pairs = pairs
local getn = table.getn
local ceil = math.ceil

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

  { text = L["Nameplates"], default = nil, type = "header" },
  -- GW2 UI dedupe: nameplates.lua swaps this row's desc for the hint
  -- "GW2 UI quest icons are active" when GW2 UI's own quest plate icons are
  -- detected; the "1" is then treated as off (rule documented there).
  { text = L["Quest Icons On Nameplates"], desc = L["Kill, loot, turn-in and quest giver icons beside enemy nameplates"], default = "1", type = "checkbox", config = "plateicons" },
  { text = L["Nameplate Icon Scale"], desc = L["Percent, 50 to 200"], default = "100", type = "text", config = "plateiconscale" },
  { text = L["Nameplate Icon X Offset"], default = "-17", type = "text", config = "plateiconx" },
  { text = L["Nameplate Icon Y Offset"], default = "-7", type = "text", config = "plateicony" },

  { text = L["Compass Bar"], default = nil, type = "header" },
  { text = L["Enable Compass Bar"], desc = L["Quest directions on a bar at the top of the screen"], tip = L["A heading strip across the top of the screen showing which way your objectives lie, like a compass. Shift and drag it to move it."], default = "0", type = "checkbox", config = "compass" },
  { text = L["Hide When Empty"], desc = L["Hide the bar when there is nothing to point at"], tip = L["In a dungeon your position on the map is unknown, so no bearing can be drawn and the bar would show only cardinal letters. This hides it instead. Turn it off to keep a plain compass at all times."], default = "1", type = "checkbox", config = "compassautohide" },
  { text = L["Bar Width"], default = "420", type = "text", config = "compasswidth" },
  { text = L["Bar Scale"], default = "1", type = "text", config = "compassscale" },
  { text = L["Metric Distances (meters)"], default = "0", type = "checkbox", config = "compassmetric" },
  { text = L["Show Available Quests"], default = "1", type = "checkbox", config = "compassavail" },
  { text = L["Show Quest Turn-Ins"], default = "1", type = "checkbox", config = "compassturnin" },
  { text = L["Show Dungeon Entrances"], default = "0", type = "checkbox", config = "compassdungeon" },
  { text = L["Show Rare Spawns"], desc = L["Ambient rare mob spawn points from the database"], default = "0", type = "checkbox", config = "compassrares" },
  -- Utility POIs (phase B3): a row cluster INSIDE the Compass Bar section,
  -- not a sidebar section of its own -- two rows do not carry a tab, and the
  -- In-world Pins insertion below anchors on compasscap staying this
  -- section's last row. These govern only the AMBIENT mode; the minimap
  -- tracking mirror and /way flight|mail|inn|repair work regardless.
  { text = L["Show Utility POIs"], desc = L["Ambient flight, mail, inn and repair markers"], tip = L["Always mark flight masters, mailboxes, innkeepers and repair vendors, whatever your minimap tracking is set to. Combine with the city option below to keep it to capitals."], default = "0", type = "checkbox", config = "compasspoi" },
  { text = L["Utility POIs Only In Cities"], desc = L["Ambient utility POIs only inside capital cities"], default = "1", type = "checkbox", config = "poicityonly" },
  { text = L["Mirror Minimap Tracking"], desc = L["Also show the POI class your minimap is tracking"], tip = L["When you set your minimap tracking to flight masters, mailboxes, innkeepers or repair, also mark those in the compass and the world. Off by default so nothing appears that you did not ask for."], default = "0", type = "checkbox", config = "poimirror" },
  { text = L["Show Objective Description"], default = "1", type = "checkbox", config = "compassdesc" },
  { text = L["Marker Cap"], desc = L["4 to 12 markers, default 8"], tip = L["How many markers the compass may show at once. The nearest ones win, so a lower number keeps it readable in a crowded zone."], default = "8", type = "text", config = "compasscap" },

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
-- navsize/multi/multicap/multibeam, so the section header comes first.
if type(WorldToScreen) == "function" then
  for i = 1, getn(pfQuest_defconfig) do
    if pfQuest_defconfig[i].config == "compasscap" then
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Party Pin Minimum Distance"], desc = L["Yards, hides party pins closer than this, dead members always show"], default = "30", type = "text", config = "pinspartymin" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Show Party Members"], desc = L["Nearby party members, dead ones get a beam and distance"], tip = L["Marks your party in the world, in class colours. A dead member gets a beam and a distance so you can find the body to resurrect. This works inside dungeons, where the map does not."], default = "0", type = "checkbox", config = "pinsparty" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Show Dungeon Entrance Pins"], desc = L["Meeting stones join the extra pins"], default = "0", type = "checkbox", config = "pinsdungeon" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Multi Waypoint Beams"], desc = L["Part of the multiple waypoints experiment"], default = "1", type = "checkbox", config = "pinsmultibeam" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Multi Waypoint Cap"], desc = L["1 to 8 extra pins, default 4"], default = "4", type = "text", config = "pinsmulticap" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Show Multiple Waypoints"], desc = L["Experimental, adds pins for nearby quest markers"], tip = L["Beyond the single quest you are following, also mark other nearby objectives, quest givers and turn-ins in the world. Useful when clearing an area, noisy when following one quest."], default = "0", type = "checkbox", config = "pinsmulti" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Extras"], type = "group" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Navigator Orbit Radius"], desc = L["How far from screen centre the arrow sits"], tip = L["Distance in pixels between the screen centre and the off-screen arrow. Larger pushes it out toward the edges."], default = "140", type = "text", config = "pinsnavradius" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Navigator Size"], desc = L["Percent, 100 is the default size"], tip = L["Size of the off-screen arrow only. The world marker has its own Pin Size setting."], default = "100", type = "text", config = "pinsnavsize" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Show Off-screen Arrow"], desc = L["The chevron that orbits the screen centre"], tip = L["When the target is behind you or off screen, an arrow orbits the screen centre pointing at it. Turn this off if you only want the marker itself, visible when you are looking at it."], default = "1", type = "checkbox", config = "pinsnav" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Off-screen Arrow"], type = "group" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pin Glow"], desc = L["Percent, 0 turns the halo off"], tip = L["The soft halo behind each marker. It gives the marker depth against bright ground. Set 0 for a completely flat marker."], default = "100", type = "text", config = "pinsglow" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Glow"], type = "group" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Beam Length"], desc = L["Percent, 100 reaches the top of the screen"], tip = L["How tall the beam is. It also grows with distance, so a far target has a taller beam than a near one."], default = "100", type = "text", config = "pinsbeamlength" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Beam Width"], desc = L["Percent, 100 is the default thickness"], default = "100", type = "text", config = "pinsbeamwidth" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pin Light Beam"], tip = L["The vertical shaft of light above the marker. It is what makes a target visible across a zone, over buildings and terrain."], default = "1", type = "checkbox", config = "pinsbeam" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Beam"], type = "group" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pinpoint Size"], default = "100", type = "text", config = "pinspointsize" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pin Opacity"], default = "100", type = "text", config = "pinsopacity" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Maximum Pin Scale"], desc = L["Percent, the size cap up close"], tip = L["Markers grow as you approach and shrink with distance. This is the ceiling, reached when the target is right in front of you."], default = "150", type = "text", config = "pinsmaxscale" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Minimum Pin Scale"], desc = L["Percent, the size floor far away"], tip = L["The floor of that same scaling, so a distant marker never shrinks to nothing."], default = "50", type = "text", config = "pinsminscale" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pin Size"], desc = L["Percent, 100 is the default size"], default = "100", type = "text", config = "pinssize" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Pylon Color"], desc = L["Empty follows the theme"], default = "", type = "color", config = "pinscolor" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Marker"], type = "group" })
      table.insert(pfQuest_defconfig, i + 1,
        { text = L["Enable Waypoint Pins"], desc = L["Needs the WorldAPI DLL (WorldToScreen)"], tip = L["Draws your current quest target in the 3D world as a marker with a light beam, the way modern WoW does. Requires a client with the WorldAPI DLL installed; without it this does nothing at all."], default = "0", type = "checkbox", config = "pins" })
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
pfQuestConfig.title:SetText("|cff33ffccpf|cffffffffQuest|r |cFF888888Reforged|r " .. L["Config"])

pfQuestConfig.close = CreateFrame("Button", "pfQuestConfigClose", pfQuestConfig)
pfQuestConfig.close:SetPoint("TOPRIGHT", -5, -5)
pfQuestConfig.close:SetHeight(20)
pfQuestConfig.close:SetWidth(20)
pfQuestConfig.close.texture = pfQuestConfig.close:CreateTexture("pfQuestionDialogCloseTex")
pfQuestConfig.close.texture:SetTexture(pfQuestConfig.path .. "\\compat\\close")
pfQuestConfig.close.texture:ClearAllPoints()
pfQuestConfig.close.texture:SetPoint("TOPLEFT", pfQuestConfig.close, "TOPLEFT", 4, -4)
pfQuestConfig.close.texture:SetPoint("BOTTOMRIGHT", pfQuestConfig.close, "BOTTOMRIGHT", -4, 4)

pfQuestConfig.close.texture:SetVertexColor(0.8, 0.3, 0.3, 1)
pfQuestConfig.close:SetScript("OnEnter", function()
  this.texture:SetVertexColor(1, 0.35, 0.35, 1)
end)
pfQuestConfig.close:SetScript("OnLeave", function()
  this.texture:SetVertexColor(0.8, 0.3, 0.3, 1)
end)
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
pfQuestConfig.welcome.text:SetFont(pfUI.font_default, pfUI_config.global.font_size)
pfQuestConfig.welcome.text:SetText(L["Welcome Screen"])
pfUI.api.CreateBackdrop(pfQuestConfig.welcome, nil, true)
pfQuestConfig.welcome:SetScript("OnEnter", function()
  local a = (pfQuestTheme and pfQuestTheme.accent) or { 0.2, 1, 0.8 }
  this.text:SetTextColor(a[1], a[2], a[3], 1)
end)
pfQuestConfig.welcome:SetScript("OnLeave", function()
  this.text:SetTextColor(1, 1, 1, 1)
end)

pfQuestConfig.save = CreateFrame("Button", "pfQuestConfigReload", pfQuestConfig)
pfQuestConfig.save:SetWidth(160)
pfQuestConfig.save:SetHeight(28)
pfQuestConfig.save:SetPoint("BOTTOMRIGHT", -10, 10)
pfQuestConfig.save:SetScript("OnClick", ReloadUI)
pfQuestConfig.save.text = pfQuestConfig.save:CreateFontString("Caption", "LOW", "GameFontWhite")
pfQuestConfig.save.text:SetAllPoints(pfQuestConfig.save)
pfQuestConfig.save.text:SetFont(pfUI.font_default, pfUI_config.global.font_size)
pfQuestConfig.save.text:SetText(L["Save & Close"])
pfUI.api.CreateBackdrop(pfQuestConfig.save, nil, true)
pfQuestConfig.save:SetScript("OnEnter", function()
  local a = (pfQuestTheme and pfQuestTheme.accent) or { 0.2, 1, 0.8 }
  this.text:SetTextColor(a[1], a[2], a[3], 1)
end)
pfQuestConfig.save:SetScript("OnLeave", function()
  this.text:SetTextColor(1, 1, 1, 1)
end)

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

-- Reforged: the settings window, rebuilt in pfUI's own idiom (pfUI
-- modules/gui.lua, shagu). The previous renderer flowed every row straight
-- onto the window with no scroll frame, so the window had to grow to fit the
-- tallest section and each sidebar entry was a SkinButton -- a bordered,
-- beveled box per item, which is what made it read as dated next to pfUI.
--
-- What pfUI actually does, and what this now does:
--   * navigation entries are FLAT: a background texture plus a label. Active
--     is expressed in COLOR (accent text over a horizontal gradient), never
--     with a border. CreateTabFrame/CreateArea, gui.lua:446-517.
--   * every pane owns a scroll frame, and its contents are built lazily on
--     first show (gui.lua:505-513), so the window size is fixed and a section
--     may be any length.
--   * widget chrome is CreateBackdrop, values are accent-colored, and invalid
--     input turns red rather than being rejected (gui.lua:252-285).
--   * a search box filters across every section (pfUI's searchDB, gui.lua:9).
--
-- Deviation, deliberate: pfUI polls MouseIsOver in an OnUpdate per row to
-- drive the hover highlight, because vanilla's OnEnter misfired inside scroll
-- frames. MouseIsOver exists here (FrameXML/UIParent.lua:2794) but OnEnter/
-- OnLeave is reliable on 3.3.5a, and ~90 permanent OnUpdate handlers is
-- exactly what the performance playbook says not to ship.
-- Layout is DERIVED, never hardcoded in pixels. The first cut fixed these at
-- 22/13 and the rows overlapped on the maintainer's client: pfUI's font size
-- is a user setting (and the GW2 theme raises it), so a row sized for a 12pt
-- label has its hint line running into the row below at 14pt. Everything here
-- keys off the font instead, and the sidebar is measured from its widest
-- label rather than guessed -- "Database & Advanced" was overflowing into the
-- pane at the old fixed 132.
local fontsize = (pfUI_config and pfUI_config.global and pfUI_config.global.font_size) or 12
local tabheight = max(22, fontsize + 10)
local rowheight = max(24, fontsize + 12)
local descheight = max(14, fontsize + 2)
local sidebarwidth = 132   -- floor; measured up from the widest section name
-- the control gutter is reserved on EVERY row, so a label or a hint can never
-- run underneath the value box on its right -- that overlap survived the
-- first layout fix because only the VERTICAL metrics were derived
local gutter = 108
local panewidth = 470
local topoffset = 58
local footer = 34

local configframes = {}
local groupframes = {}
local sections = {}
local searchText = ""

-- accent, resolved once per call site: the theme swaps it (GW2 UI installs a
-- gold palette), so it is never hardcoded teal the way upstream can afford to.
local function accent()
  return (pfQuestTheme and pfQuestTheme.accent) or { 0.2, 1, 0.8 }
end

function pfQuestConfig:ShowSection(index)
  local a = accent()
  for i = 1, getn(sections) do
    local active = (i == index)
    local s = sections[i]
    if s.pane then
      if active then s.pane:Show() else s.pane:Hide() end
    end
    if s.tab then
      if active then
        s.tab.text:SetTextColor(a[1], a[2], a[3], 1)
        s.tab.bg:SetTexture(a[1], a[2], a[3], 0.10)
        s.tab.mark:Show()
      else
        s.tab.text:SetTextColor(1, 1, 1, 1)
        s.tab.bg:SetTexture(0, 0, 0, 0)
        s.tab.mark:Hide()
      end
    end
  end

  if sections[index] then
    pfQuestConfig.sectiontitle:SetText(sections[index].name)
    pfQuestConfig:UpdateMatchCount(index)
    pfQuestConfig.activesection = index
  end
end

-- Relayout one section's visible rows from the top of its scroll child. Called
-- on build and on every search keystroke; hidden rows take no vertical space,
-- which is what makes a filtered pane read as a short list rather than a long
-- one full of gaps.
local function LayoutSection(s)
  -- A group label owns the rows beneath it up to the next label. Under a
  -- search it has to disappear with them: a lone "BEAM" heading over nothing
  -- reads as a bug. Walk backwards so each label already knows whether
  -- anything under it survived.
  local live = false
  for j = getn(s.rows), 1, -1 do
    local row = s.rows[j]
    if row.isgroup then
      row.filtered = (not live) or nil
      live = false
    elseif not row.filtered then
      live = true
    end
  end

  local y = 0
  local shown = 0
  for j = 1, getn(s.rows) do
    local row = s.rows[j]
    if row.filtered then
      row:Hide()
    else
      row:Show()
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", s.content, "TOPLEFT", 0, -y)
      row:SetWidth(panewidth - 16)
      y = y + row:GetHeight()
      -- group labels are chrome, not settings: they must not count toward
      -- "4 of 19 match", or the number stops meaning anything
      if not row.isgroup then shown = shown + 1 end
    end
  end
  -- the scroll child must be at least as tall as its contents or the range
  -- stays zero and the wheel does nothing
  s.content:SetHeight(max(y, 1))
  s.shown = shown
  if s.empty then
    if shown == 0 then s.empty:Show() else s.empty:Hide() end
  end
end

-- "4 of 19 settings match" beside the section title. A search that hides rows
-- without saying how many it found leaves the player wondering whether the
-- section is short or the filter ate it.
function pfQuestConfig:UpdateMatchCount(index)
  local s = sections[index]
  if not s or not pfQuestConfig.matchcount then return end
  if not searchText or searchText == "" then
    pfQuestConfig.matchcount:SetText("")
    return
  end
  local total = 0
  for j = 1, getn(s.rows) do
    if not s.rows[j].isgroup then total = total + 1 end
  end
  pfQuestConfig.matchcount:SetText(format(L["%d of %d settings match"], s.shown or 0, total))
end

-- pick the matched run out of the label. Case is preserved -- the query is
-- lowercased for the search, so the ORIGINAL substring is spliced back in
-- rather than the typed one, or "BEAM" would come back as "beam".
local function Highlight(caption, text, query, a)
  if not query or query == "" then
    caption:SetText(text)
    return
  end
  local at = strfind(strlower(text), query, 1, true)
  if not at then
    caption:SetText(text)
    return
  end
  local stop = at + strlen(query) - 1
  caption:SetText(strsub(text, 1, at - 1)
    .. format("|cff%02x%02x%02x", a[1] * 255, a[2] * 255, a[3] * 255)
    .. strsub(text, at, stop) .. "|r"
    .. strsub(text, stop + 1))
end

function pfQuestConfig:ApplySearch(text)
  text = text and strlower(text) or ""
  searchText = text
  local a = accent()
  for i = 1, getn(sections) do
    local s = sections[i]
    for j = 1, getn(s.rows) do
      local row = s.rows[j]
      row.filtered = (text ~= "" and not strfind(row.haystack, text, 1, true)) or nil
      if not row.isgroup and row.labeltext then
        Highlight(row.caption, row.labeltext, text, a)
      end
    end
    LayoutSection(s)
    -- a section with nothing left to show dims, so the sidebar answers "is it
    -- in here?" without clicking through every entry
    if s.tab and i ~= pfQuestConfig.activesection then
      if s.shown == 0 then
        s.tab.text:SetTextColor(0.4, 0.4, 0.4, 1)
      else
        s.tab.text:SetTextColor(1, 1, 1, 1)
      end
    end
  end
  -- jump to the first section that still has a hit, so typing lands somewhere
  -- useful instead of leaving you on an empty pane
  if text ~= "" then
    local cur = sections[pfQuestConfig.activesection]
    if not cur or cur.shown == 0 then
      for i = 1, getn(sections) do
        if sections[i].shown > 0 then
          pfQuestConfig:ShowSection(i)
          break
        end
      end
    end
  end
  if pfQuestConfig.activesection and sections[pfQuestConfig.activesection] then
    local t = sections[pfQuestConfig.activesection].tab
    if t then t.text:SetTextColor(a[1], a[2], a[3], 1) end
    pfQuestConfig:UpdateMatchCount(pfQuestConfig.activesection)
  end
end

-- Emulated backdrops (standalone, no real pfUI installed) draw a Blizzard
-- edge that renders too heavy at native size, so pfQuest inflates every input
-- and scales it back down to thin the border out. The SEARCH box was built
-- outside the row loop and never got that treatment, so it wore a visibly
-- thicker border than every value box in the pane -- the one control that
-- escaped the restyle.
--
-- Sized from the DESIRED visual box rather than the row loop's /0.6, which
-- ends up 1.33x its nominal width; the search has to fit the sidebar exactly.
local function ScaleInput(input, w, h)
  if pfUI.api.emulated then
    input:SetScale(0.8)
    input:SetWidth(w / 0.8)
    input:SetHeight(h / 0.8)
    if input.SetTextInsets then input:SetTextInsets(8, 8, 8, 8) end
  else
    input:SetWidth(w)
    input:SetHeight(h)
  end
end

-- one navigation entry plus its scrolling pane, pfUI's CreateTabFrame +
-- CreateArea collapsed into a single call because pfQuest has one nav level,
-- not two
local function CreateSection(index, name)
  local s = { name = name, rows = {} }

  local tab = CreateFrame("Button", "pfQuestConfigTab" .. index, pfQuestConfig)
  tab:SetID(index)
  tab:SetHeight(tabheight)
  tab:SetPoint("TOPLEFT", 8, -(topoffset - 4) - (index - 1) * tabheight)
  tab.bg = tab:CreateTexture(nil, "BACKGROUND")
  tab.bg:SetAllPoints()
  tab.bg:SetTexture(0, 0, 0, 0)
  tab.mark = tab:CreateTexture(nil, "ARTWORK")
  tab.mark:SetTexture(accent()[1], accent()[2], accent()[3], 1)
  tab.mark:SetWidth(2)
  tab.mark:SetPoint("TOPLEFT", 0, 0)
  tab.mark:SetPoint("BOTTOMLEFT", 0, 0)
  tab.mark:Hide()
  tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  tab.text:SetFont(pfUI.font_default, fontsize)
  tab.text:SetPoint("LEFT", 8, 0)
  tab.text:SetJustifyH("LEFT")
  tab.text:SetText(name)
  -- widest label wins: the sidebar is measured, not guessed
  sidebarwidth = max(sidebarwidth, tab.text:GetStringWidth() + 30)
  tab:SetScript("OnClick", function()
    pfQuestConfig:ShowSection(this:GetID())
  end)
  tab:SetScript("OnEnter", function()
    if pfQuestConfig.activesection ~= this:GetID() then
      local a = accent()
      this.text:SetTextColor(a[1], a[2], a[3], 0.7)
    end
  end)
  tab:SetScript("OnLeave", function()
    if pfQuestConfig.activesection ~= this:GetID() then
      this.text:SetTextColor(1, 1, 1, 1)
    end
  end)
  s.tab = tab

  local pane = CreateFrame("Frame", nil, pfQuestConfig)
  pane:Hide()
  s.pane = pane

  s.scroll = pfUI.api.CreateScrollFrame(nil, pane)
  s.scroll:SetPoint("TOPLEFT", 0, 0)
  s.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
  s.content = pfUI.api.CreateScrollChild(nil, s.scroll)
  s.content:SetWidth(panewidth - 16)

  -- search can empty a pane; say so rather than showing a blank rectangle
  s.empty = pane:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  s.empty:SetFont(pfUI.font_default, pfUI_config.global.font_size)
  s.empty:SetPoint("TOPLEFT", 4, -6)
  s.empty:SetTextColor(0.5, 0.5, 0.5, 1)
  s.empty:SetText(L["No matching settings"])
  s.empty:Hide()

  return s
end

-- a group label inside a section: small, uppercase, accent-dim, with a rule
-- under it. In-world Pins carries 19 settings; nineteen flat rows is a list
-- you scan, five labelled groups is one you navigate.
local function CreateGroup(s, data)
  local frame = CreateFrame("Frame", nil, s.content)
  frame:SetHeight(max(22, fontsize + 10))
  frame.isgroup = true
  frame.haystack = ""
  groupframes[data.text] = frame
  table.insert(s.rows, frame)

  local a = accent()
  frame.caption = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  frame.caption:SetFont(pfUI.font_default, max(9, fontsize - 3))
  frame.caption:SetPoint("BOTTOMLEFT", 6, 5)
  frame.caption:SetJustifyH("LEFT")
  frame.caption:SetTextColor(a[1], a[2], a[3], 0.62)
  frame.caption:SetText(strupper(data.text))

  frame.rule = frame:CreateTexture(nil, "BORDER")
  frame.rule:SetTexture(1, 1, 1, 0.05)
  frame.rule:SetHeight(1)
  frame.rule:SetPoint("BOTTOMLEFT", 6, 1)
  frame.rule:SetPoint("BOTTOMRIGHT", -6, 1)

  return frame
end

-- a single settings row: label (plus optional hint line) on the left, the
-- widget right-aligned. The whole row highlights on hover, pfUI-style.
local function CreateRow(s, data)
  local frame = CreateFrame("Frame", nil, s.content)
  frame:SetHeight(rowheight)
  frame:EnableMouse(true)
  configframes[data.text] = frame
  table.insert(s.rows, frame)

  -- what the search box matches against: label and hint, never the config key
  -- (the player is searching for words they can see)
  frame.haystack = strlower(data.text .. " " .. (data.desc or ""))

  frame.hover = frame:CreateTexture(nil, "BACKGROUND")
  frame.hover:SetAllPoints()
  frame.hover:SetTexture(1, 1, 1, 0.05)
  frame.hover:Hide()

  -- text stops where the control gutter starts, on both lines
  local textwidth = panewidth - 16 - gutter

  frame.caption = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  frame.caption:SetFont(pfUI.font_default, fontsize)
  frame.caption:SetJustifyH("LEFT")
  frame.caption:SetText(data.text)
  frame.caption:SetWidth(textwidth)
  frame.labeltext = data.text -- the clean label, for the search highlighter

  if data.desc then
    frame.tall = true
    frame.caption:SetPoint("TOPLEFT", 6, -4)
    frame.desc = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    frame.desc:SetFont(pfUI.font_default, fontsize - 2)
    -- clears the caption's own line height, whatever the font size is
    frame.desc:SetPoint("TOPLEFT", 6, -(fontsize + 7))
    frame.desc:SetJustifyH("LEFT")
    frame.desc:SetTextColor(0.55, 0.55, 0.55, 1)
    frame.desc:SetText(data.desc)
    -- MEASURE FIRST, THEN CONSTRAIN. A hint longer than the gutter leaves it
    -- wraps to a second line, and the row has to grow to hold it or the next
    -- row lands on top of the wrap. GetStringWidth reports the unwrapped
    -- width only while the fontstring has no width of its own, so the order
    -- here is load-bearing.
    local lines = 1
    local sw = frame.desc:GetStringWidth() or 0
    if sw > textwidth and textwidth > 0 then
      lines = ceil(sw / textwidth)
    end
    frame.desc:SetWidth(textwidth)
    frame:SetHeight(rowheight + descheight * lines)
  else
    frame.caption:SetPoint("LEFT", 6, 0)
    frame:SetHeight(rowheight)
  end

  -- tooltip: the hint line is one sentence, and several of these settings
  -- need more than that to be usable by anyone who did not write them
  frame.tip = data.tip
  frame.tipTitle = data.text
  frame:SetScript("OnEnter", function()
    this.hover:Show()
    if this.tip then
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText(this.tipTitle, 1, 1, 1)
      GameTooltip:AddLine(this.tip, 0.8, 0.8, 0.8, 1)
      GameTooltip:Show()
    end
  end)
  frame:SetScript("OnLeave", function()
    this.hover:Hide()
    if this.tip then GameTooltip:Hide() end
  end)

  return frame
end

function pfQuestConfig:CreateConfigEntries(config)
  local section = nil

  -- numeric walk, not pairs: a header opens the section its following rows
  -- belong to, so ORDER is load-bearing here and pairs() does not promise it
  for i = 1, getn(config) do
    local data = config[i]
    if data.type == "header" then
      section = CreateSection(getn(sections) + 1, data.text)
      table.insert(sections, section)

    elseif data.type == "group" and section then
      CreateGroup(section, data)

    elseif data.type and section then
      local frame = CreateRow(section, data)

      if data.type == "checkbox" then
        frame.input = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        frame.input:SetNormalTexture("")
        frame.input:SetPushedTexture("")
        frame.input:SetHighlightTexture("")
        pfUI.api.CreateBackdrop(frame.input, nil, true)
        frame.input:SetCheckedTexture("Interface\\Buttons\\WHITE8X8")
        local tick = frame.input:GetCheckedTexture()
        if tick then
          local a = accent()
          tick:SetVertexColor(a[1], a[2], a[3], 0.9)
          tick:ClearAllPoints()
          tick:SetPoint("TOPLEFT", frame.input, "TOPLEFT", 3, -3)
          tick:SetPoint("BOTTOMRIGHT", frame.input, "BOTTOMRIGHT", -3, 3)
        end
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

        -- the whole row is the hit target, not just the 16px box: an overlay
        -- button forwards the click through :Click() so the label toggles too
        frame.hit = CreateFrame("Button", nil, frame)
        frame.hit:SetAllPoints(frame)
        frame.hit:SetFrameLevel(frame.input:GetFrameLevel() + 1)
        frame.hit.input = frame.input
        frame.hit.row = frame
        frame.hit:SetScript("OnClick", function()
          this.input:Click()
        end)
        frame.hit:SetScript("OnEnter", function()
          local a = accent()
          this.row.caption:SetTextColor(a[1], a[2], a[3], 1)
          this.row.hover:Show()
        end)
        frame.hit:SetScript("OnLeave", function()
          this.row.caption:SetTextColor(1, 1, 1, 1)
          this.row.hover:Hide()
        end)

      elseif data.type == "text" then
        local a = accent()
        frame.input = CreateFrame("EditBox", nil, frame)
        frame.input:SetTextColor(a[1], a[2], a[3], 1)
        frame.input:SetJustifyH("RIGHT")
        frame.input:SetTextInsets(5, 5, 5, 5)
        frame.input:SetWidth(50)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -8, 0)
        frame.input:SetFontObject(GameFontNormal)
        frame.input:SetAutoFocus(false)
        frame.input:SetScript("OnEscapePressed", function()
          this:ClearFocus()
        end)
        frame.input.config = data.config
        frame.input.numeric = tonumber(data.default) and true or nil
        frame.input:SetText(pfQuest_config[data.config])
        -- pfUI's rule: never reject the keystroke, colour it. A half-typed
        -- number is not an error, it is a number you are not finished with.
        frame.input:SetScript("OnTextChanged", function()
          pfQuest_config[this.config] = this:GetText()
          local a2 = accent()
          if this.numeric and not tonumber(this:GetText()) then
            this:SetTextColor(1, 0.3, 0.3, 1)
          else
            this:SetTextColor(a2[1], a2[2], a2[3], 1)
          end
        end)
        pfUI.api.CreateBackdrop(frame.input, nil, true)

      elseif data.type == "color" then
        -- Opens the NATIVE 3.3.5a color picker: ColorPickerFrame is stock
        -- FrameXML on this client (.func fires on OnColorSelect, live while
        -- dragging; .cancelFunc receives previousValues), and OpenColorPicker
        -- is the stock helper that fills those fields.
        local config = data.config
        local function current()
          local p = pfQuest and pfQuest.pins
          local c = p and p.ParseColor and p.ParseColor(pfQuest_config[config])
          return c or accent()
        end
        frame.input = CreateFrame("Button", nil, frame)
        frame.input:SetWidth(16)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -8, 0)
        pfUI.api.CreateBackdrop(frame.input, nil, true)
        frame.input.swatch = frame.input:CreateTexture(nil, "OVERLAY")
        frame.input.swatch:SetPoint("TOPLEFT", frame.input, "TOPLEFT", 2, -2)
        frame.input.swatch:SetPoint("BOTTOMRIGHT", frame.input, "BOTTOMRIGHT", -2, 2)
        local function refresh()
          local c = current()
          frame.input.swatch:SetTexture(c[1], c[2], c[3], 1)
        end
        frame.input.RefreshSwatch = refresh
        refresh()
        frame.input:SetScript("OnClick", function()
          local c = current()
          local prevRaw = pfQuest_config[config]
          OpenColorPicker({
            r = c[1], g = c[2], b = c[3],
            swatchFunc = function()
              local r, g, b = ColorPickerFrame:GetColorRGB()
              pfQuest_config[config] = string.format("%.3f,%.3f,%.3f", r, g, b)
              refresh()
            end,
            cancelFunc = function()
              -- restore the RAW previous value: "" (theme-follow) must come
              -- back as "", never the theme color baked into a string
              pfQuest_config[config] = prevRaw
              refresh()
            end,
          })
        end)
        frame.reset = CreateFrame("Button", nil, frame)
        frame.reset:SetWidth(42)
        frame.reset:SetHeight(16)
        frame.reset:SetPoint("RIGHT", frame.input, "LEFT", -6, 0)
        frame.reset.text = frame.reset:CreateFontString(nil, "OVERLAY", "GameFontWhite")
        frame.reset.text:SetAllPoints(frame.reset)
        frame.reset.text:SetFont(pfUI.font_default, pfUI_config.global.font_size)
        frame.reset.text:SetText(L["Reset"])
        frame.reset.text:SetTextColor(0.7, 0.7, 0.7, 1)
        frame.reset:SetScript("OnEnter", function()
          local a = accent()
          this.text:SetTextColor(a[1], a[2], a[3], 1)
        end)
        frame.reset:SetScript("OnLeave", function()
          this.text:SetTextColor(0.7, 0.7, 0.7, 1)
        end)
        frame.reset:SetScript("OnClick", function()
          pfQuest_config[config] = ""
          refresh()
        end)

      elseif data.type == "slider" then
        local minval, maxval = data.min, data.max
        local config = data.config
        local default = data.default
        local step = data.step or 0.1
        local fmt = data.format or "%.1fx"
        local a = accent()

        frame.input = CreateFrame("Slider", nil, frame)
        frame.input:SetOrientation("HORIZONTAL")
        frame.input:SetWidth(60)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -8, 0)
        frame.input:EnableMouse(true)
        frame.input:SetMinMaxValues(minval, maxval)
        frame.input:SetValueStep(step)
        frame.input:SetThumbTexture("Interface\\BUTTONS\\WHITE8X8")
        frame.input.thumb = frame.input:GetThumbTexture()
        frame.input.thumb:SetHeight(14)
        frame.input.thumb:SetWidth(8)
        frame.input.thumb:SetTexture(a[1], a[2], a[3], 0.5)
        pfUI.api.CreateBackdrop(frame.input, nil, true)
        frame.input.config = config

        frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
        frame.value:SetFont(pfUI.font_default, pfUI_config.global.font_size)
        frame.value:SetPoint("RIGHT", frame.input, "LEFT", -6, 0)
        frame.value:SetTextColor(a[1], a[2], a[3], 1)

        local val = tonumber(pfQuest_config[config]) or tonumber(default) or 1
        frame.input:SetValue(val)
        frame.value:SetText(string.format(fmt, val))

        frame.input.updating = false
        frame.input:SetScript("OnValueChanged", function()
          if this.updating then return end
          this.updating = true

          local v = this:GetValue()
          v = max(minval, min(maxval, v))
          v = floor(v / step + 0.5) * step

          -- snap the thumb onto the stored step so position, label and saved
          -- config stay in sync
          this:SetValue(v)
          pfQuest_config[this.config] = tostring(v)
          frame.value:SetText(string.format(fmt, v))

          -- live-apply: the arrow reads its scale, the map pins their size
          if pfQuest and pfQuest.route and pfQuest.route.arrow then
            pfQuest.route.arrow:ApplyScale()
          end
          if pfMap and pfMap.ResizeNodes then
            pfMap:ResizeNodes()
          end

          this.updating = false
        end)

      elseif data.type == "button" and data.func then
        frame.input = CreateFrame("Button", nil, frame)
        frame.input:SetWidth(44)
        frame.input:SetHeight(16)
        frame.input:SetPoint("RIGHT", -8, 0)
        frame.input:SetScript("OnClick", data.func)
        frame.input.text = frame.input:CreateFontString(nil, "OVERLAY", "GameFontWhite")
        frame.input.text:SetAllPoints(frame.input)
        frame.input.text:SetFont(pfUI.font_default, pfUI_config.global.font_size)
        frame.input.text:SetText("OK")
        pfUI.api.CreateBackdrop(frame.input, nil, true)
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
    end
  end

  -- ---- window chrome -------------------------------------------------------
  local a = accent()

  -- search: one box over every section, pfUI's searchDB idea without the
  -- table -- each row already carries its own haystack
  pfQuestConfig.search = CreateFrame("EditBox", nil, pfQuestConfig)
  pfQuestConfig.search:SetPoint("TOPLEFT", 10, -32)
  ScaleInput(pfQuestConfig.search, sidebarwidth - 14, 18)
  pfQuestConfig.search:SetTextInsets(5, 5, 5, 5)
  pfQuestConfig.search:SetFontObject(GameFontNormal)
  pfQuestConfig.search:SetTextColor(1, 1, 1, 1)
  pfQuestConfig.search:SetAutoFocus(false)
  pfUI.api.CreateBackdrop(pfQuestConfig.search, nil, true)
  pfQuestConfig.search.hint = pfQuestConfig.search:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  pfQuestConfig.search.hint:SetFont(pfUI.font_default, pfUI_config.global.font_size)
  pfQuestConfig.search.hint:SetPoint("LEFT", 5, 0)
  pfQuestConfig.search.hint:SetTextColor(0.4, 0.4, 0.4, 1)
  pfQuestConfig.search.hint:SetText(L["Search"])
  pfQuestConfig.search:SetScript("OnTextChanged", function()
    if this:GetText() == "" then this.hint:Show() else this.hint:Hide() end
    pfQuestConfig:ApplySearch(this:GetText())
  end)
  pfQuestConfig.search:SetScript("OnEscapePressed", function()
    this:SetText("")
    this:ClearFocus()
  end)

  -- vertical rule between sidebar and pane
  pfQuestConfig.separator = pfQuestConfig:CreateTexture(nil, "BORDER")
  pfQuestConfig.separator:SetTexture(a[1], a[2], a[3], 0.15)
  pfQuestConfig.separator:SetWidth(1)
  pfQuestConfig.separator:SetPoint("TOPLEFT", sidebarwidth, -topoffset + 8)
  pfQuestConfig.separator:SetPoint("BOTTOMLEFT", sidebarwidth, footer + 6)

  -- active section title, ruled off from its rows
  pfQuestConfig.sectiontitle = pfQuestConfig:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  pfQuestConfig.sectiontitle:SetFont(pfUI.font_default, pfUI_config.global.font_size + 2)
  pfQuestConfig.sectiontitle:SetPoint("TOPLEFT", sidebarwidth + 12, -34)
  pfQuestConfig.sectiontitle:SetJustifyH("LEFT")
  pfQuestConfig.sectiontitle:SetTextColor(a[1], a[2], a[3], 1)

  pfQuestConfig.matchcount = pfQuestConfig:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  pfQuestConfig.matchcount:SetFont(pfUI.font_default, max(9, fontsize - 3))
  pfQuestConfig.matchcount:SetPoint("LEFT", pfQuestConfig.sectiontitle, "RIGHT", 8, -1)
  pfQuestConfig.matchcount:SetJustifyH("LEFT")
  pfQuestConfig.matchcount:SetTextColor(0.49, 0.49, 0.49, 1)

  pfQuestConfig.sectionline = pfQuestConfig:CreateTexture(nil, "BORDER")
  pfQuestConfig.sectionline:SetTexture(a[1], a[2], a[3], 0.25)
  pfQuestConfig.sectionline:SetHeight(1)
  pfQuestConfig.sectionline:SetPoint("TOPLEFT", sidebarwidth + 10, -topoffset - 6)
  pfQuestConfig.sectionline:SetPoint("TOPRIGHT", -10, -topoffset - 6)

  -- FINAL PASS. Every anchor that depends on the measured sidebar is applied
  -- here, not at section-build time: the width is only known once the last
  -- section name has been through GetStringWidth.
  pfQuestConfig:SetWidth(sidebarwidth + panewidth + 18)
  -- tall enough that the sidebar always fits and a section shows a useful
  -- number of rows before it has to scroll
  pfQuestConfig:SetHeight(max(topoffset + footer + 30 + getn(sections) * tabheight, 560))

  ScaleInput(pfQuestConfig.search, sidebarwidth - 14, 18)
  pfQuestConfig.separator:ClearAllPoints()
  pfQuestConfig.separator:SetPoint("TOPLEFT", sidebarwidth, -topoffset + 8)
  pfQuestConfig.separator:SetPoint("BOTTOMLEFT", sidebarwidth, footer + 6)
  pfQuestConfig.sectiontitle:ClearAllPoints()
  pfQuestConfig.sectiontitle:SetPoint("TOPLEFT", sidebarwidth + 12, -34)
  pfQuestConfig.sectionline:ClearAllPoints()
  pfQuestConfig.sectionline:SetPoint("TOPLEFT", sidebarwidth + 10, -topoffset - 6)
  pfQuestConfig.sectionline:SetPoint("TOPRIGHT", -10, -topoffset - 6)

  for i = 1, getn(sections) do
    local sec = sections[i]
    sec.tab:SetWidth(sidebarwidth - 12)
    sec.pane:SetPoint("TOPLEFT", sidebarwidth + 8, -topoffset - 18)
    sec.pane:SetPoint("BOTTOMRIGHT", -10, footer + 6)
    sec.content:SetWidth(panewidth - 16)
    LayoutSection(sec)
  end
  pfQuestConfig:ShowSection(1)
end

-- rows by caption. UpdateConfigEntries below walks this map, and it is also
-- the only handle anything outside this file has on a row: the section list
-- itself is a file-local.
function pfQuestConfig:GetRow(caption)
  return configframes[caption]
end

-- group labels are keyed separately from settings rows: they share the
-- caption namespace with nothing, and UpdateConfigEntries must never walk one
function pfQuestConfig:GetGroup(caption)
  return groupframes[caption]
end

function pfQuestConfig:UpdateConfigEntries()
  for _, data in pairs(pfQuest_defconfig) do
    if data.type and configframes[data.text] then
      if data.type == "checkbox" then
        configframes[data.text].input:SetChecked((pfQuest_config[data.config] == "1" and true or nil))
      elseif data.type == "text" then
        configframes[data.text].input:SetText(pfQuest_config[data.config])
      elseif data.type == "color" then
        local input = configframes[data.text].input
        if input.RefreshSwatch then
          input.RefreshSwatch()
        end
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
