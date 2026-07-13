dofile("stub.lua")
local base = os.getenv("PFQ_BASE") or "../pfq/pfQuest-wotlk-main/"

-- saved variables



local function L(f)
  local ok, err = pcall(dofile, base .. f)
  if not ok then print("LOAD-FAIL", f, err) end
  return ok
end

-- db (init/data.xml + enUS.xml + wotlk overlays per pfQuest-wotlk.toc)
for _, f in ipairs({
  "db/init.lua", "db/items.lua", "db/units.lua", "db/objects.lua", "db/refloot.lua",
  "db/quests-itemreq.lua", "db/quests.lua", "db/zones.lua", "db/minimap.lua",
  "db/areatrigger.lua", "db/meta.lua",
  "db/enUS/items.lua", "db/enUS/units.lua", "db/enUS/objects.lua", "db/enUS/quests.lua",
  "db/enUS/zones.lua", "db/enUS/professions.lua",
  "db/items-tbc.lua", "db/units-tbc.lua", "db/objects-tbc.lua", "db/refloot-tbc.lua",
  "db/quests-itemreq-tbc.lua", "db/quests-tbc.lua", "db/minimap-tbc.lua",
  "db/areatrigger-tbc.lua", "db/meta-tbc.lua",
  "db/enUS/items-tbc.lua", "db/enUS/units-tbc.lua", "db/enUS/objects-tbc.lua", "db/enUS/quests-tbc.lua",
  "db/items-wotlk.lua", "db/units-wotlk.lua", "db/objects-wotlk.lua", "db/quests-wotlk.lua",
  "db/enUS/items-wotlk.lua", "db/enUS/units-wotlk.lua", "db/enUS/objects-wotlk.lua", "db/enUS/quests-wotlk.lua",
  "db/enUS/zones-wotlk.lua",
}) do L(f) end

-- addon files (init/addon.xml order, UI-heavy modules skipped)
for _, f in ipairs({
  "compat/pfUI.lua", "compat/client.lua", "theme.lua", "locales.lua",
  "config.lua", "database.lua", "icons.lua", "map.lua", "quest.lua", "route.lua", "tracker.lua",
}) do if not L(f) then os.exit(1) end end

print("LOADED OK; pfDatabase.localized =", pfDatabase and pfDatabase.localized)

if os.getenv("PFQ_HILLSBRAD") == "1" then
  FAKE_QUESTLOG = {
    { "Hillsbrad Foothills", 0, nil, nil, 1 },
    { "Battle of Hillsbrad", 24, nil, nil, nil, nil, nil, nil, 527,
      objectives = {
        { "Hillsbrad Peasant slain: 2/14", "monster", nil },
        { "Hillsbrad Sentry slain: 0/4", "monster", nil },
      } },
    { "Souvenirs of Death", 25, nil, nil, nil, nil, nil, nil, 546,
      objectives = { { "Human Skull: 19/30", "item", nil } } },
  }
  FireEvent("ADDON_LOADED", os.getenv("PFQ_ADDONNAME") or "pfQuest-Reforged")
  FireEvent("VARIABLES_LOADED")
  if os.getenv("PFQ_DEBUG") == "1" then
    pfQuest_config.debug = true; _G.PRINT_ADDMSG = true
    DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) print("CHAT:", (tostring(msg):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
  end
  if os.getenv("PFQ_HISTORY") == "1" then
    -- /db query import artifact: unrelated completed quests in history
    for _, id in ipairs({742, 11852, 1150, 494, 5052, 764}) do
      pfQuest_history[id] = { 1, 20 }
    end
  end
  FireEvent("PLAYER_LOGIN")
  FireEvent("PLAYER_ENTERING_WORLD")
  FireEvent("QUEST_LOG_UPDATE")
  for i = 1, 400 do TickFrames(0.05) end
  local function Count(t)
    local n = 0
    local per = pfMap.nodes and pfMap.nodes["PFQUEST"]
    if per then for _, coords in pairs(per) do for _, node in pairs(coords) do
      for title in pairs(node) do if title == t then n = n + 1 end end
    end end end
    return n
  end
  local function Total()
    local n = 0
    local per = pfMap.nodes and pfMap.nodes["PFQUEST"]
    if per then for _, coords in pairs(per) do for _, node in pairs(coords) do n = n + 1 end end end
    return n
  end
  print("login: battle=" .. Count("Battle of Hillsbrad") .. " souvenirs=" .. Count("Souvenirs of Death") .. " totalcoords=" .. Total())
  -- kill a peasant AND loot its skull: both quests advance in one burst
  FAKE_QUESTLOG[2].objectives[1][1] = "Hillsbrad Peasant slain: 3/14"
  FAKE_QUESTLOG[3].objectives[1][1] = "Human Skull: 20/30"
  if os.getenv("PFQ_OBJDONEFLAG") == "1" then
    FAKE_QUESTLOG[2].objectives[1][3] = 1
    FAKE_QUESTLOG[3].objectives[1][3] = 1
  end
  FireEvent("QUEST_WATCH_UPDATE", 2)
  if os.getenv("PFQ_COUNTDROP") == "1" then
    -- core under-reports the quest count for a few ticks during the burst
    _G.FAKE_NUMQUESTS_OVERRIDE = 1
    FireEvent("QUEST_LOG_UPDATE")
    for i = 1, 30 do TickFrames(0.05) end
    _G.FAKE_NUMQUESTS_OVERRIDE = nil
    FireEvent("QUEST_LOG_UPDATE")
  else
    FireEvent("QUEST_LOG_UPDATE")
    FireEvent("QUEST_LOG_UPDATE")
  end
  for i = 1, 400 do TickFrames(0.05) end
  print("kill: battle=" .. Count("Battle of Hillsbrad") .. " souvenirs=" .. Count("Souvenirs of Death") .. " totalcoords=" .. Total())
  os.exit(0)
end

-- find the quest + its objective unit name from the DB
local ITEMQUEST = os.getenv("PFQ_ITEMQUEST") == "1"
local QTITLE = ITEMQUEST and "Highperch Venom" or "Between a Rock and a Thistlefur"
local qid
for id, data in pairs(pfDB["quests"]["loc"]) do
  if type(data) == "table" and data.T == QTITLE then qid = id break end
end
print("questid:", qid)
local mobName = "Thistlefur Avenger"
local itemName = "Highperch Venom Sac"

FAKE_QUESTLOG = {
  { "Ashenvale", 0, nil, nil, 1 },
  { QTITLE, 25, nil, nil, nil, nil, nil, nil, qid,
    objectives = (os.getenv("PFQ_MULTIMIX") == "1") and {
      { mobName .. " slain: 2/14", "monster", nil },
      { itemName .. ": 19/30", "item", nil },
    } or ITEMQUEST and {
      { itemName .. ": 6/12", "item", nil },
    } or (os.getenv("PFQ_EVENTOBJ") == "1") and {
      { mobName .. " slain: 6/12", "monster", nil },
      { "Scout the gazebo on Mystral Lake that overlooks the nearby Alliance outpost.", "event", nil },
    } or (os.getenv("PFQ_MONSTEREVENT") == "1") and {
      { mobName .. " slain: 6/12", "monster", nil },
      { "Scout the gazebo on Mystral Lake that overlooks the nearby Alliance outpost.", "monster", nil },
    } or { { mobName .. " slain: 6/12", "monster", nil } } },
}

-- variant knobs from env
if os.getenv("PFQ_TWOQUESTS") == "1" then
  -- second quest progressing from the SAME kill (its item drops from the
  -- same mobs): both quests RELOAD in one QUEST_LOG_UPDATE burst
  local qid2
  for id, data in pairs(pfDB["quests"]["loc"]) do
    if type(data) == "table" and data.T == "Highperch Venom" then qid2 = id break end
  end
  table.insert(FAKE_QUESTLOG, { "Highperch Venom", 25, nil, nil, nil, nil, nil, nil, qid2,
    objectives = { { "Highperch Venom Sac: 19/30", "item", nil } } })
end

local MODE = tonumber(os.getenv("PFQ_MODE") or "0")
local MODESTR = os.getenv("PFQ_MODESTR") == "1"
local COLLAPSED = os.getenv("PFQ_COLLAPSED") == "1"
if COLLAPSED then FAKE_QUESTLOG[1][6] = 1 end

-- login sequence
FireEvent("ADDON_LOADED", os.getenv("PFQ_ADDONNAME") or "pfQuest")
FireEvent("VARIABLES_LOADED")
if MODE > 0 then pfQuest_config["trackingmethod"] = MODESTR and tostring(MODE) or MODE end
if os.getenv("PFQ_DEBUG") == "1" then
  pfQuest_config.debug = true; _G.PRINT_ADDMSG = true
  DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) print("CHAT:", (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
end
print("trackingmethod:", tostring(pfQuest_config["trackingmethod"]), type(pfQuest_config["trackingmethod"]))
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD")
FireEvent("QUEST_LOG_UPDATE")
-- pfQuest gates its initial scan behind a lock; advance well past it
for i = 1, 400 do TickFrames(0.05) end

local function CountQuestNodes()
  local spawns, clusters = 0, 0
  local per = pfMap.nodes and pfMap.nodes["PFQUEST"]
  if per then
    for map, coords in pairs(per) do
      for coord, node in pairs(coords) do
        for title, meta in pairs(node) do
          if title == QTITLE or (os.getenv("PFQ_TWOQUESTS") == "1" and title == "Highperch Venom") then
            if meta.cluster then clusters = clusters + 1 else spawns = spawns + 1 end
          end
        end
      end
    end
  end
  return spawns, clusters
end

if MODE == 3 then
  -- manual mode: user showed the quest by hand
  pfDatabase:SearchQuestID(qid, { addon = "PFQUEST", qlogid = 2 })
  pfMap:UpdateNodes()
end
print("questlog entries:")
for qid2, d in pairs(pfQuest.questlog or {}) do print("  ", qid2, d.title, d.qlogid, d.state) end
print("after login:", CountQuestNodes())
print("queueCount:", pfQuest.queueCount, "updateQuestLog:", tostring(pfQuest.updateQuestLog))

-- simulate the kill: 6/12 -> 7/12 + wotlk AUTO QUEST WATCH flip, then the QLU burst
if os.getenv("PFQ_TWOQUESTS") == "1" then
  FAKE_QUESTLOG[3].objectives[1][1] = "Highperch Venom Sac: 20/30"
  if os.getenv("PFQ_OBJDONEFLAG") == "1" then FAKE_QUESTLOG[3].objectives[1][3] = 1 end
  if os.getenv("PFQ_DONECOMPLETE") == "1" then FAKE_QUESTLOG[3].objectives[1][3] = 1 FAKE_QUESTLOG[3][7] = 1 end
end
if os.getenv("PFQ_MULTIMIX") == "1" then
  -- kill a peasant AND loot its skull: both objectives advance in one burst
  FAKE_QUESTLOG[2].objectives[1][1] = mobName .. " slain: 3/14"
  FAKE_QUESTLOG[2].objectives[2][1] = itemName .. ": 20/30"
else
  FAKE_QUESTLOG[2].objectives[1][1] = ITEMQUEST and (itemName .. ": 7/12")
    or (mobName .. " slain: 7/12")
end
if os.getenv("PFQ_OBJDONEFLAG") == "1" then
  -- core quirk under test: the per-objective done flag goes truthy on the
  -- first kill while the text still reads x/y with x < y (QA: 1/12 hid the
  -- mob's nodes)
  FAKE_QUESTLOG[2].objectives[1][3] = 1
end
if os.getenv("PFQ_DONECOMPLETE") == "1" then
  -- combined quirk: the core raises BOTH the per-objective done flag AND the
  -- quest isComplete flag on the first loot while the text still reads x/y
  -- with x < y (QA: collect quests lose all icons after picking up drop #1)
  FAKE_QUESTLOG[2].objectives[1][3] = 1
  FAKE_QUESTLOG[2][7] = 1
end
WATCHED = {}
if os.getenv("PFQ_AUTOWATCH") == "1" then WATCHED[2] = true end
IsQuestWatched = function(i) return WATCHED[i] and 1 or nil end
FireEvent("QUEST_WATCH_UPDATE", 2)
FireEvent("QUEST_LOG_UPDATE")
FireEvent("QUEST_LOG_UPDATE")
if os.getenv("PFQ_COMPLETERACE") == "1" then
  -- server quirk: right after the kill the log entry transiently reports
  -- isComplete while the queue processes, then reverts
  FAKE_QUESTLOG[2][7] = 1
  for i = 1, 60 do TickFrames(0.05) end
  FAKE_QUESTLOG[2][7] = nil
  FireEvent("QUEST_LOG_UPDATE")
  for i = 1, 340 do TickFrames(0.05) end
elseif os.getenv("PFQ_NILRACE") == "1" then
  -- classic wow quirk: during the post-kill QLU burst, GetQuestLogTitle can
  -- transiently return nil for valid indexes. Blank the log while the queue
  -- processes, then restore it.
  local savedLog = FAKE_QUESTLOG
  local restored = false
  local ticks = 0
  FAKE_QUESTLOG = {}
  for i = 1, 400 do
    TickFrames(0.05)
    ticks = ticks + 1
    if not restored and ticks >= 40 then  -- ~2s of "blank log" burst
      FAKE_QUESTLOG = savedLog
      restored = true
      FireEvent("QUEST_LOG_UPDATE")
    end
  end
else
  for i = 1, 400 do TickFrames(0.05) end
end

print("after kill:", CountQuestNodes())
print("queueCount:", pfQuest.queueCount, "updateQuestLog:", tostring(pfQuest.updateQuestLog))

-- diagnostic: list item-objective quests near the test zone (PFQ_FINDITEMQUEST=1)
if os.getenv("PFQ_FINDITEMQUEST") == "1" then
  local n = 0
  for id, data in pairs(pfDB["quests"]["data"]) do
    if type(data) == "table" and data["obj"] and data["obj"]["I"] and data["lvl"] and data["lvl"] >= 20 and data["lvl"] <= 30 then
      local loc = pfDB["quests"]["loc"][id]
      local item = data["obj"]["I"][1]
      local iname = item and pfDB["items"]["loc"][item]
      if loc and loc.T and iname then
        print("ITEMQUEST", id, loc.T, item, iname)
        n = n + 1
        if n >= 8 then break end
      end
    end
  end
end
