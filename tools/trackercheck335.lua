-- End-to-end tracker check: load the REAL tracker.lua and theme.lua, hand them a
-- synthetic quest log, and drive the actual code path that builds a row.
--
-- The difference from runtimecheck335.lua: that file exercises our objects through a
-- sequence transcribed BY HAND from tracker.lua, so it tests the transcription. This
-- one runs tracker.ButtonAdd / ButtonEvent / DoLayout for real, so when tracker.lua
-- changes what it calls, this follows automatically. That is the chain that broke in
-- v1.0.30 (ButtonAdd -> bar:Show(), nil) and where the fill bug lived (SetProgress
-- runs BEFORE DoLayout sizes the tracker, so the fill read an unresolved width).
--
-- Usage: lua5.1 tools/trackercheck335.lua   (from the addon root)

local failures, checks = 0, 0
local function fail(f, ...) failures = failures + 1; print("  FAIL  " .. string.format(f, ...)) end
local function ok(f, ...) checks = checks + 1; print("  ok    " .. string.format(f, ...)) end
local function check(cond, f, ...) if cond then ok(f, ...) else fail(f, ...) end end

dofile("tools/framestub335.lua").install()

-- ---------------------------------------------------------------------------
-- synthetic quest log: one complete, one partial, one with no objectives
-- ---------------------------------------------------------------------------
local QUESTS = {
  [1] = { title = "Distress Call",        level = 71, objectives = { { "Survivors rescued", 8, 8 } } },
  [2] = { title = "Nick of Time",         level = 71, objectives = { { "Prisoners freed",   3, 10 } } },
  [3] = { title = "Thassarian, My Brother", level = 71, objectives = {} },
}
_G.GetNumQuestLogEntries   = function() return 3, 3 end
_G.SelectQuestLogEntry     = function() end
_G.IsQuestWatched          = function() return true end
_G.GetNumQuestLeaderBoards = function(i)
  local q = QUESTS[tonumber(i) or 1]
  return q and table.getn(q.objectives) or 0
end
_G.GetQuestLogTitle = function(i)
  local q = QUESTS[tonumber(i)]; if not q then return end
  return q.title, q.level, nil, nil, nil, nil, nil, nil
end
_G.GetQuestLogLeaderBoard = function(j, i)
  local q = QUESTS[tonumber(i)]
  local o = q and q.objectives[tonumber(j)]; if not o then return end
  return string.format("%s: %d/%d", o[1], o[2], o[3]), "monster", o[2] >= o[3]
end

-- ---------------------------------------------------------------------------
-- the addon surface tracker.lua expects, faked at the seams
-- ---------------------------------------------------------------------------
_G.pfQuest_config = { trackerfontsize = "12", trackeralpha = "0", trackingmethod = "2",
                      trackerwidth = "300", trackerscale = "1", trackerbars = "1" }
_G.pfQuestConfig  = { path = "pfQuest-Reforged" }
_G.pfQuest_history, _G.pfQuest_colors = {}, {}
-- GetDifficultyColor must return a TABLE with r/g/b: the tracker indexes it
-- directly (tracker.lua:669).
_G.pfQuestCompat = setmetatable({ GetQuestLogTitle = _G.GetQuestLogTitle,
                                  client = 11200, GetPlayerFacing = function() return 0 end,
                                  GetDifficultyColor = function() return { r = 1, g = 0.82, b = 0 } end },
                                { __index = function() return function() end end })
-- ButtonAdd only builds a row for a quest that is IN the questlog (tracker.lua:855),
-- so the harness has to look like a player who actually has these quests.
local questlog = {}
for i, q in pairs(QUESTS) do
  questlog[i] = { title = q.title, qlogid = i, ids = { i } }
end
_G.pfQuest = { questlog = questlog, tracker = nil,
               debug = function() end, UpdateQuestlog = function() end }
-- pfMap.tooltip is a TABLE the tracker indexes, so it cannot come from a catch-all
-- that hands back functions (tracker.lua:646 indexes it).
_G.pfMap = setmetatable({ nodes = {}, str2rgb = function() return 1, 1, 1 end,
                          -- GetColor must return three numbers: the tracker does
                          -- arithmetic on them directly (tracker.lua:634, 659).
                          tooltip = setmetatable({ GetColor = function(_, cur, maxv)
                            -- the tracker passes objective counts parsed out of text,
                            -- so they can arrive as strings
                            cur, maxv = tonumber(cur) or 0, tonumber(maxv) or 0
                            local p = maxv > 0 and (cur / maxv) or 0
                            return 1 - p * 0.8, 0.2 + p * 0.8, 0.2
                          end }, { __index = function() return function() end end }) },
                        { __index = function() return function() end end })
_G.pfDatabase = setmetatable({}, { __index = function() return function() end end })
_G.pfDB = { quests = { loc = {}, data = {} }, zones = { loc = {} } }
_G.pfUI = { font_default = "Fonts\\FRIZQT__.TTF" }
_G.pfUI_config = { global = { font_size = 12 } }
_G.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return tostring(k) end })

dofile("theme.lua")
local loaded, err = pcall(dofile, "tracker.lua")
if not loaded then
  fail("tracker.lua could not be loaded under the stub: %s", tostring(err))
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end
ok("tracker.lua loads and builds its frames")

local tracker = _G.pfQuest and _G.pfQuest.tracker or _G.tracker
if type(tracker) ~= "table" or type(tracker.ButtonAdd) ~= "function" then
  fail("tracker table / ButtonAdd not reachable after load")
  print(string.format("\n%d checks, %d failure(s)", checks, failures))
  os.exit(1)
end

-- ---------------------------------------------------------------------------
-- drive the REAL row-building chain
-- ---------------------------------------------------------------------------
local function addRow(title, questid)
  return pcall(tracker.ButtonAdd, title, { dummy = true, addon = "PFQUEST",
                                           questid = questid, texture = "img\\complete" })
end

for i = 1, 3 do
  local q = QUESTS[i]
  local okc, e = addRow(q.title, i)
  check(okc, "ButtonAdd(%q)%s", q.title, okc and "" or " -> " .. tostring(e))
end

-- ButtonAdd only clears the bar; the PERCENTAGE comes from ButtonEvent, which is the
-- real code that reads the quest log and calls SetProgress. Drive it, or the fill
-- assertion below passes vacuously.
local evented = 0
for _, b in pairs(tracker.buttons or {}) do
  if not b.empty then
    b.questid = b.questid or 1
    local okE = pcall(tracker.ButtonEvent, b)
    if okE then evented = evented + 1 end
  end
end
check(evented > 0, "ButtonEvent ran on %d row(s)", evented)

local okc, e = pcall(tracker.DoLayout)
check(okc, "DoLayout()%s", okc and "" or " -> " .. tostring(e))

-- assertions on what the real code produced
local rows, withBars = 0, 0
for _, b in pairs(tracker.buttons or {}) do
  if not b.empty then rows = rows + 1 end
  if b.bar then withBars = withBars + 1 end
end
check(rows >= 1, "produced %d live row(s)", rows)
check(withBars >= 1, "%d row(s) own a progress bar", withBars)
check((tracker:GetWidth() or 0) > 0, "tracker sized itself (width %s)", tostring(tracker:GetWidth()))

-- NOT asserted here: the bar FILL. ButtonEvent needs richer questlog data than this
-- harness fakes, so any fill assertion at this level would pass without measuring
-- anything, which reads as coverage while testing nothing. The fill arithmetic is
-- covered properly in tools/runtimecheck335.lua, which drives the bar directly with a
-- known track width. Widening the questlog fake to reach it here is the next step.
check(tracker:GetScale() == 1, "trackerscale applied (scale %s)", tostring(tracker:GetScale()))

-- the setting paths, driven through the real code
pfQuest_config["trackerscale"] = "1.5"
pcall(tracker.DoLayout)
check(math.abs((tracker:GetScale() or 0) - 1.5) < 0.001,
      "trackerscale=1.5 -> scale %s", tostring(tracker:GetScale()))

pfQuest_config["trackerbars"] = "0"
local okb = pcall(tracker.DoLayout)
check(okb, "DoLayout() with progress bars disabled%s", okb and "" or " -> errored")
pfQuest_config["trackerbars"] = "1"
pfQuest_config["trackerscale"] = "1"

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
