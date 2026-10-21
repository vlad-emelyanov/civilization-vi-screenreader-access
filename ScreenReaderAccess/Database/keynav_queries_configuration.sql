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

-- In-game screen reader hotkeys (handled by UI/Additions/InGameAccess.lua)
INSERT INTO "InputActions" VALUES ('KeyNavPlotDetails','Plot details','Read a detailed description of the map cursor plot','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavCursorToSelection','Cursor to selection','Move the map cursor to the selected unit or city and read it','GLOBAL','World','PC');
INSERT INTO "InputActions" VALUES ('KeyNavWhatsNext','What is next','Read what the Next Action key will do','GLOBAL','World','PC');

INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavPlotDetails',0,'KBMouse','LOC_OPTIONS_KEY_I');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavCursorToSelection',0,'KBMouse','LOC_OPTIONS_KEY_J');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavWhatsNext',0,'KBMouse','LOC_OPTIONS_KEY_N');

INSERT INTO "InputActions" VALUES ('KeyNavUnitActions','Unit actions menu','Open a keyboard menu of everything the selected unit can do','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavUnitActions',0,'KBMouse','LOC_OPTIONS_KEY_TAB');

INSERT INTO "InputActions" VALUES ('KeyNavSelectAtCursor','Select at cursor','Select your unit or city on the map cursor plot (again: the next one there)','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavSelectAtCursor',0,'KBMouse','LOC_OPTIONS_KEY_K');
INSERT INTO "InputActions" VALUES ('KeyNavCycleAllUnits','Cycle all units','Select the next of all your units, also fortified and automated ones','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavCycleAllUnits',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_K');
INSERT INTO "InputActions" VALUES ('KeyNavScanUnits','Scan for units','Move the map cursor to the nearest foreign unit in view, hostile ones first; again: the next one','GLOBAL','World','PC');
INSERT INTO "InputActionDefaultGestures" VALUES ('KeyNavScanUnits',0,'KBMouse','LOC_OPTIONS_KEY_X');
