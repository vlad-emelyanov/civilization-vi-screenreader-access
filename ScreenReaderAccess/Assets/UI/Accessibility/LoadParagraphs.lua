-- LoadParagraphs.lua: the paragraph list of the load screen (civ and leader, era, leader info, abilities, unique units and buildings).
-- Pure logic: the player moves through it with Up / Down / Home / End and nothing is read on its own (the game's narrator talks).
-- Each move returns the text to speak, which ends with ", n of N". Used by Frontend/LoadScreen.lua.
LoadParagraphs = {};

local m_list	:table = {};
local m_index	:number = 0;	-- 0 = nothing focused yet

function LoadParagraphs.Reset()
	m_list = {};
	m_index = 0;
end

function LoadParagraphs.Add( text:string )
	if text == nil or text == "" then return; end
	table.insert( m_list, text );
end

function LoadParagraphs.Count()
	return #m_list;
end

function LoadParagraphs.Index()
	return m_index;
end

-- The opening line: "Loading Rome, Trajan. <Up> and <Down> read the civilization details, 6 paragraphs". Without paragraphs: no key hint.
-- upKey / downKey are the spoken key names (SRKey tokens).
function LoadParagraphs.OpeningLine( civName:string, leaderName:string, upKey:string, downKey:string )
	local who:string = "";
	if civName ~= nil and civName ~= "" then who = civName; end
	if leaderName ~= nil and leaderName ~= "" then who = who .. ( who ~= "" and ", " or "" ) .. leaderName; end
	local line:string = "Loading";
	if who ~= "" then line = line .. " " .. who; end
	local n:number = #m_list;
	if n == 0 then return line; end
	return line .. ". " .. upKey .. " and " .. downKey .. " read the civilization details, " .. n .. ( n == 1 and " paragraph" or " paragraphs" );
end

local function Describe( i:number )
	m_index = i;
	return m_list[i] .. ", " .. i .. " of " .. #m_list;
end

-- what is "down", "up", "home", "end", "repeat" -> text to speak (never nil, never silent), or nil when there is no list at all
function LoadParagraphs.Move( what:string )
	local n:number = #m_list;
	if n == 0 then return nil; end
	if what == "down" then
		if m_index == 0 then return Describe( 1 ); end
		if m_index >= n then return "Last paragraph"; end
		return Describe( m_index + 1 );
	elseif what == "up" then
		if m_index <= 1 then return "First paragraph"; end
		return Describe( m_index - 1 );
	elseif what == "home" then
		return Describe( 1 );
	elseif what == "end" then
		return Describe( n );
	elseif what == "repeat" then
		return Describe( m_index == 0 and 1 or m_index );
	end
	return nil;
end
