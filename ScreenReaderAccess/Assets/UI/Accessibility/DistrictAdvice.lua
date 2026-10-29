-- ===========================================================================
--	DistrictAdvice: which district fits a city best, and where (docs/features.md, City report).
--
--	Pure wording (unit tested, test/lua/test_districtadvice.lua):
--	  DistrictAdvice_Line( entries ) -> "District spots: Campus plus 3 (2 tiles north-east), Holy Site plus 2. Theater Square: no spot with a bonus"
--	  DistrictAdvice_BestSpot( entry ) -> "Best spot: plus 3 Science, 2 tiles north-east"
--	entry: { name, total (adjacency points, 0 = none), adjacency = { "plus 3 Science" }, relative, owned, tileCost, removes = {} }
--
--	Engine side (cached per city, turn and district count; computed only when asked, never on panel open):
--	  DistrictAdvice_Entry( city, hash ) -> entry or nil (nil = no spot at all)
--	  DistrictAdvice_Spots( city ) -> entries of the districts the city can build now (not built, not replaced), best first
--	Cost: one PlacementScan_Scan per district = one BUILD target query plus, per tile, adjacency yields (6 calls) and a
--	CanStartOperation for owned tiles. Typically 5-8 districts x 15-40 tiles; the cache makes later calls free.
-- ===========================================================================

include( "ScreenReader" );

-- ---------------------------------------------------------------------------
-- Wording
-- ---------------------------------------------------------------------------
local function _Sorted( entries:table )
	local sorted:table = {};
	for i, e in ipairs( entries ) do sorted[i] = e; end
	table.sort( sorted, function( a, b )
		if ( a.total or 0 ) ~= ( b.total or 0 ) then return ( a.total or 0 ) > ( b.total or 0 ); end
		return ( a.name or "" ) < ( b.name or "" );
	end );
	return sorted;
end

-- The cheapest unmet requirement among districts that cannot be built now: blockers = { { name, reasons = { "Requires Population
-- of 7 or greater" } } } -> "Campus needs population 7" (a population need ranks by its number, any other reason last).
function DistrictAdvice_NextRequirement( blockers:table )
	local best:string, bestRank:number = nil, 1e9;
	for _, b in ipairs( blockers or {} ) do
		for _, reason in ipairs( b.reasons or {} ) do
			local need:string = string.match( string.lower( reason ), "population of (%d+)" );
			local text:string, rank:number;
			if need ~= nil then text, rank = b.name .. " needs population " .. need, tonumber( need );
			else text, rank = b.name .. ": " .. string.gsub( reason, "^[Rr]equires ", "" ), 1000; end
			if rank < bestRank then best, bestRank = text, rank; end
		end
	end
	return best;
end

-- withWhere: add the location of every district, not only of the best one
function DistrictAdvice_Line( entries:table, withWhere:boolean )
	local sorted:table = _Sorted( entries );
	local nextReq:string = DistrictAdvice_NextRequirement( entries.blockers );
	local bonus:table = {};
	local plain:table = {};
	for _, e in ipairs( sorted ) do
		if ( e.total or 0 ) > 0 then
			local text:string = e.name .. " plus " .. e.total;
			if ( withWhere or #bonus == 0 ) and e.relative ~= nil and e.relative ~= "" then text = text .. " (" .. e.relative .. ")"; end
			table.insert( bonus, text );
		else
			table.insert( plain, e.name );
		end
	end
	if #bonus == 0 and #plain == 0 then
		if nextReq ~= nil then return "District spots: none can be built now. Next: " .. nextReq; end
		return "District spots: none can be built now";
	end
	local text:string = "District spots: ";
	if #bonus > 0 then text = text .. table.concat( bonus, ", " ); end
	if #plain > 0 then
		if #bonus > 0 then text = text .. ". "; end
		text = text .. table.concat( plain, ", " ) .. ": no spot with a bonus";
	end
	return text;
end

function DistrictAdvice_BestSpot( entry:table )
	if entry == nil then return "Best spot: none available now"; end
	local parts:table = {};
	if entry.adjacency ~= nil and #entry.adjacency > 0 then
		table.insert( parts, table.concat( entry.adjacency, ", " ) );
	else
		table.insert( parts, "no adjacency bonus" );
	end
	if entry.relative ~= nil and entry.relative ~= "" then table.insert( parts, entry.relative ); end
	if entry.owned == false and entry.tileCost ~= nil and entry.tileCost > 0 then table.insert( parts, "tile costs " .. entry.tileCost .. " gold" ); end
	if entry.removes ~= nil and #entry.removes > 0 then table.insert( parts, "removes " .. table.concat( entry.removes, ", " ) ); end
	return "Best spot: " .. table.concat( parts, ", " );
end

-- ---------------------------------------------------------------------------
-- Engine side
-- ---------------------------------------------------------------------------
local m_cache:table = {};		-- cityKey -> { stamp, entries = { hash -> entry|false }, spots }

local function _Stamp( city:table )
	local count:number = 0;
	local ok:boolean, districts = pcall( function() return city:GetDistricts():GetNumDistricts(); end );
	if ok and districts ~= nil then count = districts; end
	local gold:number = 0;
	local plots:number = 0;
	local buildings:number = 0;
	pcall( function() gold = math.floor( Players[ city:GetOwner() ]:GetTreasury():GetGoldBalance() ); end );
	pcall( function() plots = #city:GetOwnedPlots(); end );
	pcall( function() buildings = city:GetBuildings():GetNumBuildings(); end );
	return table.concat( { Game.GetCurrentGameTurn(), count, gold, plots, buildings }, ":" );
end

local function _Slot( city:table )
	local key:string = city:GetOwner() .. ":" .. city:GetID();
	local stamp:string = _Stamp( city );
	local slot:table = m_cache[ key ];
	if slot == nil or slot.stamp ~= stamp then
		slot = { stamp = stamp, entries = {} };
		m_cache[ key ] = slot;
	end
	return slot;
end

function DistrictAdvice_Entry( city:table, hash:number )
	local slot:table = _Slot( city );
	local cached = slot.entries[ hash ];
	if cached ~= nil then return cached or nil; end
	local entry = nil;
	local ok:boolean, err = pcall( function()
		local scan:table = PlacementScan_Scan( city, "district", hash );
		local best:table = scan.best;
		if best ~= nil then
			entry = { name = scan.name, hash = hash, total = best.total or 0, adjacency = best.adjacency, relative = best.relative,
				owned = best.owned, tileCost = best.tileCost, removes = best.removes, spots = #scan.list };
		end
	end );
	if not ok then print( "DistrictAdvice error: " .. tostring( err ) ); end
	slot.entries[ hash ] = entry or false;
	return entry;
end

-- Districts worth listing: producible now, one per city, not built yet, not a base district that the civ's own replaces.
local function _Candidates( city:table )
	local queue:table = city:GetBuildQueue();
	local districts:table = city:GetDistricts();
	local result:table = {};
	for row in GameInfo.Districts() do
		if row.OnePerCity and not row.InternalOnly and not row.CityCenter and not districts:HasDistrict( row.Index )
				and queue:CanProduce( row.Hash, true ) then
			local replaced:boolean = false;
			for rep in GameInfo.DistrictReplaces() do
				if rep.ReplacesDistrictType == row.DistrictType then
					local other:table = GameInfo.Districts[ rep.CivUniqueDistrictType ];
					if other ~= nil and queue:CanProduce( other.Hash, true ) then replaced = true; end
				end
			end
			if not replaced then table.insert( result, row ); end
		end
	end
	return result;
end

-- Why the districts in the production list cannot be built now: { { name, reasons = { text } } } (the failure reasons the
-- production panel shows in the tooltip; "no suitable location" is not a requirement and is left out).
local function _Blockers( city:table )
	local list:table = {};
	local ok:boolean, err = pcall( function()
		local queue:table = city:GetBuildQueue();
		for _, row in ipairs( _Candidates( city ) ) do
			local can, results = queue:CanProduce( row.Hash, false, true );
			if not can and results ~= nil then
				local reasons:table = {};
				for _, text in ipairs( results[ CityOperationResults.FAILURE_REASONS ] or {} ) do
					local clean:string = string.gsub( CleanTextForSpeech( Locale.Lookup( text ) ), "[%.%s]+$", "" );
					if clean ~= "" and string.find( text, "NO_SUITABLE_LOCATION", 1, true ) == nil then table.insert( reasons, clean ); end
				end
				if #reasons > 0 then table.insert( list, { name = Locale.Lookup( row.Name ), reasons = reasons } ); end
			end
		end
	end );
	if not ok then print( "DistrictAdvice blockers error: " .. tostring( err ) ); end
	return list;
end

function DistrictAdvice_Spots( city:table )
	local slot:table = _Slot( city );
	if slot.spots ~= nil then return slot.spots; end
	local spots:table = {};
	local ok:boolean, err = pcall( function()
		for _, row in ipairs( _Candidates( city ) ) do
			local entry:table = DistrictAdvice_Entry( city, row.Hash );
			if entry ~= nil then table.insert( spots, entry ); end
		end
	end );
	if not ok then print( "DistrictAdvice_Spots error: " .. tostring( err ) ); end
	slot.spots = _Sorted( spots );
	if #spots == 0 then slot.spots.blockers = _Blockers( city ); end
	return slot.spots;
end

