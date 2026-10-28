-- Test harness, loaded by util/luatest.py into a fresh Lua 5.1 state per test file.
T = { passed = 0, failed = 0 }
local realPrint = print
local ACCESS = ROOT .. "/ScreenReaderAccess/Assets/UI/Accessibility/"

-- print() of the game goes to Lua.log; tests read it back from Printed
Printed = {}
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(Printed, table.concat(parts, "\t"))
end
function ClearPrinted() Printed = {} end
-- the text part of every "#SCREENREADER - x" / "#SCREENREADER[NOINTERRUPT] - x" line printed so far
-- Spoken(): keyboard wording ([KEY:kb] / [KEY:kb|button] tokens expanded to kb, [PAD:x] removed, like util/civctl.ps1); SpokenRaw(): unexpanded
function SpokenRaw()
	local out = {}
	for _, line in ipairs(Printed) do
		local text = line:match("^#SCREENREADER%[?[%u]*%]? %- (.*)$")
		if text then table.insert(out, text) end
	end
	return out
end
function Spoken()
	local out = {}
	for i, text in ipairs(SpokenRaw()) do
		out[i] = text:gsub("%[PAD:[^%]]*%]", ""):gsub("%[KEY:([^%]|]+)|?[^%]]*%]", "%1")
	end
	return out
end

-- include("X") loads Accessibility/X.lua once, like the game does per context
local included = {}
function include(name)
	if included[name] then return end
	included[name] = true
	local path = ACCESS .. name .. ".lua"
	local chunk, err = loadstring(sr_read(path), "@" .. path)
	if not chunk then error(err, 0) end
	chunk()
end

function stub(name)
	local path = ROOT .. "/test/lua/stubs/" .. name .. ".lua"
	local chunk, err = loadstring(sr_read(path), "@" .. path)
	if not chunk then error(err, 0) end
	return chunk()
end

-- Loads the n-th block between "-- Begin ScreenReaderAccess mod change" and "-- End ..." of a game-file copy
-- (so its mod code can be tested without the rest of the game screen).
function load_mod_block(relpath, n)
	local src = sr_read(ROOT .. "/ScreenReaderAccess/" .. relpath)
	local pos = 1
	for i = 1, n or 1 do
		local s, e = src:find("%-%- Begin ScreenReaderAccess mod change", pos)
		assert(s, "no mod block " .. i .. " in " .. relpath)
		local _, e2 = src:find("%-%- End ScreenReaderAccess mod change", e)
		assert(e2, "unterminated mod block in " .. relpath)
		if i == (n or 1) then
			local chunk, err = loadstring(src:sub(e + 1, e2), "@" .. relpath)
			if not chunk then error(err, 0) end
			chunk()
			return
		end
		pos = e2
	end
end

function test(name, fn)
	local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end)
	if ok then
		T.passed = T.passed + 1
	else
		T.failed = T.failed + 1
		realPrint("  FAIL " .. name .. "\n    " .. tostring(err):gsub("\n", "\n    "))
	end
end

local function show(v)
	if type(v) == "string" then return string.format("%q", v) end
	return tostring(v)
end
-- SRKey for tests that load code blocks without ScreenReader.lua (the real one replaces this when included)
if SRKey == nil then
	function SRKey(keyboard, button)
		if button ~= nil and button ~= "" then return "[KEY:" .. keyboard .. "|" .. button .. "]" end
		return "[KEY:" .. keyboard .. "]"
	end
end
if SRPadHint == nil then
	function SRPadHint(text) return "[PAD:" .. text .. "]" end
end
-- a spoken-text token [KEY:kb|button] in the actual value is compared as its keyboard wording unless the expected text has tokens itself
local function kbwording(actual, expected)
	if type(actual) == "string" and type(expected) == "string" and not expected:find("[KEY:", 1, true) and not expected:find("[PAD:", 1, true) then
		return (actual:gsub("%[PAD:[^%]]*%]", ""):gsub("%[KEY:([^%]|]+)|?[^%]]*%]", "%1"))
	end
	return actual
end
function eq(actual, expected, msg)
	actual = kbwording(actual, expected)
	if actual ~= expected then
		error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
	end
end
function istrue(v, msg) if not v then error(msg or "expected true", 2) end end
function contains(s, sub, msg)
	s = kbwording(s, sub)
	if type(s) ~= "string" or not s:find(sub, 1, true) then
		error((msg and (msg .. ": ") or "") .. show(s) .. " does not contain " .. show(sub), 2)
	end
end
function listeq(actual, expected, msg)
	if #actual ~= #expected then
		error((msg and (msg .. ": ") or "") .. "expected " .. #expected .. " items {" .. table.concat(expected, " | ") ..
			"}, got " .. #actual .. " {" .. table.concat(actual, " | ") .. "}", 2)
	end
	for i = 1, #expected do eq(actual[i], expected[i], (msg or "list") .. "[" .. i .. "]") end
end

function RunTestFile(path)
	local chunk, err = loadfile(path)
	if not chunk then error(err, 0) end
	chunk()
end
