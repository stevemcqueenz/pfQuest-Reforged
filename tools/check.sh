#!/usr/bin/env bash
# pfQuest-Reforged verification gates. Run from the addon root: ./tools/check.sh
set -uo pipefail
fail=0

echo "== [1/11] Lua 5.1 parse (the 3.3.5a client's Lua) =="
if ! find . -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n1 luac5.1 -p; then
  echo "  parse FAILED"; fail=1
else
  echo "  all files parse."
fi

echo
echo "== [2/11] XML well-formedness (the client's parser is not forgiving) =="
# A double hyphen INSIDE a comment ends it early and the parser drops the rest
# of the file: that is how db/poi-wotlk335.lua and db/tracking335.lua silently
# stopped loading on dev, which surfaced in-game as "/way flight" reporting no
# flight master in Orgrimmar. There was no XML gate here at all until then.
if command -v xmllint >/dev/null 2>&1; then
  xmlfail=0
  for f in $(find . -name '*.xml' -not -path './.git/*'); do
    xmllint --noout "$f" || xmlfail=1
  done
  if [ "$xmlfail" -ne 0 ]; then echo "  XML FAILED"; fail=1; else echo "  all xml well-formed."; fi
else
  echo "  xmllint not installed -- SKIPPED (install libxml2-utils)"; fail=1
fi

echo
echo "== [3/11] 3.3.5a API surface (vs milkyway-codex) =="
python3 tools/apicheck335.py || fail=1

echo
echo "== [4/11] runtime: build our objects and drive them =="
lua5.1 tools/runtimecheck335.lua || fail=1

echo
echo "== [5/11] end-to-end: load the real tracker and build rows =="
lua5.1 tools/trackercheck335.lua || fail=1

echo
echo "== [6/11] tracking data: db/tracking335.lua and the merge that consumes it =="
lua5.1 tools/trackingcheck335.lua || fail=1

echo
echo "== [7/11] quest reworks: db/wotlkrework335.lua and the merge that applies it =="
lua5.1 tools/reworkcheck335.lua || fail=1

echo
echo "== [8/11] skill ranks: db/quests-skillrank335.lua, its merge and the filter =="
lua5.1 tools/skillrankcheck335.lua || fail=1

echo
echo "== [9/11] compass: contract harness =="
lua5.1 tools/compasscheck335.lua compass.lua || fail=1

echo
echo "== [10/11] pins: contract harness =="
lua5.1 tools/pinscheck335.lua pins.lua || fail=1

echo
echo "== [11/11] nameplates: contract harness =="
lua5.1 tools/platecheck335.lua nameplates.lua || fail=1

echo
if [ "$fail" -ne 0 ]; then echo "CHECKS FAILED"; exit 1; fi
echo "ALL CHECKS PASSED"
