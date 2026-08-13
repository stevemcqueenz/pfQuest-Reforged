-- Vanilla quests that Blizzard REWORKED for Wrath, where pfQuest still carries
-- the 1.12 version of the content (issue #43).
--
-- pfQuest's vanilla quest data was never refreshed against 3.3.5a: of the 4435
-- quests db/quests.lua defines, exactly 5 are overridden by the -wotlk overlay.
-- So any quest Blizzard changed during Wrath still describes the vanilla one.
-- This file corrects those, field-wise, without touching upstream's data files.
--
-- Every value here was taken from TWO independent 3.3.5a sources that agree:
-- the AzerothCore world database (quest_template, creature_loot_template,
-- creature_template) and Questie-335's WotLK database. Where they disagreed,
-- nothing was changed.
--
-- Currently one rework: the Elwynn Forest wolves.
--
--   Vanilla: Timber Wolf (69) and Young Wolf (299) dropped Tough Wolf Meat
--            (750), which quest 33 "Wolves Across the Border" asked for.
--   3.3.5a:  both mobs are renamed "Diseased ...", they drop Diseased Wolf
--            Pelt (50432) instead, and quest 33 asks for that.
--
-- Note the mobs kept their creature IDs, so pfQuest's map pins were always in
-- the right place. What was wrong was the item the quest asks for, the item's
-- drop sources, and the two names.
--
-- The 750 correction is NOT incidental: on 3.3.5a Tough Wolf Meat drops only
-- from Ragged Timber Wolf (704) and Ragged Young Wolf (705). Leaving 69 and
-- 299 on its source list would send quest 179 "Dwarven Outfitters", which
-- still wants 750, to two wolves that no longer drop it.
pfDB["rework335"] = {
  -- field-wise onto pfDB.quests.data: only the named fields are replaced
  ["quests"] = {
    [33] = { ["obj"] = { ["I"] = { 50432 } } },
  },
  -- REPLACES the item's U map outright; chances are AC's Chance column
  ["items"] = {
    [50432] = { ["U"] = { [69] = 90, [299] = 90 } },
    [750] = { ["U"] = { [704] = 90, [705] = 90 } },
  },
  ["itemnames"] = {
    [50432] = "Diseased Wolf Pelt",
  },
  ["unitnames"] = {
    [69] = "Diseased Timber Wolf",
    [299] = "Diseased Young Wolf",
  },
}
