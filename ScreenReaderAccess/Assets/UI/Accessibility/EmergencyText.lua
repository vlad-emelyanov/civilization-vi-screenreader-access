-- ===========================================================================
--	EmergencyText: one active emergency / scored competition (Gathering Storm) as a Control+Y list entry.
--	Pure wording over the entry of Game.GetEmergencyManager():GetEmergencyInfoTable( playerID ), the table the World Tracker
--	(WorldCrisisTracker.lua) and the popup (WorldCrisisPopup_SRA.lua) read. Included by TopPanelData.lua.
--
--	EmergencyText_Item( e, ctx ) -> text, detail
--	  e:   the emergency table (NameText, TargetID, HasBegun, TurnsLeft, ShortGoalDescription, TargetShortGoalDescription,
--	       GoalsTable, TargetGoalsTable, GoalDescription, ScoresTables, MemberIDs, ScoreSourcesTable, BuffsText,
--	       MemberRewardsText*, TargetRewardsText, ExtraRewards ...)
--	  ctx: { localID, hostile, noTarget, name = localized name, targetName = civ name or "", clean = f( text ), playerName = f( id ) }
-- ===========================================================================

local function Count( list:table )
	if list == nil then return 0; end
	return #list;
end

local function Turns( n:number )
	return n .. ( n == 1 and " turn" or " turns" );
end

-- goals completed and total (the game counts the same table for the progress shown in the tracker)
local function GoalCounts( e:table )
	local done:number = 0;
	local total:number = 0;
	for _, goal in ipairs( e.GoalsTable or {} ) do
		total = total + 1;
		if goal.Completed then done = done + 1; end
	end
	return done, total;
end

local function Strip( ctx:table, text )
	if text == nil then return ""; end
	local clean:string = ctx.clean( tostring( text ) );
	clean = string.gsub( clean, "[ \t\r\n\v\f]*%.[ \t\r\n\v\f]*$", "" );
	return clean;
end

local function AddAll( parts:table, ctx:table, title:string, list:table )
	if Count( list ) == 0 then return; end
	local lines:table = {};
	for _, line in ipairs( list ) do
		local text:string = Strip( ctx, line );
		if text ~= "" then table.insert( lines, text ); end
	end
	if #lines > 0 then table.insert( parts, title .. ": " .. table.concat( lines, "; " ) ); end
end

function EmergencyText_Item( e:table, ctx:table )
	local isTarget:boolean = e.TargetID == ctx.localID;
	local kind:string = ctx.hostile and "Emergency" or "Competition";
	local text:string = kind .. ": " .. Strip( ctx, ctx.name );
	if not ctx.noTarget and e.TargetID ~= nil and e.TargetID >= 0 then
		text = text .. ", against " .. ( isTarget and "you" or ctx.targetName );
	end
	local ended:boolean = e.TurnsLeft ~= nil and e.TurnsLeft < 0;
	if ended then
		text = text .. ", ended";
	elseif isTarget then
		text = text .. ", you are the target";
	elseif e.HasBegun then
		text = text .. ", joined";
	else
		text = text .. ", not joined yet, accept or reject it";
	end
	if not ended and e.TurnsLeft ~= nil then
		text = text .. ", " .. ( e.TurnsLeft == 0 and "ends this turn" or ( Turns( e.TurnsLeft ) .. " left" ) );
	end

	-- Space starts with the goal, progress and score (the line above is not repeated)
	local first:table = {};
	local done, total = GoalCounts( e );
	if e.HasBegun and not ended then
		local short:string = Strip( ctx, isTarget and e.TargetShortGoalDescription or e.ShortGoalDescription );
		if short ~= "" then table.insert( first, "Goal: " .. short ); end
		if total > 0 then
			table.insert( first, isTarget and ( "The members completed " .. done .. " of " .. total ) or ( "Progress " .. done .. " of " .. total ) );
		end
	end
	local scores:table = e.ScoresTables;
	if e.HasBegun and not ended and scores ~= nil and scores[ ctx.localID ] ~= nil and not isTarget then
		table.insert( first, "Your score " .. tostring( scores[ ctx.localID ] ) );
	end

	-- Space: everything the popup says, in order
	local parts:table = first;
	local about:string = Strip( ctx, e.ShortDescriptionText );
	if about ~= "" then table.insert( parts, about ); end
	local goal:string = Strip( ctx, e.GoalDescription );
	if goal ~= "" and not ended then table.insert( parts, "Goal in full: " .. goal ); end
	if e.HasBegun then
		local goals:table = {};
		local source:table = isTarget and e.TargetGoalsTable or e.GoalsTable;
		for _, entry in ipairs( source or {} ) do
			local name:string = Strip( ctx, entry.Name );
			if name ~= "" then table.insert( goals, name .. ( entry.Completed and " (done)" or " (open)" ) ); end
		end
		if #goals > 0 then table.insert( parts, "Goals: " .. table.concat( goals, "; " ) ); end
	end
	if not isTarget then AddAll( parts, ctx, "How to score", e.ScoreSourcesTable ); end
	AddAll( parts, ctx, "Temporary effects", e.BuffsText );
	local members:table = {};
	for _, id in ipairs( e.MemberIDs or {} ) do
		if id ~= nil and id >= 0 then
			local score = scores ~= nil and scores[ id ] or nil;
			table.insert( members, ( id == ctx.localID and "you" or ctx.playerName( id ) ) .. ( score ~= nil and ( " " .. tostring( score ) ) or "" ) );
		end
	end
	if #members > 0 then table.insert( parts, "Members: " .. table.concat( members, "; " ) ); end
	AddAll( parts, ctx, "Rewards for the best", e.MemberRewardsTextFirst );
	AddAll( parts, ctx, ctx.hostile and "Rewards for members" or "Rewards for second place", e.MemberRewardsTextTop );
	AddAll( parts, ctx, "Rewards for the rest", e.MemberRewardsTextBottom );
	AddAll( parts, ctx, "Extra rewards", e.MemberRewardsTextExtra );
	if ctx.hostile then AddAll( parts, ctx, "Rewards for the target", e.TargetRewardsText ); end
	local extra:string = Strip( ctx, e.ExtraRewards );
	if extra ~= "" then table.insert( parts, extra ); end
	if #parts == 0 then return text, text; end
	return text, table.concat( parts, ". " );
end
