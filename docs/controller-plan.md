# Xbox controller support (design, 2026-10-27)

Goal: a blind player can play with an Xbox controller instead of the keyboard. The controller has far fewer buttons than the keyboard, so buttons are multipurpose, depending on what has the focus. This file is the design and the contract between the console app, the Lua side and the tests. Status at the end.

## How controller input reaches the mod

Civ VI on PC does not react to a gamepad (the engine carries console-port leftovers: `Keys.PAD_*`, `GestureType="Controller"` rows in `InputConfiguration.xml`, `UIManager:IsGamepadActive`; none of it is verified to do anything on PC, and we cannot depend on it). The mod only sees keys, so:

- The **console app** (`ScreenreaderAccess.Console`, which must run anyway for speech) polls the controller through XInput and **injects keyboard keys** into the game window (`SendInput` with scan codes, exactly like `util/civctl.ps1` `Chord`). Buttons that mean the same thing as a keyboard key everywhere (A = Enter, B = Escape, Y = Space, left stick = arrows, D-pad = Home/End/Tab) are sent as that key, so every existing list and screen works unchanged. Buttons without a keyboard equivalent are sent as keys the game and the mod do not use (F13 to F24, with Control for a second bank) and are interpreted by the mod.
- The console app only injects while the game window is in the foreground, and only when a controller is connected. `--no-gamepad` turns the feature off.
- **Controller mode** is a flag in the mod: on when the controller is in use, off when the keyboard is. The console app sends `F22` (mode on) before the first controller input after keyboard use and `F23` (mode off) when a physical key is pressed after controller use (a low-level keyboard hook; injected keys do not count). In controller mode a few keys change meaning on the bare map (below); outside it the keyboard behaves as before. The first physical key after controller use may be swallowed on the bare map (it arrives before F23); that is accepted.
- **Tests do not need a controller**: `civctl key F15` is exactly what the console app sends for RB. Regress scripts drive the controller layer with the F-keys (comment the button name in the script).
- Steam Input must be disabled for the game (Steam library, Civilization VI, Properties, Controller: "Disable Steam Input"), otherwise Steam also translates the controller into keyboard and mouse and every press arrives twice.

## Button map (canonical table: `Accessibility/Gamepad.lua`; mirrored in `ScreenreaderAccess.Console/Gamepad/GamepadMap.cs` and `util/keybindings.py`; `test/py/test_gamepadmap.py` checks that all three agree)

| Controller | Key sent | Everywhere | On the bare map (controller mode) | In a hub list (mode) | In a target mode (move to, attack) |
|---|---|---|---|---|---|
| A | Enter | activate / confirm | Next Action (the game's Enter, with the hub's Enter guards) | activate the item | confirm the tile |
| B | Escape | back / close | nothing (swallowed; it must not open the game menu) | close the list ("Closed") | cancel |
| Y | Space | details | own city on the cursor tile: city report (Control+I); else plot details (I) | read the item's details | combat modifiers (attack modes) |
| X | F13 | the list's secondary action (see "X in lists") | select your unit or city on the cursor tile (K; again: the next one there) | the list's X action, else nothing | nothing |
| Left stick | Up/Down/Left/Right | move in lists; Left/Right change values | move the map cursor one tile (also when the user did not bind the cursor to the arrows) | move | move the target cursor |
| D-pad up / down | Home / End | first / last item | What is next (N) / cursor to selection (.) | first / last | nothing |
| D-pad right / left | Tab / Control+Tab | next / previous section or tab | unit actions menu or city production (what Tab does) / area overview (Shift+J) | next / previous section (places categories, help sections, production tabs) | nothing |
| LB / RB | F14 / F15 | previous / next list of the ring (below) | opens the last / first ring list | ring previous / next | refused: "Choose a tile, or B to cancel first" |
| LT | F16 | | Attack (what the W key does for the selected unit or city) | nothing | nothing |
| RT | F17 | | Move To (what the M key does for the selected unit) | nothing | nothing |
| View (Back) | F18 | accessibility help (Control+H), toggles | | | (opens, like Control+H) |
| Menu (Start) | F19 | the in-game menu (`LuaEvents.InGame_OpenInGameOptionsMenu()`); closes an open hub list first | | | |
| Left stick click | F20 | capital city (what Shift+4 / the CapitalCity action does, with the mod's announcement) | | | |
| Right stick click | F21 | next ready unit (the NextUnit action: `UI.SelectNextReadyUnit()` with the mod's "no unit needs orders" line) | | | |
| Right stick up / down | Control+F13 / Control+F14 | previous / next of ALL your units (Control+K order, both directions) | | | |
| Right stick left / right | Control+F15 / Control+F16 | previous / next city (`UI.SelectPrevCity` / `UI.SelectNextCity`; "You have no cities") | | | |
| (console app) | F22 / F23 | controller mode on / off | | | |
| reserved | F24, Control+F17..F24 | | | | |

Popups and the in-game menu sit above the hub and take every key: there A/B/Y/sticks work through their keyboard equivalents and the F-keys do nothing. Game screens (tech tree, city-states ...) get keys after the hub: the hub passes every mode-dependent button through while `HubCore.IsGamePopupOpen()`; LB/RB then say "Close the screen first". The front end (main menu, setup) has no hub: A, B, Y, sticks and D-pad work through their key equivalents, the other buttons do nothing.

Right stick and stick clicks (selection changes) work on the bare map and inside hub lists (a selection change closes the list, as it does with the keyboard); they pass through while a game screen is open.

## The ring (LB / RB)

The in-game UI is a ring of keyboard lists; RB opens the next, LB the previous; B closes the open one back to the map. Order:

1. Notifications (Control+N list)
2. Top panel (Control+Y list)
3. Lenses (new, `HubLenses.lua`): one item per lens the number keys toggle ("Appeal lens, off"); A toggles it (the same speech as the number key) and the list stays open with the item refreshed; Y reads the legend
4. Diplomacy (V list of met civilizations)
5. Screens (new, `HubScreens.lua`): the launch bar and partial-screen hooks: Tech tree, Civics tree, Government, Religion, Great People, Great Works, Governors, City-States, Espionage, Trade routes, World rankings, Climate, Era progress, Reports, Civilopedia. A closes the list and opens the screen through the same function the game's button runs (`LuaEvents.SRA_OpenScreen(name)` handled by our `LaunchBar.lua` / `PartialScreenHooks.lua` overrides); the screen announces itself as it does today; B closes it. An item whose hook is hidden says "not available"
6. Places (J list)

RB from the bare map opens 1, LB opens 6; from a ring list they move; from another hub list (unit actions, settle browser, city report ...) RB opens 1 and LB 6. `HubPad.RingStep(currentModeName, +1|-1)` is a pure function (unit-tested).

## X in lists

Each list names its X action (the key the list already has for it): notifications: dismiss (Delete); places: send a unit there (M); every other list: nothing yet. A list declares it with `extraKeys[ Gamepad.Key( "X" ) ]` (so keyboard users are unaffected) and its help entry mentions "X".

## Controller mode on the bare map: the catcher

Keys that no screen wanted reach `WorldInput` last (it is below the hub and every screen; the game's own Escape-to-menu sits even lower, in `InGame.lua`). In controller mode its default key handlers catch: arrows (cursor move, KeyDown so a held stick repeats), Escape (swallowed), Space (Y), Home / End / Tab-with-Control (D-pad). The decision is the pure function `Gamepad_CatchKey( msg, key, isControl, active )` in `Gamepad.lua` (unit-tested); `WorldInput.lua` calls it from `DefaultKeyDownHandler` / `DefaultKeyUpHandler` and fires `LuaEvents.SRA_PadCursor( dx, dy )`, `SRA_PadDetails()`, `SRA_PadInfo( "next" | "where" | "overview" )`; the hub listens. A key the catcher consumes never becomes an input action (so Home does not also open the in-game menu). The hub keeps controller mode (`Gamepad.SetActive`) and broadcasts it with `LuaEvents.SRA_GamepadMode( active )`; WorldInput keeps a copy. Every F-key button also turns the mode on.

## Help

`HelpText.lua` gets a "Controller" section (the table above in words, one entry per button). In controller mode `HubHelp` lists that section first. Per-list help entries that have an X action mention it.

## Console app

`ScreenreaderAccess.Console/Gamepad/`: `XInputReader` (P/Invoke `xinput1_4.dll` `XInputGetState`, first connected pad of 0..3, disconnected slots re-checked every 2 s), `GamepadMapper` (pure: previous and current state plus time to key events; buttons send KeyDown on press and KeyUp on release; stick directions and the D-pad are digital at 50 % deflection with keyboard-like repeat: left stick and D-pad 350 ms then every 110 ms, right stick 500 ms then every 350 ms; triggers are buttons above 50 %), `KeyInjector` (SendInput with scan code and the extended flag for arrows/Home/End, Control held 40 ms around the second-bank keys, `dwExtraInfo` marks our own events), `ForegroundGuard` (inject only when the foreground window belongs to a `CivilizationVI*` process), `InputDeviceTracker` (WH_KEYBOARD_LL hook: a non-injected key switches to keyboard mode and sends F23; the next controller input sends F22 first). Polling at ~60 Hz on a background thread; console lines "Gamepad: connected (slot 0)", "Gamepad: disconnected", and with `--gamepad-log` every mapped key. `--no-gamepad` disables it. No controller present: the feature idles and says so once.

## Status

- 2026-10-27: design written; nothing implemented or verified. Engine facts still to probe: `Keys.VK_F13`..`VK_F24` values and that `civctl key F13` / `Control+F13` reach the hub's handler; that `WorldInput`'s default handlers see Escape/arrows/Space with nothing open and that returning true there blocks the in-game menu and the input action; whether a real controller makes the engine do anything on its own (needs the user's pad: plug it in, start the game with the mod, press A on the main menu).
- 2026-10-27: Lua core written offline (`Gamepad.lua`, `HubGamepad.lua`, catcher in `WorldInput.lua`; regress `pad-map`, `pad-select` unrecorded). Engine facts relied on (confirmed by the probe): `Keys.VK_F13..F24`, Control+F-keys reach the hub with `IsControlDown()`, WorldInput's default handlers see unclaimed keys and returning true there blocks Escape-to-menu. The catcher acts on KeyUp alone for Space/Home/End/Control+Tab and keeps no Down/Up state. Control state in WorldInput: `pInputStruct:IsControlDown()` passed as 2nd argument of `DefaultKeyDownHandler` / `DefaultKeyUpHandler`. LuaEvents introduced: `SRA_GamepadMode(active)` (hub -> WorldInput), `SRA_PadCursor(dx,dy)`, `SRA_PadDetails()`, `SRA_PadInfo(info)` (WorldInput -> hub), `SRA_PadCapital()`, `SRA_PadNextUnit()` (hub -> WorldInput, run the game's CapitalCity / NextUnit hotkey code), `SRA_PadHotkey(name)` (hub -> UnitPanel: LT/RT run the `Attack` / `MoveTo` hotkey). `HubCursor.CycleAllUnits(step)` takes -1 for previous; `HubCityReport.ToggleCityReport(preferCursor)`. Menu, View, the stick clicks and the right stick also work in target modes (the keyboard equivalents are not blocked there either). The hub re-broadcasts the flag on `LuaEvents.SRA_GamepadModeRequest()` (WorldInput asks in Initialize) and once at hub init; mode keys F22/F23 work on AI turns, the other buttons only on the local player's turn.
