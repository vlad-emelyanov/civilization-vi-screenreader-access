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
