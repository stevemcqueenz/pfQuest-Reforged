#!/usr/bin/env python3
"""Generate db/poi-wotlk335.lua -- utility POIs (flight masters, mailboxes,
innkeepers, repair vendors) for the 3.3.5a world, from an AzerothCore world DB.

Phase B part 1 of the pins work: DATA ONLY. Nothing in the addon consumes
pfDB["poi-wotlk335"] yet; the consumer (pins/compass) lands separately.

Source data
-----------
AzerothCore ships its full 3.3.5a world database as per-table mysqldump files
inside the main repo (data/sql/base/db_world/*.sql), so no MySQL server and no
release archive is needed. Fetch the six tables this tool reads, pinned to a
commit for reproducibility:

    SHA=$(git ls-remote https://github.com/azerothcore/azerothcore-wotlk.git refs/heads/master | cut -f1)
    mkdir -p ~/refs/ac-world && cd ~/refs/ac-world && echo "$SHA" > sha.txt
    for f in creature_template creature gameobject_template gameobject \
             game_event_creature game_event_gameobject; do
      curl -sSL -O "https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/$SHA/data/sql/base/db_world/$f.sql"
    done

Then run from the addon root:

    python3 tools/gen_poi335.py --ac-dir ~/refs/ac-world

POI classes
-----------
  flight  creature_template.npcflag & 8192   (UNIT_NPC_FLAG_FLIGHTMASTER)
  mail    gameobject_template.type = 19      (GAMEOBJECT_TYPE_MAILBOX)
  inn     creature_template.npcflag & 65536  (UNIT_NPC_FLAG_INNKEEPER)
  repair  creature_template.npcflag & 4096   (UNIT_NPC_FLAG_REPAIR)

Coordinate transform (same method as db/units-wotlk-acfill335.lua)
------------------------------------------------------------------
World (x,y) -> per-zone map percent is fitted EMPIRICALLY, per zone, from
entities that exist in BOTH the AC dump and pfQuest's merged database with a
single unambiguous spawn on each side: map-percent is a linear function of the
world coordinate (pctX of world Y, pctY of world X). Least squares with
iterative outlier rejection; a zone is REJECTED unless it has >= MIN_PAIRS
clean pairs and a median residual <= MAX_MEDIAN_RESID percent, so nothing is
emitted for zones we cannot map reliably. pfQuest's merged data is the fit
target (units + objects + all wotlk/sw335/icecrown/acfill overlays, merged
with patchtable semantics via a real lua5.1 load), so zone ids and the percent
convention are pfQuest's own by construction -- including the corrected
3.3.5a Stormwind rectangle from the sw335 overlay.

Zone assignment uses AC's own creature/gameobject.zoneId (AreaTable zone id,
the same id space pfQuest uses); spawns whose zone has no accepted fit or no
pfDB.minimap size entry are dropped and counted, never guessed. Spawns linked
to a game_event (holiday-only mailboxes etc.) are excluded, as are all
non-continent maps (instances render nowhere in pfQuest on 3.3.5a).

Validation (printed on every run)
---------------------------------
  * per-class counts, per-zone 0..100 range assertion;
  * named spot checks (Orgrimmar/Stormwind flight masters, Crossroads inn +
    mailbox, Dalaran mailbox, ...) against pfQuest's own shipped coordinate
    for the same entity: the delta IS the pipeline error;
  * aggregate cross-check: every emitted POI whose entity also has pfQuest
    coords in the same zone reports its distance to the nearest one --
    median/p90 per class.
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
NPCFLAG = {"repair": 4096, "flight": 8192, "inn": 65536}
GO_TYPE_MAILBOX = 19
MIN_PAIRS = 5
MAX_MEDIAN_RESID = 1.5   # percent; same rejection bar as the acfill pipeline
DEDUP_DIST = 0.3         # percent; task spec: collapse near-identical spawns
FIT_ITERATIONS = 3
OUT = os.path.join(ROOT, "db", "poi-wotlk335.lua")

# Named spot checks: (kind, id, class, human label). pfQuest's own coordinate
# for the same entity is the reference; the printed delta is the pipeline error.
SPOT_CHECKS = [
    ("U", 3310, "flight", "Doras, Orgrimmar flight master"),
    ("U", 352, "flight", "Dungar Longdrink, Stormwind flight master"),
    ("U", 6929, "inn", "Innkeeper Gryshka, Orgrimmar"),
    ("U", 6740, "inn", "Innkeeper Allison, Stormwind"),
    ("U", 3934, "inn", "Innkeeper Boorand Plainswind, Crossroads"),
    ("O", 143982, "mail", "Mailbox, Crossroads"),
    ("O", 144128, "mail", "Mailbox, Stormwind Trade District"),
    ("O", 191952, "mail", "Mailbox, Dalaran"),
    ("U", 3479, "repair", "Nargal Deatheye, Crossroads"),
    ("U", 5411, "repair", "Krinkle Goodsteel, Gadgetzan"),
]
# The Stormwind references (352/6740/144128) are the sw335-corrected values --
# pfQuest's zone-1519 coords were re-fitted to the 3.3.5a rectangle by the
# sw335 overlays, and the 1519 model here is fitted against that same
# corrected source (see fit_zones), so small deltas are the expected outcome.


# ---------------------------------------------------------------- pfQuest side

LUA_DUMP = r"""
-- Loads pfQuest's database files exactly like init/data.xml + data-wotlk.xml
-- do, applies database.lua's patchtable semantics (an overlay entry replaces
-- the base entry outright), and dumps every merged coordinate as TSV.
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
patch(pfDB["minimap"], pfDB["minimap-tbc"])
patch(pfDB["minimap"], pfDB["minimap-wotlk"])

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
-- ids whose coords come from the wotlk overlay (Questie-wotlk convention,
-- Stormwind rows rewritten by the sw335 correction) -- the trustworthy fit
-- source for zone 1519, where pfQuest's vanilla coords use the 1.12 rect.
for id in pairs(pfDB["units"]["data-wotlk"]) do print(string.format("WU\t%d\t0\t0\t0", id)) end
for id in pairs(pfDB["objects"]["data-wotlk"]) do print(string.format("WO\t%d\t0\t0\t0", id)) end
"""


def load_pfquest():
    """Merged pfQuest coords via a real lua5.1 load (exact patchtable semantics).

    Returns (units, objects, minimap_zones): id -> [(x, y, zone), ...].
    """
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
        f.write(LUA_DUMP)
        script = f.name
    try:
        out = subprocess.run(["lua5.1", script], cwd=ROOT, check=True,
                             capture_output=True, text=True).stdout
    finally:
        os.unlink(script)
    units, objects, minimap = {}, {}, {}
    corrected = {"U": set(), "O": set()}
    for line in out.splitlines():
        tag, sid, sx, sy, szone = line.split("\t")
        if tag == "M":
            minimap[int(szone)] = (float(sx), float(sy))
        elif tag in ("WU", "WO"):
            corrected[tag[1]].add(int(sid))
        else:
            dest = units if tag == "U" else objects
            dest.setdefault(int(sid), []).append((float(sx), float(sy), int(szone)))
    return units, objects, minimap, corrected


# ------------------------------------------------------------ AC dump parsing

def sql_rows(path, table):
    """Yield value tuples from mysqldump `INSERT INTO `table` VALUES` blocks
    (one row per parenthesized tuple, statements spanning multiple lines).

    Plain state machine: handles quoted strings with backslash escapes (which
    may contain newlines and parens), NULL, and numbers. Strings are
    unescaped; everything else is returned as str.
    """
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


def load_ac(ac_dir):
    """Parse the six AC tables into plain dicts (column order from each dump's
    CREATE TABLE, azerothcore-wotlk data/sql/base/db_world)."""
    p = lambda name: os.path.join(ac_dir, name + ".sql")
    for name in ("creature_template", "creature", "gameobject_template",
                 "gameobject", "game_event_creature", "game_event_gameobject"):
        if not os.path.exists(p(name)):
            sys.exit("missing %s -- see the fetch instructions in this file's "
                     "docstring" % p(name))

    # eventEntry > 0 = spawned only during the event -> exclude those guids
    ev_creature = {int(r[1]) for r in sql_rows(p("game_event_creature"), "game_event_creature")
                   if int(r[0]) > 0}
    ev_go = {int(r[1]) for r in sql_rows(p("game_event_gameobject"), "game_event_gameobject")
             if int(r[0]) > 0}

    # creature_template: entry=1 name=7 npcflag=15 (1-based)
    ct = {}
    for r in sql_rows(p("creature_template"), "creature_template"):
        ct[int(r[0])] = (r[6], int(r[14]))
    # gameobject_template: entry=1 type=2 name=4
    gt = {}
    for r in sql_rows(p("gameobject_template"), "gameobject_template"):
        gt[int(r[0])] = (int(r[1]), r[3])

    # creature: guid=1 id1=2 map=5 zoneId=6 x=11 y=12
    cspawn = {}
    for r in sql_rows(p("creature"), "creature"):
        if int(r[4]) not in CONTINENTS or int(r[0]) in ev_creature:
            continue
        cspawn.setdefault(int(r[1]), []).append(
            (int(r[4]), int(r[5]), float(r[10]), float(r[11])))
    # gameobject: guid=1 id=2 map=3 zoneId=4 x=8 y=9
    gspawn = {}
    for r in sql_rows(p("gameobject"), "gameobject"):
        if int(r[2]) not in CONTINENTS or int(r[0]) in ev_go:
            continue
        gspawn.setdefault(int(r[1]), []).append(
            (int(r[2]), int(r[3]), float(r[7]), float(r[8])))
    return ct, cspawn, gt, gspawn


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


def fit_zones(pf_units, pf_objects, cspawn, gspawn, corrected, minimap):
    """Per-zone linear world->percent models from single-spawn pairs.

    pctX is a function of world Y, pctY of world X (the WoW axis convention;
    the fit finds the signs on its own). Returns zone -> dict with the model,
    its map, pair count and median residual.

    Stormwind (1519) is fitted from wotlk-overlay pairs ONLY: pfQuest's
    vanilla coords there use the 1.12 map rectangle, which the sw335
    correction established is wrong for this client -- mixing both
    conventions yields a model between the two (that fit's median residual
    was 1.33% vs <=0.1%% everywhere else, the tell of two clusters).
    """
    by_zone = {}
    for kind, pf, ac in (("U", pf_units, cspawn), ("O", pf_objects, gspawn)):
        for eid, coords in pf.items():
            spawns = ac.get(eid, ())
            if not spawns or not coords:
                continue
            # Unambiguous = one tight cluster on each side. Strict 1:1 pairs
            # alone starve the city zones (a city NPC typically ships 2-4
            # near-identical pfQuest coords, and pfQuest dual-lists city NPCs
            # on BOTH the city map and the surrounding zone's map -- Thunder
            # Bluff had ONE strict pair), so: AC spawns must form one tight
            # cluster (one map, within 75 yards), and each ZONE's pf coords
            # must form one tight cluster (within 2%) -- every such zone
            # cluster yields a pair, so a dual-listed NPC calibrates both the
            # city map and the surrounding map.
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
                if zone in STALE_RECT_ZONES and eid not in corrected[kind]:
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
        # dimensions (pfDB.minimap, world yards): 100% spans |100/slope|
        # yards. This rejects structurally bogus fits -- battleground zones
        # "fit" from cross-map junk pairs (their real spawns sit on
        # non-continent maps), and Alterac Valley's junk model then swallowed
        # a Stormwind mailbox.
        # ... except Stormwind, whose pfDB.minimap SIZE is itself the stale
        # 1.12 value the sw335 rectangle correction diverges from.
        if zone in minimap and zone not in STALE_RECT_ZONES:
            w, h = minimap[zone]
            fitw, fith = abs(100.0 / fx[1]), abs(100.0 / fy[1])
            if not (0.75 < fitw / w < 1.25 and 0.75 < fith / h < 1.25):
                continue
        amap = statistics.mode(s[0] for s in samples)
        models[zone] = {"fx": fx, "fy": fy, "map": amap,
                        "pairs": len(samples), "med": med}
    return models


# --------------------------------------------------------------- POI building

def to_percent(model, wx, wy):
    fx, fy = model["fx"], model["fy"]
    return fx[0] + fx[1] * wy, fy[0] + fy[1] * wx


def zone_boxes(models):
    """Invert each zone model to its world-space bounding box (the world
    rectangle that maps to percent 0..100), grouped by map. AC's base dumps
    ship creature/gameobject.zoneId as 0 (the server computes it at load), so
    spawns are assigned by containment: smallest containing box wins -- the
    same rule the acfill pipeline used, which keeps a city POI in the city
    zone rather than the surrounding continent zone."""
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


def assign_zone(by_map, models, amap, wx, wy, pf_coords):
    """Pick the zone for a world spawn among all fitted zones whose box
    contains it and whose conversion lands inside 0..100.

    Neighbouring map rectangles overlap well beyond the playable zone edge, so
    "smallest containing box" alone misfiles border towns (Crossroads sits in
    the corner of Mulgore's RECTANGLE while being nowhere near Mulgore).
    Two-step rule instead:
      1. If pfQuest itself knows this entity, EVERY candidate zone that
         pfQuest also places it in wins (within a 10% sanity bound) --
         plural on purpose: pfQuest dual-lists city NPCs on both the city
         map and the surrounding zone's map, and so do we.
      2. Otherwise the single conversion farthest from any map edge wins:
         the true zone holds the point in its interior, the
         rectangle-overlap neighbours only in their fringe (a city box is
         both the smallest and the most interior for a city point, so
         pf-unknown city POIs land on the city map).
    Returns a list of (zone, px, py).
    """
    cands = []
    for _area, zone, x0, x1, y0, y1 in by_map.get(amap, ()):
        if x0 <= wx <= x1 and y0 <= wy <= y1:
            px, py = to_percent(models[zone], wx, wy)
            if 0 <= px <= 100 and 0 <= py <= 100:
                cands.append((zone, px, py))
    if not cands:
        return []
    if pf_coords:
        picked = []
        for zone, px, py in cands:
            ref = [c for c in pf_coords if c[2] == zone]
            if ref and min(math.hypot(px - x, py - y)
                           for x, y, _z in ref) <= 10.0:
                picked.append((zone, px, py))
        if picked:
            return picked
    return [max(cands, key=lambda c: min(c[1], 100 - c[1], c[2], 100 - c[2]))]


def collect(entries, spawns, models, by_map, minimap, pf, dropped):
    """entries: id -> name. Returns zone -> [(x, y, name)], deduplicated."""
    zones = {}
    for eid, name in entries.items():
        for amap, _aczone, wx, wy in spawns.get(eid, ()):
            # NB _aczone is 0 throughout AC's base dumps (the server computes
            # it at load time), hence the fitted-box assignment above.
            hits = assign_zone(by_map, models, amap, wx, wy, pf.get(eid))
            if not hits:
                dropped["nozone"] += 1
                continue
            for zone, px, py in hits:
                if zone not in minimap:
                    dropped["nosize"] += 1
                    continue
                zones.setdefault(zone, []).append(
                    (round(px, 1), round(py, 1), name, eid))
    for zone, pts in zones.items():
        pts.sort(key=lambda t: (t[0], t[1], t[2]))
        kept = []
        for pt in pts:
            if any((pt[0] - k[0]) ** 2 + (pt[1] - k[1]) ** 2 < DEDUP_DIST ** 2
                   for k in kept):
                dropped["dedup"] += 1
                continue
            kept.append(pt)
        zones[zone] = kept
    return zones


# ---------------------------------------------------------------- validation

def crosscheck(zones, pf):
    """Distance from each emitted POI to the nearest pfQuest coord of the SAME
    entity in the SAME zone (where pfQuest knows the entity at all). A POI
    whose entity pfQuest places ONLY in other zones counts as a zone
    disagreement -- the failure mode the same-zone deltas cannot see."""
    deltas, zone_mismatch = [], 0
    for zone, pts in zones.items():
        for px, py, _name, eid in pts:
            if eid not in pf:
                continue
            ref = [c for c in pf[eid] if c[2] == zone]
            if ref:
                deltas.append(min(math.hypot(px - x, py - y) for x, y, _z in ref))
            else:
                zone_mismatch += 1
    return deltas, zone_mismatch


def fmt_stats(deltas):
    if not deltas:
        return "no overlap"
    q = statistics.quantiles(deltas, n=10) if len(deltas) >= 10 else None
    return "n=%d median=%.2f%% p90=%s" % (
        len(deltas), statistics.median(deltas),
        "%.2f%%" % q[8] if q else "-")


# ------------------------------------------------------------------- emission

def lua_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def emit(path, classes, ac_sha, stats_lines):
    order = ["flight", "mail", "inn", "repair"]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % {"sha": ac_sha, "stats": "\n".join("-- " + s for s in stats_lines)})
        f.write('pfDB["poi-wotlk335"] = {\n')
        for cls in order:
            f.write('  ["%s"] = {\n' % cls)
            for zone in sorted(classes[cls]):
                pts = classes[cls][zone]
                if not pts:
                    continue
                f.write("    [%d] = {\n" % zone)
                for px, py, name, _eid in pts:
                    f.write('      { %.1f, %.1f, "%s" },\n' % (px, py, lua_escape(name)))
                f.write("    },\n")
            f.write("  },\n")
        f.write("}\n")


HEADER = """\
-- Utility POIs for the 3.3.5a world -- GENERATED by tools/gen_poi335.py, do not
-- hand-edit. Phase B part 1 of the pins work: DATA ONLY, nothing consumes this
-- table yet (the pins/compass consumer lands separately).
--
-- Source: AzerothCore world database, per-table base dumps from
-- github.com/azerothcore/azerothcore-wotlk, data/sql/base/db_world,
-- commit %(sha)s.
--   flight  creature_template.npcflag & 8192   (flight masters)
--   mail    gameobject_template.type = 19      (mailboxes)
--   inn     creature_template.npcflag & 65536  (innkeepers)
--   repair  creature_template.npcflag & 4096   (repair-capable vendors)
--
-- World (x,y) -> map percent uses per-zone linear models fitted empirically
-- against pfQuest's own merged database (same method and rejection bar as
-- db/units-wotlk-acfill335.lua: a zone needs >= 5 unambiguous spawn-cluster
-- pairs and a median residual <= 1.5%%, and its implied map extent must agree
-- with pfDB.minimap's zone dimensions, or nothing is emitted for it). A spawn
-- is assigned to a zone by fitted-rectangle containment, cross-checked against
-- pfQuest's own zone(s) for the same entity; pfQuest's convention of listing a
-- city POI on both the city map and the surrounding zone's map is preserved.
-- Zone keys are pfQuest's zone id space. Only zones with a pfDB.minimap size
-- entry are included. game_event-linked spawns (holiday mailboxes etc.) and
-- non-continent maps are excluded; near-identical spawns (< 0.3%% apart) are
-- collapsed. Where AC and pfQuest disagree about a POI's exact spot, AC's
-- position is emitted: it is where the object stands on the server played.
--
-- Shape: pfDB["poi-wotlk335"][class][zone] = { { xPct, yPct, name }, ... }.
-- Uniform 3-slot tuples -- this is NOT the units coords shape (no respawn
-- slot); consumers of this table must index exactly these three fields.
--
%(stats)s
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ac-dir", default=os.environ.get("AC_WORLD_SQL"),
                    help="directory holding the six AC db_world .sql dumps "
                         "(default: $AC_WORLD_SQL)")
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
    pf_units, pf_objects, minimap, corrected = load_pfquest()
    print("  %d units, %d objects with coords; %d zones with size data"
          % (len(pf_units), len(pf_objects), len(minimap)))

    print("parsing AC dumps from %s ..." % args.ac_dir)
    ct, cspawn, gt, gspawn = load_ac(args.ac_dir)
    print("  %d creature templates, %d spawned creature entries, "
          "%d gameobject templates, %d spawned gameobject entries"
          % (len(ct), len(cspawn), len(gt), len(gspawn)))

    print("fitting per-zone world->percent models ...")
    models = fit_zones(pf_units, pf_objects, cspawn, gspawn, corrected, minimap)
    print("  %d zones fitted (>= %d pairs, median residual <= %.1f%%)"
          % (len(models), MIN_PAIRS, MAX_MEDIAN_RESID))
    nofit = sorted(z for z in minimap if z not in models)
    nosize = sorted(z for z in models if z not in minimap)
    print("  size data but no clean fit (POIs there are dropped): %s" % (nofit or "none"))
    print("  fitted but no pfDB.minimap size (POIs there are dropped): %s" % (nosize or "none"))

    by_map = zone_boxes(models)
    classes, dropped_stats = {}, {}
    for cls, flag in NPCFLAG.items():
        entries = {e: name for e, (name, npcflag) in ct.items() if npcflag & flag}
        dropped = dropped_stats[cls] = {"nozone": 0, "nosize": 0, "dedup": 0}
        classes[cls] = collect(entries, cspawn, models, by_map, minimap,
                               pf_units, dropped)
    mailboxes = {e: name for e, (gtype, name) in gt.items() if gtype == GO_TYPE_MAILBOX}
    dropped = dropped_stats["mail"] = {"nozone": 0, "nosize": 0, "dedup": 0}
    classes["mail"] = collect(mailboxes, gspawn, models, by_map, minimap,
                              pf_objects, dropped)

    stats_lines = []
    print("\n== extraction ==")
    for cls in ("flight", "mail", "inn", "repair"):
        zones = classes[cls]
        total = sum(len(p) for p in zones.values())
        d = dropped_stats[cls]
        line = ("%s: %d POIs in %d zones (dropped: %d unmappable-spawn, "
                "%d no-size, %d dedup)"
                % (cls, total, len([z for z in zones.values() if z]),
                   d["nozone"], d["nosize"], d["dedup"]))
        print("  " + line)
        stats_lines.append(line)
        for zone, pts in zones.items():
            for px, py, name, eid in pts:
                assert 0 <= px <= 100 and 0 <= py <= 100, (cls, zone, eid, px, py)

    print("\n== spot checks (delta vs pfQuest's own coordinate) ==")
    for kind, eid, cls, label in SPOT_CHECKS:
        pf = pf_units if kind == "U" else pf_objects
        emitted = [(z, p) for z, pts in classes[cls].items()
                   for p in pts if p[3] == eid]
        if not emitted:
            # AC carries duplicate templates for some NPCs (two "Doras" ids a
            # yard apart); dedup keeps one of them -- find it by name.
            src = ct if kind == "U" else {e: (n,) for e, (_t, n) in gt.items()}
            name = src.get(eid, ("?",))[0]
            emitted = [(z, p) for z, pts in classes[cls].items()
                       for p in pts if p[2] == name]
            if emitted:
                label += " [via name; id dedup-merged]"
        if not emitted:
            # ... or the whole POI was collapsed into a near-identical
            # neighbour of the same class (e.g. two Crossroads repairers a few
            # yards apart): report the surviving neighbour instead.
            for x, y, zone in pf.get(eid, ()):
                near = [(math.hypot(p[0] - x, p[1] - y), p)
                        for p in classes[cls].get(zone, ())]
                if near and min(near)[0] <= 3 * DEDUP_DIST:
                    d, p = min(near)
                    print('  %.2f%%   %-45s zone %d (%.1f, %.1f) [dedup-merged '
                          'into "%s"]' % (d, label, zone, p[0], p[1], p[2]))
                    break
            else:
                print("  MISSING  %-45s (id %d not emitted)" % (label, eid))
            continue
        zone, (px, py, _n, _e) = emitted[0]
        ref = [c for c in pf.get(eid, ()) if c[2] == zone]
        if not ref:
            print("  NOREF    %-45s -> zone %d (%.1f, %.1f); pfQuest has no "
                  "coord there" % (label, zone, px, py))
            continue
        d = min(math.hypot(px - x, py - y) for x, y, _z in ref)
        print("  %.2f%%   %-45s zone %d (%.1f, %.1f)" % (d, label, zone, px, py))

    print("\n== aggregate cross-check vs pfQuest (same entity, same zone) ==")
    for cls in ("flight", "mail", "inn", "repair"):
        pf = pf_objects if cls == "mail" else pf_units
        deltas, mismatch = crosscheck(classes[cls], pf)
        print("  %-6s %s; %d zone disagreements" % (cls, fmt_stats(deltas), mismatch))

    emit(OUT, classes, ac_sha, stats_lines)
    print("\nwrote %s (%d bytes)" % (OUT, os.path.getsize(OUT)))


if __name__ == "__main__":
    main()
