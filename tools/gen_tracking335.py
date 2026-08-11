#!/usr/bin/env python3
"""Generate db/tracking335.lua -- the Outland and Northrend entries for pfQuest's
map tracking lists (herbs, mines, chests, fishing pools, rare mobs), from an
AzerothCore world DB.

Why this file exists (issue #18)
--------------------------------
pfQuest's pfDB["meta"] tracking lists are vanilla plus TBC. Northrend has ZERO
entries in every one of them, so "Herbs & Flowers", "Mines & Ores", "Chests &
Treasures", "Fishing" and "Rare Mobs" all find nothing anywhere in Northrend.
Outland is mostly covered, with one big hole: every WotLK ore and herb is
missing an object entry outright, and the TBC ores and several TBC herbs ship an
object entry with an EMPTY coords table, so Outland mining found nothing either.

This tool fills both, from the same world database the servers run.

Source data
-----------
AzerothCore ships its full 3.3.5a world database as per-table mysqldump files
inside the main repo (data/sql/base/db_world/*.sql), so no MySQL server and no
release archive is needed. Fetch the tables this tool reads, pinned to a commit
for reproducibility:

    SHA=$(git ls-remote https://github.com/azerothcore/azerothcore-wotlk.git refs/heads/master | cut -f1)
    mkdir -p ~/refs/ac-world && cd ~/refs/ac-world && echo "$SHA" > sha.txt
    for f in creature_template creature gameobject_template gameobject \
             game_event_creature game_event_gameobject; do
      curl -sSL -O "https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/$SHA/data/sql/base/db_world/$f.sql"
    done

The gathering roster (which gameobject names are gatherable, which profession
they belong to and the skill each one requires) is read from GatherMate 1's
Constants.lua -- a curated list that deliberately excludes instance-only and
loot-only pseudo-nodes. Any GatherMate 1 install works; the one used here is
github.com/stevemcqueenz/gathermate-and-database-3.3.5a.

    python3 tools/gen_tracking335.py --ac-dir ~/refs/ac-world \
        --gathermate ~/gathermate-and-database-3.3.5a/GatherMate

What each track is, and where it comes from
-------------------------------------------
  herbs   gameobject on GatherMate's "Herb Gathering" roster; value = the
          gathering skill it requires (drives the tracking slider)
  mines   gameobject on GatherMate's "Mining" roster; value = required skill
  chests  gameobject on GatherMate's "Treasure" roster; value = 0
  fish    gameobject_template.type = 25 (GAMEOBJECT_TYPE_FISHINGHOLE);
          value = "AH" (pfQuest's non-skill tracks store a faction STRING and
          are matched with string.find, so this must not be a number)
  rares   creature_template.rank 2 (rare elite) or 4 (rare); value = the mob's
          level as a NUMBER, matching pfQuest's own meta.rares

Coordinate transform (same method as db/units-wotlk-acfill335.lua and
tools/gen_poi335.py)
--------------------------------------------------------------------------
World (x,y) -> per-zone map percent is fitted EMPIRICALLY, per zone, from
entities that exist in BOTH the AC dump and pfQuest's merged database with a
single unambiguous spawn on each side: map-percent is a linear function of the
world coordinate (pctX of world Y, pctY of world X). Least squares with
iterative outlier rejection; a zone is REJECTED unless it has >= MIN_PAIRS
clean pairs and a median residual <= MAX_MEDIAN_RESID percent, so nothing is
emitted for zones we cannot map reliably.

A gameobject's zone is AC's own gameobject.zoneId, which is already pfQuest's
zone id space and is set on 98% of the rows here. AC leaves creature.zoneId at
0 almost everywhere, so creatures are placed by fitted-rectangle containment
instead, minus the world boxes of the zones we have no rectangle for (below).

Wintergrasp, Crystalsong Forest and Hrothgar's Landing
------------------------------------------------------
pfQuest has no spawns in any of the three to fit a model from. Wintergrasp and
Crystalsong Forest are covered anyway, from the WorldMapArea rectangle shipped
by Questie-335's QuestieCompat.UiMapData -- see UIMAP_RECTS below for what that
source is worth and where it must NOT be used. Hrothgar's Landing stays out:
nothing pfQuest tracks spawns there, so a rectangle for it could not be checked
and would gain nothing.

Anything landing in a zone with no model at all is DROPPED, never assigned to a
neighbour: neighbouring map rectangles overlap well past the playable edge, so
such a node would otherwise land in the wrong zone entirely. Those zones' world
extents are derived from the AC rows that do carry a zoneId.

Emission policy -- fill only, never overwrite
---------------------------------------------
A coordinate is emitted for an entity in a zone ONLY when pfQuest's merged
database has no coordinate for that entity in that zone at all, so the merge in
database.lua can append without ever duplicating an existing node and vanilla
data is untouched by construction. Measured on the Outland overlap: 97.7% of
the AC spawns this rule skips sit within 0.3% of the pfQuest coordinate they
would have duplicated, which is both why the rule is right and an independent
check on the transform.

Validation (printed on every run)
---------------------------------
  * the GatherMate skill values are cross-checked against pfQuest's own meta
    herbs/mines entries for the objects both sides know -- a mismatch means the
    name->node mapping is wrong and the run aborts;
  * zone labels vs fitted rectangles, reported as an agreement rate;
  * per-track counts, per-zone 0..100 range assertion, and the skip reasons.
"""

import argparse
import math
import os
import re
import statistics
import subprocess
import sys
import tempfile

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)

CONTINENTS = {0, 1, 530, 571}
# Maps we EMIT for. The fit needs all four continents (Azeroth supplies most of
# the calibration pairs), but only Outland and Northrend are filled in: they are
# the reported gap, and leaving Azeroth alone means a bugfix release cannot
# disturb the vanilla tracking data that already works.
EMIT_MAPS = {530, 571}
MIN_PAIRS = 5
MAX_MEDIAN_RESID = 1.5   # percent; same rejection bar as the acfill pipeline
DEDUP_DIST = 0.3         # percent; collapse near-identical spawns
FIT_ITERATIONS = 3
GO_TYPE_FISHINGHOLE = 25
CREATURE_RANK_RARE = {2, 4}   # 2 = rare elite, 4 = rare
OUT = os.path.join(ROOT, "db", "tracking335.lua")

# GatherMate category -> pfQuest meta track name.
CATEGORY = {
    "Mining": "mines",
    "Herb Gathering": "herbs",
    "Treasure": "chests",
}
# Tracks keyed by a NEGATIVE object id in pfDB.meta, vs by a positive unit id.
OBJECT_TRACKS = ("herbs", "mines", "chests", "fish")
UNIT_TRACKS = ("rares",)


# ---------------------------------------------------------------- pfQuest side

LUA_DUMP = r"""
-- Loads pfQuest's database files exactly like init/data.xml + data-tbc.xml +
-- data-wotlk.xml do, applies database.lua's patchtable semantics (an overlay
-- entry replaces the base entry outright), and dumps the merged database as TSV.
dofile("db/init.lua")
dofile("db/units.lua")
dofile("db/units-tbc.lua")
dofile("db/units-wotlk.lua")
dofile("db/units-wotlk-sw335.lua")
dofile("db/units-wotlk-icecrown335.lua")
dofile("db/units-wotlk-acfill335.lua")
dofile("db/objects.lua")
dofile("db/objects-tbc.lua")
dofile("db/objects-wotlk.lua")
dofile("db/objects-wotlk-sw335.lua")
dofile("db/minimap.lua")
dofile("db/minimap-tbc.lua")
dofile("db/minimap-wotlk335.lua")
dofile("db/meta.lua")
dofile("db/meta-tbc.lua")
dofile("db/enUS/objects.lua")
dofile("db/enUS/objects-tbc.lua")
dofile("db/enUS/objects-wotlk.lua")
dofile("db/enUS/units.lua")
dofile("db/enUS/units-tbc.lua")
dofile("db/enUS/units-wotlk.lua")

-- expansion patch order mirrors database.lua: -tbc first, then -wotlk
local function patch(base, diff)
  for k, v in pairs(diff) do
    if type(v) == "string" and v == "_" then base[k] = nil else base[k] = v end
  end
end
patch(pfDB["units"]["data"], pfDB["units"]["data-tbc"])
patch(pfDB["units"]["data"], pfDB["units"]["data-wotlk"])
patch(pfDB["objects"]["data"], pfDB["objects"]["data-tbc"])
patch(pfDB["objects"]["data"], pfDB["objects"]["data-wotlk"])
patch(pfDB["objects"]["enUS"], pfDB["objects"]["enUS-tbc"])
patch(pfDB["objects"]["enUS"], pfDB["objects"]["enUS-wotlk"])
patch(pfDB["units"]["enUS"], pfDB["units"]["enUS-tbc"])
patch(pfDB["units"]["enUS"], pfDB["units"]["enUS-wotlk"])
patch(pfDB["minimap"], pfDB["minimap-tbc"])
patch(pfDB["minimap"], pfDB["minimap-wotlk"])
patch(pfDB["meta"], pfDB["meta-tbc"])

local function dump(tag, data)
  for id, entry in pairs(data) do
    if entry.coords then
      for _, c in pairs(entry.coords) do
        if c[1] and c[2] and c[3] then
          print(string.format("%s\t%d\t%.4f\t%.4f\t%d", tag, id, c[1], c[2], c[3]))
        end
      end
    end
  end
end
dump("U", pfDB["units"]["data"])
dump("O", pfDB["objects"]["data"])
for zone, size in pairs(pfDB["minimap"]) do
  print(string.format("M\t%d\t%.2f\t%.2f\t%d", zone, size[1], size[2], zone))
end
for id, name in pairs(pfDB["objects"]["enUS"]) do print(string.format("NO\t%d\t%s", id, name)) end
for id, name in pairs(pfDB["units"]["enUS"]) do print(string.format("NU\t%d\t%s", id, name)) end
-- existing tracking entries, so we never restate what pfQuest already answers
for _, track in pairs({"herbs", "mines", "chests", "fish", "rares"}) do
  for id, value in pairs(pfDB["meta"][track]) do
    print(string.format("S\t%d\t%s\t%s", id, track, tostring(value)))
  end
end
-- ids whose coords come from the wotlk overlay -- the trustworthy fit source
-- for zone 1519, where pfQuest's vanilla coords use the 1.12 rect.
for id in pairs(pfDB["units"]["data-wotlk"]) do print(string.format("WU\t%d\t0\t0\t0", id)) end
for id in pairs(pfDB["objects"]["data-wotlk"]) do print(string.format("WO\t%d\t0\t0\t0", id)) end
"""


class PfQuest(object):
    def __init__(self):
        self.units = {}
        self.objects = {}
        self.minimap = {}
        self.unitnames = {}
        self.objectnames = {}
        self.meta = {}           # (track, signed id) -> value as text
        self.corrected = {"U": set(), "O": set()}

    def coords(self, kind):
        return self.units if kind == "U" else self.objects

    def names(self, kind):
        return self.unitnames if kind == "U" else self.objectnames


def load_pfquest():
    """Merged pfQuest database via a real lua5.1 load (exact patchtable
    semantics)."""
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write(LUA_DUMP)
        script = f.name
    try:
        out = subprocess.run(["lua5.1", script], cwd=ROOT, check=True,
                             capture_output=True, text=True).stdout
    finally:
        os.unlink(script)
    pf = PfQuest()
    for line in out.splitlines():
        parts = line.split("\t")
        tag = parts[0]
        if tag == "M":
            pf.minimap[int(parts[4])] = (float(parts[2]), float(parts[3]))
        elif tag == "NO":
            pf.objectnames[int(parts[1])] = parts[2]
        elif tag == "NU":
            pf.unitnames[int(parts[1])] = parts[2]
        elif tag == "S":
            pf.meta[(parts[2], int(parts[1]))] = parts[3]
        elif tag in ("WU", "WO"):
            pf.corrected[tag[1]].add(int(parts[1]))
        else:
            pf.coords(tag).setdefault(int(parts[1]), []).append(
                (float(parts[2]), float(parts[3]), int(parts[4])))
    return pf


# ------------------------------------------------------------- GatherMate side

def load_nodes(gathermate_dir):
    """Read GatherMate 1's curated gathering roster from Constants.lua.

    Returns name -> (track, nodeid, skill). Commented-out node lines (the
    instance-only and loot-only pseudo-nodes) are skipped by construction: the
    regexes only match live entries.
    """
    path = os.path.join(gathermate_dir, "Constants.lua")
    if not os.path.exists(path):
        sys.exit("missing %s -- point --gathermate at a GatherMate 1 addon "
                 "folder" % path)
    txt = open(path, encoding="utf-8-sig", errors="replace").read()

    # node_ids: ["<category>"] = { [NL["<name>"]] = <id>, ... }
    by_name, cat = {}, None
    cats = "|".join(re.escape(c) for c in CATEGORY)
    for line in txt.splitlines():
        if re.match(r"\s*--", line):
            continue
        mcat = re.search(r'\["(%s)"\]\s*=\s*\{' % cats, line)
        if mcat:
            cat = mcat.group(1)
            continue
        if cat is None:
            continue
        m = re.search(r'NL\["([^"]+)"\]\]\s*=\s*(\d+)', line)
        if m:
            by_name[m.group(1)] = (cat, int(m.group(2)))
        elif re.match(r"\s*\}", line):
            cat = None

    # node_minharvest: ["<category>"] = { [<id>] = <skill>, ... }; a later
    # duplicate key wins, exactly as the Lua table constructor would resolve it
    block = txt.split("local node_minharvest", 1)
    if len(block) != 2:
        sys.exit("no node_minharvest table in %s" % path)
    skill, cat = {}, None
    for line in block[1].splitlines():
        if re.match(r"\s*--", line):
            continue
        mcat = re.search(r'\["(%s)"\]\s*=\s*\{' % cats, line)
        if mcat:
            cat = mcat.group(1)
            continue
        if cat is None:
            continue
        m = re.search(r"\[(\d+)\]\s*=\s*(\d+)", line)
        if m:
            skill[(cat, int(m.group(1)))] = int(m.group(2))
        elif re.match(r"\s*\}", line):
            cat = None
        if line.startswith("GatherMate.nodeMinHarvest"):
            break

    nodes = {}
    for name, (cat, nid) in by_name.items():
        nodes[name] = (CATEGORY[cat], nid, skill.get((cat, nid), 0))
    return nodes


# ------------------------------------------------------------ AC dump parsing

def sql_rows(path, table):
    """Yield value tuples from mysqldump `INSERT INTO `table` VALUES` blocks
    (one row per parenthesized tuple, statements spanning multiple lines)."""
    prefix = "INSERT INTO `%s` VALUES" % table
    ESC = {"n": "\n", "r": "\r", "t": "\t", "0": "\0", "Z": "\x1a"}
    with open(path, encoding="utf-8", errors="replace") as f:
        in_insert = False
        in_row = in_str = esc = False
        row, field = [], []
        for line in f:
            if not in_insert:
                if line.startswith(prefix):
                    in_insert = True
                    line = line[len(prefix):]
                else:
                    continue
            for ch in line:
                if in_row:
                    if in_str:
                        if esc:
                            field.append(ESC.get(ch, ch))
                            esc = False
                        elif ch == "\\":
                            esc = True
                        elif ch == "'":
                            in_str = False
                        else:
                            field.append(ch)
                    elif ch == "'":
                        in_str = True
                    elif ch == ",":
                        row.append("".join(field))
                        field = []
                    elif ch == ")":
                        row.append("".join(field))
                        yield row
                        row, field, in_row = [], [], False
                    elif ch not in "\r\n":
                        field.append(ch)
                elif ch == "(":
                    in_row = True
                elif ch == ";":
                    in_insert = False
                    break


class Ac(object):
    """type/name/rank metadata plus (map, zone, worldX, worldY, respawn) spawns,
    for both creatures and gameobjects."""

    def __init__(self):
        self.gt = {}       # entry -> (type, name)
        self.ct = {}       # entry -> (name, rank, minlevel, maxlevel)
        self.gspawn = {}
        self.cspawn = {}

    def spawns(self, kind):
        return self.cspawn if kind == "U" else self.gspawn


def load_ac(ac_dir):
    """Parse the AC tables into plain dicts (column order from each dump's
    CREATE TABLE, azerothcore-wotlk data/sql/base/db_world)."""
    p = lambda name: os.path.join(ac_dir, name + ".sql")
    for name in ("creature_template", "creature", "gameobject_template",
                 "gameobject", "game_event_creature", "game_event_gameobject"):
        if not os.path.exists(p(name)):
            sys.exit("missing %s -- see the fetch instructions in this file's "
                     "docstring" % p(name))
    ac = Ac()

    # eventEntry > 0 = spawned only during the event -> exclude those guids
    ev_creature = {int(r[1]) for r in sql_rows(p("game_event_creature"), "game_event_creature")
                   if int(r[0]) > 0}
    ev_go = {int(r[1]) for r in sql_rows(p("game_event_gameobject"), "game_event_gameobject")
             if int(r[0]) > 0}

    # gameobject_template: entry=1 type=2 name=4
    for r in sql_rows(p("gameobject_template"), "gameobject_template"):
        ac.gt[int(r[0])] = (int(r[1]), r[3])
    # creature_template: entry=1 name=7 minlevel=11 maxlevel=12 rank=21
    for r in sql_rows(p("creature_template"), "creature_template"):
        ac.ct[int(r[0])] = (r[6], int(r[20]), int(r[10]), int(r[11]))
    # creature: guid=1 id1=2 map=5 zoneId=6 x=11 y=12 spawntimesecs=15
    for r in sql_rows(p("creature"), "creature"):
        if int(r[4]) not in CONTINENTS or int(r[0]) in ev_creature:
            continue
        ac.cspawn.setdefault(int(r[1]), []).append(
            (int(r[4]), int(r[5]), float(r[10]), float(r[11]), int(r[14])))
    # gameobject: guid=1 id=2 map=3 zoneId=4 x=8 y=9 spawntimesecs=17
    for r in sql_rows(p("gameobject"), "gameobject"):
        if int(r[2]) not in CONTINENTS or int(r[0]) in ev_go:
            continue
        ac.gspawn.setdefault(int(r[1]), []).append(
            (int(r[2]), int(r[3]), float(r[7]), float(r[8]), int(r[16])))
    return ac


# ------------------------------------------------------------------- fitting

def linfit(samples):
    """Least squares y = a + b*x over [(x, y)]; returns (a, b)."""
    n = len(samples)
    sx = sum(s[0] for s in samples)
    sy = sum(s[1] for s in samples)
    sxx = sum(s[0] * s[0] for s in samples)
    sxy = sum(s[0] * s[1] for s in samples)
    den = n * sxx - sx * sx
    if den == 0:
        return None
    b = (n * sxy - sx * sy) / den
    a = (sy - b * sx) / n
    return a, b


STALE_RECT_ZONES = {1519}


def fit_zones(pf, ac):
    """Per-zone linear world->percent models from single-spawn pairs.

    pctX is a function of world Y, pctY of world X (the WoW axis convention;
    the fit finds the signs on its own). Stormwind (1519) is fitted from
    wotlk-overlay pairs ONLY: pfQuest's vanilla coords there use the 1.12 map
    rectangle, which the sw335 correction established is wrong for this client.
    """
    by_zone = {}
    for kind in ("U", "O"):
        spawn_table = ac.spawns(kind)
        for eid, coords in pf.coords(kind).items():
            spawns = spawn_table.get(eid, ())
            if not spawns or not coords:
                continue
            amap = spawns[0][0]
            if any(s[0] != amap for s in spawns):
                continue
            wx = sum(s[2] for s in spawns) / len(spawns)
            wy = sum(s[3] for s in spawns) / len(spawns)
            if any(math.hypot(s[2] - wx, s[3] - wy) > 75 for s in spawns):
                continue
            groups = {}
            for c in coords:
                groups.setdefault(c[2], []).append(c)
            for zone, cl in groups.items():
                if zone in STALE_RECT_ZONES and eid not in pf.corrected[kind]:
                    continue
                px = sum(c[0] for c in cl) / len(cl)
                py = sum(c[1] for c in cl) / len(cl)
                if any(math.hypot(c[0] - px, c[1] - py) > 2.0 for c in cl):
                    continue
                by_zone.setdefault(zone, []).append((amap, wx, wy, px, py))

    models = {}
    for zone, samples in by_zone.items():
        if len(samples) < MIN_PAIRS:
            continue
        fx = fy = None
        for _ in range(FIT_ITERATIONS):
            fx = linfit([(s[2], s[3]) for s in samples])  # pctX from world Y
            fy = linfit([(s[1], s[4]) for s in samples])  # pctY from world X
            if not fx or not fy or len(samples) < MIN_PAIRS:
                fx = None
                break
            resid = [max(abs(fx[0] + fx[1] * s[2] - s[3]),
                         abs(fy[0] + fy[1] * s[1] - s[4])) for s in samples]
            order = sorted(range(len(samples)), key=lambda i: resid[i])
            keep = order[:max(MIN_PAIRS, int(len(samples) * 0.8))]
            if len(keep) == len(samples):
                break
            samples = [samples[i] for i in keep]
        if not fx or not fy:
            continue
        med = statistics.median(
            max(abs(fx[0] + fx[1] * s[2] - s[3]),
                abs(fy[0] + fy[1] * s[1] - s[4])) for s in samples)
        if med > MAX_MEDIAN_RESID:
            continue
        # The model's implied map extent must agree with pfQuest's own zone
        # dimensions (pfDB.minimap, world yards): 100% spans |100/slope| yards.
        # This rejects structurally bogus fits -- battleground zones "fit" from
        # cross-map junk pairs, since their real spawns sit on instance maps.
        if zone in pf.minimap and zone not in STALE_RECT_ZONES:
            w, h = pf.minimap[zone]
            fitw, fith = abs(100.0 / fx[1]), abs(100.0 / fy[1])
            if not (0.75 < fitw / w < 1.25 and 0.75 < fith / h < 1.25):
                continue
        amap = statistics.mode(s[0] for s in samples)
        models[zone] = {"fx": fx, "fy": fy, "map": amap,
                        "pairs": len(samples), "med": med}
    return models


# Zones pfQuest has no spawns to fit against, taken from a different source:
# Questie-335's QuestieCompat.UiMapData, which ships the WorldMapArea rectangle
# (width, height, left, top) for every zone. Validated before being trusted --
# its rectangles reproduce the fits above to a median 0.011% across 66 zones and
# pfQuest's own shipped coordinates to a median 0.041% over 1656 one-to-one
# pairs, and for Wintergrasp specifically, applied to 323 AzerothCore spawns it
# reproduces GatherMate's independent extraction of the same nodes to a median
# 0.006%. Both widths agree with GatherMate's own zone table to four decimals.
#
# This is NOT a blanket endorsement of that source: its rectangles are
# retail-era, and for the Burning Crusade starting zones (Azuremyst, Bloodmyst,
# Silvermoon, The Exodar) they disagree with this client by hundreds of percent,
# where the fit agrees with GatherMate. So it is used ONLY for zones with no fit,
# and only for the two listed here. Hrothgar's Landing is left out: nothing
# pfQuest tracks spawns there, so a rectangle for it could not be checked.
UIMAP_RECTS = {
    # zone: (width, height, left, top), map
    4197: ((2974.9998779297, 1983.33984375, 4329.169921875, 5716.669921875), 571),
    2817: ((2722.9200439453, 1814.580078125, 1443.75, 6502.080078125), 571),
}


def add_rect_models(models):
    """Fill in the zones we cannot fit, from the WorldMapArea rectangle. The
    rectangle IS the model: pctX = (left - worldY) / width, pctY = (top -
    worldX) / height -- the same transform every WoW map uses."""
    added = []
    for zone, (rect, amap) in UIMAP_RECTS.items():
        if zone in models:
            continue
        w, h, left, top = rect
        models[zone] = {"fx": (left / w * 100.0, -100.0 / w),
                        "fy": (top / h * 100.0, -100.0 / h),
                        "map": amap, "pairs": 0, "med": 0.0, "rect": True}
        added.append(zone)
    return added


def to_percent(model, wx, wy):
    fx, fy = model["fx"], model["fy"]
    return fx[0] + fx[1] * wy, fy[0] + fy[1] * wx


def zone_boxes(models):
    """Invert each zone model to its world-space bounding box (the world
    rectangle that maps to percent 0..100), grouped by map."""
    by_map = {}
    for zone, model in models.items():
        fx, fy = model["fx"], model["fy"]
        wys = sorted(((0 - fx[0]) / fx[1], (100 - fx[0]) / fx[1]))
        wxs = sorted(((0 - fy[0]) / fy[1], (100 - fy[0]) / fy[1]))
        area = (wxs[1] - wxs[0]) * (wys[1] - wys[0])
        by_map.setdefault(model["map"], []).append(
            (area, zone, wxs[0], wxs[1], wys[0], wys[1]))
    for boxes in by_map.values():
        boxes.sort()
    return by_map


def unplaceable_boxes(ac, models, pf):
    """World bounding boxes of the zones we CANNOT place anything in.

    Wintergrasp, Crystalsong Forest and Hrothgar's Landing have no pfQuest map
    rectangle, so nothing there can be converted. AC labels its gameobject rows
    with a real zoneId, so those rows give us each zone's world extent -- which
    is what lets us drop a creature that lands there instead of handing it to
    whichever neighbouring rectangle happens to reach that far.

    Returns map -> [(x0, x1, y0, y1)], padded slightly outward.
    """
    extents = {}
    for spawns in ac.gspawn.values():
        for amap, zone, wx, wy, _r in spawns:
            if amap not in EMIT_MAPS or not zone:
                continue
            if zone in models or zone in pf.minimap:
                continue
            box = extents.setdefault((amap, zone), [wx, wx, wy, wy])
            box[0] = min(box[0], wx)
            box[1] = max(box[1], wx)
            box[2] = min(box[2], wy)
            box[3] = max(box[3], wy)
    by_map = {}
    for (amap, zone), b in extents.items():
        by_map.setdefault(amap, []).append((zone, b[0], b[1], b[2], b[3]))
    return by_map


def in_unplaceable(boxes, amap, wx, wy):
    for zone, x0, x1, y0, y1 in boxes.get(amap, ()):
        if x0 <= wx <= x1 and y0 <= wy <= y1:
            return zone
    return None


def assign_zone(by_map, models, amap, wx, wy):
    """Pick the zone for a world spawn among all fitted zones whose box
    contains it and whose conversion lands inside 0..100.

    Neighbouring map rectangles overlap well beyond the playable zone edge, so
    "smallest containing box" alone misfiles border spawns. The conversion
    farthest from any map edge wins: the true zone holds the point in its
    interior, the rectangle-overlap neighbours only in their fringe.
    """
    cands = []
    for _area, zone, x0, x1, y0, y1 in by_map.get(amap, ()):
        if x0 <= wx <= x1 and y0 <= wy <= y1:
            px, py = to_percent(models[zone], wx, wy)
            if 0 <= px <= 100 and 0 <= py <= 100:
                cands.append((zone, px, py))
    if not cands:
        return None
    return max(cands, key=lambda c: min(c[1], 100 - c[1], c[2], 100 - c[2]))


# --------------------------------------------------------------- node building

def collect(entries, kind, ac, models, by_map, dead, pf, stats):
    """entries: entity id -> (name, track, value).

    Returns id -> [(x, y, zone, respawn)], honouring the fill-only policy: a
    (entity, zone) pair pfQuest already has any coordinate for is skipped.

    Gameobjects take their zone from AC's own label where it has one, which
    matters at the zone borders and, above all, for the zones we cannot place.
    Creatures have no usable label in AC's base dumps, so they fall back to
    fitted-rectangle containment, minus the unplaceable zones' world boxes.
    """
    out = {}
    spawn_table = ac.spawns(kind)
    known = pf.coords(kind)
    for eid in entries:
        known_zones = {c[2] for c in known.get(eid, ())}
        pts = []
        for amap, aczone, wx, wy, respawn in spawn_table.get(eid, ()):
            if amap not in EMIT_MAPS:
                stats["othermap"] += 1
                continue
            if aczone and aczone not in models:
                stats["norect"] += 1
                continue
            if not aczone and in_unplaceable(dead, amap, wx, wy):
                stats["norect"] += 1
                continue
            if aczone:
                px, py = to_percent(models[aczone], wx, wy)
                if not (0 <= px <= 100 and 0 <= py <= 100):
                    stats["offmap"] += 1
                    continue
                zone = aczone
            else:
                hit = assign_zone(by_map, models, amap, wx, wy)
                if not hit:
                    stats["nozone"] += 1
                    continue
                zone, px, py = hit
            if zone not in pf.minimap:
                stats["nosize"] += 1
                continue
            if zone in known_zones:
                stats["already"] += 1
                continue
            pts.append((round(px, 1), round(py, 1), zone, respawn))
        kept = []
        for pt in sorted(pts, key=lambda t: (t[2], t[0], t[1])):
            if any(pt[2] == k[2]
                   and (pt[0] - k[0]) ** 2 + (pt[1] - k[1]) ** 2 < DEDUP_DIST ** 2
                   for k in kept):
                stats["dedup"] += 1
                continue
            kept.append(pt)
        if kept:
            out[eid] = kept
    return out


def build_entries(ac, roster):
    """The entities each track is made of. Returns kind -> {id: (name, track,
    metavalue)}, where metavalue is already in pfQuest's own representation:
    a number for the skill/level tracks, the "AH" string for fishing pools."""
    objects, units = {}, {}
    for eid, (typ, name) in ac.gt.items():
        if eid not in ac.gspawn:
            continue
        hit = roster.get(name)
        if hit:
            objects[eid] = (name, hit[0], hit[2])
        elif typ == GO_TYPE_FISHINGHOLE:
            # pfQuest matches non-skill tracks with string.find(value, faction),
            # so this MUST stay a string -- a number would throw.
            objects[eid] = (name, "fish", "AH")
    for eid, (name, rank, lo, hi) in ac.ct.items():
        if eid in ac.cspawn and rank in CREATURE_RANK_RARE:
            # For a level RANGE, pfQuest's own meta.rares stores the LOW end
            # (21 of 21 ranged vanilla/TBC rares), while units[id].lvl keeps the
            # full "71-72" string. Match both.
            units[eid] = (name, "rares", min(lo, hi))
    return {"O": objects, "U": units}


# ---------------------------------------------------------------- validation

def verify_skills(entries, pf):
    """The GatherMate roster and pfQuest's meta must agree wherever both know a
    node. A disagreement means the name -> node id mapping is wrong, which
    would put a bogus skill requirement on every node we emit."""
    checked, bad = 0, []
    for eid, (name, track, value) in entries["O"].items():
        have = pf.meta.get((track, -eid))
        if have is None or track not in ("herbs", "mines", "chests"):
            continue
        checked += 1
        # pfQuest writes the no-requirement floor as 0, GatherMate as 1 (the
        # starter nodes: Peacebloom, Silverleaf, Copper Vein, Bloodthistle).
        # Anything else is a real disagreement.
        if int(have) != int(value) and not (int(have) <= 1 and int(value) <= 1):
            bad.append((eid, name, track, have, value))
    return checked, bad


# ------------------------------------------------------------------- emission

def lua_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


HEADER = """\
-- Outland + Northrend map-tracking data -- GENERATED by tools/gen_tracking335.py,
-- do not hand-edit.
--
-- pfQuest's pfDB["meta"] tracking lists are vanilla plus TBC: Northrend has ZERO
-- entries in every one of them, so "Herbs & Flowers", "Mines & Ores", "Chests &
-- Treasures", "Fishing" and "Rare Mobs" all found nothing anywhere in Northrend
-- (issue #18). Outland was mostly covered with one big hole: every WotLK ore and
-- herb had no object entry at all, and the TBC ores plus several TBC herbs had an
-- object entry with an EMPTY coords table. This table fills both.
--
-- Source: AzerothCore world database, per-table base dumps from
-- github.com/azerothcore/azerothcore-wotlk, data/sql/base/db_world,
-- commit %(sha)s.
--
-- Gathering roster and skill requirements from GatherMate 1's Constants.lua
-- (github.com/stevemcqueenz/gathermate-and-database-3.3.5a) -- a curated list
-- that excludes instance-only and loot-only pseudo-nodes. Its skill values are
-- checked against pfQuest's own meta for every object both sides know: they
-- agree everywhere, which is what makes the mapping trustworthy for the ones
-- only GatherMate knows. Fishing pools are gameobject_template.type 25; rares
-- are creature_template.rank 2 (rare elite) or 4 (rare).
--
-- A gameobject's zone is AC's own gameobject.zoneId, already pfQuest's zone id
-- space. AC leaves creature.zoneId at 0 almost everywhere, so creatures are
-- placed by fitted-rectangle containment instead. World (x,y) -> map percent
-- within a zone uses per-zone linear models fitted empirically against pfQuest's
-- own merged database (same method and rejection bar as
-- db/units-wotlk-acfill335.lua: a zone needs >= %(minpairs)d unambiguous
-- spawn-cluster pairs and a median residual <= %(maxresid).1f%%, and its implied
-- map extent must agree with pfDB.minimap's zone dimensions).
--
-- Wintergrasp and Crystalsong Forest have no pfQuest spawns to fit against, so
-- their models come from the WorldMapArea rectangle shipped by Questie-335's
-- QuestieCompat.UiMapData, checked first: it reproduces the fits above to a
-- median 0.011%% across 66 zones, pfQuest's own coordinates to 0.041%%, and for
-- Wintergrasp it reproduces GatherMate's independent extraction of the same
-- nodes to 0.006%%. Hrothgar's Landing stays out -- nothing tracked spawns there,
-- so a rectangle for it could not be checked. Anything landing in a zone with no
-- model at all is DROPPED, never handed to a neighbour, whose map rectangle
-- overlaps well past the playable edge.
--
-- SCOPE: Outland (map 530) and Northrend (map 571) only. Azeroth's tracking data
-- already works and is deliberately left untouched.
--
-- FILL ONLY: a coordinate is emitted for an entity in a zone only where
-- pfQuest's merged database has none for that entity in that zone, so existing
-- data is never replaced. game_event-linked spawns and instance maps are
-- excluded; near-identical spawns (< %(dedup).1f%% apart) are collapsed.
--
-- Shape (units and objects are separate databases in pfQuest):
--   pfDB["tracking335"]["objects"]["coords"][id] = { { xPct, yPct, zone, respawn }, ... }
--   pfDB["tracking335"]["objects"]["names"][id]  = "Cobalt Deposit"
--   pfDB["tracking335"]["units"]["coords"][id]   = { { xPct, yPct, zone, respawn }, ... }
--   pfDB["tracking335"]["units"]["names"][id]    = "Loque'nahak"
--   pfDB["tracking335"]["units"]["info"][id]     = { lvl, rnk }   -- STRINGS, as pfQuest stores them
--   pfDB["tracking335"]["meta"][track][id]       = value
-- meta keys carry pfQuest's own sign convention already: NEGATIVE for the object
-- tracks (herbs/mines/chests/fish), positive for the unit tracks (rares). The
-- values match pfQuest's own types exactly -- a NUMBER for the skill and level
-- tracks, the "AH" STRING for fishing pools, which pfQuest matches with
-- string.find and would throw on a number.
-- database.lua merges this additively after the expansion overlays; see the
-- tracking335 block there.
--
%(stats)s
"""


def listable(entries, nodes, pf, emit_zones):
    """Which entities belong on a tracking list.

    NOT the same question as "which entities did we add coordinates for". An
    entity that already had every coordinate it needs can still be missing from
    the list entirely, and then enabling that tracker shows nothing for it --
    which is how Everfrost Chip, Netherwing Egg, Glowcap and eight others were
    invisible despite pfQuest knowing exactly where they are. So the rule is
    simply: it is on the list if it has coordinates in an in-scope zone, from
    either side, and pfQuest's own meta does not already answer it.
    """
    out = {}
    for kind in ("O", "U"):
        sign = 1 if kind == "U" else -1
        keep = set()
        for eid, (_name, track, _v) in entries[kind].items():
            if (track, sign * eid) in pf.meta:
                continue
            zones = {c[2] for c in pf.coords(kind).get(eid, ())}
            zones |= {p[2] for p in nodes[kind].get(eid, ())}
            if zones & emit_zones:
                keep.add(eid)
        out[kind] = keep
    return out


def emit(path, nodes, entries, ac, pf, listable, ac_sha, stats_lines):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % {"sha": ac_sha, "minpairs": MIN_PAIRS,
                          "maxresid": MAX_MEDIAN_RESID, "dedup": DEDUP_DIST,
                          "stats": "\n".join("-- " + s for s in stats_lines)})
        f.write('pfDB["tracking335"] = {\n')

        for kind, key in (("O", "objects"), ("U", "units")):
            got, ent, shipped = nodes[kind], entries[kind], pf.names(kind)
            f.write('  ["%s"] = {\n' % key)
            f.write('    ["coords"] = {\n')
            for eid in sorted(got):
                f.write("      [%d] = {\n" % eid)
                for px, py, zone, respawn in got[eid]:
                    f.write("        { %.1f, %.1f, %d, %d },\n" % (px, py, zone, respawn))
                f.write("      },\n")
            f.write("    },\n")
            # Only entities pfQuest has no name for need one; the rest keep
            # theirs, and the player's locale where the locale database has it.
            f.write('    ["names"] = {\n')
            for eid in sorted(got):
                if eid not in shipped:
                    f.write('      [%d] = "%s",\n' % (eid, lua_escape(ent[eid][0])))
            f.write("    },\n")
            if kind == "U":
                # pfQuest stores unit level and rank as STRINGS, and level may
                # be a range ("70-71"). Match that exactly.
                f.write('    ["info"] = {\n')
                for eid in sorted(got):
                    _name, _track, _v = ent[eid]
                    _n, rank, lo, hi = ac.ct[eid]
                    lvl = str(lo) if lo == hi else "%d-%d" % (lo, hi)
                    f.write('      [%d] = { "%s", "%d" },\n' % (eid, lvl, rank))
                f.write("    },\n")
            f.write("  },\n")

        f.write('  ["meta"] = {\n')
        for track in OBJECT_TRACKS + UNIT_TRACKS:
            kind = "U" if track in UNIT_TRACKS else "O"
            sign = 1 if kind == "U" else -1
            f.write('    ["%s"] = {\n' % track)
            for eid in sorted(listable[kind]):
                name, etrack, value = entries[kind][eid]
                if etrack != track:
                    continue
                shown = '"%s"' % value if isinstance(value, str) else str(value)
                f.write("      [%d] = %s, -- %s\n" % (sign * eid, shown, lua_escape(name)))
            f.write("    },\n")
        f.write("  },\n")
        f.write("}\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ac-dir", default=os.environ.get("AC_WORLD_SQL"),
                    help="directory holding the AC db_world .sql dumps "
                         "(default: $AC_WORLD_SQL)")
    ap.add_argument("--gathermate", required=True,
                    help="path to a GatherMate 1 addon folder (the one holding "
                         "Constants.lua)")
    ap.add_argument("--ac-sha", default=None,
                    help="azerothcore-wotlk commit the dumps were fetched at "
                         "(default: contents of <ac-dir>/sha.txt)")
    args = ap.parse_args()
    if not args.ac_dir:
        sys.exit("--ac-dir (or $AC_WORLD_SQL) is required; see the fetch "
                 "instructions in this file's docstring")
    ac_sha = args.ac_sha
    if not ac_sha:
        sha_file = os.path.join(args.ac_dir, "sha.txt")
        ac_sha = (open(sha_file).read().split()[0].replace("SHA=", "")
                  if os.path.exists(sha_file) else "unknown")

    print("loading pfQuest merged db (lua5.1) ...")
    pf = load_pfquest()
    print("  %d units, %d objects with coords; %d zones with size data"
          % (len(pf.units), len(pf.objects), len(pf.minimap)))

    print("loading GatherMate node roster ...")
    roster = load_nodes(args.gathermate)
    print("  %d gatherable node names" % len(roster))

    print("loading AzerothCore dumps ...")
    ac = load_ac(args.ac_dir)
    print("  %d gameobject templates / %d spawned, %d creature templates / %d spawned"
          % (len(ac.gt), len(ac.gspawn), len(ac.ct), len(ac.cspawn)))

    entries = build_entries(ac, roster)
    by_track = {}
    for kind in ("O", "U"):
        for _n, track, _v in entries[kind].values():
            by_track[track] = by_track.get(track, 0) + 1
    print("  trackable entities with spawns: %s"
          % ", ".join("%s %d" % kv for kv in sorted(by_track.items())))

    checked, bad = verify_skills(entries, pf)
    if bad:
        for eid, name, track, have, value in bad:
            print("  SKILL MISMATCH %d %s (%s): pfQuest %s, GatherMate %s"
                  % (eid, name, track, have, value))
        sys.exit("aborting: the node mapping disagrees with pfQuest's own meta")
    print("  skill values verified against pfQuest meta: %d/%d objects agree"
          % (checked, checked))

    print("fitting zone models ...")
    models = fit_zones(pf, ac)
    print("  %d zones fitted (median residual %.2f%%)"
          % (len(models), statistics.median(m["med"] for m in models.values())))
    added = add_rect_models(models)
    print("  %d zones taken from the WorldMapArea rectangle instead (no pfQuest "
          "spawns to fit against): %s"
          % (len(added), ", ".join(str(z) for z in added) or "-"))
    by_map = zone_boxes(models)
    dead = unplaceable_boxes(ac, models, pf)
    print("  zones with no pfQuest rectangle, excluded by world box: %s"
          % ", ".join(str(z[0]) for boxes in dead.values() for z in boxes))

    # Independent check on the zone step: where AC labels a gameobject row, the
    # fitted rectangle it lands in should be the same zone.
    agree = dis = 0
    for eid in entries["O"]:
        for amap, aczone, wx, wy, _r in ac.gspawn.get(eid, ()):
            if amap not in EMIT_MAPS or not aczone or aczone not in models:
                continue
            hit = assign_zone(by_map, models, amap, wx, wy)
            if hit and hit[0] == aczone:
                agree += 1
            else:
                dis += 1
    print("  zone labels vs fitted rectangles: %d agree, %d differ (%.1f%%; "
          "border spawns, the label wins)"
          % (agree, dis, 100.0 * dis / max(1, agree + dis)))

    stats = dict.fromkeys(
        ["nozone", "nosize", "already", "dedup", "othermap", "norect", "offmap"], 0)
    nodes = {kind: collect(entries[kind], kind, ac, models, by_map, dead, pf, stats)
             for kind in ("O", "U")}

    total, per_track, per_zone = 0, {}, {}
    for kind in ("O", "U"):
        for eid, pts in nodes[kind].items():
            track = entries[kind][eid][1]
            total += len(pts)
            per_track[track] = per_track.get(track, 0) + len(pts)
            for px, py, zone, _r in pts:
                assert 0 <= px <= 100 and 0 <= py <= 100, (eid, px, py)
                per_zone[zone] = per_zone.get(zone, 0) + 1

    emit_zones = {z for z, mo in models.items() if mo["map"] in EMIT_MAPS}
    listed = listable(entries, nodes, pf, emit_zones)
    extra = sum(1 for kind in ("O", "U") for eid in listed[kind]
                if eid not in nodes[kind])
    print("  tracking-list entries: %d, of which %d are entities pfQuest already "
          "had coordinates for but never listed"
          % (sum(len(v) for v in listed.values()), extra))

    stats_lines = [
        "%d nodes across %d objects, %d units and %d zones"
        % (total, len(nodes["O"]), len(nodes["U"]), len(per_zone)),
        "by track: " + ", ".join("%s %d" % kv for kv in sorted(per_track.items())),
        "skipped: %d on Azeroth (out of scope), %d already covered by pfQuest "
        "in that zone, %d in a zone pfQuest has no rectangle for, %d outside "
        "every fitted zone, %d off the fitted map, %d in a zone with no "
        "pfDB.minimap size, %d duplicates"
        % (stats["othermap"], stats["already"], stats["norect"],
           stats["nozone"], stats["offmap"], stats["nosize"], stats["dedup"]),
    ]
    for line in stats_lines:
        print("  " + line)

    print("writing %s ..." % OUT)
    emit(OUT, nodes, entries, ac, pf, listed, ac_sha, stats_lines)
    print("done")


if __name__ == "__main__":
    main()
