-- ===========================================================================
--	HubPad: the controller ring (LB / RB), see docs/controller-plan.md ("The ring").
--	Part of the InGameAccess hub (see docs/features.md, Architecture): included by UI/Additions/InGameAccess.lua.
--	RB opens the next list of the ring, LB the previous one. HubGamepad (the button dispatch) calls HubPad.RingNext() and
--	HubPad.RingPrev() by global name at key time. The entries open their list through functions that always open (the
--	keyboard shortcuts keep their toggle behaviour).
-- ===========================================================================
HubPad = {};

-- name: spoken when the module is missing; mode: the HubCore mode name the list opens with; module: the global table
-- that holds the open function; open: opens the list (always, never closes).
HubPad.RING = {
	{ name = "Notifications",	mode = "notifications",	module = "HubRegions",	open = function() HubRegions.OpenNotifications(); end },
	{ name = "Top panel",		mode = "top",			module = "HubRegions",	open = function() HubRegions.OpenTopPanel(); end },
	{ name = "Lenses",			mode = "lenses",		module = "HubLenses",	open = function() HubLenses.Open(); end },
	{ name = "Diplomacy",		mode = "civ",			module = "HubMenus",	open = function() HubMenus.OpenCivMenu(); end },
	{ name = "Screens",			mode = "screens",		module = "HubScreens",	open = function() HubScreens.Open(); end },
	{ name = "Places",			mode = "places",		module = "HubPlaces",	open = function() HubPlaces.Open( nil ); end },
};

-- Pure: the index of the ring entry to open. From a ring member: the next (step +1) or previous (-1), wrapping. From
-- nil or a list that is not in the ring: the first for +1, the last for -1.
function HubPad.RingStep( currentModeName, step:number )
	local count:number = #HubPad.RING;
	if currentModeName ~= nil then
		for i, entry in ipairs( HubPad.RING ) do
			if entry.mode == currentModeName then
				return ( i - 1 + step ) % count + 1;
			end
		end
	end
	if step < 0 then return count; end
	return 1;
end

-- Pure: is this hub list one of the ring's?
function HubPad.IsRingMode( modeName )
	if modeName == nil then return false; end
	for _, entry in ipairs( HubPad.RING ) do
		if entry.mode == modeName then return true; end
	end
	return false;
end

-- Pure: what LB / RB do while a hub list is open. "section": the list's own Tab handler moves (wrapping where it wraps).
-- "ring": the ring steps. A list without sections is a ring stop (RB opens the next list of the ring); a ring list WITH sections
-- (Places) treats its sections as sub-stops of the ring: sections until the last / first one (atEdge), then the ring continues;
-- a list with sections outside the ring (help) just moves its sections.
function HubPad.BumperAction( modeName, hasTabs:boolean, atEdge:boolean )
	if not hasTabs then return "ring"; end
	if not HubPad.IsRingMode( modeName ) then return "section"; end
	if atEdge then return "ring"; end
	return "section";
end

-- Opens the next entry in the direction. An entry that cannot open (no civilization met, no notifications: the module
-- says why) is skipped, so RB / LB never stay stuck on it; a missing module says "not available" and is skipped too.
-- (_G does not exist in the game's UI Lua: look the global up by name explicitly.)
local function ModuleExists( name:string )
	if name == "HubRegions" then return HubRegions ~= nil; end
	if name == "HubLenses" then return HubLenses ~= nil; end
	if name == "HubMenus" then return HubMenus ~= nil; end
	if name == "HubScreens" then return HubScreens ~= nil; end
	if name == "HubPlaces" then return HubPlaces ~= nil; end
	return false;
end

local function Move( step:number )
	if not HubTargets.CanOpenMode() then return; end		-- speaks the refusal
	local current = nil;
	if HubCore.m_mode ~= nil then current = HubCore.m_mode.name; end
	local index:number = HubPad.RingStep( current, step );
	for _ = 1, #HubPad.RING do
		local entry:table = HubPad.RING[ index ];
		if not ModuleExists( entry.module ) then
			OutputMessageToScreenReader( entry.name .. " not available" );
		else
			HubCore.Safe( "ring " .. entry.name, entry.open )();
			if HubCore.m_mode ~= nil and HubCore.m_mode.name == entry.mode then return; end
		end
		index = HubPad.RingStep( entry.mode, step );
	end
end

function HubPad.RingNext() Move( 1 ); end
function HubPad.RingPrev() Move( -1 ); end
