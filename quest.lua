-- multi api compat
local compat = pfQuestCompat
local _, _, _, client = GetBuildInfo()
client = client or 11200
local _G = client == 11200 and getfenv(0) or _G

-- Performance: cache frequently-used globals
local pairs, ipairs, next = pairs, ipairs, next
local strfind = strfind
local format = string.format
local getn, insert, concat = table.getn, table.insert, table.concat
local tostring, tonumber, type = tostring, tonumber, type
local GetTime = GetTime
local UnitLevel = UnitLevel

pfQuest = CreateFrame("Frame")
pfQuest.icons = {}

-- Track which quests should be hidden because their zone header is collapsed.
-- collapsedQuestIDs[questid] = zoneName
--
-- Questid-keyed rather than zone-name-keyed because some quests appear under
-- a different zone header when their real zone header is collapsed (vanilla API
-- quirk). CollapseQuestHeader scans visible quests before the collapse takes
-- effect so the true membership is recorded before the API hides them.
pfQuest.collapsedQuestIDs = {}

local function questInPlayerZone(questid)
  local playerZone = pfMap and pfMap.playerZone
  if not playerZone or not pfMap.nodes or not pfMap.nodes["PFQUEST"] or not pfMap.nodes["PFQUEST"][playerZone] then
    return nil
  end

  for _, coordNode in pairs(pfMap.nodes["PFQUEST"][playerZone]) do
    for _, node in pairs(coordNode) do
      if (node.questid or node.title) == questid then
        return true
      end
    end
  end

  return nil
end

local function questAffectsCurrentZoneTracker(questid)
  local data = pfQuest.questlog and pfQuest.questlog[questid]
  -- Current Zone mode still shows watched off-zone quests at the top, so a
  -- collapse/expand on those quests must refresh the tracker too.
  if data and data.qlogid and IsQuestWatched(data.qlogid) then
    return true
  end

  return questInPlayerZone(questid)
end

local _CollapseQuestHeader = CollapseQuestHeader
CollapseQuestHeader = function(index)
  local title, _, _, header = compat.GetQuestLogTitle(index)
  if header and title then
    local affectsCurrentZoneTracker = nil
    -- Scan quests under this header and mark them collapsed by questid.
    -- Must be done before calling the real CollapseQuestHeader because
    -- after the collapse the quests disappear from GetQuestLogTitle.
    for qi = index + 1, 40 do
      local qtitle, _, _, qheader = compat.GetQuestLogTitle(qi)
      if qheader or not qtitle then break end
      for questid, data in pairs(pfQuest.questlog) do
        if data.title == qtitle then
          pfQuest.collapsedQuestIDs[questid] = title
          data.collapsed = true
          if not affectsCurrentZoneTracker and pfQuest_config["trackingmethod"] == 5
             and questAffectsCurrentZoneTracker(questid) then
            affectsCurrentZoneTracker = true
          end
          break
        end
      end
    end
    if pfQuest_config["trackingmethod"] == 5 then
      if affectsCurrentZoneTracker and pfQuest.tracker and pfQuest.tracker.RefreshZoneTracker then
        pfQuest.tracker.RefreshZoneTracker()
      end
    else
      pfMap.queue_update = GetTime()
    end
  end
  return _CollapseQuestHeader(index)
end

local _ExpandQuestHeader = ExpandQuestHeader
ExpandQuestHeader = function(index)
  local title, _, _, header = compat.GetQuestLogTitle(index)
  if header and title then
    if pfQuest.userClickingHeader then
      -- User explicitly expanded this zone: clear our collapsed tracking for it.
      -- Collect keys first to avoid modifying the table mid-iteration.
      local toRemove = {}
      local affectsCurrentZoneTracker = nil
      for questid, zone in pairs(pfQuest.collapsedQuestIDs) do
        if zone == title then
          toRemove[questid] = true
          if not affectsCurrentZoneTracker and pfQuest_config["trackingmethod"] == 5
             and questAffectsCurrentZoneTracker(questid) then
            affectsCurrentZoneTracker = true
          end
        end
      end
      for questid in pairs(toRemove) do
        pfQuest.collapsedQuestIDs[questid] = nil
        if pfQuest.questlog[questid] then
          pfQuest.questlog[questid].collapsed = false
        end
      end
      if pfQuest_config["trackingmethod"] == 5 then
        if affectsCurrentZoneTracker and pfQuest.tracker and pfQuest.tracker.RefreshZoneTracker then
          pfQuest.tracker.RefreshZoneTracker()
        end
      else
        pfMap.queue_update = GetTime()
      end
    end
    -- If not user-initiated (e.g. vanilla expanding a zone on quest accept/turn-in),
    -- leave collapsedQuestIDs intact. The QLU sync will re-apply data.collapsed from
    -- it after the subsequent QUEST_LOG_UPDATE, keeping collapsed quests off the tracker.
  end
  return _ExpandQuestHeader(index)
end

if client >= 30300 then
  pfQuest.dburl = "https://www.wowhead.com/wotlk/quest="
elseif client >= 20400 then
  pfQuest.dburl = "https://www.wowhead.com/tbc/quest="
else
  pfQuest.dburl = "https://www.wowhead.com/classic/quest="
end

function pfQuest:Debug(msg)
  -- only show debug output if enabled
  if not pfQuest_config.debug and pfQuest.debugwin then
    pfQuest.debugwin:Hide()
    return
  elseif not pfQuest_config.debug then
    return
  end

  if not pfQuest.debugwin then
    pfQuest.debugwin = CreateFrame("ScrollingMessageFrame", nil, UIParent)
    pfQuest.debugwin:SetWidth(320)
    pfQuest.debugwin:SetHeight(320)
    pfQuest.debugwin:SetPoint("RIGHT", -42, 0)
    local font = pfUI and pfUI.font_default or STANDARD_TEXT_FONT
    local size = tonumber(pfQuest_config["trackerfontsize"]) or 12
    pfQuest.debugwin:SetFont(font, size, "OUTLINE")
    pfQuest.debugwin:SetFading(false)
    pfQuest.debugwin:SetMaxLines(150)
    pfQuest.debugwin:SetJustifyH("RIGHT")
    pfQuest.debugwin:SetJustifyV("CENTER")
  end

  local font = pfUI and pfUI.font_default or STANDARD_TEXT_FONT
  local size = tonumber(pfQuest_config["trackerfontsize"]) or 12
  pfQuest.debugwin:SetFont(font, size, "OUTLINE")
  pfQuest.debugwin:AddMessage(msg)
  pfQuest.debugwin:Show()
end

function pfQuest:SortedPairs(t, index, reverse)
  -- collect the keys
  local keys = {}
  for k, v in pairs(t) do
    if v then
      keys[table.getn(keys) + 1] = k
    end
  end

  local order
  if reverse then
    order = function(t, a, b)
      return t[a][index] < t[b][index]
    end
  else
    order = function(t, a, b)
      return t[a][index] > t[b][index]
    end
  end
  table.sort(keys, function(a, b)
    return order(t, a, b)
  end)

  -- return the iterator function
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

pfQuest.queue = {}
pfQuest.queueCount = 0 -- Track queue size to avoid O(n) tsize() calls
pfQuest.abandon = ""
pfQuest.questlog = {}
pfQuest.questlog_tmp = {}

-- Helper to add to queue with count tracking
local function queueAdd(entry)
  insert(pfQuest.queue, entry)
  pfQuest.queueCount = pfQuest.queueCount + 1
end

local skillstate = ""
pfQuest:RegisterEvent("QUEST_WATCH_UPDATE")
pfQuest:RegisterEvent("QUEST_LOG_UPDATE")
pfQuest:RegisterEvent("QUEST_FINISHED")
pfQuest:RegisterEvent("PLAYER_LEVEL_UP")
pfQuest:RegisterEvent("PLAYER_ENTERING_WORLD")
pfQuest:RegisterEvent("SKILL_LINES_CHANGED")
pfQuest:RegisterEvent("ADDON_LOADED")
pfQuest:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if strsub(tostring(arg1), 1, 7) == "pfQuest" then
      -- Clean up legacy SavedVariable from an earlier version of this fix that
      -- accidentally stored collapsedZones in pfQuest_track, causing database.lua
      -- to crash when iterating that table as {query, meta} tracking pairs.
      if pfQuest_track and pfQuest_track.collapsedZones then
        pfQuest_track.collapsedZones = nil
      end

      -- Link collapsedQuestIDs to pfQuest_config so collapse state survives reload.
      -- The wrappers write to pfQuest.collapsedQuestIDs directly; since it is the
      -- same table as pfQuest_config.collapsedQuestIDs, the SavedVar stays in sync.
      if pfQuest_config then
        pfQuest_config.collapsedQuestIDs = pfQuest_config.collapsedQuestIDs or {}
        pfQuest.collapsedQuestIDs = pfQuest_config.collapsedQuestIDs
      end

      pfQuest:AddQuestLogIntegration()
      pfQuest:AddWorldMapIntegration()
      this.lock = GetTime() + 10
    else
      return
    end
  elseif event == "SKILL_LINES_CHANGED" then
    -- Use table.concat to avoid string concatenation garbage
    local skillParts = {}
    for i = 0, GetNumSkillLines() do
      skillParts[i + 1] = GetSkillLineInfo(i) or ""
    end
    local skills = concat(skillParts)

    -- update quest givers when new skills or
    -- professions became available
    if skills ~= skillstate then
      pfQuest.updateQuestGivers = true
      skillstate = skills
    end
  elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then
    pfQuest.updateQuestGivers = true
  else
    pfQuest.updateQuestLog = true
  end

  if event == "QUEST_LOG_UPDATE" then
    -- Keep data.collapsed in sync with collapsedQuestIDs. The wrappers update
    -- it directly on user action; this handles any edge cases where data.collapsed
    -- drifts (e.g. quest log rebuilt after a zone change).
    if pfQuest.questlog then
      local affectsCurrentZoneTracker = nil
      for questid, data in pairs(pfQuest.questlog) do
        local isCollapsed = pfQuest.collapsedQuestIDs[questid] and true or false
        if isCollapsed ~= (data.collapsed and true or false) then
          data.collapsed = isCollapsed
          if pfQuest_config["trackingmethod"] == 5 then
            if not affectsCurrentZoneTracker and questAffectsCurrentZoneTracker(questid) then
              affectsCurrentZoneTracker = true
            end
          else
            pfMap.queue_update = GetTime()
          end
        end
      end
      if pfQuest_config["trackingmethod"] == 5 and affectsCurrentZoneTracker
         and pfQuest.tracker and pfQuest.tracker.RefreshZoneTracker then
        pfQuest.tracker.RefreshZoneTracker()
      end
    end
    -- lock initial scan during incoming events
    if this.lock and this.lock > GetTime() then
      this.lock = GetTime() + 1.5
    end
  end
end)

pfQuest:SetScript("OnUpdate", function()
  if this.lock and this.lock > GetTime() then
    return
  end
  if not pfDatabase.localized then
    return
  end

  if (this.tick or 0.05) > GetTime() then
    return
  else
    this.tick = GetTime() + 0.05
  end

  -- check questlog each second
  if (this.qlogtick or 1) < GetTime() then
    local t0 = GetTime()
    if pfQuest:UpdateQuestlog() then
      pfQuest:Debug(format("Update Quest|cff33ffccLog|r [|cffff3333Tick|r] %.4fs", GetTime() - t0))
    end
    this.qlogtick = GetTime() + 1
  end

  if this.updateQuestLog == true and pfQuest.queueCount == 0 then
    local t0 = GetTime()
    pfQuest:UpdateQuestlog()
    pfQuest:Debug(format("Update Quest|cff33ffccLog %.4fs", GetTime() - t0))
    this.updateQuestLog = false
  end

  if this.updateQuestGivers == true then
    pfQuest:Debug("Update Quest|cff33ffcc Givers")
    if pfQuest_config["trackingmethod"] ~= 4 and pfQuest_config["allquestgivers"] == "1" then
      local meta = { ["addon"] = "PFQUEST" }
      local t0 = GetTime()
      pfDatabase:SearchQuests(meta)
      pfQuest:Debug(format("|cffff3333TIMER SearchQuests: %.4fs", GetTime() - t0))
    end
    this.updateQuestGivers = false
  end

  if pfQuest.queueCount == 0 then
    return
  end

  -- process queue
  for id, entry in pairs(this.queue) do
    -- questgivers only need refreshing when quests are added or removed,
    -- not when objectives change (RELOAD). track this before clearing the entry.
    if entry[4] == "NEW" or entry[4] == "REMOVE" then
      this.needsQuestGiverUpdate = true
    end

    -- remove quest
    if entry[4] == "REMOVE" then
      pfQuest:Debug("|cffff5555Remove Quest: " .. entry[1] .. " (" .. entry[2] .. ")")

      -- write pfQuest.questlog history
      if entry[1] == pfQuest.abandon then
        pfQuest_history[entry[2]] = nil
      else
        pfQuest_history[entry[2]] = { time(), UnitLevel("player") }
      end

      -- remove from collapsed tracking so the SavedVar doesn't accumulate
      -- stale questids from quests that were turned in or abandoned
      pfQuest.collapsedQuestIDs[entry[2]] = nil
      -- Mark journal dirty when history changes
      if pfJournal then
        pfJournal.dirty = true
      end

      if pfQuest_config["trackingmethod"] ~= 4 then
        -- delete nodes by title
        local t0 = GetTime()
        pfMap:DeleteNode("PFQUEST", entry[1])

        -- also delete nodes by quest ids for servers with different names
        if entry[2] and pfDB["quests"]["loc"][entry[2]] and pfDB["quests"]["loc"][entry[2]].T then
          pfMap:DeleteNode("PFQUEST", pfDB["quests"]["loc"][entry[2]].T)
        end
        pfQuest:Debug(format("|cffffff00TIMER DeleteNode(REMOVE): %.4fs", GetTime() - t0))
      end

      pfQuest.abandon = ""
    else
      if entry[4] == "NEW" then
        pfQuest:Debug("|cff55ff55New Quest: " .. entry[1] .. " (" .. entry[2] .. ")")
      else
        pfQuest:Debug("|cffffff55Update Quest: " .. entry[1] .. " (" .. entry[2] .. ")")
      end

      -- update quest nodes
      if pfQuest_config["trackingmethod"] ~= 4 then
        -- Reforged: decide the re-add BEFORE deleting. The old flow deleted the
        -- quest's nodes unconditionally and could then skip the re-add (manual
        -- mode, tracked-mode gates, a transiently unreadable quest log slot mid
        -- QUEST_LOG_UPDATE burst), consuming the queue entry with the state
        -- string already recorded -- so nothing ever restored the nodes and the
        -- quest vanished from map+minimap until a /reload. The wotlk AUTO QUEST
        -- WATCH flips the watch state on the very first kill, which is exactly
        -- when players noticed (QA: "killing a quest mob hides the markers").
        local method = pfQuest_config["trackingmethod"]
        local eligible = method ~= 3 and (method ~= 2 or IsQuestWatched(entry[3]))

        -- manual mode: a quest the user has ALREADY shown by hand gets
        -- refreshed instead of dropped
        if not eligible and method == 3 and pfMap.nodes["PFQUEST"] then
          for _, coords in pairs(pfMap.nodes["PFQUEST"]) do
            for _, node in pairs(coords) do
              if node[entry[1]] then eligible = true break end
            end
            if eligible then break end
          end
        end

        local verified = nil
        if eligible then
          -- Verify the quest is still at the expected log position. If the
          -- slot is empty or holds a different quest (e.g. turned in while
          -- this entry was queued), skip SearchQuestID to avoid adding a
          -- spurious complete_c node.
          verified = entry[3] and compat.GetQuestLogTitle(entry[3]) == entry[1]
          if not verified then
            -- transiently unreadable slot: retry a few ticks with the nodes
            -- (and the queue entry) untouched instead of wiping the quest
            entry.retries = (entry.retries or 0) + 1
            if entry.retries < 10 then
              return
            end
          end
        end

        -- delete only when about to re-add (refresh), or when hiding is the
        -- intended behavior (tracked-only mode + quest not watched)
        if (eligible and verified) or (not eligible and method == 2) then
          local t0 = GetTime()
          pfMap:DeleteNode("PFQUEST", entry[1])

          -- delete nodes by quest ids for servers with different names
          if entry[2] and pfDB["quests"]["loc"][entry[2]] and pfDB["quests"]["loc"][entry[2]].T then
            pfMap:DeleteNode("PFQUEST", pfDB["quests"]["loc"][entry[2]].T)
          end
          pfQuest:Debug(format("|cffffff00TIMER DeleteNode(NEW/RELOAD): %.4fs", GetTime() - t0))
        end

        if eligible and verified then
          local meta = { ["addon"] = "PFQUEST", ["qlogid"] = entry[3] }
          local t1 = GetTime()
          pfDatabase:SearchQuestID(entry[2], meta)
          pfQuest:Debug(format("|cffff8800TIMER SearchQuestID: %.4fs", GetTime() - t1))
        end
      end
    end

    -- remove entry from queue and decrement counter
    pfQuest.queue[id] = nil
    pfQuest.queueCount = pfQuest.queueCount - 1

    -- Force map update so tracker refreshes (even for quests with no objectives)
    pfMap.queue_update = GetTime()

    -- only return when other entries exist
    -- otherwise, continue and update questgivers
    if pfQuest.queueCount > 0 then
      return
    end
  end

  -- trigger questgiver update only when needed
  if pfQuest.queueCount == 0 then
    this.updateQuestLog = true
    if this.needsQuestGiverUpdate then
      this.updateQuestGivers = true
      this.needsQuestGiverUpdate = false
    end
  end
end)

local questlog_flip, questlog_flop = {}, {}
function pfQuest:UpdateQuestlog()
  -- initialize flip flop if not yet defined
  pfQuest.questlog_tmp = pfQuest.questlog_tmp or questlog_flip

  local _, numQuests = GetNumQuestLogEntries()
  local found = 0
  local change = nil
  local underCollapsedHeader = false

  -- iterate over all quests
  for qlogid = 1, 40 do
    local title, _, _, header, collapsed, complete = compat.GetQuestLogTitle(qlogid)
    local objectives = GetNumQuestLeaderBoards(qlogid)
    local watched, questid, state

    if header then
      -- track the collapsed state for subsequent quests
      underCollapsedHeader = collapsed and true or false
    elseif title then
      questid = pfDatabase:GetQuestIDs(qlogid)
      questid = questid and tonumber(questid[1]) or title
      watched = IsQuestWatched(qlogid)

      -- build state string using table.concat (avoid string concat garbage)
      local stateParts = { watched and "track" or "" }
      if objectives then
        for i = 1, objectives, 1 do
          local text, _, done = GetQuestLogLeaderBoard(i, qlogid)
          stateParts[getn(stateParts) + 1] = i
          stateParts[getn(stateParts) + 1] = done and "done" or "todo"
        end
      end
      state = concat(stateParts)

      -- Some WoW clients (e.g. group/dungeon/raid quests) set collapsed=true on the
      -- individual quest entry itself rather than (or in addition to) the zone header.
      local effectiveCollapsed = underCollapsedHeader or (collapsed and true or false)

      -- add new quest to the questlog
      if not pfQuest.questlog[questid] then
        queueAdd({ title, questid, qlogid, "NEW" })
        -- Use collapsedQuestIDs (questid-keyed SavedVar) as the authoritative
        -- collapsed state. Zone-name lookup is unreliable because vanilla
        -- reassigns some quests to a different zone header when their real
        -- zone header is collapsed (e.g. DM quests appear under SoS).
        local initCollapsed = pfQuest.collapsedQuestIDs[questid] and true or effectiveCollapsed
        pfQuest.questlog_tmp[questid] = {
          title = title,
          qlogid = qlogid,
          state = state,
          collapsed = initCollapsed,
        }
        change = true
      elseif pfQuest.questlog[questid].qlogid ~= qlogid then
        queueAdd({ title, questid, qlogid, "RELOAD" })
        pfQuest.questlog_tmp[questid] = pfQuest.questlog[questid]
        pfQuest.questlog_tmp[questid].qlogid = qlogid
        pfQuest.questlog_tmp[questid].state = state
        change = true
      elseif pfQuest.questlog[questid].state ~= state then
        queueAdd({ title, questid, qlogid, "RELOAD" })
        pfQuest.questlog_tmp[questid] = pfQuest.questlog[questid]
        pfQuest.questlog_tmp[questid].qlogid = qlogid
        pfQuest.questlog_tmp[questid].state = state
        change = true
      else
        pfQuest.questlog_tmp[questid] = pfQuest.questlog[questid]
      end
      -- seen this scan -> reset the consecutive-miss counter used by the
      -- removal loop below
      if pfQuest.questlog_tmp[questid] then pfQuest.questlog_tmp[questid].gwMiss335 = nil end

      found = found + 1
      -- Reforged: do NOT break at `found >= numQuests`. GetNumQuestLogEntries()
      -- transiently UNDER-reports during a QUEST_LOG_UPDATE burst on some cores
      -- (QA: kill/loot); breaking early left every not-yet-scanned quest out of
      -- questlog_tmp, and the removal loop below then wrote them all to
      -- pfQuest_history (marked complete) and deleted their nodes -- a wipe that
      -- never recovered because the false "completed" flag suppresses the re-add.
      -- Scanning all 40 slots is cheap (empty slots short-circuit on nil title)
      -- and makes the rebuild independent of the unreliable count.
    end
  end

  -- quest removal events. A quest present last scan but absent from this
  -- rebuild is only a REMOVE candidate; a SINGLE absence is almost always a
  -- transient burst hiccup (unreadable slot, or the count under-report above),
  -- not a real turn-in. Require TWO consecutive misses before removing, so a
  -- one-scan flicker never deletes nodes or poisons pfQuest_history.
  for questid, data in pairs(pfQuest.questlog) do
    if not pfQuest.questlog_tmp[questid] then
      data.gwMiss335 = (data.gwMiss335 or 0) + 1
      if data.gwMiss335 >= 2 and not pfQuest.collapsedQuestIDs[questid] then
        queueAdd({ data.title, questid, nil, "REMOVE" })
        change = true
      else
        -- transient miss (or collapsed): preserve, nodes untouched
        pfQuest.questlog_tmp[questid] = data
      end
    end
  end

  -- set questlog to current flip flop
  pfQuest.questlog = pfQuest.questlog_tmp

  -- switch tmp to the other flip flop
  if pfQuest.questlog_tmp == questlog_flip then
    pfQuest.questlog_tmp = questlog_flop
  else
    pfQuest.questlog_tmp = questlog_flip
  end

  -- clear next temporary questlog entries
  for k, v in pairs(pfQuest.questlog_tmp) do
    pfQuest.questlog_tmp[k] = nil
  end

  return change
end

function pfQuest:ResetAll()
  -- force reload all quests
  pfMap:DeleteNode("PFQUEST")
  pfQuest.questlog = {}
  pfQuest.updateQuestLog = true
  pfQuest.updateQuestGivers = true
  -- pfMap.nodes["PFQUEST"] is now empty; tell SearchQuests to start fresh
  if pfDatabase then
    for id in pairs(pfDatabase.lastQuestGiversSet) do
      pfDatabase.lastQuestGiversSet[id] = nil
    end
  end
end

-- register popup dialog to copy urls
StaticPopupDialogs["PFQUEST_URLCOPY"] = {
  text = "|cff33ffccpf|cffffffffQuest " .. pfQuest_Loc["Online Search"],
  button1 = "Close",
  hasEditBox = 1,
  hasWideEditBox = 1,
  timeout = 0,
  exclusive = 1,
  whileDead = 1,
  hideOnEscape = 1,
  OnShow = function()
    local editBox = _G[this:GetName() .. "WideEditBox"]
    editBox:SetText(StaticPopupDialogs["PFQUEST_URLCOPY"].data)
    editBox:HighlightText()
  end,
  OnHide = function()
    _G[this:GetName() .. "WideEditBox"]:SetText("")
  end,
  EditBoxOnEnterPressed = function()
    this:GetParent():Hide()
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  EditBoxOnTextChanged = function()
    this:SetText(StaticPopupDialogs["PFQUEST_URLCOPY"].data)
    this:HighlightText()
  end,
}

function pfQuest:AddQuestLogIntegration()
  if pfQuest_config["questlogbuttons"] == "0" then
    return
  end

  local dockFrame = EQL3_QuestLogDetailScrollChildFrame
    or ShaguQuest_QuestLogDetailScrollChildFrame
    or QuestLogDetailScrollChildFrame
  local dockTitle = EQL3_QuestLogDescriptionTitle
    or ShaguQuest_QuestLogDescriptionTitle
    or pfQuestCompat.QuestLogDescriptionTitle

  dockTitle:SetHeight(dockTitle:GetHeight() + 30)
  dockTitle:SetJustifyV("BOTTOM")

  pfQuest.buttonOnline = pfQuest.buttonOnline or CreateFrame("Button", "pfQuestOnline", dockFrame)
  pfQuest.buttonOnline:SetWidth(18)
  pfQuest.buttonOnline:SetHeight(15)
  pfQuest.buttonOnline:SetPoint("TOPRIGHT", dockFrame, "TOPRIGHT", -12, -10)
  pfQuest.buttonOnline:SetScript("OnClick", function()
    if pfUI and pfUI.chat then
      pfUI.chat.urlcopy.text:SetText(pfQuest.dburl .. (this:GetID() or 0))
      pfUI.chat.urlcopy:Show()
    else
      StaticPopupDialogs["PFQUEST_URLCOPY"].data = pfQuest.dburl .. (this:GetID() or 0)
      local dialog = StaticPopup_Show("PFQUEST_URLCOPY")
      _G[dialog:GetName() .. "Button1"]:ClearAllPoints()
      _G[dialog:GetName() .. "Button1"]:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 16)
      _G[dialog:GetName() .. "WideEditBox"]:SetScript("OnTextChanged", StaticPopup_EditBoxOnTextChanged)
      dialog:SetWidth(420)
    end
  end)

  pfQuest.buttonOnline.txt = pfQuest.buttonOnline:CreateFontString("pfQuestIDButton", "HIGH", "GameFontWhite")
  pfQuest.buttonOnline.txt:SetAllPoints(pfQuest.buttonOnline)
  pfQuest.buttonOnline.txt:SetJustifyH("RIGHT")
  pfQuest.buttonOnline.txt:SetText("|cff000000[|cffaa2222?|cff000000]")

  pfQuest.buttonLanguage = pfQuest.buttonLanguage or CreateFrame("Button", "pfQuestLanguage", dockFrame)
  pfQuest.buttonLanguage:SetWidth(75)
  pfQuest.buttonLanguage:SetHeight(15)
  pfQuest.buttonLanguage:SetPoint("RIGHT", pfQuest.buttonOnline, "LEFT", 0, 0)

  pfQuest.buttonLanguage.txt = pfQuest.buttonLanguage:CreateFontString("pfQuestIDButton", "HIGH", "GameFontWhite")
  pfQuest.buttonLanguage.txt:SetAllPoints(pfQuest.buttonLanguage)
  pfQuest.buttonLanguage.txt:SetJustifyH("RIGHT")
  pfQuest.buttonLanguage.txt:SetText("|cff000000[|cff333333" .. pfQuest_Loc["Translate"] .. "|cff000000]")

  pfQuest.buttonLanguage:SetScript("OnClick", function()
    UIDropDownMenu_Initialize(self, function()
      local func = function()
        pfQuest_config.translate = this.value
      end
      local info = {}
      info.text = "|cffaaaaaa" .. pfQuest_Loc["Reset Language"]
      info.value = nil
      info.func = func
      UIDropDownMenu_AddButton(info)

      for loc, caption in pairs(pfDB.locales) do
        local info = {}
        info.text = caption
        info.value = loc
        info.func = func
        UIDropDownMenu_AddButton(info)
      end
    end)
    ToggleDropDownMenu(1, nil, self, "cursor", 3, -3)
  end)

  pfQuest.buttonLanguage:SetScript("OnUpdate", function()
    local id = pfQuest.buttonOnline:GetID()
    local lang = pfQuest_config.translate

    if this.translate ~= pfQuest_config.translate then
      pfQuest.buttonLanguage.txt:SetText(
        "|cff000000[|cff3333ff"
          .. (pfDB.locales[pfQuest_config.translate] or "|cff333333" .. pfQuest_Loc["Translate"])
          .. "|cff000000]"
      )
      this.translate = pfQuest_config.translate
      QuestLog_UpdateQuestDetails(true)
      return
    end

    if id and pfDB["quests"][lang] and pfDB["quests"][lang][id] then
      local QuestLogQuestTitle = EQL3_QuestLogQuestTitle or pfQuestCompat.QuestLogQuestTitle
      local QuestLogObjectivesText = EQL3_QuestLogObjectivesText or pfQuestCompat.QuestLogObjectivesText
      local QuestLogQuestDescription = EQL3_QuestLogQuestDescription or pfQuestCompat.QuestLogQuestDescription
      local QuestLogDetailScrollFrame = EQL3_QuestLogDetailScrollFrame or QuestLogDetailScrollFrame

      QuestLogQuestTitle:SetText(pfDatabase:FormatQuestText(pfDB["quests"][lang][id]["T"]))
      QuestLogObjectivesText:SetText(pfDatabase:FormatQuestText(pfDB["quests"][lang][id]["O"]))
      QuestLogQuestDescription:SetText(pfDatabase:FormatQuestText(pfDB["quests"][lang][id]["D"]))
      QuestLogDetailScrollFrame:UpdateScrollChildRect()
    end
  end)

  pfQuest.buttonShow = pfQuest.buttonShow or CreateFrame("Button", "pfQuestShow", dockFrame, "UIPanelButtonTemplate")
  pfQuest.buttonShow:SetWidth(70)
  pfQuest.buttonShow:SetHeight(20)
  pfQuest.buttonShow:SetText(pfQuest_Loc["Show"])
  pfQuest.buttonShow:SetPoint("TOP", dockTitle, "TOP", -110, 0)
  pfQuest.buttonShow:SetScript("OnClick", function()
    local questIndex = GetQuestLogSelection()
    local questids = pfDatabase:GetQuestIDs(questIndex)
    local title, _, _, header, _, complete = compat.GetQuestLogTitle(questIndex)
    local id = questids and tonumber(questids[1])
    if header or not id then
      return
    end

    local maps, meta = {}, { ["addon"] = "PFQUEST", ["qlogid"] = questIndex }
    maps = pfDatabase:SearchQuestID(id, meta, maps)
    pfMap:ShowMapID(pfDatabase:GetBestMap(maps))
  end)

  pfQuest.buttonHide = pfQuest.buttonHide or CreateFrame("Button", "pfQuestHide", dockFrame, "UIPanelButtonTemplate")
  pfQuest.buttonHide:SetWidth(70)
  pfQuest.buttonHide:SetHeight(20)
  pfQuest.buttonHide:SetText(pfQuest_Loc["Hide"])
  pfQuest.buttonHide:SetPoint("TOP", dockTitle, "TOP", -37, 0)
  pfQuest.buttonHide:SetScript("OnClick", function()
    local questIndex = GetQuestLogSelection()
    local title, _, _, header, _, complete = compat.GetQuestLogTitle(questIndex)
    if header then
      return
    end

    pfMap:DeleteNode("PFQUEST", title)
  end)

  pfQuest.buttonClean = pfQuest.buttonClean or CreateFrame("Button", "pfQuestClean", dockFrame, "UIPanelButtonTemplate")
  pfQuest.buttonClean:SetWidth(70)
  pfQuest.buttonClean:SetHeight(20)
  pfQuest.buttonClean:SetText(pfQuest_Loc["Clean"])
  pfQuest.buttonClean:SetPoint("TOP", dockTitle, "TOP", 37, 0)
  pfQuest.buttonClean:SetScript("OnClick", function()
    pfMap:DeleteNode("PFQUEST")
  end)

  pfQuest.buttonReset = pfQuest.buttonReset or CreateFrame("Button", "pfQuestReset", dockFrame, "UIPanelButtonTemplate")
  pfQuest.buttonReset:SetWidth(70)
  pfQuest.buttonReset:SetHeight(20)
  pfQuest.buttonReset:SetText(pfQuest_Loc["Reset"])
  pfQuest.buttonReset:SetPoint("TOP", dockTitle, "TOP", 110, 0)
  pfQuest.buttonReset:SetScript("OnClick", function()
    pfQuest:ResetAll()
  end)

  -- use pfUI buttons in native mode
  if not pfUI.api.emulated then
    pfUI.api.SkinButton(pfQuest.buttonShow)
    pfUI.api.SkinButton(pfQuest.buttonHide)
    pfUI.api.SkinButton(pfQuest.buttonClean)
    pfUI.api.SkinButton(pfQuest.buttonReset)
  end
end

function pfQuest:AddWorldMapIntegration()
  if pfQuest_config["worldmapmenu"] == "0" then
    return
  end

  -- Quest Display Selection
  -- Parent + anchor to the visible map viewport so the dropdown stays pinned
  -- to the top-right of the visible map AND scales with the map mode:
  --   * default 3.3.5: WorldMapDetailFrame is the visible map area, scales
  --     with WORLDMAP_SETTINGS.size (windowed=0.573, fullmap=1.0), doesn't pan.
  --   * Magnify: it creates WorldMapScrollFrame as the clipped viewport,
  --     reparents WorldMapDetailFrame inside it as a panned/scaled scroll
  --     child. WorldMapScrollFrame scales with WORLDMAP_SETTINGS.size and
  --     doesn't pan/zoom, so it's the safe anchor.
  local mapAnchor = WorldMapScrollFrame or WorldMapDetailFrame
  pfQuest.mapButton = CreateFrame("Frame", "pfQuestMapDropdown", mapAnchor, "UIDropDownMenuTemplate")
  pfQuest.mapButton:ClearAllPoints()
  pfQuest.mapButton:SetPoint("TOPRIGHT", mapAnchor, "TOPRIGHT", 0, -10)
  -- Lift above WorldMapButton (Blizzard sets it to WORLDMAP_POI_FRAMELEVEL - 10
  -- = 90 in WorldMapFrame_ResetFrameLevels). Without this, Magnify's
  -- WorldMapButton OnMouseDown handler swallows clicks aimed at the dropdown
  -- because WorldMapScrollFrame (created at .toc-load time, before WMF's
  -- ResetFrameLevels) sits at a very low frame level, leaving its children
  -- below WorldMapButton's 90.
  pfQuest.mapButton:SetFrameLevel((WORLDMAP_POI_FRAMELEVEL or 100) + 2)
  pfQuest.mapButton:SetScript("OnShow", function()
    pfQuest.mapButton.current = tonumber(pfQuest_config["trackingmethod"])
    pfQuest.mapButton:UpdateMenu()
  end)

  pfQuest.mapButton.point = "TOPLEFT"
  pfQuest.mapButton.relativePoint = "BOTTOMLEFT"

  -- One-time width/justify setup. Previously these lived inside UpdateMenu
  -- and re-ran on every map show, which would overwrite the width that
  -- ElvUI's HandleDropDownBox sets when it skins the dropdown.
  if client >= 30300 then
    UIDropDownMenu_SetWidth(pfQuest.mapButton, 120)
    UIDropDownMenu_SetButtonWidth(pfQuest.mapButton, 125)
    UIDropDownMenu_JustifyText(pfQuest.mapButton, "RIGHT")
  else
    UIDropDownMenu_SetWidth(120, pfQuest.mapButton)
    UIDropDownMenu_SetButtonWidth(125, pfQuest.mapButton)
    UIDropDownMenu_JustifyText("RIGHT", pfQuest.mapButton)
  end

  function pfQuest.mapButton:UpdateMenu()
    local function CreateEntries()
      local info = {}
      info.text = pfQuest_Loc["All Quests"]
      info.checked = false
      info.func = function()
        UIDropDownMenu_SetSelectedID(pfQuest.mapButton, this:GetID(), 0)
        pfQuest_config["trackingmethod"] = this:GetID()
        pfQuest:ResetAll()
      end
      UIDropDownMenu_AddButton(info)

      local info = {}
      info.text = pfQuest_Loc["Tracked Quests"]
      info.checked = false
      info.func = function()
        UIDropDownMenu_SetSelectedID(pfQuest.mapButton, this:GetID(), 0)
        pfQuest_config["trackingmethod"] = this:GetID()
        pfQuest:ResetAll()
      end
      UIDropDownMenu_AddButton(info)

      local info = {}
      info.text = pfQuest_Loc["Manual Selection"]
      info.checked = false
      info.func = function()
        UIDropDownMenu_SetSelectedID(pfQuest.mapButton, this:GetID(), 0)
        pfQuest_config["trackingmethod"] = this:GetID()
        pfQuest:ResetAll()
      end
      UIDropDownMenu_AddButton(info)

      local info = {}
      info.text = pfQuest_Loc["Hide Quests"]
      info.checked = false
      info.func = function()
        UIDropDownMenu_SetSelectedID(pfQuest.mapButton, this:GetID(), 0)
        pfQuest_config["trackingmethod"] = this:GetID()
        pfQuest:ResetAll()
      end
      UIDropDownMenu_AddButton(info)

      local info = {}
      info.text = pfQuest_Loc["Current Zone"]
      info.checked = false
      info.func = function()
        UIDropDownMenu_SetSelectedID(pfQuest.mapButton, this:GetID(), 0)
        pfQuest_config["trackingmethod"] = this:GetID()
        pfQuest:ResetAll()
      end
      UIDropDownMenu_AddButton(info)
    end

    UIDropDownMenu_Initialize(pfQuest.mapButton, CreateEntries)
    UIDropDownMenu_SetSelectedID(pfQuest.mapButton, pfQuest.mapButton.current)
  end

  -- ElvUI skin: mirror ModernMapMarkers' approach. If ElvUI is loaded,
  -- wait until its engine is initialized, then run S:HandleDropDownBox on
  -- pfQuest's All-Quests dropdown so it matches MMM's filter/find dropdowns.
  do
    local function SkinDropdown(S)
      if pfQuest.mapButton.backdrop then return end
      S:HandleDropDownBox(pfQuest.mapButton, 134)
    end

    local function OnReady()
      if not ElvUI then return end
      local E = ElvUI[1]
      if not E then return end
      local S = E:GetModule("Skins")
      if not S then return end
      SkinDropdown(S)
    end

    if ElvUI and ElvUI[1] then
      if ElvUI[1].initialized then
        OnReady()
      else
        hooksecurefunc(ElvUI[1], "Initialize", OnReady)
      end
    end
  end
end

-- [[ Hook UI Functions ]] --
-- Set certain events on quest watch
local pfHookRemoveQuestWatch = RemoveQuestWatch
RemoveQuestWatch = function(questIndex)
  local ret = pfHookRemoveQuestWatch(questIndex)

  -- Reforged: do NOT delete the quest's nodes here. On WotLK the client's
  -- auto-quest-watch (autoQuestWatch=1) churns the watch list on every
  -- objective tick -- killing a mob or looting a quest item fires
  -- RemoveQuestWatch and then immediately re-adds the watch. The old
  -- unconditional DeleteNode wiped the quest's map+minimap nodes on that
  -- churn; because the watch state round-tripped to UNCHANGED, the next
  -- UpdateQuestlog saw no state change, queued no RELOAD, and never
  -- re-added them -- so the dots stayed gone until a settings reset.
  -- Node visibility already
  -- follows the watch state correctly through the normal queue path (the
  -- state string includes the watched flag, and tracked-only mode hides
  -- un-watched quests there), so flagging a refresh is all that's needed.
  pfQuest.updateQuestLog = true
  pfQuest.updateQuestGivers = true

  return ret
end

-- Set certain events on quest unwatch
local pfHookAddQuestWatch = AddQuestWatch
AddQuestWatch = function(questIndex)
  local ret = pfHookAddQuestWatch(questIndex)
  pfQuest.updateQuestLog = true
  pfQuest.updateQuestGivers = true
  return ret
end

-- Save the abandoned questname to remove from history
local HookAbandonQuest = AbandonQuest
AbandonQuest = function()
  pfQuest.abandon = GetAbandonQuestName()
  HookAbandonQuest()
end

local function UpdateQuestLevel(button, id)
  local title, level, tag, header = compat.GetQuestLogTitle(id)
  if header or not title then
    return
  end
  button:SetText(" [" .. (level or "??") .. (tag and "+" or "") .. "] " .. title)
  if not QuestLogTitleButton_Resize then
    return
  end
  QuestLogTitleButton_Resize(button)
end

-- Update quest id button
local pfHookQuestLog_Update = QuestLog_Update
QuestLog_Update = function()
  pfHookQuestLog_Update()

  if pfQuest_config["questloglevel"] == "1" then
    if client >= 30300 then
      for i, button in pairs(QuestLogScrollFrame.buttons) do
        UpdateQuestLevel(button, button:GetID())
      end
    else
      for i = 1, QUESTS_DISPLAYED, 1 do
        UpdateQuestLevel(_G["QuestLogTitle" .. i], i + FauxScrollFrame_GetOffset(QuestLogListScrollFrame))
      end
    end
  end

  if pfQuest_config["questlogbuttons"] == "1" then
    local questids = pfDatabase:GetQuestIDs(GetQuestLogSelection())
    if questids and questids[1] and tonumber(questids[1]) and pfQuest.questlog[questids[1]] then
      pfQuest.buttonOnline:SetID(questids[1])
      pfQuest.buttonOnline:Show()
      pfQuest.buttonLanguage:Show()
      -- enable buttons
      pfQuest.buttonShow:Enable()
      pfQuest.buttonHide:Enable()

      if pfQuest_config.showids == "1" then
        pfQuest.buttonOnline.txt:SetText("|cff000000[|cffaa2222id: " .. questids[1] .. "|cff000000]")
        pfQuest.buttonOnline:SetWidth(pfQuest.buttonOnline.txt:GetStringWidth())
      end
    else
      pfQuest.buttonOnline:Hide()
      pfQuest.buttonLanguage:Hide()
      -- disable buttons
      pfQuest.buttonShow:Disable()
      pfQuest.buttonHide:Disable()
    end
  end
end

-- attach the new function to the scroll frame
if QuestLogScrollFrame then
  QuestLogScrollFrame.update = QuestLog_Update
end

-- refresh language and url on quest selection
local pfHookQuestLogTitleButton_OnClick = QuestLogTitleButton_OnClick
QuestLogTitleButton_OnClick = function(self, button)
  -- Signal that ExpandQuestHeader/CollapseQuestHeader is being triggered by the
  -- user clicking a zone header, not by vanilla internally (e.g. on quest accept).
  pfQuest.userClickingHeader = true
  pfHookQuestLogTitleButton_OnClick(self, button)
  pfQuest.userClickingHeader = false
  QuestLog_Update()
end

if not GetQuestLink then -- Allow to send questlinks from questlog
  local pfHookQuestLogTitleButton_OnClick = QuestLogTitleButton_OnClick
  QuestLogTitleButton_OnClick = function(button)
    local scrollFrame = EQL3_QuestLogListScrollFrame or ShaguQuest_QuestLogListScrollFrame or QuestLogListScrollFrame
    local questIndex = this:GetID() + FauxScrollFrame_GetOffset(scrollFrame)
    local questName, questLevel = compat.GetQuestLogTitle(questIndex)
    local questids = pfDatabase:GetQuestIDs(questIndex)
    local questid = questids and tonumber(questids[1]) or 0

    if IsShiftKeyDown() and not this.isHeader and ChatFrameEditBox:IsVisible() then
      pfQuestCompat.InsertQuestLink(questid, questName)
      QuestLog_SetSelection(questIndex)
      QuestLog_Update()
      return
    end

    pfHookQuestLogTitleButton_OnClick(button)
  end

  -- Patch ItemRef to display Questlinks
  local pfQuestHookSetItemRef = SetItemRef
  SetItemRef = function(link, text, button)
    local isQuest, _, id = string.find(link, "quest:(%d+):.*")
    local isQuest2, _, _ = string.find(link, "quest2:.*")

    if isQuest or isQuest2 then
      if IsShiftKeyDown() and ChatFrameEditBox:IsVisible() then
        ChatFrameEditBox:Insert(text)
        return
      end

      if ItemRefTooltip:IsShown() and ItemRefTooltip.pfQtext == text then
        HideUIPanel(ItemRefTooltip)
        return
      end

      ShowUIPanel(ItemRefTooltip)
      ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")

      local hasTitle, _, questTitle = string.find(text, ".*|h%[(.*)%]|h.*")

      id = tonumber(id)

      if not id or id == 0 then
        for scanID, data in pairs(pfDB["quests"]["loc"]) do
          if data.T == questTitle then
            id = scanID
            break
          end
        end
      end

      -- read and set title
      if id and id > 0 and pfDB["quests"]["loc"][id] then
        local questlevel = tonumber(pfDB["quests"]["data"][id]["lvl"])
        local color = pfQuestCompat.GetDifficultyColor(questlevel)
        ItemRefTooltip:AddLine(pfDB["quests"]["loc"][id].T, color.r, color.g, color.b)
      elseif hasTitle then
        ItemRefTooltip:AddLine(questTitle, 1, 1, 0)
      end

      -- scan for active quests
      local queststate = pfQuest_history[id] and 2 or 0
      queststate = pfQuest.questlog[id] and 1 or queststate

      if queststate == 0 then
        ItemRefTooltip:AddLine(pfQuest_Loc["You don't have this quest."] .. "\n\n", 1, 0.5, 0.5)
      elseif queststate == 1 then
        ItemRefTooltip:AddLine(pfQuest_Loc["You are on this quest."] .. "\n\n", 1, 1, 0.5)
      elseif queststate == 2 then
        ItemRefTooltip:AddLine(pfQuest_Loc["You already did this quest."] .. "\n\n", 0.5, 1, 0.5)
      end

      -- add database entries if existing
      if pfDB["quests"]["loc"][id] then
        if pfDB["quests"]["loc"][id]["O"] then
          ItemRefTooltip:AddLine(pfDatabase:FormatQuestText(pfDB["quests"]["loc"][id]["O"]), 1, 1, 1, true)
        end

        if pfDB["quests"]["loc"][id]["O"] and pfDB["quests"]["loc"][id]["D"] then
          ItemRefTooltip:AddLine(" ", 0, 0, 0)
        end

        if pfDB["quests"]["loc"][id]["D"] then
          ItemRefTooltip:AddLine(pfDatabase:FormatQuestText(pfDB["quests"]["loc"][id]["D"]), 0.8, 0.8, 0.8, true)
        end

        if pfDB["quests"]["data"][id]["lvl"] or pfDB["quests"]["data"][id]["min"] then
          ItemRefTooltip:AddLine(" ", 0, 0, 0)
        end

        if pfDB["quests"]["data"][id]["min"] then
          local questlevel = tonumber(pfDB["quests"]["data"][id]["min"])
          local color = pfQuestCompat.GetDifficultyColor(questlevel)
          ItemRefTooltip:AddLine(
            "|cffffffff" .. pfQuest_Loc["Required Level"] .. ": |r" .. questlevel,
            color.r,
            color.g,
            color.b
          )
        end

        if pfDB["quests"]["data"][id]["lvl"] then
          local questlevel = tonumber(pfDB["quests"]["data"][id]["lvl"])
          local color = pfQuestCompat.GetDifficultyColor(questlevel)
          ItemRefTooltip:AddLine(
            "|cffffffff" .. pfQuest_Loc["Quest Level"] .. ": |r" .. questlevel,
            color.r,
            color.g,
            color.b
          )
        end
      end

      ItemRefTooltip:Show()
    else
      pfQuestHookSetItemRef(link, text, button)
    end
    ItemRefTooltip.pfQtext = text
  end
else
  -- patch itemref to show known quest levels on tbc
  local pfQuestHookSetItemRef = SetItemRef
  SetItemRef = function(link, text, button)
    pfQuestHookSetItemRef(link, text, button)

    -- skip modifier clicks
    if IsAltKeyDown() or IsControlKeyDown() or IsShiftKeyDown() then
      return
    end

    local quest, _, id = string.find(link, "quest:(%d+):.*")
    if not quest then
      return
    end
    id = tonumber(id)

    -- adjust text color to level color
    if id and id > 0 and pfDB["quests"]["loc"][id] then
      local questlevel = tonumber(pfDB["quests"]["data"][id]["lvl"])
      local color = pfQuestCompat.GetDifficultyColor(questlevel)
      ItemRefTooltipTextLeft1:SetTextColor(color.r, color.g, color.b)
    end

    -- add quest levels to tooltip
    if pfDB["quests"]["loc"][id] then
      ItemRefTooltip:AddLine(" ")

      if pfDB["quests"]["data"][id]["min"] then
        local questlevel = tonumber(pfDB["quests"]["data"][id]["min"])
        local color = pfQuestCompat.GetDifficultyColor(questlevel)
        ItemRefTooltip:AddLine(
          "|cffffffff" .. pfQuest_Loc["Required Level"] .. ": |r" .. questlevel,
          color.r,
          color.g,
          color.b
        )
      end

      if pfDB["quests"]["data"][id]["lvl"] then
        local questlevel = tonumber(pfDB["quests"]["data"][id]["lvl"])
        local color = pfQuestCompat.GetDifficultyColor(questlevel)
        ItemRefTooltip:AddLine(
          "|cffffffff" .. pfQuest_Loc["Quest Level"] .. ": |r" .. questlevel,
          color.r,
          color.g,
          color.b
        )
      end
    end

    ItemRefTooltip:Show()
  end
end
