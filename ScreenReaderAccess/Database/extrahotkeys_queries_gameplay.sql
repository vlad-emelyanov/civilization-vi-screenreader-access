-- Shamelessly copied from ExtraHotkeys mod
-- Update information about input actions for unit operations/commands:
UPDATE "UnitOperations" SET "HotkeyId" = "ExtraHotkeysPillageOrRepair" WHERE "HotkeyId" IS NULL AND ("OperationType" = "UNITOPERATION_PILLAGE" OR "OperationType" = "UNITOPERATION_COASTAL_RAID" OR "OperationType" = "UNITOPERATION_REPAIR");
UPDATE "UnitOperations" SET "HotkeyId" = "ExtraHotkeysPillageRoadOrRepair" WHERE "HotkeyId" IS NULL AND ("OperationType" = "UNITOPERATION_PILLAGE_ROUTE" OR "OperationType" = "UNITOPERATION_REPAIR_ROUTE" OR "OperationType" = "UNITOPERATION_MAKE_TRADE_ROUTE");
UPDATE "UnitOperations" SET "HotkeyId" = "ExtraHotkeysTeleportToCity" WHERE "HotkeyId" IS NULL AND ("OperationType" = "UNITOPERATION_TELEPORT_TO_CITY" OR "OperationType" = "UNITOPERATION_REBASE");
-- Use the existing in-game "FortifyUntilHeal" hotkey ("H") to heal ships too.
UPDATE "UnitOperations" SET "HotkeyId" = "FortifyUntilHeal" WHERE "HotkeyId" IS NULL AND "OperationType" = "UNITOPERATION_REST_REPAIR";

UPDATE "UnitCommands" SET "HotkeyId" = "ExtraHotkeysUpgrade" WHERE "HotkeyId" IS NULL AND ("CommandType" = "UNITCOMMAND_UPGRADE" OR "CommandType" = "UNITCOMMAND_ACTIVATE_GREAT_PERSON");
UPDATE "UnitCommands" SET "HotkeyId" = "ExtraHotkeysPromote" WHERE "HotkeyId" IS NULL AND "CommandType" = "UNITCOMMAND_PROMOTE";
UPDATE "UnitCommands" SET "HotkeyId" = "ExtraHotkeysFormCorps" WHERE "HotkeyId" IS NULL AND "CommandType" = "UNITCOMMAND_FORM_CORPS";
UPDATE "UnitCommands" SET "HotkeyId" = "ExtraHotkeysFormArmy" WHERE "HotkeyId" IS NULL AND "CommandType" = "UNITCOMMAND_FORM_ARMY";
UPDATE "UnitCommands" SET "HotkeyId" = "ExtraHotkeysEnterFormation" WHERE "HotkeyId" IS NULL AND ("CommandType" = "UNITCOMMAND_ENTER_FORMATION" OR "CommandType" = "UNITCOMMAND_EXIT_FORMATION");
UPDATE "UnitCommands" SET "HotkeyId" = "ExtraHotkeysUnitCancel" WHERE "HotkeyId" IS NULL AND "CommandType" = "UNITCOMMAND_CANCEL";
UPDATE "UnitCommands" SET "HotkeyId" = "ExtraHotkeysUnitWake" WHERE "HotkeyId" IS NULL AND "CommandType" = "UNITCOMMAND_WAKE";
