-- Add new input actions:
INSERT INTO "InputActions" VALUES ('KeyNavMoveCellLeft','Move cell left','Move 1 cell left of current location','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavMoveCellRight','Move cell right','Move 1 cell right of current location','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavMoveCellUp','Move cell up','Move 1 cell up of current location','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavMoveCellDown','Move cell down','Move 1 cell down of current location','GLOBAL','World','PC');

-- Add default hotkeys for these actions:
-- @see "InputKeyData" table to find all keys.
-- KEY_SHIFT
-- KEY_CONTROL
-- KEY_ALT
-- KEY_CAPSLOCK
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavMoveCellLeft',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_LEFT');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavMoveCellRight',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_RIGHT');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavMoveCellUp',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_UP');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavMoveCellDown',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_DOWN');

-- Five-tile cursor jumps
INSERT INTO "InputActions" VALUES ('KeyNavJumpCellLeft','Jump cells left','Move the map cursor 5 cells left','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavJumpCellRight','Jump cells right','Move the map cursor 5 cells right','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavJumpCellUp','Jump cells up','Move the map cursor 5 cells up','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavJumpCellDown','Jump cells down','Move the map cursor 5 cells down','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavJumpCellLeft',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_LEFT');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavJumpCellRight',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_RIGHT');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavJumpCellUp',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_UP');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavJumpCellDown',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_DOWN');

-- In-game screen reader hotkeys (handled by UI/Additions/InGameAccess.lua)
INSERT INTO "InputActions" VALUES ('KeyNavPlotDetails','Plot details','Read a detailed description of the map cursor plot','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavCursorToSelection','Cursor to selection','Move the map cursor to the selected unit or city and read it','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavWhatsNext','What is next','Read what the Next Action key will do','GLOBAL','World','PC');

INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavPlotDetails',0,'KBMouse','LOC_OPTIONS_KEY_I');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavCursorToSelection',0,'KBMouse','LOC_OPTIONS_KEY_PERIOD');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavWhatsNext',0,'KBMouse','LOC_OPTIONS_KEY_N');

INSERT INTO "InputActions" VALUES ('KeyNavUnitActions','Unit actions menu','Open a keyboard menu of everything the selected unit can do','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavUnitActions',0,'KBMouse','LOC_OPTIONS_KEY_TAB');

INSERT INTO "InputActions" VALUES ('KeyNavSelectAtCursor','Select at cursor','Select your unit or city on the map cursor plot (again: the next one there)','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavSelectAtCursor',0,'KBMouse','LOC_OPTIONS_KEY_K');
INSERT INTO "InputActions" VALUES ('KeyNavCycleAllUnits','Cycle all units','Select the next of all your units, also fortified and automated ones','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavCycleAllUnits',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_K');
INSERT INTO "InputActions" VALUES ('KeyNavScanUnits','Scan for units','Move the map cursor to the nearest foreign unit in view, hostile ones first; again: the next one','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavScanUnits',0,'KBMouse','LOC_OPTIONS_KEY_X');
INSERT INTO "InputActions" VALUES ('KeyNavDiplomacy','Diplomacy','List the civilizations you have met and open the diplomacy screen with one','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavDiplomacy',0,'KBMouse','LOC_OPTIONS_KEY_V');
INSERT INTO "InputActions" VALUES ('KeyNavStanding','Standing','Say where you stand among the civilizations you have met: score, military, science, culture, gold, faith','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavStanding',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_R');

INSERT INTO "InputActions" VALUES ('KeyNavTopPanel','Top panel','Open a keyboard list of the top panel: yields, resources, research, civic, turn, era','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavTopPanel',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_Y');
INSERT INTO "InputActions" VALUES ('KeyNavNotifications','Notifications','Open a keyboard list of the active notifications','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavNotifications',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_N');
INSERT INTO "InputActions" VALUES ('KeyNavMessages','Messages','Open a keyboard list of what the mod announced on its own: the history of events','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavMessages',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_M');
INSERT INTO "InputActions" VALUES ('KeyNavYields','Read yields','Read gold, science, culture and faith in one sentence','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavYields',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_G');
INSERT INTO "InputActions" VALUES ('KeyNavCityReport','City report','Open a keyboard list about the selected city (or your city on the map cursor): yields, growth, amenities, loyalty, defense, production, districts, citizens, religion','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavCityReport',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_I');
INSERT INTO "InputActions" VALUES ('KeyNavReports','Reports screen','Open or close the Reports screen (yields, resources, city status, gossip)','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavReports',0,'KBMouse','LOC_OPTIONS_KEY_F8');
INSERT INTO "InputActions" VALUES ('KeyNavGreatWorks','Great Works screen','Open or close the Great Works screen (works, slots, themes)','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavGreatWorks',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_W');
INSERT INTO "InputActions" VALUES ('KeyNavPlaces','Places','Open a keyboard list of places: your cities, your units (also automated ones), points of interest, notification locations, foreign cities; M sends a unit there','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavPlaces',0,'KBMouse','LOC_OPTIONS_KEY_J');
INSERT INTO "InputActions" VALUES ('KeyNavAreaOverview','Area overview','Open a keyboard list that describes the area around the map cursor, its continent and each direction: terrain, coast, resources, cities, what is unexplored','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavAreaOverview',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_J');
INSERT INTO "InputActions" VALUES ('KeyNavSendHere','Send a unit to the cursor tile','Open the list of your units that can go to the map cursor tile, fastest first; Enter sends the chosen one','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavSendHere',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_M');

INSERT INTO "InputActions" VALUES ('KeyNavEraProgress','Era progress','Open or close the Era Progress panel (Rise and Fall, Gathering Storm) as a keyboard list; same as the numpad Divide','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavEraProgress',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_E');
INSERT INTO "InputActions" VALUES ('KeyNavHelp','Accessibility help','Open a read-only list of the accessibility shortcuts of this mod and what they do','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavHelp',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_H');
