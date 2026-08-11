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
-- Crystalsong Forest and Wintergrasp could not be fitted this way (2 pairs and 0),
-- so they were left out. They are now filled in from a DIFFERENT source, since
-- pfQuest has no spawns there to fit against: Questie-335's QuestieCompat.UiMapData,
-- which ships the WorldMapArea rectangle (width, height, left, top) for every zone.
-- That source was validated before being trusted -- its rectangles reproduce the
-- fitted models above to a median 0.011% across 66 zones, and pfQuest's own shipped
-- coordinates to a median 0.041% over 1656 one-to-one spawn pairs. For Wintergrasp
-- specifically, its rectangle applied to 323 AzerothCore spawns reproduces
-- GatherMate's independent extraction of the same nodes to a median 0.006%.
-- Both widths also agree with GatherMate's own zone table to four decimals.
--
-- NOT a blanket endorsement of that source: its rectangles are retail-era, and for
-- the Burning Crusade starting zones (Azuremyst, Bloodmyst, Silvermoon, The Exodar)
-- they disagree with this client by hundreds of percent. Those zones keep the
-- fitted values, which GatherMate agrees with. Use UiMapData only where there is
-- nothing to fit, and only after checking it.
--
-- Still absent: Hrothgar's Landing. Nothing pfQuest tracks spawns there, so there is
-- no way to check a rectangle for it and no benefit to adding one.
-- Eastern Plaguelands is not a WotLK zone, but its map rectangle was rescaled
-- during Wrath and pfQuest still ships the 1.12 size (3870.83 x 2581.25). The
-- coordinate correction in database.lua moves every EPL node onto the 3.3.5a
-- rectangle, so the minimap needs that rectangle's size too or it would undo the
-- correction on the minimap while the world map showed it right.
pfDB["minimap-wotlk"] = {
  [139] = { 4031.25, 2687.5 }, -- Eastern Plaguelands (rescaled in Wrath)
  [2817] = { 2722.92, 1814.58 }, -- Crystalsong Forest (UiMapData)
  [4197] = { 2975.0, 1983.34 }, -- Wintergrasp (UiMapData)
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
