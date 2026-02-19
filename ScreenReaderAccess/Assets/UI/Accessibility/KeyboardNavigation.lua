-- Keyboard Navigation module
--------------------------------------------------------------

local KEYNAV_LOG_PREFIX: string = "#KEYBOARDNAV - ";

-- Internal task queue for stable sampling
local _KeyNavTasks = {}            -- queued sampling tasks

local function _DebugCall(f)
	local ok, trace = xpcall(f, function(e)
		if debug and debug.traceback then
			return debug.traceback(tostring(e), 2)
		end
		return tostring(e)
	end)

	if not ok then
		print(tostring(trace))
	end
end

local function _PrintKeyNavSet(id, elementList, accessor, labelAccessor)
	local prefix = KEYNAV_LOG_PREFIX..id.." "
	print(prefix.."START")
	for i, elem in ipairs(elementList) do
		_DebugCall(function()
			local keyNavElem = accessor(elem)
			local xOffset, yOffset = keyNavElem:GetScreenOffset()
			local width, height = keyNavElem:GetSizeVal()

			local xAnchor = xOffset + width / 2
			local yAnchor = yOffset + height / 2
			print(prefix..i.." "..xAnchor..","..yAnchor.." "..labelAccessor(elem))
		end)
	end
	print(prefix.."END")
end

-- Per-frame updater: polls tasks and emits when stable or timed out
local function _KeyNavUpdater(deltaTime)
	if #_KeyNavTasks == 0 then
		return
	end

	local remaining = {}
	for tIndex, task in ipairs(_KeyNavTasks) do
		task.framesElapsed = task.framesElapsed + 1
		local timedOut = task.framesElapsed >= task.maxFrames
		if task.stableReached or timedOut then
			if timedOut then
				print("Set: "..task.id.." timed out.")
			end
			_PrintKeyNavSet(task.id, task.elementList, task.accessor, task.labelAccessor)
		else
			-- Wait 1 tick after animations done to let the UI finalize
			if task.checkStable() then
				task.stableReached = true
			end
			table.insert(remaining, task)
		end
	end

	-- replace queue
	_KeyNavTasks = remaining
end

-- checkStable (optional): function to check if element positions have stabilized
function PrintKeyboardNavigationElements(elementList: table, accessor, labelAccessor, checkStable)
	local id = math.random(0, 99999)
	print("Processing keyboard navigation set "..id)
	if checkStable == nil then
		_PrintKeyNavSet(id, elementList, accessor, labelAccessor)
		return
	end

	-- queue a stable sampling task
	local task = {
		id = id,
		elementList = elementList,
		accessor = accessor,
		labelAccessor = labelAccessor,
		checkStable = checkStable,
		stableReached = false,
		maxFrames = 600,    -- default timeout (frames)
		framesElapsed = 0,
	}

	table.insert(_KeyNavTasks, task)
end

function KeyNav_Tick(deltaTime)
	_KeyNavUpdater(deltaTime)
end
