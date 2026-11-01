-- ===========================================================================
--	DiplomacyIntel: what the leader's intel panels (Overview, Relationship, Gossip, Access Level, Alliance, Grievances) tell a sighted
--	player, as a KeyNavList item list: why they like or dislike you, their agendas, running deals, who they are at war with.
--	Used by the V list (HubMenus: I on a civilization = DiplomacyIntel.Items, I on "You" = DiplomacyIntel.WorldItems) and by
--	DiplomacyActionView.lua (the "Intel report" entry of the overview).
--
--	Two layers: Gather( playerId ) reads the game (every group inside a pcall: a failed group is logged and skipped) into a plain
--	snapshot; BuildItems( snapshot ) turns the snapshot into items (pure, test/lua/test_diplomacyintel.lua). The visibility rules are
--	the game's own (DiplomacyActionView.lua of the game: OnActivateIntel*Panel, AddOverview*, AddIntelAlliance, WorldCongressTab).
--
--	Item: { key, text, section = <group>, detail = <string, optional> }. Groups in this order: Relationship, Agendas, Agreements,
--	Their relations, Access, Gossip.
-- ===========================================================================
include( "ScreenReader" );
include( "DealSpeech" );

DiplomacyIntel = {};

DiplomacyIntel.MAX_GOSSIP = 20;

-- ---------------------------------------------------------------------------
--	Pure wording
-- ---------------------------------------------------------------------------
local function Turns( n:number )
	return n .. ( n == 1 and " turn" or " turns" );
end

local function Capital( text:string )
	return string.upper( string.sub( text, 1, 1 ) ) .. string.sub( text, 2 );
end

-- "plus 6" / "minus 3" / "zero"
function DiplomacyIntel.Signed( n:number )
	if n > 0 then return "plus " .. n; end
	if n < 0 then return "minus " .. ( -n ); end
	return "zero";
end

-- Game text for speech: no markup, no trailing full stop.
function DiplomacyIntel.Clean( text )
	if text == nil then return ""; end
	text = CleanTextForSpeech( tostring( text ) );
	text = string.gsub( text, "[%.%s]+$", "" );
	return text;
end

-- "14 turns left" from a deal item's duration and the turn it was enacted; nil for a one-time or open-ended item.
function DiplomacyIntel.TurnsLeft( duration:number, enacted:number, currentTurn:number )
	if duration == nil or duration <= 0 then return nil; end
	local left:number = duration - ( currentTurn - ( enacted or currentTurn ) );
	if left < 0 then left = 0; end
	return left;
end

-- Relationship group. rel = { state = "Friendly", note = <optional text>, modifiers = { { score, text } ... } or nil (no score list: a human),
-- grievances = { direction = "them"|"you", total, perTurn, log = { { turn, amount, text } ... } } or nil }
local function RelationshipItems( rel:table )
	local items:table = {};
	local mods:table = {};
	local total:number = 0;
	local byText:table = {};
	for i, mod in ipairs( rel.modifiers or {} ) do
		total = total + mod.score;
		-- the same reason twice (two "Unknown Reason" entries of +3): one line with the sum
		local merged:table = byText[ mod.text ];
		if merged ~= nil then
			merged.score = merged.score + mod.score;
		else
			merged = { score = mod.score, text = mod.text, order = i };
			byText[ mod.text ] = merged;
			table.insert( mods, merged );
		end
	end
	local head:string = "Relationship: " .. rel.state;
	if rel.modifiers ~= nil and #mods > 0 then head = head .. ", total " .. DiplomacyIntel.Signed( total ); end
	table.insert( items, { text = head, detail = rel.note } );
	-- biggest magnitude first, the game's order among equals
	table.sort( mods, function( a, b )
		if math.abs( a.score ) ~= math.abs( b.score ) then return math.abs( a.score ) > math.abs( b.score ); end
		return a.order < b.order;
	end );
	for _, mod in ipairs( mods ) do
		table.insert( items, { text = Capital( DiplomacyIntel.Signed( mod.score ) ) .. ": " .. mod.text } );
	end
	local g:table = rel.grievances;
	if g ~= nil and g.total ~= nil and g.total > 0 then
		local text:string = ( g.direction == "you" ) and ( "Grievances: you hold " .. g.total .. " against them" ) or ( "Grievances: they hold " .. g.total .. " against you" );
		local lines:table = {};
		if g.perTurn ~= nil and g.perTurn ~= 0 then table.insert( lines, "Changing by " .. g.perTurn .. " per turn" ); end
		for i, entry in ipairs( g.log or {} ) do
			if i > 5 then break; end
			table.insert( lines, "Turn " .. entry.turn .. ", " .. entry.amount .. ": " .. entry.text );
		end
		table.insert( items, { text = text, detail = ( #lines > 0 ) and table.concat( lines, ". " ) or nil } );
	end
	return items;
end

-- Agendas group. ag = { agendas = { { name, text } ... }, hidden = { { count, level = <access level name> } ... }, none = <true: the game says none> }
local function AgendaItems( ag:table )
	local items:table = {};
	for _, agenda in ipairs( ag.agendas or {} ) do
		local text:string = agenda.name;
		if agenda.text ~= nil and agenda.text ~= "" then text = text .. ": " .. agenda.text; end
		table.insert( items, { text = text } );
	end
	for _, hidden in ipairs( ag.hidden or {} ) do
		local text:string = ( hidden.count > 1 and ( hidden.count .. " hidden agendas" ) or "Hidden agenda" ) .. ", not known yet";
		if hidden.level ~= nil and hidden.level ~= "" then text = text .. ": needs access level " .. hidden.level; end
		table.insert( items, { text = text, detail = hidden.hint } );
	end
	if #items == 0 then table.insert( items, { text = ag.noneText or "No agendas known" } ); end
	return items;
end

-- Text of one running deal. deal = { mine = { { kind = "gold"|"resource"|"agreement", name, amount } }, theirs = { ... }, left = <turns or nil> }
function DiplomacyIntel.DealText( deal:table )
	local function Side( label:string, entries:table )
		if entries == nil or #entries == 0 then return nil; end
		local texts:table = {};
		for i, entry in ipairs( entries ) do
			if entry.kind == "gold" then
				texts[i] = ( entry.amount or 0 ) .. " gold per turn";
			else
				texts[i] = DealSpeech_ItemText( { kind = entry.kind, name = entry.name, amount = entry.amount } );
			end
		end
		return label .. " " .. table.concat( texts, ", " );
	end
	local parts:table = {};
	table.insert( parts, Side( "You give", deal.mine ) );
	table.insert( parts, Side( "they give", deal.theirs ) );
	local text:string = table.concat( parts, "; " );
	if text == "" then text = "Deal"; end
	if deal.left ~= nil then text = text .. "; " .. Turns( deal.left ) .. " left"; end
	return Capital( text );
end

-- Agreements group. ag = { deals = { deal ... }, others = { { text, detail, left } ... } }
local function AgreementItems( ag:table )
	local items:table = {};
	for _, deal in ipairs( ag.deals or {} ) do
		table.insert( items, { text = DiplomacyIntel.DealText( deal ) } );
	end
	for _, other in ipairs( ag.others or {} ) do
		local text:string = other.text;
		if other.left ~= nil then text = text .. ", " .. Turns( other.left ) .. " left"; end
		table.insert( items, { text = text, detail = other.detail } );
	end
	if #items == 0 then table.insert( items, { text = "No agreements" } ); end
	return items;
end

-- Their relations group. list = { { kind = "war"|"allied"|"friend"|"denounced"|"other", name = <civ or nil: not met>, state = <state name> } ... }
function DiplomacyIntel.RelationText( rel:table )
	local who:string = rel.name or "a civilization you have not met";
	if rel.kind == "war" then return "At war with " .. who; end
	if rel.kind == "allied" then return "Allied with " .. who; end
	if rel.kind == "friend" then return "Declared friend of " .. who; end
	if rel.kind == "denounced" then return "Denounced, " .. who; end
	return "Relationship with " .. who .. ": " .. ( rel.state or "unknown" );
end

local function RelationItems( list:table )
	local items:table = {};
	for _, rel in ipairs( list or {} ) do
		table.insert( items, { text = DiplomacyIntel.RelationText( rel ) } );
	end
	if #items == 0 then table.insert( items, { text = "They have no relations with other civilizations you know of" } ); end
	return items;
end

-- Access group. acc = { level = "Limited", gives = { text ... }, next = { text ... }, sources = { text ... }, needs = { text ... } }
local function AccessItems( acc:table )
	local text:string = "Access level: " .. acc.level;
	if acc.gives ~= nil and #acc.gives > 0 then text = text .. ". Gives " .. table.concat( acc.gives, ", " ); end
	if acc.needs ~= nil and #acc.needs > 0 then text = text .. ". To raise it: " .. table.concat( acc.needs, "; " ); end
	local lines:table = {};
	if acc.sources ~= nil and #acc.sources > 0 then table.insert( lines, "Giving you access now: " .. table.concat( acc.sources, "; " ) ); end
	if acc.next ~= nil and #acc.next > 0 then table.insert( lines, "The next level gives " .. table.concat( acc.next, ", " ) ); end
	return { { text = text, detail = ( #lines > 0 ) and table.concat( lines, ". " ) or nil } };
end

-- Gossip group. list = { { turn, text } ... } in any order
local function GossipItems( list:table )
	local sorted:table = {};
	for i, entry in ipairs( list or {} ) do table.insert( sorted, { turn = entry.turn, text = entry.text, order = i } ); end
	table.sort( sorted, function( a, b )
		if a.turn ~= b.turn then return a.turn > b.turn; end
		return a.order < b.order;
	end );
	local items:table = {};
	for i, entry in ipairs( sorted ) do
		if i > DiplomacyIntel.MAX_GOSSIP then break; end
		table.insert( items, { text = "Turn " .. entry.turn .. ": " .. entry.text } );
	end
	if #items == 0 then table.insert( items, { text = "No gossip yet" } ); end
	return items;
end

local GROUPS:table = {
	{ field = "relationship",	section = "Relationship",		build = RelationshipItems },
	{ field = "agendas",		section = "Agendas",			build = AgendaItems },
	{ field = "agreements",		section = "Agreements",			build = AgreementItems },
	{ field = "relations",		section = "Their relations",	build = RelationItems },
	{ field = "access",			section = "Access",				build = AccessItems },
	{ field = "gossip",			section = "Gossip",				build = GossipItems },
};

-- The snapshot as items. A group whose gathering failed (snap.failed[field]) or is absent (nil) is left out; a group whose wording fails
-- is logged and skipped.
function DiplomacyIntel.BuildItems( snap:table )
	local items:table = {};
	for _, group in ipairs( GROUPS ) do
		local data = snap[ group.field ];
		if data ~= nil then
			local ok:boolean, built = pcall( group.build, data );
			if ok then
				for i, item in ipairs( built ) do
					item.section = group.section;
					item.key = "intel:" .. group.field .. ":" .. i;
					table.insert( items, item );
				end
			else
				print( "DiplomacyIntel build error (" .. group.field .. "): " .. tostring( built ) );
			end
		end
	end
	return items;
end

-- The one-line detail of the V list item: "Relationship plus 12. Agendas: Darwinist. 2 agreements. At war with 1 civilization. I opens ..."
function DiplomacyIntel.SummaryText( snap:table )
	local parts:table = {};
	local rel:table = snap.relationship;
	if rel ~= nil then
		local total:number = 0;
		local count:number = 0;
		for _, mod in ipairs( rel.modifiers or {} ) do total = total + mod.score; count = count + 1; end
		if count > 0 then
			table.insert( parts, "Relationship " .. DiplomacyIntel.Signed( total ) );
		else
			table.insert( parts, "Relationship " .. string.lower( rel.state ) );
		end
	end
	local ag:table = snap.agendas;
	if ag ~= nil then
		local names:table = {};
		for _, agenda in ipairs( ag.agendas or {} ) do table.insert( names, agenda.name ); end
		local hidden:number = 0;
		for _, h in ipairs( ag.hidden or {} ) do hidden = hidden + h.count; end
		if hidden > 0 then table.insert( names, hidden .. " hidden" ); end
		if #names > 0 then table.insert( parts, "Agendas: " .. table.concat( names, ", " ) ); end
	end
	local agr:table = snap.agreements;
	if agr ~= nil then
		local n:number = #( agr.deals or {} ) + #( agr.others or {} );
		table.insert( parts, n == 0 and "No agreements" or ( n .. ( n == 1 and " agreement" or " agreements" ) ) );
	end
	local wars:number = 0;
	for _, r in ipairs( snap.relations or {} ) do if r.kind == "war" then wars = wars + 1; end end
	if wars > 0 then table.insert( parts, "At war with " .. wars .. ( wars == 1 and " civilization" or " civilizations" ) ); end
	table.insert( parts, SRKey( "I", "X" ) .. " opens the full intel report" );
	return table.concat( parts, ". " );
end

-- World relations. world = { wars = { rel ... }, alliances = { rel ... }, denunciations = { rel ... } }, rel = { a = <name>, b = <name>,
-- youA = <true: a is you>, kind = "allied"|"friend" (alliances) }.
function DiplomacyIntel.WorldRelationText( kind:string, rel:table )
	if kind == "wars" then
		if rel.youA then return "You are at war with " .. rel.b; end
		return rel.a .. " at war with " .. rel.b;
	elseif kind == "alliances" then
		if rel.kind == "friend" then
			if rel.youA then return "You and " .. rel.b .. " are declared friends"; end
			return rel.a .. " and " .. rel.b .. " are declared friends";
		end
		if rel.youA then return "You are allied with " .. rel.b; end
		return rel.a .. " allied with " .. rel.b;
	end
	if rel.youA then return "Denunciation between you and " .. rel.b; end
	return "Denunciation between " .. rel.a .. " and " .. rel.b;
end

function DiplomacyIntel.WorldBuild( world:table )
	local items:table = {};
	local function Add( field:string, section:string, kind:string )
		for i, rel in ipairs( world[ field ] or {} ) do
			table.insert( items, { key = "world:" .. field .. ":" .. i, section = section, text = DiplomacyIntel.WorldRelationText( kind, rel ) } );
		end
	end
	Add( "wars", "Wars", "wars" );
	if #items == 0 then
		table.insert( items, { key = "world:wars:none", section = "Wars", text = "No wars between civilizations you have met" } );
	end
	Add( "alliances", "Alliances", "alliances" );
	Add( "denunciations", "Denunciations", "denunciations" );
	return items;
end

-- ---------------------------------------------------------------------------
--	Gathering from the game
-- ---------------------------------------------------------------------------
local function SafeName( key )
	if key == nil then return ""; end
	return DiplomacyIntel.Clean( Locale.Lookup( key ) );
end

local function CivName( playerId:number )
	local config:table = PlayerConfigurations[ playerId ];
	if config == nil then return "unknown"; end
	return DiplomacyIntel.Clean( Locale.Lookup( config:GetCivilizationShortDescription() ) );
end

local function LeaderTitle( playerId:number )
	local config:table = PlayerConfigurations[ playerId ];
	return DiplomacyIntel.Clean( Locale.Lookup( config:GetLeaderName() ) ) .. " of " .. CivName( playerId );
end

-- "Intel on Cleopatra of Egypt"
function DiplomacyIntel.Title( playerId:number )
	return "Intel on " .. LeaderTitle( playerId );
end

-- The game's relationship tab (OnActivateIntelRelationshipPanel) and, with Gathering Storm, the grievances tab.
local function GatherRelationship( localId:number, sel:table, selId:number )
	local ai:table = sel:GetDiplomaticAI();
	local stateIndex = ai:GetDiplomaticStateIndex( localId );
	local row:table = GameInfo.DiplomaticStates[ stateIndex ];
	local rel:table = { state = ( row ~= nil and SafeName( row.Name ) or "unknown" ) };
	-- the game gives no score list for a human (the tab is not added)
	if not sel:IsHuman() then
		rel.modifiers = {};
		local modifiers = ai:GetDiplomaticModifiers( localId );
		if modifiers ~= nil then
			for _, mod in ipairs( modifiers ) do
				if mod.Score ~= nil and mod.Score ~= 0 then
					table.insert( rel.modifiers, { score = mod.Score, text = DiplomacyIntel.Clean( Locale.Lookup( mod.Text ) ) } );
				end
			end
		end
	end
	-- how long a denunciation / declared friendship lasts: the game's tooltip (DiplomacyActionView AddOverviewOurRelationship)
	local localDip:table = Players[ localId ]:GetDiplomacy();
	local current:number = Game.GetCurrentGameTurn();
	if row ~= nil and row.StateType == "DIPLO_STATE_DECLARED_FRIEND" then
		local left:number = localDip:GetDeclaredFriendshipTurn( selId ) + Game.GetGameDiplomacy():GetDenounceTimeLimit() - current;
		rel.friendLeft = left;
		rel.note = DiplomacyIntel.Clean( Locale.Lookup( "LOC_DIPLOMACY_DECLARED_FRIENDSHIP_TOOLTIP", PlayerConfigurations[ localId ]:GetCivilizationShortDescription(),
			PlayerConfigurations[ selId ]:GetCivilizationShortDescription(), left ) );
	elseif row ~= nil and row.StateType == "DIPLO_STATE_DENOUNCED" then
		rel.note = "Denounced";
	end
	-- grievances (Gathering Storm): GetGrievancesAgainst < 0 = they hold grievances against you (DiplomacyActionView_WorldCongressTab)
	local okG:boolean, total = pcall( function() return localDip:GetGrievancesAgainst( selId ); end );
	if okG and total ~= nil and total ~= 0 then
		local gameDip:table = Game.GetGameDiplomacy();
		local g:table = { direction = ( total > 0 ) and "you" or "them", total = math.abs( total ), log = {} };
		pcall( function() g.perTurn = gameDip:GetGrievanceChangePerTurn( selId, localId ); end );
		pcall( function()
			local entries = {};
			for _, entry in ipairs( gameDip:GetGrievanceLogEntries( selId, localId ) ) do table.insert( entries, entry ); end
			table.sort( entries, function( a, b ) return a.Turn > b.Turn; end );
			for _, entry in ipairs( entries ) do
				table.insert( g.log, { turn = entry.Turn, amount = entry.Amount, text = DiplomacyIntel.Clean( entry.Description ) } );
			end
		end );
		rel.grievances = g;
	end
	return rel;
end

-- Agendas the game shows at the local player's access level (AddOverviewAgendas, Gathering Storm version; the base version as fallback).
local function GatherAgendas( localId:number, sel:table, selId:number )
	if PlayerConfigurations[ selId ]:IsHuman() then return nil; end		-- the game hides the whole block for a human
	local ag:table = { agendas = {}, hidden = {} };
	local access = Players[ localId ]:GetDiplomacy():GetVisibilityOn( selId );
	local function AddAgenda( agendaIndex )
		local def:table = GameInfo.Agendas[ agendaIndex ];
		if def == nil then return; end
		table.insert( ag.agendas, { name = SafeName( def.Name ), text = SafeName( def.Description ) } );
	end
	local function LevelName( index )
		local row:table = GameInfo.Visibilities[ index ];
		return row ~= nil and SafeName( row.Name ) or nil;
	end
	local entries = nil;
	if sel.GetAgendasAndVisibilities ~= nil then entries = sel:GetAgendasAndVisibilities(); end
	if entries ~= nil then
		local hiddenByLevel:table = {};
		local order:table = {};
		for _, entry in ipairs( entries ) do
			if entry.Visibility <= access then
				AddAgenda( entry.Agenda );
			else
				if hiddenByLevel[ entry.Visibility ] == nil then hiddenByLevel[ entry.Visibility ] = 0; table.insert( order, entry.Visibility ); end
				hiddenByLevel[ entry.Visibility ] = hiddenByLevel[ entry.Visibility ] + 1;
			end
		end
		table.sort( order );
		for _, level in ipairs( order ) do
			table.insert( ag.hidden, { count = hiddenByLevel[ level ], level = LevelName( level ), hint = SafeName( "LOC_DIPLOMACY_HIDDEN_AGENDAS_TT" ) } );
		end
	else
		-- base game: the historical agenda is always shown, the random ones from the access level that reveals agendas
		local leader:string = PlayerConfigurations[ selId ]:GetLeaderTypeName();
		for row in GameInfo.HistoricalAgendas() do
			if row.LeaderType == leader and GameInfo.Agendas[ row.AgendaType ] ~= nil then
				AddAgenda( GameInfo.Agendas[ row.AgendaType ].Index );
				break;
			end
		end
		local revealLevel = nil;
		for row in GameInfo.Visibilities() do
			if row.RevealAgendas == true and ( revealLevel == nil or row.Index < revealLevel ) then revealLevel = row.Index; end
		end
		local random = sel:GetAgendaTypes();
		table.remove( random, 1 );
		if #random > 0 then
			if revealLevel ~= nil and access >= revealLevel then
				for _, agendaType in ipairs( random ) do AddAgenda( agendaType ); end
			else
				table.insert( ag.hidden, { count = #random, level = revealLevel ~= nil and LevelName( revealLevel ) or nil, hint = SafeName( "LOC_DIPLOMACY_HIDDEN_AGENDAS_TT" ) } );
			end
		end
	end
	if #ag.agendas == 0 and #ag.hidden == 0 then ag.noneText = SafeName( "LOC_DIPLOMACY_RANDOM_AGENDA_NONE" ); end
	return ag;
end

-- Running deals with this player (DealManager.GetPlayerDeals, like the Reports screen), then the agreements the diplomacy overview
-- lists (delegation, embassy, open borders, research agreement ...), declared friendship and the alliance.
local function GatherAgreements( localId:number, sel:table, selId:number, rel:table )
	local ag:table = { deals = {}, others = {} };
	local current:number = Game.GetCurrentGameTurn();
	local covered:table = {};
	local pDeals = DealManager.GetPlayerDeals( localId, selId );
	-- deal agreement subtype -> the overview flag it stands for (so the same agreement is not listed twice)
	local subtypes:table = {};
	for typeKey, flag in pairs( { OPEN_BORDERS = "borders", RESEARCH_AGREEMENT = "research", JOINT_WAR = "jointwar", DEFENSIVE_PACT = "pact", ALLIANCE = "alliance" } ) do
		if DealAgreementTypes ~= nil and DealAgreementTypes[ typeKey ] ~= nil then subtypes[ DealAgreementTypes[ typeKey ] ] = flag; end
	end
	if pDeals ~= nil then
		for _, pDeal in ipairs( pDeals ) do
			local deal:table = { mine = {}, theirs = {} };
			local left = nil;
			for pItem in pDeal:Items() do
				local itemType = pItem:GetType();
				local duration:number = pItem:GetDuration();
				local entry:table = nil;
				if itemType == DealItemTypes.GOLD then
					if duration ~= 0 then entry = { kind = "gold", amount = pItem:GetAmount() }; end
				elseif itemType == DealItemTypes.RESOURCES then
					if duration ~= 0 then
						local resource:table = GameInfo.Resources[ pItem:GetValueType() ];
						entry = { kind = "resource", name = resource ~= nil and SafeName( resource.Name ) or "Resource", amount = pItem:GetAmount() };
					end
				elseif itemType == DealItemTypes.AGREEMENTS then
					local subtype = pItem:GetSubType();
					covered[ subtypes[ subtype ] or "" ] = true;
					if subtypes[ subtype ] ~= "alliance" then		-- the alliance has its own item below (type, level, benefits)
						local nameId = pItem:GetSubTypeNameID();
						entry = { kind = "agreement", name = nameId ~= nil and SafeName( nameId ) or "Agreement" };
					end
				end
				if entry ~= nil then
					table.insert( pItem:GetFromPlayerID() == localId and deal.mine or deal.theirs, entry );
					local itemLeft = DiplomacyIntel.TurnsLeft( duration, pItem:GetEnactedTurn(), current );
					if itemLeft ~= nil and ( left == nil or itemLeft < left ) then left = itemLeft; end
				end
			end
			deal.left = left;
			if #deal.mine + #deal.theirs > 0 then table.insert( ag.deals, deal ); end
		end
	end
	local localDip:table = Players[ localId ]:GetDiplomacy();
	local function Other( text, detail, left ) table.insert( ag.others, { text = text, detail = detail, left = left } ); end
	if rel ~= nil and rel.friendLeft ~= nil then Other( "Declared Friendship", rel.note, rel.friendLeft ); end
	if localDip:HasDelegationAt( selId ) then Other( SafeName( "LOC_DIPLO_MODIFIER_DELEGATION" ) ); end
	if localDip:HasEmbassyAt( selId ) then Other( SafeName( "LOC_DIPLO_MODIFIER_RESIDENT_EMBASSY" ) ); end
	if localDip:HasDefensivePact( selId ) and not covered.pact then Other( SafeName( "LOC_DIPLO_MODIFIER_DEFENSIVE_PACT" ) ); end
	if not covered.borders then
		if localDip:HasOpenBordersFrom( selId ) then Other( SafeName( "LOC_DIPLO_MODIFIER_RECEIVED_OPEN_BORDERS" ) ); end
		if sel:GetDiplomacy():HasOpenBordersFrom( localId ) then Other( SafeName( "LOC_DIPLO_MODIFIER_GAVE_OPEN_BORDERS" ) ); end
	end
	if not covered.research and localDip:GetResearchAgreementTech( selId ) ~= -1 then
		local tech:table = GameInfo.Technologies[ localDip:GetResearchAgreementTech( selId ) ];
		Other( SafeName( "LOC_DIPLOACTION_RESEARCH_AGREEMENT_NAME" ), tech ~= nil and ( "Researching " .. SafeName( tech.Name ) ) or nil );
	end
	if not covered.jointwar and localDip:IsFightingAnyJointWarWith( selId ) then Other( SafeName( "LOC_DIPLOACTION_JOINT_WAR_NAME" ) ); end
	-- alliance (Gathering Storm / Rise and Fall): type, level, turns until it expires, benefits
	local okA:boolean, allianceType = pcall( function() return localDip:GetAllianceType( selId ); end );
	if okA and allianceType ~= nil and allianceType ~= -1 and GameInfo.Alliances[ allianceType ] ~= nil then
		local def:table = GameInfo.Alliances[ allianceType ];
		local level = localDip:GetAllianceLevel( selId );
		local left = localDip:GetAllianceTurnsUntilExpiration( selId );
		local benefits = nil;
		pcall( function() benefits = DiplomacyIntel.Clean( Game.GetGameDiplomacy():GetAllianceBenefitsString( def.Index, level, true ) ); end );
		Other( "Alliance: " .. SafeName( def.Name ) .. ", level " .. level, benefits, ( left ~= nil and left > 0 ) and left or nil );
	end
	return ag;
end

-- Relations of the selected player with the other majors (AddOverviewOtherRelationships): only states the game shows as icons;
-- a civilization the local player has not met is shown without its name.
local function RelationValid( stateType:string, humanPair:boolean )
	if Relationship == nil then return true; end
	if humanPair then return Relationship.IsValidWithHuman( stateType ); end
	return Relationship.IsValidWithAI( stateType );
end

local KIND_OF_STATE:table = {
	DIPLO_STATE_WAR = "war", DIPLO_STATE_ALLIED = "allied", DIPLO_STATE_DECLARED_FRIEND = "friend", DIPLO_STATE_DENOUNCED = "denounced",
};

local function GatherRelations( localId:number, sel:table, selId:number )
	local list:table = {};
	local localDip:table = Players[ localId ]:GetDiplomacy();
	local selDip:table = sel:GetDiplomacy();
	for _, other in ipairs( PlayerManager.GetAliveMajors() ) do
		local id:number = other:GetID();
		if id ~= localId and id ~= selId and selDip:HasMet( id ) then
			local stateIndex = other:GetDiplomaticAI():GetDiplomaticStateIndex( selId );
			local row:table = GameInfo.DiplomaticStates[ stateIndex ];
			if row ~= nil and row.Hash ~= DiplomaticStates.NEUTRAL then
				local humanPair:boolean = not ( sel:IsAI() or other:IsAI() );
				if RelationValid( row.StateType, humanPair ) then
					table.insert( list, { kind = KIND_OF_STATE[ row.StateType ] or "other", state = SafeName( row.Name ), name = localDip:HasMet( id ) and CivName( id ) or nil } );
				end
			end
		end
	end
	-- named civilizations first, then the unmet ones
	table.sort( list, function( a, b )
		if ( a.name == nil ) ~= ( b.name == nil ) then return a.name ~= nil; end
		return false;
	end );
	return list;
end

local function GatherAccess( localId:number, selId:number )
	local localDip:table = Players[ localId ]:GetDiplomacy();
	local level = localDip:GetVisibilityOn( selId );
	local acc:table = { level = SafeName( GameInfo.Visibilities[ level ].Name ), gives = {}, next = {}, sources = {}, needs = {} };
	for row in GameInfo.Gossips() do
		if row.Description ~= nil then
			if row.VisibilityLevel == level then table.insert( acc.gives, DiplomacyIntel.Clean( Locale.Lookup( row.Description ) ) );
			elseif row.VisibilityLevel == level + 1 then table.insert( acc.next, DiplomacyIntel.Clean( Locale.Lookup( row.Description ) ) ); end
		end
	end
	for row in GameInfo.DiplomaticVisibilitySources() do
		if localDip:IsVisibilitySourceActive( selId, row.Index ) then
			if row.Description ~= nil then table.insert( acc.sources, DiplomacyIntel.Clean( Locale.Lookup( row.Description ) ) ); end
		elseif row.ActionDescription ~= nil then
			table.insert( acc.needs, DiplomacyIntel.Clean( Locale.Lookup( row.ActionDescription ) ) );
		end
	end
	return acc;
end

-- The gossip the game's gossip tab shows (the last 100 turns).
local function GatherGossip( localId:number, selId:number )
	local list:table = {};
	local current:number = Game.GetCurrentGameTurn();
	local strings = Game.GetGossipManager():GetRecentVisibleGossipStrings( current - 100, localId, selId );
	for _, entry in ipairs( strings or {} ) do
		if entry[1] ~= nil then table.insert( list, { turn = entry[2], text = DiplomacyIntel.Clean( entry[1] ) } ); end
	end
	return list;
end

-- The snapshot for one civilization. Each group is gathered on its own: a failure logs and leaves the group out.
function DiplomacyIntel.Gather( playerId:number )
	local snap:table = {};
	local localId:number = Game.GetLocalPlayer();
	local sel:table = Players[ playerId ];
	if sel == nil or localId == nil or localId < 0 or playerId == localId then return snap; end
	local function Try( field:string, fn )
		local ok:boolean, result = pcall( fn );
		if ok then snap[ field ] = result; else print( "DiplomacyIntel gather error (" .. field .. "): " .. tostring( result ) ); end
	end
	Try( "relationship", function() return GatherRelationship( localId, sel, playerId ); end );
	Try( "agendas", function() return GatherAgendas( localId, sel, playerId ); end );
	Try( "agreements", function() return GatherAgreements( localId, sel, playerId, snap.relationship ); end );
	Try( "relations", function() return GatherRelations( localId, sel, playerId ); end );
	Try( "access", function() return GatherAccess( localId, playerId ); end );
	Try( "gossip", function() return GatherGossip( localId, playerId ); end );
	return snap;
end

-- The items of the intel report on this civilization.
function DiplomacyIntel.Items( playerId:number )
	return DiplomacyIntel.BuildItems( DiplomacyIntel.Gather( playerId ) );
end

function DiplomacyIntel.Summary( playerId:number )
	return DiplomacyIntel.SummaryText( DiplomacyIntel.Gather( playerId ) );
end

-- World relations among the civilizations the local player has met (and the player): the states the game shows as icons.
function DiplomacyIntel.GatherWorld()
	local world:table = { wars = {}, alliances = {}, denunciations = {} };
	local localId:number = Game.GetLocalPlayer();
	local ids:table = { localId };
	for _, other in ipairs( PlayerManager.GetAliveMajors() ) do
		local id:number = other:GetID();
		if id ~= localId and Players[ localId ]:GetDiplomacy():HasMet( id ) then table.insert( ids, id ); end
	end
	for i = 1, #ids do
		for j = i + 1, #ids do
			local a:number, b:number = ids[ i ], ids[ j ];
			local pa:table, pb:table = Players[ a ], Players[ b ];
			if a == localId or pa:GetDiplomacy():HasMet( b ) then
				local rel:table = { a = ( a == localId ) and "You" or CivName( a ), b = CivName( b ), youA = ( a == localId ) };
				local kinds:table = {};
				if pa:GetDiplomacy():IsAtWarWith( b ) then kinds.war = true; end
				for _, pair in ipairs( { { pa, b }, { pb, a } } ) do
					local row:table = GameInfo.DiplomaticStates[ pair[1]:GetDiplomaticAI():GetDiplomaticStateIndex( pair[2] ) ];
					if row ~= nil and RelationValid( row.StateType, not ( pa:IsAI() or pb:IsAI() ) ) then
						local kind = KIND_OF_STATE[ row.StateType ];
						if kind ~= nil then kinds[ kind ] = true; end
					end
				end
				if kinds.war then
					table.insert( world.wars, rel );
				elseif kinds.allied then
					table.insert( world.alliances, { a = rel.a, b = rel.b, youA = rel.youA, kind = "allied" } );
				elseif kinds.friend then
					table.insert( world.alliances, { a = rel.a, b = rel.b, youA = rel.youA, kind = "friend" } );
				end
				if kinds.denounced and not kinds.war then table.insert( world.denunciations, rel ); end
			end
		end
	end
	return world;
end

function DiplomacyIntel.WorldItems()
	local ok:boolean, world = pcall( DiplomacyIntel.GatherWorld );
	if not ok then
		print( "DiplomacyIntel world error: " .. tostring( world ) );
		world = { wars = {}, alliances = {}, denunciations = {} };
	end
	return DiplomacyIntel.WorldBuild( world );
end
