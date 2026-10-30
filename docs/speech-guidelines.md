# Speech guidelines: what a blind player hears

The rules for every spoken line the mod produces: list items, announcements, hints, refusals, confirmations. They were learned from play-tests (the agents' and the user's) and are the standard for new code and for reviews. `docs/keynav-guide.md` covers the mechanics (input handling, focus tracking, `SRKey` tokens); this file covers the words.

When a rule here and a habit in old code disagree, the rule wins; fix the old code when you touch it.

## 1. Lead with what differs

The first words of an item are the ones that tell it apart from its neighbours. A screen reader user decides after two or three words whether to listen on or press Down.

- **Content before category.** "Conscription, military slot 1", not "Military Policies slot 1: Conscription". "Gypsum, luxury, 1 available", not "Luxury: Gypsum". "Friend, button", not "Button: Friend".
- **Words every item shares go to the opening line, once.** The counterspy list opens with "Counterspy missions in Rome: 7 missions" and its items read "Campus, 6 turns, 1 of 7", not "Counterspy, Campus, ...". The send list says "Send a unit to Zanzibar" once; its items are "Builder, 3 turns, stops next to it".
- **Never repeat the title in the item.** "Building expenses: Minus 4 gold in total", not "Building expenses: Building expenses: minus 4 gold".
- **On a change inside one item, say only what changed.** Left/Right on a World Congress resolution says "Option B: ...", not the resolution name again; the name comes with Up/Down to another resolution.
- **Order inside an item:** the distinguishing part, then where, then the details, then status and numbers, then the position ("n of m") last. Builder tiles: "Lumber Mill plus 2 production, 2 tiles south, Plains Rainforest, 2 turns, worked, 1 of 5". Climate events: "Major Drought, Kayseri, turn 224". Resources: "Pearls (luxury), Coast".
- **Section heads in a long list are spoken once**, on the first item of the section (KeyNavList `section`), and after the item when the player scrolls into it: "Settler, 5 turns, 80 production, in Units, 12 items, 7 of 40" (an item that already starts with its group name stays whole: "Builder, 5 tiles east, 3 items, 2 of 9"). A scroller must not miss the first item of a group. When the player asked for the group (PageUp / PageDown, Tab to another section, opening the list) the group name comes first: "Units, 12: Warrior, ...". Never a prefix on every item.
- **Two items must never read the same.** When they would, add what tells them apart (the position from the nearest city, then a counter): "Farm plus 1 food, 2 tiles north-west, ..., 2 tiles north of Rome".
- **Sort for the decision.** What the player can act on comes first: attack targets reachable this turn before far ones, buildable items before "already built" rows, real unit actions before unavailable ones, destructive actions last.

## 2. Short items, details on demand

- An item is a few words a player can take in while scrolling. Everything else goes to the detail (Space on the keyboard, Y on the pad). Great people: "Great General Douglas MacArthur, 73 of 480 points, 6305 gold"; the rate, the leader, the faith price and the ability are in the detail. Aim for about 15 words; 40 is far too long.
- **The effect before the flavour.** Speak what a thing does; flavour quotes go to the detail or nowhere. The Climate Accords item reads its scoring rules, not "We all share this planet...".
- **Details stay relevant.** A repair item's detail says what is repaired and the cost, not the district's full adjacency text.
- **Advertise the detail where it helps,** without noise: on the pad, a list that opens on an item with a detail says ", Y for details" once per open (`SRPadHint`).

## 3. Name the subject

A line must say what it is about, without the player opening anything.

- Notifications name their city or unit: "Choose Production: Cumae", "Unit available for promotion: Musketman". When the game's summary is a short full sentence, the item is that sentence: "Lugdunum needs more Amenities to keep it productive".
- Use the precise verb: "Edirne captured from Ottomans", not "Edirne founded"; a great person's ability says "Retire Hannibal: <effect>" and the result "Hannibal retired: <effect>", not a generic "activated".
- When something is attacked, name what is hit: "Moving to attack Edirne", not the unit standing in it.
- Say the current state when a choice replaces it: the production panel opens with "Currently building Coal Power Plant, 3 turns" and Enter on another item says "..., replaces Coal Power Plant".
- Name the parties: war and peace notifications say who and with whom; a diplomacy scene says why it opened (a warning, a deal, a denouncement).

## 4. Never silent, never vague

Every key the player presses gets an answer.

- **Nothing to do is an answer:** "No units need orders", "No options to switch here", "No places this ship can reach", "No further details".
- **Refusals say why:** "Cannot ranged attack: no enemy it can target in range", "Cannot repair Campus: an enemy unit stands on it", "Alert, unavailable: not available for this unit now". Use the game's reason when it has one; a generic reason beats none.
- **Results are spoken:** "Delete cancelled", "Bought Trader, 120 gold left", "Tribal village: 30 faith", "Diplomacy closed", "Menu closed".
- **A filtered list says it is filtered:** "Your cities, 4 items, 3 out of this ship's reach left out"; a category emptied by the filter is named in the opening line.

## 5. Say it once

- One event, one line. The turn line is spoken once per turn (not again after each advisor popup), a count once ("Casus Belli, 5 options", not "5 options, 5 options"), a merged notification summary once.
- Batch bursts: several camps removed by one new border are one line with the count and the total gold.
- Don't re-announce on refresh: a list rebuilt at key time keeps quiet unless the focused item changed.
- Hover speech is muted while the mod moves the mouse or a menu opens (the in-game menu says "In game menu, <first item>", not a stale hovered item).

## 6. Clean text

- No markup reaches speech: `[ICON_*]`, `[SIZE_n]`, `[COLOR...]`, `[NEWLINE]` are removed or turned into sentence breaks (`CleanTextForSpeech`). Popup buttons too: "Denounce", not "[SIZE_16]Denounce".
- No raw `LOC_` keys: run names through `Locale.Lookup`; when the text is still a key (a tuner-made city), fall back to a readable form ("Ulundi") or leave the part out.
- No doubled punctuation or words: no "..", "., ", "Atomic Era era", "Plains, Plains Floodplains". Strip a trailing period from a game text before joining it into a list ("Too many units here, Insufficient resources"). Strip stray periods from game labels ("Establish Resident Embassy", not "Establish Resident Embassy.").
- Capitalise a line's first word ("Military slot 1, choose a policy").
- Never use control characters as in-text markers; the speech cleaner treats them as its own (a district hint broke this way).

## 7. Tell the truth

- **Numbers say what they are.** "Food produced 14, food surplus 0" where the city report says 0: gross and net are both labelled. Combat previews are estimates: "deals about 33 damage".
- **Distances and places must be right.** "Near Rome" only within about 3 tiles; farther away say "9 tiles east of Rome".
- **Do not reveal what a sighted player cannot see.** Lists use revealed plots only; unexplored places stay listed by distance without path finding, so reachability does not leak the map.
- **Do not offer what cannot work.** The ship's places list leaves out landlocked places; the unit menu leaves out "not possible on this tile" entries and Transfer for non-traders.
- **Use the game's own data and decisions** (its target lists, its reasons, its effect texts), not a guess that can disagree with what happens.

## 8. Safe keys

- **Focus where Enter does the expected thing.** A screen opens on the current choice (current production, or the recommended item it announces), never on a neighbour of what it announced. A mode switch (Tab) keeps the focused item when it exists in the new mode.
- **Irreversible actions ask first and sit last:** Retire, Delete, removing an improvement: "... cannot be undone. Enter again to confirm". Escape on a confirmation says "Cancelled" (or "Delete cancelled") and nothing happens.
- **No input lands on a screen that is going away.** After Goodbye in diplomacy, Enter does nothing until the screen closes (a second Enter once declared friendship).
- **Detail keys only read.** Space/Y never activates (Y on "Save Game" opened the save screen).
- **A key that would act on a stale item re-reads it first** (KeyNavList focus-lost-safe: when focus moved, the next Enter only names the new item).

## 9. Key hints

- Every key named in speech goes through `SRKey( keyboard, button )`, so the pad player hears the button and the keyboard player the key (`docs/keynav-guide.md`, "Key names in spoken text").
- **Check the hint against the context where it is spoken.** The same key can mean different things on the map, in a list and in a target mode (pad X selects on the map but browses in a target mode; the first hints said "X to browse" where X did not browse).
- **Pad-only and keyboard-only hints:** `SRPadHint` for buttons with no keyboard equivalent ("Y for details"), `SRKbHint` for key names that are noise on the pad (", key D" in the unit menu, where A runs the entry).
- **A hint with no pad route names the route:** "D-pad right, Found City, to found the city here".
- **Name the way out:** "Close the screen first, B closes it", not only "Close the screen first".
- Every shortcut, including keys inside lists and screens, has a line in `HelpText.lua` (Control+H).

## 10. Openings

- A list or screen opens with its title, the count, and the focused item: "Places. Your cities, 1 of 4 categories, 1 item. Rome, capital, 3 tiles west, 1 of 1".
- The title uses `nointerrupt` so it is not cut by the first item; the first item follows without a pause.
- Say the context the player needs before choosing: the current production, the filter in effect, the city a list is about.

## Checking a change against these rules

- Walk 5-8 items of every list you changed with Down and read them aloud in your head: does each start with what differs, and are any two the same?
- `python util/speechaudit.py <Lua.log copy or test/regress/*.recorded.txt>` flags lists whose items share their first phrase, repeat the title, or bury the difference late.
- Play-test agents walk every list they open and report wording problems with exact speech; reviewers check new speech against this file.
