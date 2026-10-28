-- ===========================================================================
--	ProductionText: pure wording helpers for the production panel (Panels/ProductionPanel.lua).
--	No engine calls: test/lua/test_productiontext.lua checks the wording.
-- ===========================================================================

-- "Currently building Coal Power Plant, 3 turns" (turns may be nil).
function ProductionText_Current( name:string, turns:string )
	local text:string = "Currently building " .. name;
	if turns ~= nil and turns ~= "" then text = text .. ", " .. turns; end
	return text;
end

-- "Renaissance Walls, replaces Coal Power Plant" (oldName nil or equal to name: unchanged).
function ProductionText_Replaces( text:string, oldName:string, name:string )
	if oldName == nil or oldName == "" or oldName == name then return text; end
	return text .. ", replaces " .. oldName;
end

-- The identity of a list item across the production and purchase tabs ("buy:unit:123" and "unit:123" are the same unit).
function ProductionText_Identity( key:string )
	if key == nil then return nil; end
	return ( string.gsub( key, "^buy:", "" ) );
end
