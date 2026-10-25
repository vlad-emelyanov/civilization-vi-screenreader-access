-- Plot descriptions for the screen reader: short and detailed text for one map plot, and "3 tiles north-east"
-- style direction/distance words between two plots. Pure functions returning strings; the caller speaks them.
-- Names come from the game's own text (GameInfo + Locale.Lookup) wherever the game has it.
--------------------------------------------------------------

local ROOT3_2:number = 0.8660254;	-- row height of the hex grid in units of the plot width

-- ===========================================================================
--	Helpers
-- ===========================================================================

-- Lower case a localized name, keeping the first letter as the game wrote it unless asked otherwise.
local function _Lower( s:string )
	return string.lower(s);
end

local function _Plural( n:number, one:string, many:string )
	if n == 1 then return one; end
	return many;
end

-- Visibility of a plot for the local player: "unexplored", "fogged" or "visible".
function PlotDescription_GetVisibility( plot:table )
	local localPlayer:number = Game.GetLocalPlayer();
	if localPlayer == nil or localPlayer == -1 then return "visible"; end
	local vis:table = PlayersVisibility[localPlayer];
	if vis == nil then return "unexplored"; end
	local index:number = plot:GetIndex();
	if not vis:IsRevealed(index) then return "unexplored"; end
	if not vis:IsVisible(index) then return "fogged"; end
	return "visible";
end

local function _CivName( playerId:number )
	local config:table = PlayerConfigurations[playerId];
	if config == nil then return ""; end
	local name:string = Locale.Lookup(config:GetCivilizationShortDescription());
	if name == nil or name == "" then
		name = Locale.Lookup("LOC_TOOLTIP_PLAYER_ID", playerId);
	end
	return name;
end

-- ===========================================================================
--	Direction and distance between two plots
-- ===========================================================================

-- Compass direction (localized, lower case) from plot A to plot B, or nil when they are the same plot.
-- Uses the real hex geometry (odd rows are shifted half a plot to the east) and the shorter way around a wrapping map.
function PlotDescription_GetDirectionWord( x1:number, y1:number, x2:number, y2:number )
	if x1 == x2 and y1 == y2 then return nil; end
	local width:number, height:number = Map.GetGridSize();
	local dx:number = (x2 + ((y2 % 2) * 0.5)) - (x1 + ((y1 % 2) * 0.5));
	if Map.IsWrapX() then
		if dx > width / 2 then dx = dx - width; elseif dx < -width / 2 then dx = dx + width; end
	end
	local dy:number = (y2 - y1) * ROOT3_2;
	local angle:number = math.deg(math.atan2(dy, dx));	-- 0 = east, 90 = north
	if angle < 0 then angle = angle + 360; end
	local sector:number = math.floor((angle + 22.5) / 45) % 8;
	local names:table = {
		[0] = "LOC_DIRECTION_EAST", [1] = "LOC_DIRECTION_NORTH_EAST", [2] = "LOC_DIRECTION_NORTH", [3] = "LOC_DIRECTION_NORTH_WEST",
		[4] = "LOC_DIRECTION_WEST", [5] = "LOC_DIRECTION_SOUTH_WEST", [6] = "LOC_DIRECTION_SOUTH", [7] = "LOC_DIRECTION_SOUTH_EAST",
	};
	return _Lower(Locale.Lookup(names[sector]));
end

-- "3 tiles north-east" / "1 tile west" / nil for the same plot.
function PlotDescription_GetRelative( fromPlot:table, toPlot:table )
	if fromPlot == nil or toPlot == nil then return nil; end
	local x1:number, y1:number = fromPlot:GetX(), fromPlot:GetY();
	local x2:number, y2:number = toPlot:GetX(), toPlot:GetY();
	local direction:string = PlotDescription_GetDirectionWord(x1, y1, x2, y2);
	if direction == nil then return nil; end
	local distance:number = Map.GetPlotDistance(x1, y1, x2, y2);
	return distance .. " " .. _Plural(distance, "tile", "tiles") .. " " .. direction;
end

-- Danger refusals ("Cannot automate exploration: Danger"): the engine does not say what the danger is.
-- Pure wording: "Danger" + ", Barbarian Galley 1 tile east". Other reasons and no enemy: unchanged.
function PlotDescription_DangerReason( reason:string, enemyName:string, relative:string )
	if reason == nil or enemyName == nil or enemyName == "" then return reason; end
	if string.find( string.lower( reason ), "danger", 1, true ) == nil then return reason; end
	return reason .. ", " .. enemyName .. ( ( relative ~= nil and relative ~= "" ) and ( " " .. relative ) or "" );
end

-- The nearest visible barbarian / at-war unit within radius tiles of the unit: its name and relative position
-- ("Barbarian Galley", "1 tile east"), or nil. Soldiers first, civilians only when no soldier is near.
function PlotDescription_NearestHostile( unit:table, radius:number )
	if unit == nil then return nil; end
	local localId:number = Game.GetLocalPlayer();
	local diplomacy:table = Players[localId]:GetDiplomacy();
	local ux:number, uy:number = unit:GetX(), unit:GetY();
	local width:number = Map.GetGridSize();
	local from:table = Map.GetPlot(ux, uy);
	local best:table = nil;
	for dy = -radius, radius do
		for dx = -radius, radius do
			local x:number = ux + dx;
			if Map.IsWrapX() then x = x % width; end
			local plot:table = Map.GetPlot(x, uy + dy);
			if plot ~= nil and Map.GetPlotDistance(ux, uy, plot:GetX(), plot:GetY()) <= radius then
				for _, other in ipairs(Units.GetUnitsInPlot(plot)) do
					local owner:number = other:GetOwner();
					local player:table = Players[owner];
					if owner ~= localId and player ~= nil and PlotDescription_IsUnitVisible(other)
							and (player:IsBarbarian() or (diplomacy ~= nil and diplomacy:IsAtWarWith(owner))) then
						local distance:number = Map.GetPlotDistance(ux, uy, plot:GetX(), plot:GetY());
						local soldier:number = (other:GetCombat() > 0 or other:GetRangedCombat() > 0) and 0 or 1;
						if best == nil or soldier < best.soldier or (soldier == best.soldier and distance < best.distance) then
							best = { unit = other, plot = plot, distance = distance, soldier = soldier };
						end
					end
				end
			end
		end
	end
	if best == nil then return nil; end
	return PlotDescription_GetUnitName(best.unit), PlotDescription_GetRelative(from, best.plot);
end

-- ===========================================================================
--	Parts of a description
-- ===========================================================================

-- True when the local player may see this unit right now (foreign units can be invisible: submarines, stealth, fog).
function PlotDescription_IsUnitVisible( unit:table )
	local localPlayer:number = Game.GetLocalPlayer();
	if unit == nil or localPlayer == nil or localPlayer == -1 then return false; end
	if unit:GetOwner() == localPlayer then return true; end
	local vis:table = PlayersVisibility[localPlayer];
	if vis == nil then return false; end
	return vis:IsVisible(unit:GetX(), unit:GetY()) and vis:IsUnitVisible(unit);
end

-- Name of a unit with its military formation: "Musketman corps" / "Musketman army", "Frigate fleet" / "Frigate armada".
-- Does not double the word when the name already ends with it.
function PlotDescription_FormationName( unit:table, name:string )
	local formation:number = unit:GetMilitaryFormation();
	if formation == nil or formation == MilitaryFormationTypes.STANDARD_FORMATION then return name; end
	local row:table = GameInfo.Units[ unit:GetType() ];
	local naval:boolean = ( row ~= nil and row.Domain == "DOMAIN_SEA" );
	local suffix:string;
	if formation == MilitaryFormationTypes.CORPS_FORMATION then
		suffix = naval and "fleet" or "corps";
	elseif formation == MilitaryFormationTypes.ARMY_FORMATION then
		suffix = naval and "armada" or "army";
	else
		return name;
	end
	if string.lower( string.sub( name, -#suffix ) ) == suffix then return name; end
	return name .. " " .. suffix;
end

-- "Warrior" for the local player's units, "Roman Warrior" / "Barbarian Warrior" for the others. The owner is
-- not repeated when the unit's own name already starts with it ("Barbarian Horseman").
function PlotDescription_GetUnitName( unit:table )
	local text:string = PlotDescription_FormationName(unit, Locale.Lookup(unit:GetName()));
	local owner:number = unit:GetOwner();
	if owner ~= Game.GetLocalPlayer() then
		local player:table = Players[owner];
		local prefix:string;
		if player ~= nil and player:IsBarbarian() then
			prefix = "Barbarian";
		else
			prefix = _CivName(owner);
		end
		if prefix ~= "" and string.lower(string.sub(text, 1, #prefix)) ~= string.lower(prefix) then
			text = prefix .. " " .. text;
		end
	end
	return text;
end

-- Name of a civilization (short form, e.g. "Rome").
function PlotDescription_GetCivName( playerId:number )
	return _CivName(playerId);
end

local function _UnitsText( plot:table, excludeUnitId:number )
	local parts:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	for _, unit in ipairs(Units.GetUnitsInPlot(plot)) do
		if (excludeUnitId == nil or unit:GetID() ~= excludeUnitId or unit:GetOwner() ~= localPlayer) and PlotDescription_IsUnitVisible(unit) then
			local text:string = PlotDescription_GetUnitName(unit);
			local damage:number = unit:GetDamage();
			if damage > 0 then
				text = text .. " " .. (unit:GetMaxDamage() - damage) .. " of " .. unit:GetMaxDamage() .. " health";
			end
			table.insert(parts, text);
		end
	end
	return parts;
end

local function _ResourceText( plot:table )
	local resourceType:number = plot:GetResourceType();
	if resourceType == nil or resourceType < 0 then return nil; end
	local row:table = GameInfo.Resources[resourceType];
	if row == nil then return nil; end
	local localPlayer:number = Game.GetLocalPlayer();
	if localPlayer ~= -1 then
		local resources:table = Players[localPlayer]:GetResources();
		if resources ~= nil and not resources:IsResourceVisible(row.Hash) then return nil; end
	end
	local text:string = Locale.Lookup(row.Name);
	if row.ResourceClassType ~= nil then
		local class:string = Locale.Lookup("LOC_" .. row.ResourceClassType .. "_NAME");
		if class ~= nil and class ~= "" and string.sub(class, 1, 4) ~= "LOC_" then
			text = text .. " (" .. _Lower(class) .. ")";
		end
	end
	return text;
end

local function _YieldsText( plot:table )
	local parts:table = {};
	for row in GameInfo.Yields() do
		local amount:number = plot:GetYield(row.Index);
		if amount ~= nil and amount > 0 then
			table.insert(parts, amount .. " " .. Locale.Lookup(row.Name));
		end
	end
	return parts;
end

-- Terrain, feature and water words, e.g. "Grassland (Hills), Woods, river, coastal".
local function _TerrainParts( plot:table )
	local parts:table = {};
	if plot:IsLake() then
		table.insert(parts, Locale.Lookup("LOC_TOOLTIP_LAKE"));
	else
		local terrain:table = GameInfo.Terrains[plot:GetTerrainType()];
		if terrain ~= nil then
			if terrain.TerrainType == "TERRAIN_COAST" then
				table.insert(parts, Locale.Lookup("LOC_TOOLTIP_COAST"));
			else
				table.insert(parts, Locale.Lookup(terrain.Name));
			end
		end
	end
	local featureType:number = plot:GetFeatureType();
	if featureType ~= nil and featureType >= 0 then
		local feature:table = GameInfo.Features[featureType];
		if feature ~= nil then table.insert(parts, Locale.Lookup(feature.Name)); end
	end
	return parts;
end

-- Barbarian Clans mode: the named clan (tribe) of a barbarian camp on this plot, or nil. Everything is guarded, so it is a
-- no-op without the mode (no Game.GetBarbarianManager / BarbarianTribes table / tribe method, or no tribe there: -1).
-- Returns the clan's display name ("Badger Claw") and its type ("Melee Open"), and the tribe index.
-- The tribe tables and the manager exist in the base game too, so the mode itself is the gate. Evaluated lazily and cached
-- (GameConfiguration may not be ready at include time; nothing is cached until it is).
local m_clanMode:boolean = nil;

function PlotDescription_ResetClanMode()
	m_clanMode = nil;
end

local function _ClanModeOn()
	if m_clanMode == nil then
		if GameConfiguration == nil or GameConfiguration.GetValue == nil then return false; end
		m_clanMode = ( GameConfiguration.GetValue("GAMEMODE_BARBARIAN_CLANS") == true );
	end
	return m_clanMode;
end

function PlotDescription_GetClan( plot:table )
	if plot == nil or Game == nil or Game.GetBarbarianManager == nil or not _ClanModeOn() then return nil; end
	if GameInfo.BarbarianTribes == nil or GameInfo.BarbarianTribeNames == nil then return nil; end
	if PlotDescription_GetVisibility(plot) == "unexplored" then return nil; end		-- the camp banner is hidden there too
	local ok:boolean, name, kind, tribe = pcall(function()
		local manager:table = Game.GetBarbarianManager();
		if manager == nil or manager.GetTribeIndexAtLocation == nil then return nil; end
		local index:number = manager:GetTribeIndexAtLocation(plot:GetX(), plot:GetY());
		if index == nil or index < 0 then return nil; end
		local nameRow:table = GameInfo.BarbarianTribeNames[ manager:GetTribeNameType(index) ];
		if nameRow == nil or nameRow.TribeDisplayName == nil then return nil; end
		local typeRow:table = GameInfo.BarbarianTribes[ manager:GetTribeType(index) ];
		local kindText:string = nil;
		if typeRow ~= nil and typeRow.Name ~= nil then kindText = Locale.Lookup(typeRow.Name); end
		return Locale.Lookup(nameRow.TribeDisplayName), kindText, index;
	end);
	if not ok or name == nil then return nil; end
	return name, kind, tribe;
end

-- "Badger Claw clan, Melee Open" (the type left out when the game has none), or nil.
function PlotDescription_GetClanPhrase( plot:table )
	local name:string, kind:string = PlotDescription_GetClan(plot);
	if name == nil then return nil; end
	local text:string = name .. " clan";
	if kind ~= nil and kind ~= "" then text = text .. ", " .. kind; end
	return text;
end

-- True when the clan camp can be treated with now: a clan there and the plot in view (the places list offers T for it).
function PlotDescription_CanTreatWithClan( plot:table )
	return PlotDescription_GetClan(plot) ~= nil and PlotDescription_GetVisibility(plot) == "visible";
end

local function _ImprovementParts( plot:table )
	local parts:table = {};
	local wonderType:number = plot:GetWonderType();
	if wonderType ~= nil and wonderType >= 0 then
		local row:table = GameInfo.Buildings[wonderType];
		if row ~= nil then table.insert(parts, Locale.Lookup(row.Name)); end
	end
	if not plot:IsCity() then
		local districtType:number = plot:GetDistrictType();
		if districtType ~= nil and districtType >= 0 then
			local row:table = GameInfo.Districts[districtType];
			if row ~= nil and not row.InternalOnly then
				local text:string = Locale.Lookup(row.Name);
				local city:table = Cities.GetPlotPurchaseCity(plot);
				local districts:table = (city ~= nil) and city:GetDistricts() or nil;
				if districts ~= nil then
					if districts:IsPillaged(districtType, plot:GetIndex()) then
						text = text .. " " .. Locale.Lookup("LOC_TOOLTIP_PLOT_PILLAGED_TEXT");
					elseif not districts:IsComplete(districtType, plot:GetIndex()) then
						text = text .. " " .. Locale.Lookup("LOC_TOOLTIP_PLOT_CONSTRUCTION_TEXT");
					end
				end
				table.insert(parts, text);
			end
		end
	end
	local improvementType:number = plot:GetImprovementType();
	if improvementType ~= nil and improvementType >= 0 then
		local row:table = GameInfo.Improvements[improvementType];
		if row ~= nil then
			local text:string = Locale.Lookup(row.Name);
			if plot:IsImprovementPillaged() then text = text .. " " .. Locale.Lookup("LOC_TOOLTIP_PLOT_PILLAGED_TEXT"); end
			table.insert(parts, text);
			local clan:string = PlotDescription_GetClanPhrase(plot);
			if clan ~= nil then table.insert(parts, clan); end
		end
	end
	return parts;
end

local function _OwnerText( plot:table )
	local owner:number = plot:GetOwner();
	if owner == nil or owner < 0 then return nil; end
	if owner == Game.GetLocalPlayer() then return "yours"; end
	return _CivName(owner);
end

-- ===========================================================================
--	Short description
-- ===========================================================================
-- options.excludeUnitId: leave this (own) unit out of the unit list (the selected unit's own plot).
-- Order: city, units, terrain/feature, resource, river/coast, improvement/district/wonder, owner, yields, fogged.
-- Fogged plots: owner, improvement and yields are spoken exactly as the game's own plot tooltip (PlotToolTip.lua)
-- shows them for revealed plots, so nothing is told that a sighted player would not see; units are only named while
-- the plot is visible.
function PlotDescription_GetShort( plot:table, options:table )
	if plot == nil then return "Edge of the map"; end
	options = options or {};
	local visibility:string = PlotDescription_GetVisibility(plot);
	if visibility == "unexplored" then return "Unexplored"; end

	local parts:table = {};

	-- City
	if plot:IsCity() then
		local city:table = Cities.GetCityInPlot(plot:GetX(), plot:GetY());
		if city ~= nil then
			local text:string = Locale.Lookup(city:GetName());
			if city:GetOwner() ~= Game.GetLocalPlayer() then
				text = text .. ", " .. _CivName(city:GetOwner()) .. " city";
			elseif city:IsCapital() then
				text = text .. ", capital";
			else
				text = text .. ", city";
			end
			table.insert(parts, text);
		end
	end

	-- Units (only what is visible right now)
	if visibility == "visible" then
		for _, text in ipairs(_UnitsText(plot, options.excludeUnitId)) do table.insert(parts, text); end
	end

	-- Terrain, feature, resource, rivers
	local terrain:table = _TerrainParts(plot);
	local resource:string = _ResourceText(plot);
	local line:table = {};
	for _, t in ipairs(terrain) do table.insert(line, t); end
	if resource ~= nil then table.insert(line, resource); end
	if plot:IsRiver() then table.insert(line, _Lower(Locale.Lookup("LOC_TOOLTIP_RIVER"))); end
	if plot:IsCoastalLand() then table.insert(line, "coastal"); end
	if plot:IsImpassable() then table.insert(line, _Lower(Locale.Lookup("LOC_TOOLTIP_PLOT_IMPASSABLE_TEXT"))); end
	table.insert(parts, table.concat(line, ", "));

	-- Improvement, district, wonder
	for _, text in ipairs(_ImprovementParts(plot)) do table.insert(parts, text); end

	-- Owner
	local owner:string = _OwnerText(plot);
	-- "yours" next to a foreign unit reads as if the unit were ours: say it is the territory
	if owner == "yours" and visibility == "visible" then
		for _, other in ipairs(Units.GetUnitsInPlot(plot)) do
			if other:GetOwner() ~= Game.GetLocalPlayer() then owner = "your territory"; break; end
		end
	end
	if owner ~= nil then table.insert(parts, owner); end

	-- Yields
	local yields:table = _YieldsText(plot);
	if #yields > 0 then table.insert(parts, table.concat(yields, " ")); end

	if visibility == "fogged" then table.insert(parts, "fogged"); end
	return table.concat(parts, ", ");
end

-- ===========================================================================
--	Detailed description (I key)
-- ===========================================================================
function PlotDescription_GetDetailed( plot:table, options:table )
	if plot == nil then return "Edge of the map"; end
	local visibility:string = PlotDescription_GetVisibility(plot);
	local parts:table = { PlotDescription_GetShort(plot, options) };
	if visibility == "unexplored" then
		table.insert(parts, "coordinates " .. plot:GetX() .. ", " .. plot:GetY());
		return table.concat(parts, ". ");
	end

	local facts:table = {};
	table.insert(facts, "coordinates " .. plot:GetX() .. ", " .. plot:GetY());

	if not plot:IsImpassable() and plot:GetMovementCost() > 0 then
		table.insert(facts, Locale.Lookup("LOC_TOOLTIP_MOVEMENT_COST", plot:GetMovementCost()));
	end
	if plot:IsRoute() then
		local route:table = GameInfo.Routes[plot:GetRouteType()];
		if route ~= nil then
			local text:string = Locale.Lookup(route.Name);
			if plot:IsRoutePillaged() then text = text .. " " .. Locale.Lookup("LOC_TOOLTIP_PLOT_PILLAGED_TEXT"); end
			table.insert(facts, text);
		end
	end
	local defense:number = plot:GetDefenseModifier();
	if defense ~= 0 then table.insert(facts, Locale.Lookup("LOC_TOOLTIP_DEFENSE_MODIFIER", defense)); end
	if plot:IsNWOfCliff() or plot:IsWOfCliff() or plot:IsNEOfCliff() then table.insert(facts, Locale.Lookup("LOC_TOOLTIP_CLIFF")); end

	if GameCapabilities.HasCapability("CAPABILITY_LENS_APPEAL") and not plot:IsWater() then
		for row in GameInfo.AppealHousingChanges() do
			if plot:GetAppeal() >= row.MinimumValue then
				table.insert(facts, Locale.Lookup("LOC_TOOLTIP_APPEAL", Locale.Lookup(row.Description), plot:GetAppeal()));
				break;
			end
		end
	end

	local continent:number = plot:GetContinentType();
	if continent ~= nil and continent >= 0 then
		local row:table = GameInfo.Continents[continent];
		if row ~= nil then table.insert(facts, Locale.Lookup("LOC_TOOLTIP_CONTINENT", row.Description)); end
	end

	local owner:number = plot:GetOwner();
	if owner ~= nil and owner >= 0 then
		local ownerCity:table = Cities.GetPlotPurchaseCity(plot);
		if ownerCity ~= nil then
			table.insert(facts, "territory of " .. Locale.Lookup(ownerCity:GetName()));
		end
	end
	if plot:GetWorkerCount() > 0 and plot:GetOwner() == Game.GetLocalPlayer() then
		table.insert(facts, "worked by " .. plot:GetWorkerCount() .. " " .. _Plural(plot:GetWorkerCount(), "citizen", "citizens"));
	end

	table.insert(parts, table.concat(facts, ", "));
	if PlotDescription_CanTreatWithClan(plot) then table.insert(parts, "Open it from the places list with T"); end
	return table.concat(parts, ". ");
end
