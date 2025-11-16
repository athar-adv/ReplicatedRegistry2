--!strict
--!optimize 2

local RunService = game:GetService("RunService")

local Signal do
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
	
	Signal = {
		fire = fire,
		connect = connect
	}
end

export type Table = {[any]: any}
export type FrozenTable = {[never]: any}
export type Filter = (sender: Player?, path: {any}, value: any) -> boolean
type Remote = UnreliableRemoteEvent | RemoteEvent
type FilterList = {
	player_blacklist: {number}?,
	player_whitelist: {number}?,
	rate_limit: number?,
	no_recieve: boolean?,
	custom: Filter?,
	[string]: any
}
export type TableChanges = {
	{v: any, p: {any}}
}
type Registree<T=Table> = {
	value: T,
	copy: Table,
	filter: Filter?,
	
	onRecievedListeners: {(plr: Player?, tbl: Table, changes: TableChanges) -> ()},
	--onKeyChangedListeners: {(path: {any}, key: any, plr: Player?, value: any) -> ()}
}
export type RegistreeInterface<T=Table, ReplicateArgs...=()> = {
	set: (...any) -> (any) -> (),
	get: (...any) -> any,
	incr: (...any) -> (number) -> (),
	replicate: (ReplicateArgs...) -> (),
	full: () -> T & FrozenTable,
}

local IS_CLIENT = RunService:IsClient()
local MUST_SERVER = "Function cannot be called from client."
local MUST_CLIENT = "Function cannot be called from server."

-- For storing register keys which shouldn't be processed (maybe because of a caught error)
local inactiveKeys = {}
local registrees: {[any]: Registree<any>} = {}

local serialize: ((changes: TableChanges) -> any)? = nil
local deserialize: ((serialized: any) -> TableChanges)? = nil
local serde_serialized_type: string? = nil

local replication_filters = {
	player_blacklist = function(blacklist: {number})
		assert(not IS_CLIENT, "Blacklist filter may only be used from server.")
		return function(sender)
			return table.find(blacklist, sender.UserId) == nil
		end
	end,
	player_whitelist = function(whitelist: {number})
		assert(not IS_CLIENT, "Whitelist filter may only be used from server.")
		return function(sender)
			return table.find(whitelist, sender.UserId) ~= nil
		end
	end,
	rate_limit = function(limitPerSecond: number)
		local lastSent = {}
		local interval = 1 / limitPerSecond

		return function(sender: Player?)
			local sender = sender or "server"
			local now = os.clock()

			if not lastSent[sender] or (now - lastSent[sender] >= interval) then
				lastSent[sender] = now
				return true
			end

			return false
		end
	end,
	no_recieve = function(noRecieve: boolean)
		return function()
			return not noRecieve
		end
	end,
}
local default_callbacks = {
	on_request_with_validate_key = function(plr: Player, key: any)
		if not replication_filters.rate_limit(5) (plr) then return false end

		for i = 1, 5 do
			local exists = registrees[key] ~= nil
			if exists then break end
			task.wait(1)
		end
		if type(key) == "number" then
			return plr.UserId == key
		end
		if type(key) ~= "string" then return false end
		return string.find(key, tostring(plr.UserId)) ~= nil
	end,
	-- Determines if a request of a full table by a player of a register key should be accepted or not.
	on_request = function(plr: Player, key: any)
		return true
	end,
	-- Callback to execute side effects whenever a key is disabled for whatever reason.
	on_key_disable = function(register_key: any, reason: string)
		error(`[{IS_CLIENT and "client" or "server"}] key '{register_key}' was disabled: '{reason}'`)
	end,
	-- Callback to be called whenever a remote event is recieved from the other side. Should return a string indicating what to do.
	-- If the first return value is <code>"disable"</code>, then you can optionally return a 2nd value for the reason of disabling.
	on_changes_recieved = function(sender: Player?, register_key: any, changes: TableChanges): ("pass" | "return" | "disable", string?)
		return "pass"
	end
}

local ReplicatedRegistry = {
	filters = replication_filters,
	registrees = registrees,
	request_full_remote_function = nil :: RemoteFunction?,
	default_changes_remote_event = nil :: RemoteEvent?,
	callbacks = {
		on_changes_recieved = default_callbacks.on_changes_recieved,
		on_key_disabled = default_callbacks.on_key_disable,
	},
	default_callbacks = default_callbacks,
	
	server = {
		callbacks = {
			validate_full_request = default_callbacks.on_request
		}
	},
	client = {
		callbacks = {}
	},
	meta = {}
}

local function diff_changes(changed: (value: any, path: {any}) -> (), current: Table, lastCopy: Table, path: {any})
	for k, v in current do
		local ov = lastCopy[k]
		local newPath = table.clone(path)
		table.insert(newPath, k)

		if type(v) == "table" and type(ov) == "table" then
			diff_changes(changed, v, ov, newPath)
		elseif (type(v) == "table" and type(ov) ~= "table") or (type(v) ~= "table" and type(ov) == "table") then
			changed(v, newPath)
		elseif type(v) ~= "table" and type(ov) ~= "table" and ov ~= v then
			changed(v, newPath)
		end
	end

	for k, v in lastCopy do
		local newPath = table.clone(path)
		table.insert(newPath, k)
		if current[k] == nil then
			changed(nil, newPath)
		end
	end
end

local NO_CHANGE = newproxy()
local function apply_changes(tbl: Table, updates: {{v: any, p: {any}}})
	for _, u in updates do
		if u == NO_CHANGE then continue end
		local current = tbl
		local n = #u.p
		for i = 1, n - 1 do
			current = current[u.p[i]]
		end
		current[u.p[n]] = u.v
	end
end

local function deep_copy(t: any): any
	if type(t) ~= "table" then
		return t
	end

	local copy = {}
	local stack = {{src = t, dest = copy}}
	local stackSize = 1

	while stackSize > 0 do
		local item = stack[stackSize]
		stackSize -= 1

		for k, v in item.src do
			if type(v) == "table" then
				local nested_copy = {}
				item.dest[k] = nested_copy
				stackSize += 1
				stack[stackSize] = {src = v, dest = nested_copy}
			else
				item.dest[k] = v
			end
		end
	end

	return copy
end

local function create_registree_proxy(tbl: Table): (any, TableChanges)
	local changes = {}
	local proxy = {
		set = function(...)
			local path = {...}
			return function(value)
				local current = tbl
				local n = #path
				for i = 1, n - 1 do
					local k = path[i]
					current = current[k]
				end
				current[path[n]] = value
				table.insert(changes, {v = value, p = path})
			end
		end,
		get = function(...)
			local path = {...}
			local current = tbl
			local n = #path
			for i = 1, n - 1 do
				local k = path[i]
				current = current[k]
			end
			return current[path[n]]
		end,
		incr = function(...)
			local path = {...}
			return function(value)
				local current = tbl
				local n = #path
				for i = 1, n - 1 do
					local k = path[i]
					current = current[k]
				end
				current[path[n]] += value
				table.insert(changes, {v = current[path[n]], p = path})
			end
		end,
		replicate = function(plr, r)
			
		end,
		full = function() return tbl end
	}
	return proxy, changes
end

local function disableKey(registree: Registree<any>, register_key: any, reason: string)
	inactiveKeys[register_key] = true
	registree.value = deep_copy(registree.copy)
	ReplicatedRegistry.callbacks.on_key_disabled(register_key, reason)
end

local function remoteFilter(player: Player?, register_key: any, changes: TableChanges, registree: Registree<any>): any
	local result, reason = ReplicatedRegistry.callbacks.on_changes_recieved(player, register_key, changes)
	if result == "return" then
		return nil
	elseif result == "disable" then
		disableKey(registree, register_key, reason or "OnRemoteRecieveCallback indicated to disable.")
	elseif result ~= "pass" then
		disableKey(registree, register_key, "OnRemoteRecieveCallback returned a string other than 'return | disable | pass'")
	end

	if serde_serialized_type and deserialize and typeof(changes) == serde_serialized_type then
		return deserialize(changes)
	elseif typeof(changes) ~= "table" then
		disableKey(registree, register_key, "type of TableChanges was not serde_serializedType nor 'table'")
		return nil
	end
	return true
end

local function remote_event_reciever(player: Player?, register_key: any, changes: TableChanges)
	if inactiveKeys[register_key] then return end
	local registree = registrees[register_key]

	if not registree then return end

	local result = remoteFilter(player, register_key, changes, registree)
	local t = typeof(result)
	if t == "table" then
		changes = result
	elseif not result then
		return
	end

	local filter = registree.filter
	local registerTable = registree.value
	local onRecievedSignal = registree.onRecievedListeners

	for i, change in changes do
		local value, path = change.v, change.p
		if type(path) ~= "table" then
			disableKey(registree, register_key, "TableChanges was not of valid structure: path was of incorrect type")
			return
		end
		if filter then
			local accepted = filter(player, path, value)
			if not accepted then
				changes[i] = NO_CHANGE
			end
		end
	end

	Signal.fire(onRecievedSignal, player, registerTable, changes)
	apply_changes(registerTable, changes)
end

function ReplicatedRegistry.get_filter(nameToArgs: FilterList): Filter
	local filters = {}
	local custom: Filter?

	for name, arg: Filter in nameToArgs do
		if name == "custom" then
			custom = arg
			continue
		end
		local filter = replication_filters[name]
		if not name then
			error(`{name} is not a valid replication filter.`)
		end
		table.insert(filters, filter(arg))
	end

	return function(...)
		local valid = true
		for _, filter in filters do
			local passed = filter(...)
			if not passed then
				valid = false
				break
			end
		end
		if custom and valid then
			valid = custom(...)
		end
		return valid
	end
end

--[[
	Connects a callback function to be called when changes are received for a specific table.
	
    @param registerKey: The unique identifier for the table
    @param fn: The callback function to call when changes are received
    @return: An RBXScriptConnection representing the connection.
]]
function ReplicatedRegistry.on_recieve(register_key: string, fn: (sender: Player?, tbl: Table, changes: TableChanges) -> ())
	local registree = assert(registrees[register_key], `Registree '{register_key}' does not exist.`)
	
	return Signal.connect(registree.onRecievedListeners, fn)
end

--[[
	<strong>THIS FUNCTION NEEDS TO BE CALLED FOR BOTH THE CLIENT AND SERVER IF YOU WANT BOTH SIDES TO SERDE PROPERLY</strong>
	Sets ser/des functions to be called for everytime <code>TableChanges</code> are sent over the network.
	
	@param serializedType: The type of the value returned by <code>ser</code>, must not be <code>"table"</code>.
	@param ser: The serializer for <code>TableChanges</code>, must return a value that is of type <code>serializedType</code>.
	@param des: The deserialized for serialized <code>TableChanges</code>. Must return the original <code>TableChanges</code> otherwise all register keys will be disabled.
]]
function ReplicatedRegistry.set_change_serde(serializedType: string?, ser: ((changes: TableChanges) -> any)?, des: ((serialized: any) -> TableChanges)?)
	assert(serializedType ~= "table", "serializedType is not allowed to be 'table' to keep differentiation between serialized and unserialized changes cheap.")
	if serializedType == nil or ser == nil or des == nil then
		serde_serialized_type = nil
		serialize = nil
		deserialize = nil
		return
	end
	assert(serializedType and ser and des, "if one argument is nil, all must be nil.")

	serde_serialized_type = serializedType
	serialize = ser
	deserialize = des
end

--[[
	Calculates all pending changes for a registered table.
	
	@param registerKey: The unique identifier for the table
]]
function ReplicatedRegistry.get_changes(registerKey: any): TableChanges
	local registree = registrees[registerKey]
	local regTbl = registree.value
	local copy = registree.copy

	local changes: TableChanges = {}
	diff_changes(function(value, path)
		table.insert(changes, {
			v = value,
			p = path
		})
	end, regTbl, copy, {})
	
	return changes
end

--[[
	Commits all changes made to a registered table since the last commit/registry of the table.
	
	@param registerKey: The unqiue identifier for the table
]]
function ReplicatedRegistry.commit_changes(registerKey: any, changes: TableChanges?)
	local registree = registrees[registerKey]
	local copy = registree.copy
	
	local changes = changes or ReplicatedRegistry.get_changes(registerKey)
	apply_changes(copy, changes)
end

--[[
	Reverts all changes made to a registered table since the last commit.
	
	@param registerKey: The unique identifier for the table
]]
function ReplicatedRegistry.revert_changes(registerKey: any, changes: TableChanges?)
	local registree = registrees[registerKey]
	local regTbl = registree.value
	local copy = registree.copy

	local changes = changes or ReplicatedRegistry.get_changes(registerKey)
	for _, change in changes do
		local path = change.p
		local n = #path
		local currentC = copy
		local current = regTbl
		for i, segment in path do
			if i == n then
				local key = segment
				local oldValue = currentC[key]
				current[key] = oldValue
				break
			end
			currentC = currentC[segment]
			current = current[segment]
		end
	end
end

local function changes_serialize(changes: TableChanges)
	if not serialize then return end
	local des = serialize(changes)
	if typeof(changes) ~= serde_serialized_type then
		error(`expected '{serde_serialized_type}' for serializer return value, got '{typeof(changes)}'`)
	end
	return des
end

function ReplicatedRegistry.client.set_remote_instances(request_full: RemoteFunction, send_changes: RemoteEvent)
	assert(IS_CLIENT, MUST_CLIENT)
	ReplicatedRegistry.request_full_remote_function = request_full
	ReplicatedRegistry.default_changes_remote_event = send_changes
	send_changes.OnClientEvent:Connect(ReplicatedRegistry.client.callbacks.remote_event_reciever)
end

function ReplicatedRegistry.client.to_server(registerKey: any, customEvent: Remote?, _changes: TableChanges?, _auto_commit: boolean?)
	assert(IS_CLIENT, MUST_CLIENT)

	local event = customEvent or ReplicatedRegistry.default_changes_remote_event
	assert(event, "RemoteEvent not specified")

	local changes = _changes or ReplicatedRegistry.get_changes(registerKey)
	if #changes == 0 then return end
	
	if _auto_commit == nil or _auto_commit == true then
		ReplicatedRegistry.commit_changes(registerKey, changes)
	end
	if serialize then changes = changes_serialize(changes) end

	(event::any):FireServer(registerKey, changes)
end

function ReplicatedRegistry.client.view(register_key: string): Table
	assert(IS_CLIENT, MUST_CLIENT)
	local registree = registrees[register_key]
	if not registree then
		assert(ReplicatedRegistry.request_full_remote_function, "ReplicatedRegistry.request_full_remote_function must be set in order to use client.view for the first time")
		local tbl = ReplicatedRegistry.request_full_remote_function:InvokeServer(register_key)

		assert(tbl, `Registree '{register_key}' couldn't be accessed.`)
		local reg: Registree = {
			value = tbl,
			copy = deep_copy(tbl),
			filter = nil,

			onRecievedListeners = {},
		}
		registrees[register_key] = reg

		return tbl
	end

	return registree.value
end

function ReplicatedRegistry.client.view_as_proxy(register_key: string): RegistreeInterface<any, (RemoteEvent?)>
	assert(IS_CLIENT, MUST_CLIENT)
	local tbl = ReplicatedRegistry.client.view(register_key)
	
	local proxy, changes = create_registree_proxy(tbl)
	function proxy.replicate(r)
		ReplicatedRegistry.client.to_server(register_key, r, changes)
	end
	
	return proxy
end

function ReplicatedRegistry.client.callbacks.remote_event_reciever(register_key: string, changes: TableChanges)
	remote_event_reciever(nil, register_key, changes)
end

function ReplicatedRegistry.server.to_clients(registerKey: any, players: {Player}, customEvent: Remote?, _changes: TableChanges?, _auto_commit: boolean?)
	assert(not IS_CLIENT, MUST_SERVER)

	local event = customEvent or ReplicatedRegistry.default_changes_remote_event
	assert(event, "RemoteEvent not specified")

	local changes = _changes or ReplicatedRegistry.get_changes(registerKey)
	if #changes == 0 then return end
	
	if _auto_commit == nil or _auto_commit == true then
		ReplicatedRegistry.commit_changes(registerKey, changes)
	end
	if serialize then changes = changes_serialize(changes) end
	
	for _, player in players do
		(event::any):FireClient(player, registerKey, changes)
	end
end

function ReplicatedRegistry.server.to_all_clients(registerKey: any, customEvent: Remote?, _changes: TableChanges?, _auto_commit: boolean?)
	assert(not IS_CLIENT, MUST_SERVER)

	local event = customEvent or ReplicatedRegistry.default_changes_remote_event
	assert(event, "RemoteEvent not specified")

	local changes = _changes or ReplicatedRegistry.get_changes(registerKey)
	if #changes == 0 then return end
	
	if _auto_commit == nil or _auto_commit == true then
		ReplicatedRegistry.commit_changes(registerKey, changes)
	end
	if serialize then changes = changes_serialize(changes) end
	
	(event::any):FireAllClients(registerKey, changes)
end

function ReplicatedRegistry.server.set_remote_instances(request_full: RemoteFunction, send_changes: RemoteEvent)
	assert(not IS_CLIENT, MUST_SERVER)
	ReplicatedRegistry.default_changes_remote_event = send_changes
	send_changes.OnServerEvent:Connect(ReplicatedRegistry.server.callbacks.remote_event_reciever)
	request_full.OnServerInvoke = ReplicatedRegistry.server.callbacks.request_full_handler
end

function ReplicatedRegistry.server.view(register_key: string): Table
	assert(not IS_CLIENT, MUST_SERVER)
	return assert(registrees[register_key], `Registree '{register_key}' does not exist.`).value
end

function ReplicatedRegistry.server.view_as_proxy(register_key: string): RegistreeInterface<any, ({Player}?, RemoteEvent?)>
	assert(not IS_CLIENT, MUST_SERVER)
	local tbl = ReplicatedRegistry.server.view(register_key)
	
	local proxy, changes = create_registree_proxy(tbl)
	function proxy.replicate(plrs, r)
		if not plrs or #plrs == 0 then
			ReplicatedRegistry.server.to_all_clients(register_key, r, changes)
		else
			ReplicatedRegistry.server.to_clients(register_key, plrs, r, changes)
		end
	end

	return proxy
end

function ReplicatedRegistry.server.register<T>(register_key: string, registree_value: T & Table, filter: Filter?)
	assert(not IS_CLIENT, MUST_SERVER)
	local reg: Registree = {
		value = registree_value,
		copy = deep_copy(registree_value),
		filter = filter,

		onRecievedListeners = {},
	}
	
	registrees[register_key] = reg
end

function ReplicatedRegistry.server.callbacks.remote_event_reciever(plr: Player, register_key: string, changes: TableChanges)
	remote_event_reciever(plr, register_key, changes)
end

function ReplicatedRegistry.server.callbacks.request_full_handler(player: Player, registerKey: any)
	if registerKey == nil then return end
	if not ReplicatedRegistry.server.callbacks.validate_full_request(player, registerKey) then return end
	local registree = registrees[registerKey]
	
	if not registree then
		return
	end
	return registree.value
end

function ReplicatedRegistry.meta.switch_signal_lib(new_signal_lib: typeof(Signal))
	Signal = new_signal_lib
end

return ReplicatedRegistry