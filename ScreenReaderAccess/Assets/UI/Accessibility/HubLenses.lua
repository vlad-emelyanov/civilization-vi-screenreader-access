-- ===========================================================================
--	HubLenses: the lenses list (a ring list of the controller, see HubPad.lua and docs/controller-plan.md).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by UI/Additions/InGameAccess.lua.
--	One item per lens action that LensText knows (the number keys): "Appeal lens, off". Enter toggles the lens exactly like
--	its number key (the same input action is triggered, so MinimapPanel switches the lens and the hub's registered action
--	LensText_OnKey speaks the result); the list stays open, the next Up/Down shows the new state. Space: the legend.
--	No input action opens this list: it is reachable through the ring (HubPad) only.
-- ===========================================================================
include( "LensText" );

HubLenses = {};

local m_list:table;

-- Items in a stable order (by spoken name; pairs order is not defined).
local function BuildItems()
	local actions:table = {};
	for action, lens in pairs( LensText_Actions ) do
		table.insert( actions, { action = action, lens = lens } );
	end
	table.sort( actions, function( a, b ) return a.lens.name < b.lens.name; end );
	local active = LensText_ActiveLens();
	local items:table = {};
	for _, entry in ipairs( actions ) do
		local legend:string = LensText_Legend( entry.lens.id ) or "";
		table.insert( items, {
			key		= entry.action,
			text	= entry.lens.name .. " lens, " .. ( active == entry.lens.id and "on" or "off" ),
			detail	= legend ~= "" and legend or "No legend",
			action	= entry.action,
		} );
	end
	return items;
end
HubLenses.BuildItems = BuildItems;

-- Triggers the lens's input action as the key would (replaceable in tests): Events.InputActionTriggered.Call does nothing in
-- the engine (verified), so our MinimapPanel copy (UI/Replacements/MinimapPanel_SRA.lua) answers LuaEvents.SRA_ToggleLens.
function HubLenses.Fire( actionId:number )
	LuaEvents.SRA_ToggleLens( actionId );
end

local function Toggle( item:table )
	local id = Input.GetActionId( item.action );
	local ok:boolean = id ~= nil and pcall( HubLenses.Fire, id );
	if not ok then
		OutputMessageToScreenReader( item.text:gsub( ", o[nf]+$", "" ) .. " cannot be switched from the list. Use its number key" );
	end
end

HubLenses.Toggle = Toggle;		-- (tests)

m_list = KeyNavList_Create{
	build		= BuildItems,
	isActive	= function() return HubCore.IsModeOpen( "lenses" ); end,
	onActivate	= Toggle,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

function HubLenses.Open()
	if not HubTargets.CanOpenMode() then return; end
	HubCore.OpenMode( "lenses", m_list, "Lenses" );
end
