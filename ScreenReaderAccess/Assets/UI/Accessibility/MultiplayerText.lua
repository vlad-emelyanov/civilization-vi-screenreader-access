-- ===========================================================================
--	MultiplayerText: the words of the in-game multiplayer helpers (HubMultiplayer): chat lines, the turn timer, player notices.
--	Pure functions, no engine calls (tested in test/lua/test_multiplayertext.lua).
-- ===========================================================================

-- Typed chat text: only the game's markup (icons, colours, newlines) goes; "[sad]" stays. A map pin the game shows as a button
-- ("[pin:1,2]") is read as "map pin".
function MPText_CleanChat( text:string )
	text = text or "";
	text = string.gsub( text, "%[pin:%d+,%d+%]", "map pin" );
	text = string.gsub( text, "%[NEWLINE%]", " " );
	text = string.gsub( text, "%[ICON_[^%]]*%]", "" );
	text = string.gsub( text, "%[[Cc][Oo][Ll][Oo][Rr][^%]]*%]", "" );
	text = string.gsub( text, "%[ENDCOLOR%]", "" );
	text = string.gsub( text, "[ \t\r\n\v\f]+", " " );
	text = string.gsub( text, "^[ \t\r\n\v\f]+", "" );
	text = string.gsub( text, "[ \t\r\n\v\f]+$", "" );
	return text;
end

-- kind: "all", "team" or "private". "Anna: hello", "Anna, team: hello", "Anna, private: hello".
function MPText_ChatLine( name:string, kind:string, text:string )
	local tag:string = "";
	if kind == "team" then tag = ", team"; elseif kind == "private" then tag = ", private"; end
	return name .. tag .. ": " .. MPText_CleanChat( text );
end

-- "1 minute 20 seconds", "45 seconds", "2 minutes", "1 second" (whole seconds, rounded up).
function MPText_Duration( seconds:number )
	local total:number = math.ceil( ( seconds or 0 ) - 0.0001 );
	if total < 0 then total = 0; end
	local minutes:number = math.floor( total / 60 );
	local rest:number = total - minutes * 60;
	local parts:table = {};
	if minutes > 0 then table.insert( parts, minutes .. ( minutes == 1 and " minute" or " minutes" ) ); end
	if rest > 0 or minutes == 0 then table.insert( parts, rest .. ( rest == 1 and " second" or " seconds" ) ); end
	return table.concat( parts, " " );
end

-- The turn timer warnings: at 60, 30 and 10 seconds left. `warned` (a table, kept by the caller for the turn) remembers which
-- were given. Returns the threshold that is due now (the smallest one the remaining time has reached; a timer first seen at 25
-- seconds gives the 30 warning, not 60 as well) or nil. Remaining time above 60 seconds clears `warned` (a new turn).
local THRESHOLDS:table = { 10, 30, 60 };
function MPText_TimerPending( remaining:number, warned:table )
	if remaining == nil or remaining <= 0 then return nil; end
	if remaining > 60 then
		for _, t in ipairs( THRESHOLDS ) do warned[ t ] = nil; end
		return nil;
	end
	local due = nil;
	for _, t in ipairs( THRESHOLDS ) do
		if remaining <= t and not warned[ t ] then due = due or t; end
	end
	return due;
end

-- Marks the warning `due` (and the larger ones) as given.
function MPText_TimerMark( due:number, warned:table )
	for _, t in ipairs( THRESHOLDS ) do
		if t >= due then warned[ t ] = true; end
	end
end

function MPText_TimerDue( remaining:number, warned:table )
	local due = MPText_TimerPending( remaining, warned );
	if due ~= nil then MPText_TimerMark( due, warned ); end
	return due;
end

function MPText_TimerWarning( remaining:number )
	return MPText_Duration( remaining ) .. " left in the turn";
end

function MPText_TimerItem( remaining:number )
	return "Turn timer: " .. MPText_Duration( remaining ) .. " left";
end

function MPText_ChatTitle( count:number )
	return "Chat, " .. count .. ( count == 1 and " message" or " messages" );
end

-- kind: "ai" (the slot is played by the computer now), "disconnected", "kicked", "reconnected".
function MPText_PlayerNotice( name:string, kind:string )
	if kind == "ai" then return name .. " is now played by the computer"; end
	if kind == "kicked" then return name .. " was kicked"; end
	if kind == "reconnected" then return name .. " reconnected"; end
	return name .. " disconnected";
end

-- ---------------------------------------------------------------------------
-- Staging room / host notices
-- ---------------------------------------------------------------------------
-- A joiner downloads the game's mods: `remaining` of `required` still to get ("2 of 3 left").
function MPText_ModProgress( remaining:number, required:number )
	return remaining .. " of " .. required .. " left";
end

function MPText_ModDownload( name:string, remaining:number, required:number )
	return name .. " is downloading mods, " .. MPText_ModProgress( remaining, required );
end

function MPText_ModsReady( name:string )
	return name .. " has the mods";
end

-- The row / S text of a player who is still downloading.
function MPText_ModRowStatus( remaining:number, required:number )
	return "downloading mods, " .. MPText_ModProgress( remaining, required );
end

-- True when the download step changed in a way worth a line: first sight, or a different mods-remaining count.
function MPText_ModStepChanged( lastRemaining, remaining:number )
	return lastRemaining == nil or lastRemaining ~= remaining;
end

-- "Anna is now the host" / "You are now the host".
function MPText_HostNotice( name:string, isLocal:boolean )
	if isLocal then return "You are now the host"; end
	return name .. " is now the host";
end

-- A loaded save in the staging room: `seats` human seats, `empty` of them still without a player.
function MPText_LoadedGame( seats:number, empty:number )
	local text:string = "Loaded game, " .. seats .. ( seats == 1 and " human seat, " or " human seats, " );
	if empty == 0 then return text .. "all taken"; end
	return text .. empty .. " still empty";
end

-- The empty human seats by name (S key): "Waiting for the players: Trajan, Cleopatra". nil without any.
function MPText_MissingHumans( names:table )
	if names == nil or #names == 0 then return nil; end
	return "Waiting for the players: " .. table.concat( names, ", " );
end

function MPText_StillWaiting()
	return "Still waiting for the others";
end
