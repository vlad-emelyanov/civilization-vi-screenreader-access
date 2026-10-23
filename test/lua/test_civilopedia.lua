-- Civilopedia/CivilopediaSupport.lua: page recording by the layout helpers and the keyboard flow (engine stubbed)
local Strings = stub("engine")
Keys.VK_TAB = 9; Keys.VK_BACK = 8; Keys.F = 70; Keys.VK_F9 = 120

-- an object that accepts any call, index and arithmetic (stands in for every control / instance manager)
local function Any()
	local mt = {}
	local obj = setmetatable({}, mt)
	mt.__index = function() return obj end
	mt.__call = function() return obj end
	mt.__add = function() return 0 end
	mt.__sub = function() return 0 end
	return obj
end
local any = Any()
Controls = any; Mouse = any; UIManager = any; PopupPriority = any; Search = any; LuaEvents = any; Events = any
local MakeInput = Input
Input = setmetatable({ GetActionId = function() return 1 end }, { __call = function(_, spec) return MakeInput(spec) end })
InstanceManager = { new = function() return { GetInstance = function() return Any() end, ResetInstances = function() end, DestroyInstances = function() end } end }
GameCapabilities = { HasCapability = function() return true end }
ContextPtr = { IsHidden = function() return false end, SetUpdate = function() end, SetInputHandler = function() end, SetShutdown = function() end }
UI.GetColorValue = function() return 0 end
UI.PlaySound = function() end
Locale.StripTags = function(s) return s end
Locale.ToUpper = function(s) return s end

local realInclude = include
include = function(name, wildcard) pcall(realInclude, name) end
local src = sr_read(ROOT .. "/ScreenReaderAccess/Assets/UI/Civilopedia/CivilopediaSupport.lua")
local chunk, err = loadstring(src, "@CivilopediaSupport.lua")
if not chunk then error(err, 0) end
chunk()

Strings.LOC_STATS = "Traits"; Strings.LOC_UPGRADES = "Upgrades to"; Strings.LOC_DESC = "Description"

-- data the game would read from the database
_Sections = { { SectionId = "UNITS", TabName = "Units" }, { SectionId = "CONCEPTS", TabName = "Concepts" } }
local function page(id, name, group)
	return { SectionId = "UNITS", PageId = id, TabName = name, Title = name, PageLayoutId = "Unit", PageGroupId = group }
end
_PagesBySection = { UNITS = { page("UNIT_WARRIOR", "Warrior", "G1"), page("UNIT_SPEARMAN", "Spearman", "G1") },
	CONCEPTS = { { SectionId = "CONCEPTS", PageId = "C1", TabName = "Cities", Title = "Cities", PageLayoutId = "Unit" } } }
_PageGroupsBySection = { UNITS = { { PageGroupId = "G1", TabName = "Ancient era" } } }
_PagesById = {}
for sid, pages in pairs(_PagesBySection) do for _, p in ipairs(pages) do _PagesById[sid .. "::" .. p.PageId] = p end end
_PageLayoutScriptTemplates = { Unit = "Unit" }
PageLayouts["Unit"] = function(p)
	SetPageHeader(p.Title)
	AddRightColumnStatBox("LOC_STATS", function(s)
		s:AddHeader("LOC_UPGRADES")
		s:AddIconLabel({ "ICON_X", "Spearman", "UNIT_SPEARMAN" }, "Spearman")
		s:AddIconNumberLabel({ "ICON_S", nil, "COMBAT_5" }, 20, "Melee Strength")
	end)
	AddRightColumnStatBox("LOC_EMPTY", function(s) s:AddSeparator() end)
	AddChapter("LOC_DESC", "A fighter.")
end
NavigateTo = function(sec, pg)
	_CurrentSectionId, _CurrentPageId = sec, pg
	local p = GetPage(sec, pg)
	ResetPageContent()
	PageLayouts[_PageLayoutScriptTemplates[p.PageLayoutId]](p)
end

local function press(key, spec)
	ClearPrinted()
	spec = spec or {}
	local handled = OnInputHandler(Input{ key = key, up = false, ctrl = spec.ctrl })
	OnInputHandler(Input{ key = key, up = true, ctrl = spec.ctrl })
	return handled
end

test("opens on the section list, enters a page, follows a link and goes back", function()
	ClearPrinted()
	OnOpenCivilopedia()
	listeq(Spoken(), { "Civilopedia. Units, 1 of 2 sections", "Ancient era: Warrior, 1 of 2" })
	press(Keys.VK_RETURN)
	listeq(Spoken(), { "Warrior page, 6 lines. Traits" })
	press(Keys.VK_DOWN); press(Keys.VK_DOWN)
	listeq(Spoken(), { "Link: Spearman, 3 of 6" })
	press(Keys.VK_SPACE)
	listeq(Spoken(), { "Spearman. Melee Strength 20. Description. A fighter." })
	press(Keys.VK_RETURN)
	listeq(Spoken(), { "Spearman page, 6 lines. Traits" })
	press(Keys.VK_BACK)
	listeq(Spoken(), { "Back to Warrior", "Link: Spearman, 3 of 6" })
	press(Keys.VK_ESCAPE)
	listeq(Spoken(), { "Back to Units.", "Ancient era: Warrior, 1 of 2" })
	press(Keys.VK_ESCAPE)
	listeq(Spoken(), { "Civilopedia closed" })
end)

test("empty stat boxes leave no line, stat rows read caption and value", function()
	OnOpenCivilopedia("UNITS", "UNIT_WARRIOR")
	press(Keys.VK_END)
	listeq(Spoken(), { "A fighter., 6 of 6" })
	press(Keys.VK_UP)
	listeq(Spoken(), { "Description, 5 of 6" })
	press(Keys.VK_UP)
	listeq(Spoken(), { "Melee Strength 20, 4 of 6" })
end)

test("Tab switches sections, opened on a page starts in page view, F9 passes through", function()
	OnOpenCivilopedia()
	press(Keys.VK_TAB)
	listeq(Spoken(), { "Concepts, 2 of 2 sections", "Cities, 1 of 1" })
	eq(press(Keys.VK_F9), false)
	OnOpenCivilopedia("UNITS", "UNIT_SPEARMAN")
	local handled = press(Keys.VK_DOWN)
	eq(handled, true)
	listeq(Spoken(), { "Upgrades to, 2 of 6" })
end)
