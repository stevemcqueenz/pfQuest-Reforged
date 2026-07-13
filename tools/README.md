# Dev tools (not shipped in releases)

Offline development harness for the addon — everything runs under plain
`lua5.1` on a scripted 3.3.5a stub, no game client needed.

| File | Purpose |
| --- | --- |
| `stub.lua` | Minimal WoW 3.3.5a API stub (frames, events, quest log fakes) |
| `run.lua` | Regression harness: simulates login + quest progress and counts map nodes per scenario (env knobs: `PFQ_MODE`, `PFQ_ITEMQUEST`, `PFQ_OBJDONEFLAG`, `PFQ_DONECOMPLETE`, `PFQ_COMPLETERACE`, `PFQ_NILRACE`, `PFQ_AUTOWATCH`) |
| `dumpdb.lua` | Dumps the merged quest DB to `pfquest-quests.tsv` (id + title) |
| `comparefields.lua` | Field-level diff of the shared quest set vs Questie's WotLK DB |
| `convert.lua` | The Questie→pfDB converter that generated the `db/*-wotlk.lua` overlay (2,487 quests, NPCs/objects/items/zones). Re-run to regenerate after a Questie data update. |

Path expectations: the scripts were written against a working directory
containing this repo checkout and a sibling shallow clone of
[Questie](https://github.com/Questie/Questie) (`convert.lua` and
`comparefields.lua` read `Database/Wotlk/*.lua` from it). Adjust the `base`
path variables at the top of each script to your layout before running.

Typical regression run:

```sh
cd tools
lua5.1 run.lua                                   # monster-quest baseline
PFQ_ITEMQUEST=1 PFQ_DONECOMPLETE=1 lua5.1 run.lua  # collect-quest + server-quirk case
```

"after login" and "after kill" node counts must match within a scenario —
a drop means quest pins vanished on progress (the bug class the harness
exists to catch).
