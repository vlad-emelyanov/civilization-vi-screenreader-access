-- luacheck config for the mod. Run through util/lint.py (it strips Civ's `x:number` annotations first).
std = "lua51"
max_line_length = false
-- globals defined at the top of a file may be used within that file (Civ screens define OnInput etc.)
allow_defined_top = true
unused_args = false
self = false
-- noise for this code base: unused locals/values/globals, shadowing, whitespace
ignore = { "21[1-5]", "231", "232", "233", "311", "312", "313", "314", "43[1-3]", "131", "61[1-4]" }

-- Engine globals (read-only)
read_globals = {
	"ActivityTypes", "Automation", "Benchmark", "BoostSources", "Calendar", "Challenges", "ChatTargetTypes",
	"CityCommandResults", "CityCommandTypes", "CityManager", "CityOperationResults", "CityOperationTypes",
	"Cities", "CivilizationLevelTypes", "CloudNotifyTypes", "CombatManager", "CombatResultParameters",
	"CombatTypes", "CombatVisType", "ComponentType", "Controls", "ContextPtr", "CursorTypes", "DB", "DealManager",
	"DefenseTypes", "DiplomacyManager", "DiplomacyMoodTypes", "DiplomacyResponseTypes", "DiplomaticStates",
	"DirectionTypes", "EffectsManager", "EndTurnBlockingTypes", "Events", "FireWireTypes", "FiraxisLive",
	"Game", "GameCapabilities", "GameClimate", "GameConfiguration", "GameInfo", "GameStateTypes",
	"GlobalParameters", "IconManager", "Input", "InstanceManager", "InterfaceModeTypes", "KeyEvents", "Keys",
	"KickReason", "LuaEvents", "Locale", "MPLobbyTypes", "Map", "MapConfiguration", "MapFeatureManager",
	"MapLayers", "Matchmaking", "MilitaryFormationTypes", "Modding", "MomentDataTypes", "Mouse", "MouseEvents",
	"Network", "NetworkPlatform", "NotificationManager", "NotificationTypes", "Options", "PlayerComponentTypes",
	"PlayerConfigurations", "PlayerManager", "PlayerOperations", "PlayerTypes", "Players", "PlayersVisibility",
	"PopupDialog", "PopupPriority", "ReportingStatusTypes", "RevealedState", "RiverManager", "SaveFileTypes",
	"SaveLocationOptions", "SaveLocations", "SaveTypes", "ServerType", "SlotStatus", "TTManager", "TeamTypes", "Teams",
	"TerrainManager", "TouchManager", "UI", "UILens", "UIManager", "UITutorialManager", "UnitCommandResults",
	"UnitCommandTypes", "UnitManager", "UnitOperationResults", "UnitOperationTypes", "Units", "UserConfiguration",
	-- provided by game files pulled in with include(): ToolTipHelper_PlayerYields, Civ6Common
	"Round", "Clamp", "GetCityData", "DATA_DOMINANT_RELIGION", "YIELD_STATE", "GetScienceTooltip", "GetCultureTooltip", "GetFaithTooltip", "GetGoldTooltip", "MoveUnitToPlot",
	"View", "WarTypes", "WorldBuilder", "YieldTypes", "include", "ToolTipHelper", "Cities", "Locale",
}

-- Globals the mod defines in Assets/UI/Accessibility/*.lua (shared via include()). Keep in sync.
globals = {
	"CleanTextForSpeech", "DealSpeech_AvailableText", "DealSpeech_ChangeText", "DealSpeech_DealItemText", "DealSpeech_Intro",
	"DealSpeech_ItemText", "DealSpeech_Summary", "GetDlcContext", "GetLocalizedDirectionString", "HideIfVisible", "KeyNavActivate",
	"KeyNavAfterPageChange", "KeyNavAnnounceFocus", "KeyNavAnnouncePage", "KeyNavEditBox_Begin",
	"KeyNavEditBox_Cancel", "KeyNavEditBox_Describe", "KeyNavEditBox_HandleInput", "KeyNavEditBox_IsEditing",
	"KeyNavEditBox_Update", "KeyNavErrorHandler", "KeyNavItems", "KeyNavKeyHandler", "KeyNavLabel",
	"KeyNavLeftClick", "KeyNavList_Create", "KeyNavList_ShortList", "KeyNavMoveFocus", "KeyNavMoveMouse",
	"KeyNavMoveMouseToScreen", "KeyNavPageText", "KeyNavScrollIntoView", "KeyNavSetup_BuildParameterItems",
	"KeyNavSetup_ButtonItem", "KeyNavSetup_GetDriver", "KeyNavSetup_GetOptions", "KeyNavSetup_GetValueByOffset",
	"KeyNavSetup_IsUsable", "KeyNavSetup_LeaderItem", "KeyNavSetup_MapItem", "KeyNavSetup_NewController",
	"KeyNavSetup_OpenPicker", "KeyNavSetup_ParameterItem", "KeyNavSetup_PulldownItem", "KeyNavSetup_SectionPrefix",
	"KeyNavSetup_SortByPosition", "KeyNavToggleDontShow", "KeyNav_Tick", "OutputMessageToScreenReader",
	"PlacementScan_Blockers", "PlacementScan_Cannot", "PlacementScan_Explain", "PlacementScan_Scan",
	"PlotDescription_GetCivName", "PlotDescription_GetDetailed", "PlotDescription_GetDirectionWord",
	"PlotDescription_GetRelative", "PlotDescription_GetShort", "PlotDescription_GetUnitName",
	"PlotDescription_GetVisibility", "PlotDescription_IsUnitVisible", "ReligionText_Beliefs", "ReligionText_Capital", "ReligionText_CityLine", "ReligionText_Count", "ReligionText_Followers", "ReligionText_Founder", "ReligionText_Join", "ReligionText_ToChoose", "PrintKeyMap",
	"PrintKeyboardNavigationElements", "SRListen", "SRUnlistenAll", "ReplaceDlcPopup", "SettleScan_CanFound", "SettleScan_CannotText",
	"SettleScan_CheckPlot", "SettleScan_Scan", "StringifyCity", "StringifyUnit", "TopPanelData_BuildItems",
	"TopPanelData_Summary",
	"GreatPeopleText_Actions", "GreatPeopleText_ActionsTitle", "GreatPeopleText_Afford", "GreatPeopleText_Detail",
	"GreatPeopleText_Item", "GreatPeopleText_Num", "GreatPeopleText_Opening", "GreatPeopleText_PastDetail",
	"GreatPeopleText_PastItem", "GreatPeopleText_PatronageReason",
	"PromotionText_Detail", "PromotionText_Done", "PromotionText_Item", "PromotionText_Opening",
	"PromotionText_Reason", "PromotionText_State",
	"TradeText_Detail", "TradeText_Origin", "TradeText_Route", "TradeText_SortRoutes", "TradeText_YieldList",
	"CityReport_BuildItems", "CityReport_Gather", "CityManage_Gather", "CityManage_YieldType", "CityManage_Totals",
	"CityManage_TileState", "CityManage_TileText", "CityManage_TileItems", "CityManage_DistrictText", "CityManage_DistrictItems",
	"CityManage_FocusItems", "TXT_NO_PRODUCTION", "SIZE_PRODUCTION_ICON",
	"WCText_CostList", "WCText_Letter", "WCText_Missing", "WCText_Plural", "WCText_ProposalLine", "WCText_ReviewProposal", "WCText_ReviewResolution", "WCText_ResolutionLine", "WCText_Strip", "WCText_VoteBlock", "WCText_VotesPhrase",
	"TopPanelData_Summary", "RankingsText_Ordinal", "RankingsText_Count", "RankingsText_And", "RankingsText_Join", "RankingsText_Clean",
	"RankingsText_Percent", "RankingsText_Label", "RankingsText_ScoreLine", "RankingsText_PositionOf", "RankingsText_OverviewLine",
	"RankingsText_OverviewDetail", "RankingsText_Science", "RankingsText_Culture", "RankingsText_Domination",
	"RankingsText_Religion", "RankingsText_Diplomatic", "RankingsText_Tab",
	"TradeOverviewText_Opening", "TradeOverviewText_Tab", "TradeOverviewText_Route", "TradeOverviewText_Slot", "TradeOverviewText_Detail",
	"EspionageText_Plural", "EspionageText_Header", "EspionageText_Spy", "EspionageText_City", "EspionageText_History",
	"EspionageText_EnemySpy", "EspionageText_Destination", "EspionageText_Mission", "EspionageText_Outcomes",
}
