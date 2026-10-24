# What content this install owns

The user owns the base game and Gathering Storm only (plus the free content). Plan tests, scenarios and features around that. Multiplayer with friends can only use this content too.

## Evidence

- `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\Logs\Modding.log`, "Target Mods" block when a game loads: only Aztec_Montezuma, Expansion2 (Gathering Storm, id 4873eb62-8ccc-4574-b784-dda455e74e68) and Screen Reader Access. In the front end the list also holds the free content: Barbarian Clans and Tech and Civic Shuffle game modes, and the free scenarios (War Machine, Cold War, Pirates, Black Death, Civ Royale, Ancient Rivals, Religious Combat, Napoleon).
- All fixture saves contain only `EXPANSION2_MOD` and no `GAMEMODE_*` strings.
- Every DLC folder exists under `...\Sid Meier's Civilization VI\DLC\` because Steam downloads them all: folder presence and `appmanifest_289070.acf` do NOT show ownership.

Re-check: load a game, then grep `Modding.log` for the Target Mods block; for a save: `grep -a -o -E "GAMEMODE_[A-Z_]+|[A-Z0-9_]+_MOD" save.Civ6Save`.

## Available

| Content | Notes |
|---|---|
| Base game civs and leaders | |
| Aztec (Montezuma) | |
| Gathering Storm | civs, World Congress, climate and disasters, power, diplomatic favor |
| Rise and Fall systems | included by Gathering Storm: governors, loyalty, eras/golden/dark ages, historic moments, emergencies (R&F alone is NOT owned: its civs such as Cree, Georgia, Korea, Mapuche, Mongolia, Netherlands, Scotland, Zulu are missing) |
| Game mode Barbarian Clans | parameter `GameMode_BarbarianClans` |
| Game mode Tech and Civic Shuffle | parameter `GameMode_Tree_Randomizer` |
| Free scenarios | listed above |

## Not available

| Content | Folder |
|---|---|
| Secret Societies | Ethiopia (also referenced by Babylon, Byzantium_Gaul, Portugal) |
| Heroes and Legends | Babylon |
| Dramatic Ages | Byzantium_Gaul |
| Apocalypse | GranColombia_Maya |
| Monopolies and Corporations | KublaiKhan_Vietnam |
| Zombie Defense | not installed |
| Civ/leader packs: Poland, Australia, Macedonia and Persia, Nubia, Khmer and Indonesia, Vikings (incl. landmarks) | |
| New Frontier Pass (its game modes and civs), Leader Pass (Rulers of China/England/Sahara, Great Builders/Negotiators/Warlords), personas TeddyRoosevelt, CatherineDeMedici, JuliusCaesar | |

## Do not test / do not build features for

Secret society governors, hero units and Heroes and Legends UI, monopolies and corporations (resource monopolies, the Great Merchant corporation flow), Dramatic Ages (era score variants, Dark/Golden/Heroic age text beyond the base rules), Apocalypse, Zombie Defense, any non-owned civ or leader, and any game mode other than Barbarian Clans and Tech/Civic Shuffle.

Mod code that is only reached through unowned content (the secret-society governor entries in `UI/Replacements/GovernorPanel_SRA.lua` and `GovernorDetailsPanel_SRA.lua`, the Dramatic Ages text in `EraProgressPanel_SRA.lua`) is upstream code kept as is; it cannot be verified here.

The `modes` profile enables the two owned modes. The `modes-start` fixture predates that: it is a plain Medieval start with no game mode (regenerate with `civctl newgame modes`).
