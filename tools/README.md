# Data provenance (not shipped in releases)

`convert.lua` is the Questie→pfDB converter that generated the WotLK data
overlay in `db/*-wotlk.lua` (quests, NPCs, objects, items, zone names). It
reads [Questie](https://github.com/Questie/Questie)'s `Database/Wotlk/*.lua`
and emits only the entries missing from pfQuest's merged vanilla+TBC database.
Kept here to document where the WotLK data came from and to regenerate the
overlay after a Questie data update.

It runs under plain `lua5.1` against `stub.lua` (a minimal WoW API shim so
the pfDB files load outside the client); adjust the `pfqbase` / `questiebase`
path variables at the top of the script to point at your repo checkout and a
sibling Questie clone before running:

```sh
cd tools
lua5.1 convert.lua
```
