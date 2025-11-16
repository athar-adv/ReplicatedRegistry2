--!optimize 2
--Signal.luau (props to ffrostfall for this one)

local function connect<T...>(tbl: {(T...) -> ()}, item: (T...) -> ()): RBXScriptConnection
	table.insert(tbl, item)
	return {
		Connected = false,
		Disconnect = function(self)
			local idx = table.find(tbl, item)
			if idx then
				table.remove(tbl, idx)
			end
		end,
	} :: any
end

local freeThread: thread?
local function handler(tracker: Table, fns: Table, ...: any)
	local ref = freeThread
	freeThread = nil

	while tracker.n ~= 0 do
		local n = tracker.n
		tracker.n -= 1
		fns[n](...)
	end

	freeThread = ref
end

local function yieldLoop()
	while true do
		handler(coroutine.yield())
	end
end

local function fire<T...>(tbl: {(T...) -> ()}, ...: T...)
	local n = #tbl
	if n == 0 then return end
	
	local tracker = {
		n = n
	}
	while tracker.n ~= 0 do
		if not freeThread then
			freeThread = task.spawn(yieldLoop)
		end

		task.spawn(freeThread :: thread, tracker, tbl, ...)
	end
end

return {
	fire = fire,
	connect = connect
}