-- ===========================================================================
--	HubEvents: results of orders, combat and map event announcements.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubEvents.
-- ===========================================================================
HubEvents = {};

local m_spottedTurn			:number = -1;		-- turn m_spottedCount counts
local m_spottedCount		:number = 0;

-- ===========================================================================
--	RESULTS of the player's orders and what happens around the player's units
-- ===========================================================================
function HubEvents.OnUnitOperationStarted( ownerID:number, unitID:number, operationID:number )
	if HubSettle ~= nil and HubSettle.OnUnitOrder ~= nil then HubSettle.OnUnitOrder( ownerID, unitID ); end
	if ownerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationID ];
	if row == nil then return; end
	local text = HubMenus.OPERATION_RESULTS[ row.OperationType ];
	if type( text ) == "function" then text = text( unitID ); end
	if text ~= nil then HubCore.SayResult( text ); end
end

-- Automate Exploration starts no operation event (UnitOperationStarted); the game only adds the operation.
function HubEvents.OnUnitOperationAdded( ownerID:number, unitID:number, hOperation:number, operationIndex:number )
	if ownerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationIndex ];
	if row ~= nil and row.OperationType == "UNITOPERATION_HEAL" then
		-- Fortify Until Healed only adds the operation (no UnitOperationStarted, like Automate Exploration)
		if UI.GetElapsedTime() - HubCore.m_lastKeyTime <= 2.0 then HubCore.SayResult( HubMenus.OPERATION_RESULTS.UNITOPERATION_HEAL ); end
		return;
	end
	if row == nil or row.OperationType ~= "UNITOPERATION_AUTOMATE_EXPLORE" then return; end
	-- The game also re-adds the operation of units that are already exploring (every turn, after a load): only the
	-- order the player just gave is told. (The old "it has not moved" check after 1 s was dropped: unreliable.)
	if UI.GetElapsedTime() - HubCore.m_lastKeyTime > 2.0 then return; end
	local text:string = HubMenus.OPERATION_RESULTS.UNITOPERATION_AUTOMATE_EXPLORE;
	-- a hostile soldier within 3 tiles: the explorer may walk into it
	local unit = Players[ ownerID ] ~= nil and Players[ ownerID ]:GetUnits():FindID( unitID ) or nil;
	local caution = HubEnemies ~= nil and HubEnemies.NearestHostileText( unit, 3 ) or nil;
	if caution ~= nil then text = text .. ". Caution: " .. caution; end
	HubCore.SayResult( text );
end

function HubEvents.OnUnitCommandStarted( ownerID:number, unitID:number, commandID:number )
	if HubSettle ~= nil and HubSettle.OnUnitOrder ~= nil then HubSettle.OnUnitOrder( ownerID, unitID ); end
	if ownerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local row:table = GameInfo.UnitCommands[ commandID ];
	if row == nil then return; end
	local text:string = HubMenus.OPERATION_RESULTS[ row.CommandType ];
	if text ~= nil then HubCore.SayResult( text ); end
	-- Delete Unit: UnitPanel says "<unit> deleted"; the next unit the game selects must not cut it off
	if row.CommandType == "UNITCOMMAND_DELETE" then HubCore.m_lastResultTime = UI.GetElapsedTime(); end
end

-- The trade choosers hide their contexts (and so stop their update loops) when they close; they ask the hub to tell the
-- outcome a moment later. kind "route": a trade route was requested (unit, origin city owner and id, destination name);
-- kind "move": a trader was moved to another city (unit, plot it left, city name).
function HubEvents.OnTradeResult( kind:string, unitID:number, a, b, c, d )
	local owner:number = Game.GetLocalPlayer();
	if kind == "route" then
		HubCore.After( 1.0, function()
			local origin:table = CityManager.GetCity( a, b );
			local started:boolean = false;
			if origin ~= nil then
				for _, route in ipairs( origin:GetTrade():GetOutgoingRoutes() ) do
					if route.TraderUnitID == unitID then started = true; end
				end
			end
			if started then
				HubCore.SayResult( "Trade route to " .. c .. " started" );
			else
				HubCore.SayResult( "Trade route to " .. c .. " requested, but the trader has no route yet" );
			end
		end );
	elseif kind == "move" then
		HubCore.After( 0.5, function()
			local unit:table = Players[ owner ]:GetUnits():FindID( unitID );
			if unit ~= nil and ( unit:GetX() ~= a or unit:GetY() ~= b ) then
				HubCore.SayResult( "Trader moved to " .. c );
			else
				HubCore.SayResult( "Trader not moved" );
			end
		end );
	end
end

local function MovesText( unit:table )
	return HubCore.FormatNumber( unit:GetMovesRemaining() ) .. " of " .. HubCore.FormatNumber( unit:GetMaxMoves() ) .. " moves";
end

-- A move ordered with Enter in the move-to mode: arrived, still on the way, or stopped short.
function HubEvents.OnUnitMoveComplete( playerID:number, unitID:number, x:number, y:number )
	if playerID ~= Game.GetLocalPlayer() then return; end
	local record:table = HubCore.m_movers[ unitID ];
	if record == nil then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil then
		HubCore.m_movers[ unitID ] = nil;
		return;
	end
	local plot:table = Map.GetPlot( x, y );
	if plot ~= nil and plot:GetIndex() == record.dest then
		HubCore.m_movers[ unitID ] = nil;
		local text:string = "Arrived, ";
		local state:string = PlotDescription_UnitStateText( unit );
		if state ~= nil then
			text = text .. state .. ", ";
		elseif record.from ~= nil and Map.GetPlotByIndex ~= nil then
			local fromPlot:table = Map.GetPlotByIndex( record.from );
			local row:table = GameInfo.Units[ unit:GetType() ];
			if fromPlot ~= nil and fromPlot:IsWater() and not plot:IsWater() and row ~= nil and row.Domain == "DOMAIN_LAND" then
				text = text .. "disembarked, ";
			end
		end
		text = text .. MovesText( unit );
		if HubCore.IsSettler( unit ) then
			local ok:boolean, extra = SettleScan_CanFound( unit, plot );
			if not ok then
				text = text .. ", " .. SettleScan_CannotText( extra );
			elseif extra ~= true then
				text = text .. ", " .. SRKey( "B", "D-pad right, Found City," ) .. " to found the city";
			else
				text = text .. ", can settle, " .. SRKey( "B", "D-pad right, Found City," ) .. " to found next turn";
			end
		end
		if record.build ~= nil and HubSettle ~= nil and HubSettle.OnArrived ~= nil then
			local okBuild:boolean, extra = pcall( HubSettle.OnArrived, unit, plot, record );
			if okBuild and extra ~= nil then text = text .. ". " .. extra; end
		end
		HubCore.SayResult( text );
		return;
	end
	local queued = UnitManager.GetQueuedDestination( unit );
	if queued == nil then
		HubCore.m_movers[ unitID ] = nil;
		local destPlot:table = Map.GetPlotByIndex( record.dest );
		local text:string = "Stopped";
		if destPlot ~= nil and plot ~= nil then
			text = text .. ", " .. HubCore.Plural( Map.GetPlotDistance( x, y, destPlot:GetX(), destPlot:GetY() ), "tile", "tiles" ) .. " from the destination";
		end
		HubCore.SayResult( text );
		return;
	end
	-- still on the way: only said right after the order (not again every turn of a long move)
	if UI.GetElapsedTime() - ( record.issued or -100 ) > 3 then return; end
	local path:table = UnitManager.GetMoveToPathEx( unit, queued );
	local text:string = "Moving";
	if path ~= nil and path.turns ~= nil and #path.turns > 0 then
		text = text .. ", " .. HubCore.Plural( path.turns[ #path.turns ], "turn", "turns" ) .. " left";
	end
	HubCore.SayResult( text );
end

-- Who fights whom: the game announces a fight (CombatVisBegin) just before the damage events of both sides.
local m_combat:table = nil;

-- Spoken name of one side of a fight (unit or city).
function HubEvents.CombatSide( data:table )
	if data == nil or data.playerID == nil or data.playerID < 0 or Players[ data.playerID ] == nil then return nil; end
	local player:table = Players[ data.playerID ];
	local side:table = { player = data.playerID, id = data.componentID };
	if data.componentType == ComponentType.UNIT then
		local unit:table = player:GetUnits():FindID( data.componentID );
		if unit == nil then return nil; end
		side.name = PlotDescription_GetUnitName( unit );
		side.short = Locale.Lookup( unit:GetName() );
		side.x, side.y = unit:GetX(), unit:GetY();
		-- never name a unit the player cannot see (or an unmet civ behind it)
		if data.playerID ~= Game.GetLocalPlayer() and not ( HubCore.IsPlotVisibleToLocal( Map.GetPlot( side.x, side.y ) ) and PlotDescription_IsUnitVisible( unit ) ) then
			side.name, side.short, side.unseen = "An unseen unit", "The unseen unit", true;
		end
	else
		local city:table = nil;
		if data.componentType == ComponentType.DISTRICT then
			local district:table = player:GetDistricts():FindID( data.componentID );
			if district == nil then return nil; end
			city = district:GetCity();
			if city == nil then return nil; end
			side.x, side.y = district:GetX(), district:GetY();
		elseif data.componentType == ComponentType.CITY then
			city = player:GetCities():FindID( data.componentID );
			if city == nil then return nil; end
			side.x, side.y = city:GetX(), city:GetY();
		else
			return nil;
		end
		side.name = Locale.Lookup( city:GetName() );
		side.short = side.name;
		side.isCity = true;
	end
	if data.playerID == Game.GetLocalPlayer() and not side.unseen then side.name = "Your " .. side.name; end
	return side;
end

function HubEvents.OnCombatVisBegin( data:table )
	m_combat = nil;
	if not HubCore.m_ready or data == nil then return; end
	local attacker:table, defender:table = HubEvents.CombatSide( data[ CombatVisType.ATTACKER ] ), HubEvents.CombatSide( data[ CombatVisType.DEFENDER ] );
	if attacker == nil or defender == nil then return; end
	m_combat = { attacker = attacker, defender = defender, time = UI.GetElapsedTime(), told = false };
end

-- "3 tiles north-east of Rome": where a plot is, seen from the nearest own city (else the selected unit).
function HubEvents.PlaceFromOwn( x:number, y:number )
	local localPlayer:number = Game.GetLocalPlayer();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	if bestName == nil then
		local selected:table = UI.GetHeadSelectedUnit();
		if selected ~= nil and selected:GetOwner() == localPlayer then
			bestName, bestPlot = "your " .. Locale.Lookup( selected:GetName() ), Map.GetPlot( selected:GetX(), selected:GetY() );
		end
	end
	if bestName == nil then return nil; end
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	if relative == nil then return "at " .. bestName; end
	return relative .. " of " .. bestName;
end

function HubEvents.OnUnitDamageChanged( playerID:number, unitID:number, newDamage:number, oldDamage:number )
	if not HubCore.m_ready or newDamage <= oldDamage then return; end
	HubCore.ClearAttackPending();		-- a result of the fight (units and cities report their damage as unit damage; the line below tells it)
	local player:table = Players[ playerID ];
	if player == nil then return; end
	local unit:table = player:GetUnits():FindID( unitID );
	if unit == nil then return; end
	if not HubCore.IsPlotVisibleToLocal( Map.GetPlot( unit:GetX(), unit:GetY() ) ) or not PlotDescription_IsUnitVisible( unit ) then return; end
	HubCore.RememberUnit( unit );
	-- only fights that concern the player: their own units, or anything close to their units and cities
	if playerID ~= Game.GetLocalPlayer() and not HubCore.IsNearLocal( unit:GetX(), unit:GetY(), 3 ) then return; end
	local name:string = PlotDescription_GetUnitName( unit );
	if playerID == Game.GetLocalPlayer() then name = "Your " .. name; end
	local maxDamage:number = unit:GetMaxDamage();
	if newDamage >= maxDamage then return; end		-- H.OnUnitKilledInCombat tells it
	local text:string = name .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " left";
	-- the first damage line of a fight says who attacked whom (and where, when it is not our fight)
	local fight:table = m_combat;
	if fight ~= nil and not fight.told and UI.GetElapsedTime() - fight.time < 10
			and ( ( fight.attacker.player == playerID and fight.attacker.id == unitID ) or ( fight.defender.player == playerID and fight.defender.id == unitID ) ) then
		fight.told = true;
		HubCore.ClearAttackPending();
		local localPlayer:number = Game.GetLocalPlayer();
		local ours:boolean = fight.attacker.player == localPlayer or fight.defender.player == localPlayer;
		local victim:table = ( fight.defender.player == playerID and fight.defender.id == unitID ) and fight.defender or fight.attacker;
		local who:string = ( victim.player == localPlayer ) and victim.name or victim.short;
		local place:string = nil;
		if not ours then place = HubEvents.PlaceFromOwn( fight.defender.x, fight.defender.y ); end
		text = fight.attacker.name .. " attacks " .. fight.defender.name .. ( place ~= nil and ( ", " .. place ) or "" ) .. ": "
			.. who .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " left";
	end
	HubCore.Announce( text, true );
	LuaEvents.SRA_CombatSpoken();		-- StatusMessagePanel drops its duplicate of this fight
end

-- (killed player, killed unit, killer player, killer unit): told when the local player is on either side.
function HubEvents.OnUnitKilledInCombat( killedPlayer:number, killedId:number, killerPlayer:number, killerId:number )
	if not HubCore.m_ready then return; end
	local localPlayer:number = Game.GetLocalPlayer();
	-- a city shot reports no killer (-1): the fight announced just before names the attacker
	local fight0:table = m_combat;
	-- (a city shot may also report the city's id as a unit id: it can match a unit of ours standing in the city)
	if fight0 ~= nil and ( killerPlayer < 0 or fight0.attacker.isCity ) and fight0.defender.player == killedPlayer and fight0.defender.id == killedId
			and UI.GetElapsedTime() - fight0.time < 15 then
		killerPlayer, killerId = fight0.attacker.player, fight0.attacker.id;
	end
	if killedPlayer ~= localPlayer and killerPlayer ~= localPlayer then return; end
	HubCore.ClearAttackPending();
	local function NameOf( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		local unit:table = ( player ~= nil ) and player:GetUnits():FindID( unitID ) or nil;
		if unit ~= nil then return PlotDescription_GetUnitName( unit ); end
		-- the unit is gone by now: the name remembered while it was alive
		return HubCore.m_unitNames[ playerID .. ":" .. unitID ];
	end
	local killed:string = NameOf( killedPlayer, killedId ) or "unit";
	local killer:string = NameOf( killerPlayer, killerId );
	if fight0 ~= nil and fight0.attacker.isCity and fight0.attacker.player == killerPlayer and fight0.defender.player == killedPlayer
			and fight0.defender.id == killedId then killer = nil; end		-- the city, not a unit that shares its id: told below
	-- a city or district shot (bombard): the killer is no unit, but the fight announced just before names it
	local fight:table = m_combat;
	if killer == nil and fight ~= nil and fight.attacker.isCity and fight.attacker.player == killerPlayer
			and fight.defender.player == killedPlayer and fight.defender.id == killedId and UI.GetElapsedTime() - fight.time < 15 then
		killer = fight.attacker.short;
		HubCore.Announce( ( killedPlayer == localPlayer and ( "Your " .. killed .. " was killed" ) or ( killed .. " killed" ) ) .. " by " .. killer, true );
		LuaEvents.SRA_CombatSpoken();
		return;
	end
	local text:string;
	if killedPlayer == localPlayer then
		text = "Your " .. killed .. " was killed";
	else
		text = killed .. " killed";
	end
	if killer ~= nil then
		if killerPlayer == localPlayer then killer = "your " .. killer; end
		text = text .. " by " .. killer;
	end
	HubCore.Announce( text, true );
	LuaEvents.SRA_CombatSpoken();		-- StatusMessagePanel drops its duplicate of this fight
end

function HubEvents.OnCityAddedToMap( ownerID:number, cityID:number, x:number, y:number )
	if ownerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local city:table = Players[ ownerID ]:GetCities():FindID( cityID );
	local name:string = ( city ~= nil ) and Locale.Lookup( city:GetName() ) or "City";
	-- CityAddedToMap also fires for a captured or traded city: its original owner is then another civ
	local verb:string = "founded";
	local original:number = ownerID;
	if city ~= nil then
		local okC:boolean, loser = pcall( function() return city:GetJustConqueredFrom(); end );		-- the loser (RazeCity.lua uses it too)
		if okC and type( loser ) == "number" and loser >= 0 and loser ~= ownerID then
			original = loser;
		else
			local okO:boolean, orig = pcall( function() return city:GetOriginalOwner(); end );
			if okO and type( orig ) == "number" then original = orig; end
		end
	end
	if original ~= nil and original ~= ownerID and original >= 0 then
		verb = "captured";
		local cfg:table = PlayerConfigurations[ original ];
		if cfg ~= nil and cfg:GetCivilizationShortDescription() ~= nil then verb = verb .. " from " .. Locale.Lookup( cfg:GetCivilizationShortDescription() ); end
	end
	HubCore.SayResult( name .. " " .. verb );
end

-- A builder finished an improvement on its own plot.
function HubEvents.OnImprovementAddedToMap( x:number, y:number, improvementType:number, owner:number )
	if owner ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetX() ~= x or unit:GetY() ~= y then return; end
	local row:table = GameInfo.Improvements[ improvementType ];
	if row == nil then return; end
	local name:string = Locale.Lookup( row.Name );
	local unitID:number = unit:GetID();
	HubCore.After( 0.4, function()	-- the charges are counted down a moment later
		local builder:table = Players[ owner ]:GetUnits():FindID( unitID );
		local text:string = name .. " built";
		if builder ~= nil then
			text = text .. ", " .. HubCore.Plural( builder:GetBuildCharges(), "charge", "charges" ) .. " left";
		else
			text = text .. ", the builder is used up";
		end
		HubCore.SayResult( text );
	end );
end

-- Tribal village reward, spoken as "Tribal village: 40 gold". Events.GoodyHutReward( playerID, unitID, goodyHutTypeHash, subTypeHash ):
-- the hashes are DB.MakeHash of GoodyHuts.GoodyHutType / GoodyHutSubTypes.SubTypeGoodyHut. The game's Description strings take the amount
-- as parameter; some have no text at all (units, population, relic: spoken here) and the boosts have no Description because the
-- boost popup says them (BoostUnlockedPopup, BOOST_SOURCE_GOODYHUT): nothing is added for those.
local GOODY_FALLBACK:table = {
	GOODYHUT_ONE_RELIC = "a relic",
	GOODYHUT_ADD_POP = "a new citizen",
	GOODYHUT_GRANT_BUILDER = "a free Builder",
	GOODYHUT_GRANT_TRADER = "a free Trader",
	GOODYHUT_GRANT_SETTLER = "a free Settler",
	GOODYHUT_ENVOY = "a free envoy",
	GOODYHUT_FAVOR = "diplomatic favor",
	GOODYHUT_RESOURCES = "strategic resources",
};

function HubEvents.GoodyRewardText( row:table )
	local amount:number = nil;
	for arg in GameInfo.ModifierArguments() do
		if arg.ModifierId == row.ModifierID and arg.Name == "Amount" then amount = tonumber( arg.Value ); break; end
	end
	local speed:table = GameInfo.GameSpeeds[ GameConfiguration.GetGameSpeedType() ];
	if amount ~= nil and speed ~= nil and ( row.GoodyHut == "GOODYHUT_GOLD" or row.GoodyHut == "GOODYHUT_FAITH" ) then
		amount = math.floor( amount * speed.CostMultiplier / 100 );
	end
	local text:string = ( row.Description ~= nil ) and Locale.Lookup( row.Description, amount or 1 ) or "";
	text = text:gsub( "%[ICON_Gold%]", " gold" ):gsub( "%[ICON_Faith%]", " faith" ):gsub( "%[ICON_Envoy%]", "" ):gsub( "%[ICON_Governor%]", "" );
	text = text:gsub( "%[[%w_]+%]", "" ):gsub( "^%s*%+", "" ):gsub( "%s+", " " ):gsub( "^ ", "" ):gsub( " $", "" );
	if text == "" or row.SubTypeGoodyHut == "GOODYHUT_GRANT_BUILDER" or row.SubTypeGoodyHut == "GOODYHUT_GRANT_TRADER" or row.SubTypeGoodyHut == "GOODYHUT_GRANT_SETTLER"
		or row.SubTypeGoodyHut == "GOODYHUT_ONE_RELIC" or row.SubTypeGoodyHut == "GOODYHUT_ADD_POP" then
		text = GOODY_FALLBACK[ row.SubTypeGoodyHut ] or text;
	end
	return text;
end

function HubEvents.OnGoodyHutReward( playerID:number, unitID:number, typeHash:number, subTypeHash:number )
	if playerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local row:table = nil;
	for r in GameInfo.GoodyHutSubTypes() do
		if DB.MakeHash( r.SubTypeGoodyHut ) == subTypeHash then row = r; break; end
	end
	if row == nil then return; end
	local text:string = HubEvents.GoodyRewardText( row );
	if text == "" then return; end
	HubCore.After( 0.3, function() HubCore.Announce( "Tribal village: " .. text, true ); end );		-- after "Arrived"
end

-- "Barbarian Warrior spotted, 2 tiles north of Rome": hostile soldiers that come into view near our cities and units.
function HubEvents.OnUnitVisibilityChanged( playerID:number, unitID:number, visibility:number )
	local localPlayer:number = Game.GetLocalPlayer();
	if not HubCore.m_ready or playerID == localPlayer or visibility ~= RevealedState.VISIBLE or not HubCore.IsHostile( playerID ) then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil then return; end
	if HubEnemies ~= nil and PlotDescription_IsUnitVisible( unit ) then HubEnemies.OnHostileVisible( unit ); end		-- scout alarm, raid, civilian danger
	if unit:GetCombat() <= 0 and unit:GetRangedCombat() <= 0 then return; end
	if not PlotDescription_IsUnitVisible( unit ) then return; end
	HubCore.RememberUnit( unit );
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = playerID .. ":" .. unitID;
	if HubCore.m_spotted[ key ] ~= nil and turn - HubCore.m_spotted[ key ] < 10 then return; end
	if m_spottedTurn ~= turn then m_spottedTurn = turn; m_spottedCount = 0; end
	if m_spottedCount >= 4 then return; end
	local x:number, y:number = unit:GetX(), unit:GetY();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	for _, mine in Players[ localPlayer ]:GetUnits():Members() do
		local distance:number = Map.GetPlotDistance( x, y, mine:GetX(), mine:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, "your " .. Locale.Lookup( mine:GetName() ), Map.GetPlot( mine:GetX(), mine:GetY() );
		end
	end
	if bestName == nil or bestDistance > 4 then return; end
	HubCore.m_spotted[ key ] = turn;
	m_spottedCount = m_spottedCount + 1;
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	local text:string = PlotDescription_GetUnitName( unit ) .. " spotted";
	if relative ~= nil then text = text .. ", " .. relative .. " of " .. bestName; else text = text .. " at " .. bestName; end
	HubRegions.m_lastSpotSpeech = UI.GetElapsedTime();
	HubCore.Announce( text, true );
end
