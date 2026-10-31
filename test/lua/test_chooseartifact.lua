-- Popups/ChooseArtifact.lua: opening speech, button focus, Enter runs the focused button's callback, Escape does not close
stub("engine")
include("ScreenReader")
include("Gamepad")

-- a minimal control: text and visibility
local function Label(text) return { GetText = function() return text end } end
local function Button(text, hidden)
	local b = { text = text, hidden = hidden or false }
	function b:IsHidden() return self.hidden end
	function b:GetTextControl() return Label(self.text) end
	return b
end

local hidden = false
local hides = 0
ContextPtr = { IsHidden = function() return hidden end, GetID = function() return "ChooseArtifact" end,
	SetHide = function(_, h) hidden = h; if h then hides = hides + 1 end end }
local pressed = {}
function OnButton1() table.insert(pressed, 1); ContextPtr:SetHide(true) end
function OnButton2() table.insert(pressed, 2); ContextPtr:SetHide(true) end
function KeyNavErrorHandler(e) return tostring(e) end

load_mod_block("Assets/UI/Popups/ChooseArtifact.lua", 1)

local function Setup(choice)
	hidden = false; hides = 0; pressed = {}
	Controls = {
		PanelHeader = Label("CONFIRM CHOICE"),
		Explanation = Label("Your Archaeologist found a relic of a battle fought between Egypt and Rome."),
		EraString = Label("The artifact is from the Classical Era."),
		ChoiceHeader = Label(choice and "Choose which civilization receives it." or "Egypt gets it."),
		Button1 = Button(choice and "Cleopatra" or "OK"),
		Button2 = Button("Caesar", not choice),
	}
	ClearPrinted()
end

local function press(key, up, mods)
	ClearPrinted()
	local spec = { key = key, up = up }
	for k, v in pairs(mods or {}) do spec[k] = v end
	return SRA_HandleInput(Input(spec))
end

local function tap(key)
	press(key, false)
	return press(key, true)
end

test("choice variant: title, text once, then the first player with a count", function()
	Setup(true)
	SRAnnounceOpen()
	local s = Spoken()
	eq(s[1], "Confirm choice")
	eq(s[2], "Your Archaeologist found a relic of a battle fought between Egypt and Rome. The artifact is from the Classical Era. Choose which civilization receives it.")
	eq(s[3], "Cleopatra, 1 of 2")
	eq(#s, 3)
	eq(Printed[1]:match("^#SCREENREADER%[NOINTERRUPT%]") ~= nil, true)
end)

test("a part that repeats an earlier one is dropped", function()
	Setup(true)
	Controls.ChoiceHeader = Label("The artifact is from the Classical Era.")
	SRAnnounceOpen()
	eq(Spoken()[2], "Your Archaeologist found a relic of a battle fought between Egypt and Rome. The artifact is from the Classical Era.")
end)

test("arrows and Tab move and wrap, Home and End jump, announced at once", function()
	Setup(true)
	SRAnnounceOpen()
	press(Keys.VK_RIGHT)
	eq(Spoken()[1], "Caesar, 2 of 2")
	press(Keys.VK_RIGHT)
	eq(Spoken()[1], "Cleopatra, 1 of 2")
	press(Keys.VK_UP)
	eq(Spoken()[1], "Caesar, 2 of 2")
	press(Keys.VK_LEFT)
	eq(Spoken()[1], "Cleopatra, 1 of 2")
	press(Keys.VK_END)
	eq(Spoken()[1], "Caesar, 2 of 2")
	press(Keys.VK_HOME)
	eq(Spoken()[1], "Cleopatra, 1 of 2")
	press(Keys.VK_DOWN)
	eq(Spoken()[1], "Caesar, 2 of 2")
	press(Keys.VK_TAB, false, { ctrl = true })
	eq(Spoken()[1], "Cleopatra, 1 of 2")
	eq(Printed[1]:match("NOINTERRUPT") == nil, true)
end)

test("Enter on the second player calls OnButton2 and says so before the popup hides", function()
	Setup(true)
	SRAnnounceOpen()
	press(Keys.VK_RIGHT)
	eq(press(Keys.VK_RETURN, false), true)		-- KeyDown does nothing
	eq(#pressed, 0)
	eq(press(Keys.VK_RETURN, true), true)
	eq(pressed[1], 2)
	eq(#pressed, 1)
	eq(Spoken()[1], "Artifact from Caesar chosen")
	eq(hidden, true)
end)

test("Enter on the first player calls OnButton1", function()
	Setup(true)
	SRAnnounceOpen()
	tap(Keys.VK_RETURN)
	eq(pressed[1], 1)
	eq(Spoken()[1], "Artifact from Cleopatra chosen")
end)

test("Escape says a choice is needed and does not close", function()
	Setup(true)
	SRAnnounceOpen()
	press(Keys.VK_ESCAPE, true)
	eq(Spoken()[1], "Choose an artifact first. Enter takes the focused one")
	eq(hidden, false)
	eq(hides, 0)
	eq(#pressed, 0)
end)

test("Space repeats the explanation and the era", function()
	Setup(true)
	SRAnnounceOpen()
	tap(Keys.VK_SPACE)
	eq(Spoken()[1], "Your Archaeologist found a relic of a battle fought between Egypt and Rome. The artifact is from the Classical Era")
end)

test("no-choice variant: OK without a count, Enter hint, arrows say it again", function()
	Setup(false)
	SRAnnounceOpen()
	local s = Spoken()
	eq(s[1], "Confirm choice")
	eq(s[#s], "OK. Enter confirms")
	press(Keys.VK_RIGHT)
	eq(Spoken()[1], "OK")
	press(Keys.VK_UP)
	eq(Spoken()[1], "OK")
	press(Keys.VK_ESCAPE, true)
	eq(Spoken()[1], "Take the artifact first. Enter confirms")
	eq(hidden, false)
	tap(Keys.VK_RETURN)
	eq(pressed[1], 1)
	eq(Spoken()[1], "Artifact received")
end)

test("every other key is swallowed while shown, nothing when hidden", function()
	Setup(true)
	SRAnnounceOpen()
	eq(press(string.byte("J")), true)
	eq(press(string.byte("J"), true), true)
	eq(press(Keys.VK_RIGHT, false, { shift = true }), true)
	eq(#Spoken(), 0)
	hidden = true
	eq(press(Keys.VK_RETURN, true), false)
end)

test("a KeyUp of Enter or Space without a KeyDown since the popup showed does nothing", function()
	Setup(true)
	SRAnnounceOpen()
	eq(press(Keys.VK_RETURN, true), true)
	eq(#pressed, 0)
	eq(#Spoken(), 0)
	press(Keys.VK_SPACE, true)
	eq(#Spoken(), 0)
	eq(press(Keys.VK_RETURN, false), true)
	press(Keys.VK_RETURN, true)
	eq(pressed[1], 1)
	-- the flag is used up: a second stray KeyUp does nothing (and a reopen clears a pending KeyDown)
	Setup(true)
	SRAnnounceOpen()
	press(Keys.VK_RETURN, false)
	SRAnnounceOpen()
	press(Keys.VK_RETURN, true)
	eq(#pressed, 0)
end)

test("the title is spoken in normal case", function()
	Setup(false)
	Controls.PanelHeader = Label("ARTIFACT FOUND")
	SRAnnounceOpen()
	eq(Spoken()[1], "Artifact found")
end)
