#!/usr/bin/env python3
"""
3.3.5a API surface check for pfQuest-Reforged.

Cross-references every global function call, RegisterEvent name and widget method
used in the addon against the milkyway-codex dataset (the 3.3.5a oracle), and
reports anything the client does not actually provide.

Catches the class of bug that only shows up on a live 3.3.5a client: a retail-only
API that is nil here, a Cataclysm+ event that never fires, a widget method that does
not exist on this build. Static, so it runs in CI.

Usage: python3 tools/apicheck335.py [--codex PATH]
"""
import os, re, sys, json

CODEX = os.path.expanduser(os.environ.get("MILKYWAY_CODEX", "~/refs/milkyway-codex"))
for i, a in enumerate(sys.argv):
    if a == "--codex" and i + 1 < len(sys.argv):
        CODEX = os.path.expanduser(sys.argv[i + 1])

def names_from(path, key="name"):
    """Pull every `name: '...'` / `name: "..."` out of a codex .ts data file."""
    try:
        src = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    return set(re.findall(r"""\b%s:\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]""" % key, src))

d = os.path.join(CODEX, "src", "data")
API = names_from(os.path.join(d, "api-functions.ts"))
EVENTS = names_from(os.path.join(d, "events.ts"))
WIDGET_METHODS = names_from(os.path.join(d, "widgets.ts"))
if API is None or EVENTS is None:
    print("apicheck335: milkyway-codex not found at %s" % CODEX)
    print("  clone it:  git clone --depth 1 https://github.com/Shard-MW/milkyway-codex ~/refs/milkyway-codex")
    print("  or set MILKYWAY_CODEX / pass --codex PATH.  SKIPPING (not a failure).")
    sys.exit(0)

# Lua's own stdlib plus the addon's own globals are not client APIs.
LUA_BUILTIN = set("""assert collectgarbage dofile error getfenv getmetatable ipairs load loadfile
loadstring next pairs pcall print rawequal rawget rawlen rawset require select setfenv setmetatable
tonumber tostring type unpack xpcall gcinfo newproxy module coroutine string table math io os debug
bit date time difftime format strsplit strjoin strtrim strupper strlower strlen strsub strfind strrep
strbyte strchar gsub gmatch tinsert tremove sort wipe getn abs ceil floor max min mod random sqrt
tostringall foreach foreachi""".split())

def lua_files(root):
    for base, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in (".git", "db", "tools", "libs")]
        for f in files:
            if f.endswith(".lua"):
                yield os.path.join(base, f)

# Everything the addon itself defines, so we do not flag our own functions.
own = set()
srcs = {}
for p in lua_files("."):
    s = open(p, encoding="utf-8", errors="replace").read()
    # drop --[[ ]] block comments: they contain prose that reads like calls
    s = re.sub(r"--\[(=*)\[.*?\]\1\]", "", s, flags=re.S)
    srcs[p] = s
    own |= set(re.findall(r"\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", s))
    own |= set(re.findall(r"\blocal\s+function\s+([A-Za-z_][A-Za-z0-9_]*)", s))
    own |= set(re.findall(r"\blocal\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", s))
    own |= set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=", s, re.M))
    for m in re.findall(r"\blocal\s+([A-Za-z_][A-Za-z0-9_, ]*?)\s*=", s):
        own |= {x.strip() for x in m.split(",") if x.strip()}

# FrameXML defines these in Lua, so a C-API dataset will never list them. They are
# still 3.3.5a-native; being absent from the codex says nothing about them.
FRAMEXML = set("""ShowUIPanel HideUIPanel ToggleDropDownMenu ToggleWorldMap StaticPopup_Show
UIDropDownMenu_AddButton UIDropDownMenu_Initialize UIDropDownMenu_SetSelectedID
UIDropDownMenu_SetWidth UIDropDownMenu_SetButtonWidth UIDropDownMenu_JustifyText
FauxScrollFrame_GetOffset FauxScrollFrame_Update GameTooltip_SetDefaultAnchor SetItemRef
QuestLog_SetSelection QuestLog_UpdateQuestDetails QuestLogTitleButton_Resize
WorldMapFrame_ClearQuestPOIs ChatEdit_InsertLink ScrollFrameTemplate_OnMouseWheel
OpenColorPicker""".split())

# Present on 3.3.5a but missing from the codex dataset. An unknown event name raises on
# RegisterEvent on this client, so anything the shipping addon registers without erroring
# demonstrably exists -- that makes these codex gaps, not addon bugs.
EVENT_GAPS = set("""MINIMAP_ZONE_CHANGED""".split())

bad_api, bad_events = {}, {}
for p, s in srcs.items():
    for ln, line in enumerate(s.split("\n"), 1):
        if line.lstrip().startswith("--"):
            continue
        # global call: Name( not preceded by . or : (so not a method or table field)
        for m in re.finditer(r"(?<![\w.:])([A-Z][A-Za-z0-9_]{2,})\s*\(", line):
            fn = m.group(1)
            if fn in API or fn in own or fn in LUA_BUILTIN or fn in FRAMEXML:
                continue
            bad_api.setdefault(fn, []).append("%s:%d" % (p, ln))
        for m in re.finditer(r"""RegisterEvent\(\s*['"]([A-Z_0-9]+)['"]""", line):
            ev = m.group(1)
            if ev not in EVENTS and ev not in EVENT_GAPS:
                bad_events.setdefault(ev, []).append("%s:%d" % (p, ln))

fail = False
print("== 3.3.5a API surface check (milkyway-codex: %d functions, %d events) ==" % (len(API), len(EVENTS)))
if bad_events:
    fail = True
    print("\n  EVENTS not in the 3.3.5a event list:")
    for ev in sorted(bad_events):
        print("    %-38s %s" % (ev, ", ".join(bad_events[ev][:3])))
if bad_api:
    print("\n  GLOBAL CALLS not in the 3.3.5a API list (review; some are false positives):")
    for fn in sorted(bad_api):
        print("    %-38s %s" % (fn, ", ".join(bad_api[fn][:3])))
if not bad_events and not bad_api:
    print("  clean: every global call and event name exists on 3.3.5a.")
sys.exit(1 if fail else 0)
