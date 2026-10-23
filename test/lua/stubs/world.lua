-- A small fake map for SettleScan / PlotDescription tests. stub("engine") must be loaded first.
--   local w = stub("world").new{ width = 12, height = 10, wrap = false }
--   w:set(x, y, { terrain = "water", river = true, ... })    -- defaults: revealed grass land, 2 food 1 production
--   w:city(playerId, x, y, "Rome")   w:unit(playerId, x, y, { combat = 10 })   w:install()
-- install() defines Map, Players, PlayersVisibility, GameInfo, UnitManager, Units and the other engine globals the
-- scan code touches.
local M = {}
M.__index = M

local TERRAINS = { "TERRAIN_GRASS", "TERRAIN_PLAINS", "TERRAIN_GRASS_HILLS", "TERRAIN_COAST", "TERRAIN_DESERT" }
local TERRAIN_INDEX = { grass = 0, plains = 1, hills = 2, water = 3, desert = 4 }

function M.new(opts)
	local self = setmetatable({}, M)
	self.width, self.height, self.wrap = opts.width or 12, opts.height or 10, opts.wrap or false
	self.plots, self.cities, self.units = {}, {}, {}
	self.at_war = {}
	self.resourceNames = {}		-- plot.resource = "Wheat" (+ plot.rclass = "bonus" | "luxury" | "strategic", default bonus)
	self.revealed_all = true
	for y = 0, self.height - 1 do
		for x = 0, self.width - 1 do
			self.plots[y * self.width + x] = { x = x, y = y, terrain = "grass", food = 2, prod = 1, owner = -1 }
		end
	end
	return self
end

function M:set(x, y, props) for k, v in pairs(props) do self.plots[y * self.width + x][k] = v end end
function M:city(owner, x, y, name)
	table.insert(self.cities, { owner = owner, x = x, y = y, name = name, id = #self.cities + 1 })
	self.plots[y * self.width + x].city = true
end
function M:unit(owner, x, y, props)
	local u = props or {}
	u.owner, u.x, u.y, u.id = owner, x, y, 100 + #self.units
	table.insert(self.units, u)
	return u
end

local function flatDist(x1, y1, x2, y2)
	local q1 = x1 - (y1 - (y1 % 2)) / 2
	local q2 = x2 - (y2 - (y2 % 2)) / 2
	local dq, dr = q2 - q1, y2 - y1
	return (math.abs(dq) + math.abs(dr) + math.abs(dq + dr)) / 2
end

function M:install()
	local world = self
	local w, h = self.width, self.height

	local function plotObject(p)
		if p.object then return p.object end
		local o = {}
		function o:GetX() return p.x end
		function o:GetY() return p.y end
		function o:GetIndex() return p.y * w + p.x end
		function o:IsWater() return p.terrain == "water" end
		function o:IsLake() return p.lake == true end
		function o:IsCity() return p.city == true end
		function o:IsNaturalWonder() return p.wonder == true end
		function o:IsMountain() return p.mountain == true end
		function o:IsImpassable() return p.impassable == true end
		function o:IsRiver() return p.river == true end
		function o:IsFreshWater() return p.river == true or p.lake == true end
		function o:IsCoastalLand()
			if p.terrain == "water" then return false end
			for dx = -1, 1 do
				for dy = -1, 1 do
					local q = world.plots[(p.y + dy) * w + (p.x + dx)]
					if q and q.terrain == "water" and (dx ~= 0 or dy ~= 0) then return true end
				end
			end
			return false
		end
		function o:GetOwner() return p.owner end
		function o:GetResourceType()
			if not p.resource then return -1 end
			for i, name in ipairs(world.resourceNames) do if name == p.resource then return i end end
			table.insert(world.resourceNames, p.resource)
			return #world.resourceNames
		end
		function o:GetFeatureType() return -1 end
		function o:GetImprovementType() return p.improvement or -1 end
		function o:IsImprovementPillaged() return p.pillaged == true end
		function o:GetDistrictType() return p.district or -1 end
		function o:GetTerrainType() return TERRAIN_INDEX[p.terrain] end
		function o:GetYield(i) if i == 0 then return p.food end return p.prod end
		p.object = o
		return o
	end

	GlobalParameters = { CITY_MIN_RANGE = 3 }
	Map = {
		GetGridSize = function() return w, h end,
		IsWrapX = function() return world.wrap end,
		GetPlot = function(x, y)
			if world.wrap then x = x % w end
			if x < 0 or x >= w or y < 0 or y >= h then return nil end
			return plotObject(world.plots[y * w + x])
		end,
		GetPlotByIndex = function(i) local p = world.plots[i]; return p and plotObject(p) or nil end,
		GetPlotDistance = function(x1, y1, x2, y2)
			local d = flatDist(x1, y1, x2, y2)
			if world.wrap then d = math.min(d, flatDist(x1, y1, x2 + w, y2), flatDist(x1, y1, x2 - w, y2)) end
			return d
		end,
	}

	GameInfo = {
		Yields = { YIELD_FOOD = { Index = 0 }, YIELD_PRODUCTION = { Index = 1 } },
		Terrains = setmetatable({}, { __index = function(_, i) return TERRAINS[i + 1] and { TerrainType = TERRAINS[i + 1] } end }),
		Features = {}, Improvements = {},
		Resources = setmetatable({}, { __index = function(_, id)
			local name = world.resourceNames[id]
			if not name then return nil end
			local class = "bonus"
			for _, p in pairs(world.plots) do if p.resource == name then class = p.rclass or "bonus"; break end end
			return { Hash = id, Name = name, ResourceType = "RESOURCE_" .. string.upper(name), ResourceClassType = "RESOURCECLASS_" .. string.upper(class) }
		end }),
	}

	PlayersVisibility = { [0] = {
		IsRevealed = function(_, index) local p = world.plots[index]; return world.revealed_all and not p.hidden end,
		IsVisible = function(_, a, b)
			local p = b and world.plots[b * w + a] or world.plots[a]
			return p ~= nil and not p.fogged and not p.hidden
		end,
		IsUnitVisible = function() return true end,
	} }

	local function unitObject(u)
		return {
			GetID = function() return u.id end, GetX = function() return u.x end, GetY = function() return u.y end,
			GetOwner = function() return u.owner end, GetMovesRemaining = function() return u.moves or 2 end,
			GetCombat = function() return u.combat or 0 end, GetRangedCombat = function() return u.ranged or 0 end,
			GetName = function() return u.name or "LOC_UNIT_SETTLER_NAME" end,
			GetUnitType = function() return u.unitType or 0 end,
		}
	end
	local function playerObject(id)
		-- the player's cities, computed on use because tests add cities after install()
		local function members()
			local list = {}
			for _, c in ipairs(world.cities) do if c.owner == id then table.insert(list, c) end end
			return list
		end
		local function cityObject(c)
			return { GetX = function() return c.x end, GetY = function() return c.y end, GetID = function() return c.id end,
				GetName = function() return c.name end }
		end
		return {
			IsAlive = function() return true end,
			IsBarbarian = function() return id == 63 end,
			GetCities = function() return {
				GetCount = function() return #members() end,
				Members = function() local list = {}; for _, c in ipairs(members()) do list[#list + 1] = cityObject(c) end; return ipairs(list) end,
				FindID = function(_, cid) for _, c in ipairs(members()) do if c.id == cid then return cityObject(c) end end end,
			} end,
			GetUnits = function() return {
				Members = function()
					local list = {}
					for _, u in ipairs(world.units) do if u.owner == id then list[#list + 1] = unitObject(u) end end
					return ipairs(list)
				end,
			} end,
			GetDiplomacy = function() return {
				IsAtWarWith = function(_, other) return world.at_war[other] == true end,
				HasMet = function() return true end,
			} end,
			GetResources = function() return { IsResourceVisible = function() return true end } end,
			GetGrandStrategicAI = function() return nil end,
		}
	end
	Players = setmetatable({}, { __index = function(t, id)
		if type(id) == "number" and id >= 0 and id < 64 then
			local p = playerObject(id); rawset(t, id, p); return p
		end
	end })
	PlayerConfigurations = setmetatable({}, { __index = function(_, id)
		return { GetCivilizationShortDescription = function() return "LOC_CIV_" .. id end }
	end })
	Units = { GetUnitsInPlot = function() return {} end }
	UnitOperationTypes = { FOUND_CITY = "FOUND_CITY" }
	UnitManager = {
		CanStartOperation = function() return true end,
		-- every plot is one turn away unless the test says otherwise (world.unreachable[index] = true)
		GetMoveToPathEx = function(_, index)
			if world.unreachable and world.unreachable[index] then return nil end
			return { plots = { 0, index }, turns = { 1 } }
		end,
	}
	world.fakeUnit = unitObject
	return world
end

return M
