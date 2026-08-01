-- Zone dimensions for the WotLK maps, so pfQuest can draw MINIMAP nodes there.
--
-- pfDB.minimap maps a zone to its map rectangle in world yards; map.lua uses it to
-- convert a node's map-percentage into a minimap offset. pfQuest shipped sizes for
-- vanilla and TBC only, and the minimap loop skips any zone missing one -- silently,
-- via `minimap_sizes[mapID] and ...`. So minimap dots have never worked anywhere in
-- Northrend, on the world map alone. These entries switch them on.
--
-- DERIVED, not copied. Each rectangle is fitted from the maintainer's AzerothCore
-- world DB (acore_world, AC rev 13e8857b515d): for creatures with exactly one AC
-- spawn AND exactly one pfQuest coordinate, map-percent is a linear function of the
-- world coordinate, and the slope IS the zone extent -- width = 100 / |d(pctX)/d(worldY)|.
-- Fitted by least squares, iteratively dropping the worst 20% of points.
--
-- The method was validated against the 57 vanilla/TBC zones where pfQuest already
-- ships the answer: MEDIAN error 0.09%, 90th percentile 0.26%. Every zone below then
-- came out on the exact 3:2 rectangle every WorldMapArea uses, with a 0.00% median
-- residual -- so width and height are averaged across both axes and squared to 3:2.
--
-- Deliberately absent -- too few unambiguous spawns to fit, and a size that is merely
-- plausible would put every minimap dot in the wrong place:
--   Crystalsong Forest (2 pairs; the 2-point fit lands on ratio 1.59, not 1.50)
--   Wintergrasp (0), Hrothgar's Landing (1)
-- They keep the current behaviour: world map nodes only, no minimap dots.
pfDB["minimap-wotlk"] = {
  [3537] = { 5765.07, 3843.38 }, -- Borean Tundra (75 spawns)
  [4395] = { 830.12, 553.41 }, -- Dalaran (12 spawns)
  [65] = { 5609.0, 3739.33 }, -- Dragonblight (53 spawns)
  [394] = { 5249.87, 3499.91 }, -- Grizzly Hills (41 spawns)
  [495] = { 6046.03, 4030.68 }, -- Howling Fjord (60 spawns)
  [210] = { 6271.32, 4180.88 }, -- Icecrown (57 spawns)
  [4298] = { 3162.12, 2108.08 }, -- Plaguelands: The Scarlet Enclave (15 spawns)
  [3711] = { 4356.19, 2904.13 }, -- Sholazar Basin (20 spawns)
  [67] = { 7112.05, 4741.36 }, -- The Storm Peaks (28 spawns)
  [66] = { 4993.84, 3329.23 }, -- Zul'Drak (24 spawns)
}
