-- Shamelessly copied from ExtraHotkeys mod
-- Add new input actions:
INSERT INTO "InputActions" VALUES ('ExtraHotkeysPillageOrRepair','LOC_UNITOPERATION_PILLAGE_DESCRIPTION','Pillage/Coastal Raid/Repair','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysPillageRoadOrRepair','LOC_UNITOPERATION_PILLAGE_ROUTE_DESCRIPTION','Pillage Road/Repair Road/Make Trade Route','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysEnterFormation','Create/Exit Escort','LOC_UNITCOMMAND_EXIT_FORMATION_DESCRIPTION','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysUpgrade','LOC_UNITOPERATION_UPGRADE_DESCRIPTION','Upgrade Unit/Activate Great Person','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysPromote','LOC_UNITCOMMAND_PROMOTE_DESCRIPTION','LOC_UNITCOMMAND_PROMOTE_DESCRIPTION','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysFormCorps','LOC_UNITCOMMAND_FORM_CORPS_DESCRIPTION','LOC_UNITCOMMAND_FORM_CORPS_DESCRIPTION','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysFormArmy','LOC_UNITCOMMAND_FORM_ARMY_DESCRIPTION','LOC_UNITCOMMAND_FORM_ARMY_DESCRIPTION','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysUnitCancel','LOC_UNITCOMMAND_CANCEL_DESCRIPTION','LOC_UNITCOMMAND_CANCEL_DESCRIPTION','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysUnitWake','LOC_UNITCOMMAND_WAKE_DESCRIPTION','LOC_UNITCOMMAND_WAKE_DESCRIPTION','UNIT','World','PC');
INSERT INTO "InputActions" VALUES ('ExtraHotkeysTeleportToCity','LOC_UNITOPERATION_TELEPORT_TO_CITY_DESCRIPTION','LOC_UNITOPERATION_REBASE_DESCRIPTION','UNIT','World','PC');


-- Add default hotkeys for these actions:
-- @see "InputKeyData" table to find all keys.
-- KEY_SHIFT
-- KEY_CONTROL
-- KEY_ALT
-- KEY_CAPSLOCK
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysPillageOrRepair',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_P');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysPillageRoadOrRepair',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_P');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysUpgrade',0,'KBMouse','LOC_OPTIONS_KEY_U');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysPromote',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_U');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysFormCorps',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_F');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysFormArmy',0,'KBMouse','LOC_OPTIONS_KEY_CONTROL+LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_F');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysEnterFormation',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_E');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysUnitCancel',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_C');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysUnitWake',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_W');
INSERT INTO "InputActionDefaultGestures" VALUES ('ExtraHotkeysTeleportToCity',0,'KBMouse','LOC_OPTIONS_KEY_SHIFT+LOC_OPTIONS_KEY_R');
