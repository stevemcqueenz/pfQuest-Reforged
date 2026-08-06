#!/usr/bin/env bash
# pfQuest-Reforged verification gates. Run from the addon root: ./tools/check.sh
set -uo pipefail
fail=0

echo "== [1/6] Lua 5.1 parse (the 3.3.5a client's Lua) =="
if ! find . -name '*.lua' -not -path './.git/*' -print0 | xargs -0 -n1 luac5.1 -p; then
  echo "  parse FAILED"; fail=1
else
  echo "  all files parse."
fi

echo
echo "== [2/6] 3.3.5a API surface (vs milkyway-codex) =="
python3 tools/apicheck335.py || fail=1

echo
echo "== [3/6] runtime: build our objects and drive them =="
lua5.1 tools/runtimecheck335.lua || fail=1

echo
echo "== [4/6] end-to-end: load the real tracker and build rows =="
lua5.1 tools/trackercheck335.lua || fail=1

echo
echo "== [5/6] compass: contract harness =="
lua5.1 tools/compasscheck335.lua compass.lua || fail=1

echo
echo "== [6/6] pins: stage-1 contract harness =="
lua5.1 tools/pinscheck335.lua pins.lua || fail=1

echo
if [ "$fail" -ne 0 ]; then echo "CHECKS FAILED"; exit 1; fi
echo "ALL CHECKS PASSED"
