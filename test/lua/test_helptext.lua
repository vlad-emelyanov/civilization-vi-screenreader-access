-- HelpText.lua: the accessibility help list (Control+H) is pure data: sections are filled, every entry says something,
-- action entries show the current binding and fall back to their default.
include("HelpText")

local sections = HelpText_Sections()

test("sections and entries are filled", function()
	assert(#sections >= 9, "sections")
	for _, section in ipairs(sections) do
		assert(type(section.title) == "string" and section.title ~= "", "title")
		assert(#section.entries > 0, section.title .. " has no entries")
		for i, entry in ipairs(section.entries) do
			local where = section.title .. " #" .. i
			assert(type(entry.text) == "string" and entry.text ~= "", where .. " has no text")
			assert((entry.action ~= nil) ~= (entry.keys ~= nil), where .. " needs exactly one of action / keys")
			if entry.action ~= nil then assert(type(entry.default) == "string" and entry.default ~= "", where .. " (" .. entry.action .. ") needs a default key text") end
		end
	end
end)

test("an action entry shows the current binding, else the default", function()
	local entry = { action = "KeyNavWhatsNext", default = "N", text = "what Enter will do next" }
	eq(HelpText_KeyText(entry, function(name) return name == "KeyNavWhatsNext" and "Ctrl+B" or nil end), "Ctrl+B")
	eq(HelpText_KeyText(entry, function() return nil end), "N")
	eq(HelpText_KeyText(entry, function() return "" end), "N")
	eq(HelpText_KeyText(entry, function() error("engine") end), "N")
	eq(HelpText_KeyText(entry, nil), "N")
	eq(HelpText_Line(entry, nil), "N: what Enter will do next")
	eq(HelpText_KeyText({ action = "X", text = "x" }, nil), "unbound")
	eq(HelpText_KeyText({ keys = "Shift+Arrows", text = "x" }, function() return "no" end), "Shift+Arrows")
end)

test("Build gives keyed lines for every entry, with a stub binding", function()
	local built = HelpText_Build(function(name) return "<" .. name .. ">" end)
	eq(#built, #sections)
	local seen = {}
	for s, section in ipairs(built) do
		eq(#section.items, #sections[s].entries)
		for _, item in ipairs(section.items) do
			assert(not seen[item.key], "duplicate key " .. item.key)
			seen[item.key] = true
			assert(item.text:find(": ", 1, true), item.text)
			eq(item.detail, item.text)
		end
	end
	local found
	for _, section in ipairs(built) do
		for _, item in ipairs(section.items) do
			if item.text:find("<KeyNavWhatsNext>: ", 1, true) then found = item end
		end
	end
	assert(found, "KeyNavWhatsNext resolved")
end)
