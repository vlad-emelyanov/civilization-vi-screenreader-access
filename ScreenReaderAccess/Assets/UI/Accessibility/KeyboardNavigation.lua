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

local function _TakeSnapshot(elementList, accessor, labelAccessor)
	local snap = {}
	_DebugCall(function()
		for i, elem in ipairs(elementList) do
			local keyNavElem = accessor(elem)
			local xOffset, yOffset = keyNavElem:GetScreenOffset()
			local width, height = keyNavElem:GetSizeVal()
			-- store as numbers (integers) for stable comparison
			table.insert(snap, { x = math.floor(tonumber(xOffset) or 0), y = math.floor(tonumber(yOffset) or 0), w = math.floor(tonumber(width) or 0), h = math.floor(tonumber(height) or 0), label = tostring(labelAccessor(elem) or "") })
		end
	end)
	return snap
end

local function _SnapshotsEqual(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i].x ~= b[i].x or a[i].y ~= b[i].y or a[i].w ~= b[i].w or a[i].h ~= b[i].h or a[i].label ~= b[i].label then
			return false
		end
	end
	return true
end

local function _EmitSnapshotWithId(id, snap)
	local prefix = KEYNAV_LOG_PREFIX..id.." "
	print(prefix.."START")
	for i = 1, #snap do
		local s = snap[i]
		local xAnchor = s.x + s.w / 2
		local yAnchor = s.y + s.h / 2
		print(prefix..i.." "..xAnchor..","..yAnchor.." "..s.label)
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
		local current = _TakeSnapshot(task.elementList, task.accessor, task.labelAccessor)

		if task.prevSnapshot == nil then
			task.prevSnapshot = current
			task.stableCount = 0
			task.maxFalseStableCount= 0
		else
			if _SnapshotsEqual(current, task.prevSnapshot) then
				task.stableCount = task.stableCount + 1
			else
				task.prevSnapshot = current
				if task.maxFalseStableCount< task.stableCount then
					task.maxFalseStableCount= task.stableCount
				end 
				task.stableCount = 0
			end
		end

		local reachedStable = task.stableCount >= task.stableTarget
		local timedOut = task.framesElapsed >= task.maxFrames
		if reachedStable or timedOut then
			-- emit using the task id and the most recent snapshot
			print("Set: "..task.id.." Frames elapsed: "..task.framesElapsed.." Stable frames: "..task.stableCount.." Max false stable: "..task.maxFalseStableCount)
			_EmitSnapshotWithId(task.id, task.prevSnapshot)
		else
			table.insert(remaining, task)
		end
	end

	-- replace queue
	_KeyNavTasks = remaining
end

-- waitForStable (optional): if true, poll until coordinates stabilize (default: false)
-- maxFrames / stableTarget are optional tuning parameters
function PrintKeyboardNavigationElements(elementList: table, accessor, labelAccessor, waitForStable, stableTarget, maxFrames)
	local id = math.random(0, 99999)
	print("Processing keyboard navigation set "..id)
	waitForStable = waitForStable or false
	if not waitForStable then
		_EmitSnapshotWithId(id, _TakeSnapshot(elementList, accessor, labelAccessor))
		return
	end

	-- queue a stable sampling task
	local task = {
		id = id,
		elementList = elementList,
		accessor = accessor,
		labelAccessor = labelAccessor,
		maxFrames = tonumber(maxFrames) or 600,    -- default timeout (frames)
		framesElapsed = 0,
		stableTarget = tonumber(stableTarget) or 30, -- require this many identical frames
		stableCount = 0,
		maxFalseStableCount= 0,
		prevSnapshot = nil,
	}

	table.insert(_KeyNavTasks, task)
end

function KeyNav_Tick(deltaTime)
	_KeyNavUpdater(deltaTime)
end
