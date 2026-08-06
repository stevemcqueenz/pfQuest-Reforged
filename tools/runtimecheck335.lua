-- Runtime check: build our own UI objects and DRIVE them, under the 3.3.5a stub.
--
-- Why this exists: tools/loadall-style checks LOAD every file and confirm it parses,
-- but they never build a tracker row, so a method that does not exist on one of our
-- objects is invisible to them. That is exactly how v1.0.30 shipped
--   tracker.lua:523: attempt to call method 'Show' (a nil value)
-- with a green parse and a green load. The progress bar is a plain Lua table, not a
-- frame, so it only has the methods theme.lua defines -- and Hide existed while Show
-- never did.
--
-- So: for each of our own objects, declare the methods the addon actually calls on it,
-- assert they exist, then run the real call sequence and check the result.
--
-- Usage: lua5.1 tools/runtimecheck335.lua   (from the addon root)

local failures, checks = 0, 0
local function fail(fmt, ...) failures = failures + 1; print("  FAIL  " .. string.format(fmt, ...)) end
local function ok(fmt, ...) checks = checks + 1; print("  ok    " .. string.format(fmt, ...)) end

local function requireMethods(obj, objname, methods)
  for _, m in ipairs(methods) do
    if type(obj[m]) ~= "function" then
      fail("%s is missing :%s() -- something calls it", objname, m)
    else
      checks = checks + 1
    end
  end
end

local function drive(label, fn)
  local okc, err = pcall(fn)
  if okc then ok(label) else fail("%s -> %s", label, tostring(err)) end
end

-- ---------------------------------------------------------------------------
-- minimal 3.3.5a-shaped widget stub (textures track their own width so fill
-- arithmetic is actually exercised, not just called)
-- ---------------------------------------------------------------------------
local function mkTexture()
  local t = { w = 0, shown = true }
  local noop = function() end
  return setmetatable(t, { __index = function(_, k)
    if k == "SetWidth" then return function(s, v) s.w = v end end
    if k == "GetWidth" then return function(s) return s.w end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    return noop
  end })
end
local parent = { CreateTexture = function() return mkTexture() end }
_G.pfQuest_config = {}
_G.GetLocale = function() return "enUS" end
_G.IsAddOnLoaded = function() return nil end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
_G.UIParent = _G.CreateFrame()

print("== pfQuest runtime check (3.3.5a stub) ==")

-- ---------------------------------------------------------------------------
-- theme.lua :: progress bar  (the object that broke in v1.0.30)
-- ---------------------------------------------------------------------------
dofile("theme.lua")
local T = _G.pfQuestTheme
if not T or not T.CreateProgressBar then
  fail("pfQuestTheme.CreateProgressBar missing")
else
  local bar = T.CreateProgressBar(parent, 3)
  -- every method tracker.lua calls on a bar
  requireMethods(bar, "progress bar", { "SetPoint", "SetProgress", "Refresh", "SetEnabled", "Hide" })

  -- ButtonAdd / Reset path: enable, then clear
  drive("bar: reset path (SetEnabled + SetProgress(nil))", function()
    bar:SetEnabled(pfQuest_config["trackerbars"] ~= "0")
    bar:SetProgress(nil)
  end)

  -- percentage path, then the post-layout refresh the tracker performs
  drive("bar: percentage path + post-layout Refresh", function()
    bar:SetEnabled(pfQuest_config["trackerbars"] ~= "0")
    bar:SetProgress(1.0, 1, 1, 1)
    bar.track.w = 180
    bar:Refresh()
  end)
  if bar.fill.w == 180 then ok("bar: 100%% fills the full track (180px)")
  else fail("bar: 100%% filled %s px, expected 180 (the v1.0.30 sliver bug)", tostring(bar.fill.w)) end

  drive("bar: 25%% fills a quarter", function()
    bar:SetProgress(0.25); bar:Refresh()
  end)
  if bar.fill.w == 45 then ok("bar: 25%% fills 45px")
  else fail("bar: 25%% filled %s px, expected 45", tostring(bar.fill.w)) end

  -- bars turned off
  pfQuest_config["trackerbars"] = "0"
  drive("bar: disabled path", function()
    bar:SetEnabled(pfQuest_config["trackerbars"] ~= "0")
    bar:SetProgress(1.0, 1, 1, 1)
    bar:Refresh()
  end)
  if bar.track.shown == false and bar.fill.shown == false then ok("bar: disabled hides both textures")
  else fail("bar: disabled left track=%s fill=%s shown", tostring(bar.track.shown), tostring(bar.fill.shown)) end
  pfQuest_config["trackerbars"] = nil
end

print(string.format("\n%d checks, %d failure(s)", checks, failures))
os.exit(failures > 0 and 1 or 0)
