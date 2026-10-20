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

## Traps

- **Mouse resting on a slider eats arrow keys.** The engine gives the slider all arrow input and the context stops receiving keys. Park the mouse on the slider's label instead.
- **Errors in an input handler kill keyboard input for the screen silently.** Wrap in `xpcall` and print the traceback while developing.
- **The front-end menu animates in.** Positions read during the slide are wrong (e.g. x=699 instead of 978).
- **Popups own input while open.** Make your handler inactive when a picker/popup in the same context is shown, and re-announce the focused item when it closes.
- **The game must be restarted** to load Lua changes after `build`.

## Coverage (2026-10-19)

Keyboard path that works end to end: Main menu → Single Player → Create Game (basic options) / Advanced Setup (all options, players, add/remove AI) → Start Game → load screen announcements → Enter begins the game. Load Game (see below) and the Exit confirmation popup also work.

Setup-screen pulldowns are covered by the mod-side selection mode (d4a7e11): Enter opens it, Up/Down/Home/End announce "value, i of n", Enter applies, Escape cancels.

Load Game (`Frontend/LoadGameMenu.lua`): announces the title and "N saves" / "No saved games" on open, focuses the first save. Up/Down walk saves (name, leader, civ, turn, date, "i of n"; selecting loads the details panel), Autosaves, Cloud, sort, Load, Delete, Back, wrapping. Tab jumps between the groups (saves / options / buttons), Home/End first/last save, Space on a save reads its full details, Space/Enter toggles the checkboxes (state announced), Left/Right/Enter changes the sort, Enter on a save or Load loads it, Delete opens the confirmation popup (Up/Down + Enter work in it, Escape cancels), Escape goes back. The in-game Save Game screen (same shared code) is not covered.

Map Select popup and Multi-Select window (Natural Wonders; only shown for non-static maps): navigable (see their files). Gaps: inside the leader picker and city-state picker (Enter opens, Escape closes, no navigation inside; Left/Right on the setup screens covers the same choices); the Gathering Storm welcome popup and most of the in-game UI. Known in-game Lua error: `WorldInput.lua` `KeyNavPlotMoveTo` (function expected instead of nil).

Options screen (main menu > Game Options, `Options.lua`): every tab is keyboard accessible. Tab level: Up/Down over the tabs, Confirm, Restore Defaults and Back (announced, disabled state spoken), Enter/Right enters a tab, Escape = Back ("Changes discarded" if Confirm was enabled). Inside a tab (controls listed in `TAB_ITEMS`, rebuilt from visible state at key time): Up/Down/Home/End, Left/Right change pulldowns and sliders (sliders announce value, minimum, maximum; the mouse is parked off sliders), Enter opens the mod-side pulldown list ("value, i of n"), Enter/Space toggles checkboxes, Enter presses buttons (Show Advanced Options), Escape returns to the tab bar. Key Bindings: Up/Down/Home/End/Tab(next category), Left/Right primary or alternate, Enter rebinds (the next key is captured by the engine, Escape cancels, "X bound to Y"), Delete clears. The Confirm/Reset popups (including the 15 second keep-display-settings countdown) are announced and operated with Up/Down/Enter, Escape = the last (No) button. Gaps: the in-game multiplayer game parameters, and the Switch UI Layout popup. Note: the engine only records a rebinding key if the input handler returns false for it, and key-state polling needs `civctl key <Key> -Hold 200`.

Text fields (Map/Game Random Seed in Advanced Setup, LAN player name and webhook URL in Options): `Accessibility/KeyNavEditBox.lua`. Focus reads "label, edit, value|blank, Enter to edit"; Enter starts editing ("editing label"), typed characters / deletions are echoed, Enter commits ("label set to value"), Escape restores the old text ("Cancelled, ...") and stays on the screen. Engine facts it works around: while an EditBox has focus the context's input handler gets no key events at all; Enter fires the commit callback; Escape reverts the text, fires the commit callback, and its KeyUp still reaches the context (so the helper swallows the KeyUp of the key that ended the edit); the HasFocus callback receives the control, not a boolean; characters rejected by `SetNumberInput(true)` produce no callback, so "invalid input" can't be announced. Reuse: see the header of that file.
