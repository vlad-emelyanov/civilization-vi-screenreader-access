-- ===========================================================================
--	HubScreens: the screens list (a ring list of the controller, see HubPad.lua and docs/controller-plan.md).
--	Part of the InGameAccess hub (see docs/features.md, Architecture): included by UI/Additions/InGameAccess.lua.
--	One item per screen of the launch bar and the partial-screen hooks. Enter closes the list and opens the screen through
--	the function the game's own button runs: the hub fires LuaEvents.SRA_OpenScreen( name ); our LaunchBar.lua and
--	PartialScreenHooks.lua (mod-change blocks) run that function and answer LuaEvents.SRA_ScreenOpened( name, ok ) in the
--	same call. ok = false (hook hidden or not unlocked) or no answer at all: "<name> not available". The screen then
--	announces itself as it does today. Civilopedia has no hook: LuaEvents.OpenCivilopedia() is what the game uses.
--	No input action opens this list: it is reachable through the ring (HubPad) only.
-- ===========================================================================
HubScreens = {};

-- text: the spoken name (the launch bar / hook names). Order as in the design.
HubScreens.SCREENS = {
	{ name = "Tech tree" },
	{ name = "Civics tree" },
	{ name = "Government" },
	{ name = "Religion" },
	{ name = "Great People" },
	{ name = "Great Works" },
	{ name = "Governors" },
	{ name = "City-States" },
	{ name = "Espionage" },
	{ name = "Trade routes" },
	{ name = "World rankings" },
	{ name = "Climate" },
	{ name = "Era progress" },
	{ name = "Reports" },
	{ name = "Civilopedia", open = function() LuaEvents.OpenCivilopedia(); end },
};

local m_list:table;
local m_answer = nil;		-- { name, ok } of the last SRA_ScreenOpened
local m_listening:boolean = false;

local function OnScreenOpened( name, ok )
	m_answer = { name = name, ok = ( ok == true ) };
end

local function BuildItems()
	local items:table = {};
	for i, screen in ipairs( HubScreens.SCREENS ) do
		table.insert( items, { key = screen.name, text = screen.name, screen = screen } );
	end
	return items;
end
HubScreens.BuildItems = BuildItems;

-- Opens the screen of the item; false when it is not available.
function HubScreens.OpenScreen( screen:table )
	if screen.open ~= nil then
		screen.open();
		return true;
	end
	m_answer = nil;
	LuaEvents.SRA_OpenScreen( screen.name );
	return m_answer ~= nil and m_answer.name == screen.name and m_answer.ok;
end

local function Activate( item:table )
	HubCore.CloseMode( false, false );
	if not HubScreens.OpenScreen( item.screen ) then
		OutputMessageToScreenReader( item.screen.name .. " not available" );
	end
end

m_list = KeyNavList_Create{
	build		= BuildItems,
	isActive	= function() return HubCore.IsModeOpen( "screens" ); end,
	wheel		= true,		-- the pad wheel: a short list of the main interface
	onActivate	= Activate,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

function HubScreens.Open()
	if not HubTargets.CanOpenMode() then return; end
	if not m_listening then
		m_listening = true;
		HubCore.Listen( LuaEvents.SRA_ScreenOpened, OnScreenOpened );
	end
	HubCore.OpenMode( "screens", m_list, "Screens" );
end
