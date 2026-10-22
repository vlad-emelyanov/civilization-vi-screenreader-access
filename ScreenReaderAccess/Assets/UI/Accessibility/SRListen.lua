-- SRListen: event listeners that can be removed again.
--
-- A hot reload (or leaving a game) re-runs a context's script without telling the old instance's listeners to go away,
-- so every Events.X.Add / LuaEvents.X.Add made by the old copy keeps firing into stale state. Register listeners with
-- SRListen and drop them all in the context's shutdown handler:
--
--	include( "SRListen" );
--	SRListen( Events.UnitSelectionChanged, OnUnitSelectionChanged );
--	SRListen( LuaEvents.SomeEvent, OnSomeEvent );
--	ContextPtr:SetShutdown( function() SRUnlistenAll(); end );
--------------------------------------------------------------

local m_listeners:table = {};

-- event: Events.X or LuaEvents.X (anything with .Add / .Remove taking the function)
function SRListen( event:table, fn )
	event.Add( fn );
	table.insert( m_listeners, { event = event, fn = fn } );
end

-- Removes every listener registered with SRListen in this context (each one guarded: a failing Remove must not stop the rest).
function SRUnlistenAll()
	for i = #m_listeners, 1, -1 do
		local entry:table = m_listeners[ i ];
		local ok:boolean, err = pcall( entry.event.Remove, entry.fn );
		if not ok then print( "SRUnlistenAll: " .. tostring( err ) ); end
	end
	m_listeners = {};
end
