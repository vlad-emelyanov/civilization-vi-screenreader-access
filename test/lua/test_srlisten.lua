-- SRListen.lua: listeners are recorded and removed again
stub("engine")
include("SRListen")

-- a fake event like Events.X: Add / Remove take the function (dot call, no self)
local function fakeEvent()
	local e = { fns = {} }
	e.Add = function(fn) table.insert(e.fns, fn) end
	e.Remove = function(fn)
		for i, f in ipairs(e.fns) do if f == fn then table.remove(e.fns, i); return end end
	end
	e.Fire = function(...) for _, f in ipairs({ unpack(e.fns) }) do f(...) end end
	return e
end

test("SRListen adds the function to the event", function()
	local e, calls = fakeEvent(), 0
	SRListen(e, function() calls = calls + 1 end)
	e.Fire()
	eq(calls, 1)
	SRUnlistenAll()
end)

test("SRUnlistenAll removes every listener from every event, and is repeatable", function()
	local e1, e2, calls = fakeEvent(), fakeEvent(), 0
	local fn = function() calls = calls + 1 end
	SRListen(e1, fn)
	SRListen(e2, fn)
	SRListen(e2, function() calls = calls + 10 end)
	SRUnlistenAll()
	e1.Fire(); e2.Fire()
	eq(calls, 0)
	eq(#e1.fns, 0)
	eq(#e2.fns, 0)
	SRUnlistenAll()		-- nothing left to do
end)

test("listeners of other code stay", function()
	local e, own, other = fakeEvent(), 0, 0
	e.Add(function() other = other + 1 end)
	SRListen(e, function() own = own + 1 end)
	SRUnlistenAll()
	e.Fire()
	eq(own, 0)
	eq(other, 1)
end)

test("a failing Remove does not stop the rest", function()
	local bad, good, calls = fakeEvent(), fakeEvent(), 0
	bad.Remove = function() error("engine said no") end
	SRListen(good, function() calls = calls + 1 end)
	SRListen(bad, function() end)
	ClearPrinted()
	SRUnlistenAll()
	good.Fire()
	eq(calls, 0)
	contains(Printed[1], "SRUnlistenAll")
end)

test("the same function can be re-registered after unlistening", function()
	local e, calls = fakeEvent(), 0
	local fn = function() calls = calls + 1 end
	SRListen(e, fn); SRUnlistenAll()
	SRListen(e, fn)
	e.Fire()
	eq(calls, 1)
	SRUnlistenAll()
end)
