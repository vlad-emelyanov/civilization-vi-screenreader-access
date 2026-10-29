# Civilization VI - Screen Reader Access mod

[Proof of Concept video on YouTube](https://www.youtube.com/watch?v=asmt26CQf8Q)

## Introduction

Sid Meier's Civilization VI is a superb turn based empire building strategy game. One thing it lacks is accessibility for people with low or no vision, or who have difficulty reading large amounts of text.

This mod lets people who use a screen reader play the game with the keyboard (or an Xbox controller) and speech, at an equal level to their peers. It covers the front end (main menu, game setup, load game, options, multiplayer lobby) and the game itself: a map cursor, unit orders, the production/research/civic choosers, the city report, notifications, diplomacy and deals, city-states, governors, religion, trade, World Congress and most other screens. Control+H in game lists every shortcut.

Content supported: the base game and Gathering Storm (which includes the Rise and Fall systems), plus the free Barbarian Clans and Tech and Civic Shuffle modes. Other DLC is untested.

## How it works

Civilization VI mods cannot call DLLs, make HTTP calls, write files or write database rows at run time. One of the few channels out of the game is Lua's `print`, which lands in `Lua.log`. The mod prints lines with special prefixes, so genuine log messages are never read out.

A separate console application (`ScreenreaderAccess.Console`, .NET 10, Windows) watches `Lua.log`. It speaks the prefixed lines through the player's screen reader (using the [AccessibleOutput](https://github.com/saqibS/accessibleOutput) package) and, where a screen still needs it, moves or clicks the real mouse. The console app must be running while you play.

The mod itself consists of:

* a hub context (`ScreenReaderAccess/UI/Additions/InGameAccess`) with its modules in `ScreenReaderAccess/Assets/UI/Accessibility/Hub*.lua`: global hotkeys, the map cursor, keyboard lists and event announcements;
* modified copies of the game's own Lua UI files where no event exists to hook into. These are more work and risk conflicts with other mods that change the same files, but are often necessary.

## Controller

The console app also turns an Xbox-style controller (XInput) into keyboard input for the game: it injects Enter, Escape, Space, the arrows, Home/End, Tab and F13-F24 (and Control+F13..F16 for the right stick) while Civilization VI is in the foreground; the mod's hub then reads those keys. The button map is in `docs/controller-plan.md`. Hold RT to use the left stick, D-pad and A with Shift (Shift+Arrows, Shift+Home/End, Shift+Enter; D-pad left/right stay Tab / Control+Tab). F22/F23 tell the mod when controller mode switches on or off, and F13-F24 are used as the controller's extra keys, so do not bind them yourself. Spoken key hints name the controller button when the pad was used last.

Steam Input must be disabled for the game (Steam library, Civilization VI, Properties, Controller, "Disable Steam Input"), otherwise every press arrives twice. Start the console app with `--no-gamepad` to turn the feature off, or `--gamepad-log` to print every key it sends.

## Contributing

Help, advice and feedback are welcome.

### Development environment

* Base game: [Civilization VI](https://store.steampowered.com/app/289070/Sid_Meiers_Civilization_VI/)
* SDK: [Civilization VI Development Tools](https://steamdb.info/app/404350/) (ModBuddy builds the mod)
* [Visual Studio](https://visualstudio.microsoft.com/) or [Visual Studio Code](https://code.visualstudio.com/), and the .NET 10 SDK for the console app

Note for screen reader users: ModBuddy's code editing windows are not accessible to screen readers, so edit the code in VS or VS Code; ModBuddy is still the way to build the mod.

Developer documentation: `CLAUDE.md` (architecture, layout, build and test loop, workflow rules) and the `docs/` folder (how to make a screen accessible, speech rules, engine notes, feature status, backlog).
