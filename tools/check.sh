#!/usr/bin/env bash
# pfQuest-Reforged verification gates. Run from the addon root: ./tools/check.sh
set -uo pipefail
fail=0

echo "== [1/7] Lua 5.1 parse (the 3.3.5a client's Lua) =="
if ! find . -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n1 luac5.1 -p; then
  echo "  parse FAILED"; fail=1
else
  echo "  all files parse."
fi

echo
echo "== [2/7] 3.3.5a API surface (vs milkyway-codex) =="
python3 tools/apicheck335.py || fail=1

echo
echo "== [3/7] runtime: build our objects and drive them =="
lua5.1 tools/runtimecheck335.lua || fail=1

echo
echo "== [4/7] end-to-end: load the real tracker and build rows =="
lua5.1 tools/trackercheck335.lua || fail=1

echo
echo "== [5/7] compass: contract harness =="
lua5.1 tools/compasscheck335.lua compass.lua || fail=1

echo
echo "== [6/7] pins: contract harness =="
lua5.1 tools/pinscheck335.lua pins.lua || fail=1

echo
echo "== [7/7] nameplates: contract harness =="
lua5.1 tools/platecheck335.lua nameplates.lua || fail=1

echo
if [ "$fail" -ne 0 ]; then echo "CHECKS FAILED"; exit 1; fi
echo "ALL CHECKS PASSED"
