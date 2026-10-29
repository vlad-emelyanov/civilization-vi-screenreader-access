# Making a screen keyboard- and screen-reader-accessible

Lessons from implementing keynav on the main menu, Create Game, Advanced Setup and load screens. Reference implementations: `ScreenReaderAccess/Assets/UI/Frontend/MainMenu.lua` and `AdvancedSetup.lua`.

## Recipe

1. **Find the right file.** Locate the screen's Lua in the game install (`Base/Assets/UI/...`); check whether `DLC/Expansion*/UI/Replacements` replaces it. Copy it into `ScreenReaderAccess/Assets/UI/...` and commit it untouched first (pristine asset), then register it in the `.civ6proj` (see `CLAUDE.md`).
2. **Hook input.** Most screens have `ContextPtr:SetInputHandler(OnInputHandler, true)`. Handle `KeyEvents.KeyUp` like the existing screens, and route to a `KeyHandler(key)`. Keep the game's own keys (Escape = back, etc.) working. Return `false` for keys you don't use when the original did, so hotkeys still work.
3. **Hook a per-frame update** (`ContextPtr:SetUpdate`) if you need deferred mouse moves; call `KeyNav_Tick(deltaTime)` from it if you use the helpers in `KeyboardNavigation.lua`.
4. **Announce on show:** the screen title with `nointerrupt = true`, then the initially focused item.
5. **Test in the game** with `util\civctl.cmd` (see the `civ-test` skill), including returning to the screen (Back, popups closing) and a second fresh launch.

## Conventions

| Key | Meaning |
|---|---|
| Up / Down | move focus, wrapping |
| Left / Right | change the focused option's value (pulldowns, sliders, leaders, map type); in the main menu, switch between top level and submenu |
| Enter | activate button / open picker |
| Enter / Space | toggle checkbox |
| Escape | back / close submenu / close popup |

Announcement formats: `"<Label>: <value>"` for options, `"<Label>: checked|unchecked"` for checkboxes, the button's own text for buttons, `"<Section>, <Label>: <value>"` where a section name disambiguates (Advanced Setup). Read labels from the parameter/control text, not hardcoded strings (localization).

## Patterns that work

- **Announce directly on focus change** with `OutputMessageToScreenReader`. Don't rely on the mouse moving onto a control and its `MouseEnter` announcing it: the move can be late, land on the wrong control while things animate, or never happen.
- **Build the item list at key-press time** from what is currently visible and enabled (`IsHidden()`/`IsDisabled()`), not once at show time. Setup parameters refresh and controls appear/disappear (e.g. changing ruleset removes the disaster slider; Resume Game is hidden without saves). Note `IsHidden()` only checks the control's own flag, not its ancestors; check the containing window/container too.
- **Track focus by identity** (label, parameter id, a stable key like `"param:<pid>"`, `"leader:<playerId>"`), never by index: lists change between key presses.
- **Activate by calling the callback** (`OnStartButton()`, the menu entry's callback) rather than `KeyNavLeftClick()`. A synthetic click hits wherever the real mouse is, which was the root cause of the main menu's "Enter does the wrong thing" bug. Use the click only when there's no reachable callback, and only after the mouse is known to be on the control.
- **Change values through the game's own path:** setup parameters via `o:SetParameterValue(parameter, value)` then `Network.BroadcastGameConfig()` (what the pulldown callbacks do); skip values marked `Invalid`.
- **Still move the mouse to the focused control** (`KeyNavMoveMouse`) so sighted helpers/tooltips follow and clicks land right, but **defer it until layout has settled**: wait until the control's screen offset is unchanged for several frames (and its animation `IsStopped()`); `IsStopped()` alone fired too early on the main menu. After scrolling a panel, wait a few frames before reading positions.
- **Suppress hover announcements while you move the mouse** (and while items slide in under the cursor), otherwise you get bursts of announcements. Real mouse hover can still move focus and announce once.
- **Scroll the focused item into view** in scroll panels before moving the mouse (see `KeyNavFocus` in `AdvancedSetup.lua`).
- **Clean text for speech:** convert `[NEWLINE]` to `. `, drop `[ICON_*]` and other markup (`CleanForSpeech` in `LoadScreen.lua`).
- **Register listeners with `SRListen`** (`Accessibility/SRListen.lua`, `include( "SRListen" )`): `SRListen( Events.X, OnX )` does the `Add` and remembers it; call `SRUnlistenAll()` once in the context's shutdown handler (`ContextPtr:SetShutdown( function() SRUnlistenAll(); end )`) and a hot reload or game exit leaves no stale listener behind. **A hot reload (`civctl reload`/`deploy`) does run the old instance's `ContextPtr:SetShutdown` handler** (verified 2026-10-22 with a probe print in `UnitPanel.lua`: it appeared once per reload), so the shutdown cleanup is reliable. Adopted in `UnitPanel.lua`, `AdvisorPopup.lua`, `HistoricMoments_SRA.lua` (two reloads each: one `SR>` line per unit selection, no `Runtime Error`); use it for every override you touch (others still use hand-written `.Remove` calls). Offline-tested in `test/lua/test_srlisten.lua`.

## Where new in-game hub code goes

The in-game hub (`UI/Additions/InGameAccess.lua`) is split into `Accessibility/Hub*.lua` modules (module list and ownership: `docs/features.md`, Architecture; what each front-end screen covers: `docs/features.md`, Front end). Put new code in the module that owns the feature (map cursor in `HubCursor`, a new keyboard list or region in `HubRegions` / its own `HubX.lua`), and only wire it up in the hub's `Initialize` (`Hub.RegisterAction`, `HubCore.AddEvent` / `HubCore.Listen`). Define shared functions and state as fields of the module table (`function HubX.Name()`, `HubX.m_state = ...`); keep helpers used by a single file `local` (a chunk holds at most 200 locals). A new module is a new file: define one global table `HubX = {};`, add it to `.luacheckrc` `globals`, register it with `python util/civ6proj.py add --context InGame Assets/UI/Accessibility/HubX.lua`, `include( "HubX" )` it in the hub before `Initialize` (modules must not use other modules at load time, only inside functions), and note that it needs a build + restart.

**New shortcuts need a help entry.** Add every new or changed shortcut (input action, or a key inside a screen or list) to `Accessibility/HelpText.lua`: it is the one place that describes the shortcuts, shown by Control+H (`HubHelp.lua`, action `KeyNavHelp`). Entries with `action = "<Id>"` show the current binding (so rebinding is reflected), entries with `keys = "..."` are for keys inside our own lists. `test/py/test_helptext.py` fails when a `KeyNav*` input action has no entry. The help list exists in game only, not in the front end (the front-end screens announce their keys themselves).

## Item wording in lists

The full set of speech rules is `docs/speech-guidelines.md`; read it before writing any spoken text. In short: an item starts with what tells it apart from its neighbours; words every item shares or the title already said are dropped or moved to the opening line; status and numbers follow; position (n of m) stays last. Example, the builder's tile browser: "Lumber Mill plus 2 production, 2 tiles south, Plains Rainforest, 2 turns, worked, 1 of 5" (improvement and yield first, then where, then the tile, then turns and status).

## Key names in spoken text

Any key name in spoken text goes through `SRKey( keyboard[, button] )` (`ScreenReader.lua`), never as a literal: `"Choose a tile, or " .. SRKey( "Escape" ) .. " to cancel"`. The console app speaks the keyboard or the controller button, depending on the device last used (see `docs/controller-plan.md`, "Spoken key hints"). Give the button when the screen has a pad alias for that key (`SRKey( "C", "X" )` in the religion screen, where X is the alias of C); the common keys (Enter, Escape, Space, Tab, Home, End, arrows) have a default button (Tab/Control+Tab default to the D-pad, which is right on the bare map; where Tab means "next section" in a list or screen pass `SRKey( "Tab", "RB" )` / `SRKey( "Control+Tab", "LB" )`). A list gets D-pad, bumper and PageUp/PageDown handling for free from `KeyNavList` (items' `section` = groups, `sectionCounts`, `tabEdge`); a hand-written handler with Tab/Home/End calls `input = Gamepad.WrapInput( input )` first. Keys without any pad equivalent stay unwrapped. Hints that only make sense on the pad (a button the keyboard has no equivalent of, e.g. "Y for details") go through `SRPadHint( text )`, which returns `[PAD:text]`: spoken as `text` when the pad is current, removed on the keyboard. `text` must not contain `]`. `KeyNavList` appends `SRPadHint( ", Y for details" )` to the first announcement after open when that item has a `detail` (option `noDetailHint = true` opts out). The mirror, `SRKbHint( text )` -> `[KB:text]`, is spoken only when the pad is NOT current (removed on the pad): use it for a keyboard-only key name that is noise on the pad (the unit actions menu's ", key D", because A already runs the entry). Tests: `Spoken()` returns the keyboard text (`[PAD:]` removed, `[KB:x]` kept as `x`), `SpokenRaw()` the tokens.

## Traps

- **Mouse resting on a slider eats arrow keys.** The engine gives the slider all arrow input and the context stops receiving keys. Park the mouse on the slider's label instead.
- **Errors in an input handler kill keyboard input for the screen silently.** Wrap in `xpcall` and print the traceback while developing.
- **The front-end menu animates in.** Positions read during the slide are wrong (e.g. x=699 instead of 978).
- **Popups own input while open.** Make your handler inactive when a picker/popup in the same context is shown, and re-announce the focused item when it closes.
- **The game's Lua sandbox has no `debug` table.** `xpcall` error handlers must not call `debug.traceback` (that errors inside the handler and hides the real error); use `tostring(e)`.
- **Helpers that a front-end screen `include`s must be imported in both `FrontEndActionData` and `InGameActionData`** (`ImportFiles` in the `.civ6proj`). After a game is played and exited, the front end is rebuilt from the in-game file set; a helper missing there makes `include` find nothing and the screen script silently aborts (e.g. an empty Create Game).
- **Every `Events.X.Add` / `LuaEvents.X.Add` needs a matching `.Remove` on shutdown** (`ContextPtr:SetShutdown`), with the same function reference. Hot reload (`civctl deploy`) re-runs the script but the old instance's listeners stay registered in the engine: they fire in a dead environment (globals gone, e.g. "function expected instead of nil" from an error handler) and the stale instance also runs its handlers, so everything is spoken twice and mode changes happen twice. The hub registers through a `Listen(event, fn)` helper that records each listener and removes them all in its shutdown handler; give anonymous handlers a name so they can be removed. Also capture globals such as `KeyNavErrorHandler` in a local at load.
- **The game must be restarted** to load Lua changes after `build`.
