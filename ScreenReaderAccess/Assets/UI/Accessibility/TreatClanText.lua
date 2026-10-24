-- ===========================================================================
--	TreatClanText: pure wording for the Treat With Clan popup of the Barbarian Clans mode
--	(UI/Replacements/TreatWithTribePopup_SRA.lua). No engine calls: the popup passes already cleaned strings,
--	test/lua/test_treatclantext.lua checks the wording.
-- ===========================================================================

-- "Treat With Badger Claw Clan. Melee Open. 3 options. <first option line>"; the game's header already starts with
-- "Treat With", so nothing is prefixed when it does.
function TreatClanText_Opening( header:string, subheader:string, count:number, firstLine:string )
	local parts:table = {};
	header = header or "";
	if header == "" then header = "Treat with a clan"; end
	table.insert( parts, header );
	if subheader ~= nil and subheader ~= "" then table.insert( parts, subheader ); end
	table.insert( parts, count .. ( count == 1 and " option" or " options" ) );
	if firstLine ~= nil and firstLine ~= "" then table.insert( parts, firstLine ); end
	return table.concat( parts, ". " );
end

-- "Target: Rome - Trajan, cost 120 gold" / ", not enough gold" / ", cost unknown, cannot be incited"
function TreatClanText_Target( label:string, cost:number, balance:number )
	local text:string = "Target: " .. label;
	if cost == nil or cost <= 0 then return text .. ", cost unknown, cannot be incited"; end
	text = text .. ", cost " .. cost .. " gold";
	if balance ~= nil and cost > balance then text = text .. ", not enough gold"; end
	return text;
end

-- One option of the popup as a list item.
--	spec = { id, label, description, reasons, disabled, incite = { canStart, target = { label, cost, balance } or nil } }
-- Returns { text, detail, choosable, reason }.
function TreatClanText_Item( spec:table )
	local label:string = spec.label or spec.id or "";
	local description:string = spec.description or "";
	local reasons:string = spec.reasons or "";
	local item:table = { choosable = true };
	local function unavailable( why:string )
		item.text = label .. ", unavailable" .. ( why ~= "" and ( ": " .. why ) or "" );
		item.reason = "Unavailable" .. ( why ~= "" and ( ": " .. why ) or "" );
		item.detail = description ~= "" and description or why;
		item.choosable = false;
	end
	local incite:table = spec.incite;
	if incite ~= nil and incite.canStart then
		-- the game disables the button until a target is chosen and while the cost is more than the gold
		local target:table = incite.target;
		if target == nil then
			item.text = label .. ", choose a target with Left and Right";
			item.reason = "Choose a target first, with Left and Right";
			item.detail = description;
			item.choosable = false;
		else
			local line:string = TreatClanText_Target( target.label, target.cost, target.balance );
			if target.cost == nil or target.cost <= 0 or target.cost > ( target.balance or 0 ) then
				unavailable( line );
			else
				item.text = label .. ": " .. ( description ~= "" and ( description .. ". " ) or "" ) .. line;
				item.detail = item.text;
			end
		end
		return item;
	end
	if spec.disabled then
		unavailable( reasons ~= "" and reasons or description );
		return item;
	end
	item.text = description ~= "" and ( label .. ": " .. description ) or label;
	item.detail = item.text;
	return item;
end

-- What is said after Enter on an option.
function TreatClanText_Result( id:string, clan:string, target:string )
	clan = ( clan ~= nil and clan ~= "" ) and ( clan .. " clan" ) or "the clan";
	if id == "Hire" then return "Hired from " .. clan; end
	if id == "Bribe" then return "Bribed " .. clan; end
	if id == "Ransom" then return "Ransom paid to " .. clan; end
	if id == "Incite" then return "Incited " .. clan .. " against " .. ( target or "the chosen civilization" ); end
	return "Closed";
end
