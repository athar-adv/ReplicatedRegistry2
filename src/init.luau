--!strict
--!optimize 2
--ReplicatedRegistry2.luau (1.5.0)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Signal do
	--Signal.luau (props to ffrostfall for this one)
	local function connect<T...>(tbl: {(T...) -> ()}, item: (T...) -> (), side_effect: ((tbl: {(T...) -> ()}) -> ())?): RBXScriptConnection
		table.insert(tbl, item)
		return {
			Connected = true,
			Disconnect = function(self)
				self.Connected = false
				local idx = table.find(tbl, item)
				if idx then
					table.remove(tbl, idx)
				end
				if side_effect then
					side_effect(tbl)
				end
			end,
		} :: any
	end

	local freeThread: thread?
	local function handler(tracker: {n: number}, fns: Table, ...: any)
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

export type View<T = Table, ProxyType = any> = {
	await: () -> T,
	unwrap: () -> T?,
	expect: () -> T,
	as_proxy: () -> {
		await: () -> ProxyType,
		unwrap: () -> ProxyType?,
		expect: () -> ProxyType
	}
}
export type Table = {[any]: any}
export type Filter = (sender: Player?, registry_key: any, old_tbl: Table, changes: TableChanges) -> boolean
type Sender_Client = (register_key: any, changes: TableChanges) -> ()
type Sender_Server = (plr: Player, register_key: any, changes: TableChanges) -> ()
type RequestFull = (register_key: any) -> TableChanges?
type RequestFullInit = ((plr: Player, register_key: any) -> Table?) -> ()
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
	
	onRecievedListeners: {(...any) -> ()},
	onKeyChangedListeners: {[string]: {(...any) -> ()}}
}
export type RegistreeInterface_Server<T=Table> = {
	set: (path: {any}, v: any) -> (),
	get: (path: {any}) -> any,
	incr: (path: {any}, delta: number) -> (),
	replicate: (plrs: {Player}, _sender: Sender_Server) -> (),
	key_changed: (path: {any}, fn: (sender: Player, old_value: any, new_value: any) -> ()) -> RBXScriptConnection,
	data: () -> T,
}
export type RegistreeInterface_Client<T=Table> = {
	set: (path: {any}, v: any) -> (),
	get: (path: {any}) -> any,
	incr: (path: {any}, delta: number) -> (),
	replicate: (_sender: Sender_Client) -> (),
	key_changed: (path: {any}, fn: (old_value: any, new_value: any) -> ()) -> RBXScriptConnection,
	data: () -> T,
}

local IS_CLIENT = RunService:IsClient()
local MUST_SERVER = "Function cannot be called from client."
local MUST_CLIENT = "Function cannot be called from server."

-- For storing register keys which shouldn't be processed (maybe because of a caught error)
local inactiveKeys = {}
local registrees: {[any]: Registree} = {}

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
		return "pass", nil
	end
}

local ReplicatedRegistry = {
	filters = replication_filters,
	registrees = registrees,
	callbacks = {
		on_changes_recieved = default_callbacks.on_changes_recieved,
		on_key_disabled = default_callbacks.on_key_disable,
	},
	default_callbacks = default_callbacks,
	
	server = {
		callbacks = {
			validate_full_request = default_callbacks.on_request,
			default_send_changes = nil :: Sender_Server?,
		}
	},
	client = {
		callbacks = {
			default_send_changes = nil :: Sender_Client?,
			request_full = nil :: RequestFull?,
		}
	},
	meta = {}
}

local function weak_table<K, V>(): {[K]: V}
	local t = setmetatable({}, {__mode = "v"})
	return t :: any
end

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

local function ensure_tbl(dict: Table, k: any)
	local v = dict[k]
	if v then return v end
	local nv = {}
	dict[k] = nv
	return nv
end

local function create_registree_proxy(register_key: any, tbl: Table)
	local changes = {}
	local proxy = {
		set = function(path, value)
			local current = tbl
			local n = #path
			for i = 1, n - 1 do
				local k = path[i]
				current = current[k]
			end
			current[path[n]] = value
			table.insert(changes, {v = value, p = path})
		end,
		get = function(path)
			local current = tbl
			local n = #path
			for i = 1, n - 1 do
				local k = path[i]
				current = current[k]
			end
			return current[path[n]]
		end,
		incr = function(path, delta)
			local current = tbl
			local n = #path
			for i = 1, n - 1 do
				local k = path[i]
				current = current[k]
			end
			current[path[n]] += delta
			table.insert(changes, {v = current[path[n]], p = path})
		end,
		replicate = function(plr, r)
			
		end,
		key_changed = function(path, fn)
			
		end,
		full = function() return tbl end,
	}
	return proxy :: any, changes
end

local function create_server_proxy(register_key: any, tbl: Table)
	local proxy: RegistreeInterface_Server, changes = create_registree_proxy(register_key, tbl)
	function proxy.replicate(plrs, r)
		if not plrs or #plrs == 0 then
			ReplicatedRegistry.server.to_clients(register_key, Players:GetPlayers(), r, changes)
		else
			ReplicatedRegistry.server.to_clients(register_key, plrs, r, changes)
		end
	end
	function proxy.key_changed(path, fn)
		return ReplicatedRegistry.server.on_key_changed(register_key, path, fn)
	end

	return proxy
end

local function create_client_proxy(register_key: any, tbl: Table)
	local proxy: RegistreeInterface_Client, changes = create_registree_proxy(register_key, tbl)
	function proxy.replicate(r)
		ReplicatedRegistry.client.to_server(register_key, r, changes)
	end
	function proxy.key_changed(path, fn)
		return ReplicatedRegistry.client.on_key_changed(register_key, path, fn)
	end
	
	return proxy
end

local function yield_call(fn: any, ...)
	local arg = fn(...)
	if arg then return arg end
	
	local cor = coroutine.running()
	task.spawn(function(...)
		while true do
			local arg = fn(...)
			if arg then task.spawn(cor, arg) return end
			task.wait()
		end
	end, ...)
	return coroutine.yield()
end

local function disableKey(registree: Registree<any>, register_key: any, reason: string)
	inactiveKeys[register_key] = true
	registree.value = deep_copy(registree.copy)
	ReplicatedRegistry.callbacks.on_key_disabled(register_key, reason)
end

local function remoteFilter(player: Player?, register_key: any, changes: TableChanges, registree: Registree<any>): boolean
	local result, reason = ReplicatedRegistry.callbacks.on_changes_recieved(player, register_key, changes)
	if result == "return" then
		return false
	elseif result == "disable" then
		disableKey(registree, register_key, reason or "OnRemoteRecieveCallback indicated to disable.")
	elseif result ~= "pass" then
		disableKey(registree, register_key, "OnRemoteRecieveCallback returned a string other than 'return | disable | pass'")
	end
	
	return true
end

local function hash(array: {any})
	local stringed = {}
	for i, v in array do
		stringed[i] = tostring(v)
	end
	return table.concat(stringed, "\0")
end

local function remote_event_reciever(player: Player?, register_key: any, changes: TableChanges)
	if inactiveKeys[register_key] then return end
	local registree = registrees[register_key]

	if not registree then return end

	local shouldReturn = remoteFilter(player, register_key, changes, registree)
	if not shouldReturn then return end

	local filter = registree.filter
	local registerTable = registree.value
	local onRecievedSignal = registree.onRecievedListeners
	
	if filter then
		if not filter(player, register_key, registerTable, changes) then
			return
		end
	end
	for i, change in changes do
		local value, path = change.v, change.p
		if type(path) ~= "table" then
			disableKey(registree, register_key, "TableChanges was not of valid structure: path was of incorrect type")
			return
		end
		
		local k = hash(change.p)
		local listeners = registree.onKeyChangedListeners[k]
		if not listeners then continue end

		local old_value: any do
			local curr = registerTable
			for _, pk in change.p do
				curr = curr[pk]
			end
			old_value = curr
		end
		if listeners then
			if IS_CLIENT then
				Signal.fire(listeners, old_value, change.v)
			else
				Signal.fire(listeners, player, old_value, change.v)
			end
		end
	end

	if IS_CLIENT then
		Signal.fire(onRecievedSignal, registerTable, changes)
	else
		Signal.fire(onRecievedSignal, player, registerTable, changes)
	end
	apply_changes(registerTable, changes)
end

--[[
	Returns an array of currently registered register keys.
	
	@return Array of currently registered register keys.
]]
function ReplicatedRegistry.get_registered_keys()
	local array = {}
	for k in registrees do
		table.insert(array, k)
	end
	return array
end

--[[
	Returns a composite filter from a dictionary mapping filter names to arguments
	
	@param nameToArgs: Dictionary mapping filter names to arguments
	@return: Filter that will use all the filters passed in nameToArgs
]]
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
	Calculates all pending changes for a registered table.
	
	@param registerKey: The unique identifier for the table
	@return The TableChanges which are pending
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

--[[
	Sets default remote middleware that all the functions will use from Roblox remote instances.
	
	@param request_full: The RemoteFunction that'll be used to request the server for the full data of a registree (this is done when the data is first accessed)
	@param send_changes: The RemoteEvent that'll be used to handle 2-way data sync between server and clients
]]
function ReplicatedRegistry.client.set_remote_instances(request_full: RemoteFunction, send_changes: RemoteEvent)
	ReplicatedRegistry.client.set_remote_callbacks(
		function(...)
			return request_full:InvokeServer(...)
		end,
		function(...)
			send_changes:FireServer(...)
		end,
		function(reciever)
			send_changes.OnClientEvent:Connect(reciever)
		end
	)
end

--[[
	Sets default remote middleware that all the functions will use.
	
	@param request_full: The callback that'll be called to request the server for the full data of a registree (this is done when the data is first accessed)
	@param send_changes: The callback that'll be called to send changes to clients
	@param connect_change_reciever: The callback that should connect the internal delta reciever handler (passed as an argument to the callback) to a middleware, such as a RemoteEvent
]]
function ReplicatedRegistry.client.set_remote_callbacks(request_full: RequestFull, send_changes: Sender_Client, connect_change_reciever: (reciever: (register_key: any, changes: TableChanges) -> ()) -> () )
	assert(IS_CLIENT, MUST_CLIENT)
	ReplicatedRegistry.client.callbacks.request_full = request_full
	ReplicatedRegistry.client.callbacks.default_send_changes = send_changes
	connect_change_reciever(function(...)
		assert(ReplicatedRegistry.client.callbacks.remote_event_reciever, "remote_event_reciever not set")
		ReplicatedRegistry.client.callbacks.remote_event_reciever(...)
	end)
end

--[[
	Connects a callback function to be called when changes are received for a specific table.
	
    @param registerKey: The unique identifier for the table
    @param fn: The callback function to call when changes are received
    @return: A ScriptConnection representing the connection.
]]
function ReplicatedRegistry.client.on_receive(register_key: string, fn: (data: Table, changes: TableChanges) -> ())
	assert(IS_CLIENT, MUST_CLIENT)
	
	local registree = assert(registrees[register_key], `Registree '{register_key}' does not exist.`)

	return Signal.connect(registree.onRecievedListeners, fn)
end

--[[
	Connects a callback function to be called when changes are recieved for a specific path in a registree.
	
	@behavior: Only gets called when a key is changed via a delta being sent and applied, not changes made on the same run context.
	@param register_key: The registree whose data contains the path
	@param path: The path you want to listen to for changes
	@param fn: The callback to be called
	@return: A ScriptConnection representing the connection.
]]
function ReplicatedRegistry.client.on_key_changed(register_key: string, path: {any}, fn: (old_value: any, new_value: any) -> ())
	assert(IS_CLIENT, MUST_CLIENT)
	
	local registree = registrees[register_key]
	assert(registree)

	local k = hash(path)
	return Signal.connect(ensure_tbl(registree.onKeyChangedListeners, k), fn, function(tbl)
		if #tbl == 0 then
			registree.onKeyChangedListeners[k] = nil
		end
	end)
end

--[[
	Replicates deltas of a registree to the server.
	
	@param register_key: The key of the registree being replicated
	@param _sender: An optional sender function, overriding the default one
	@param _changes: An optional array of your own deltas, overriding the default one
	@param _auto_commit: If a commit should be automatically done by this function, default = true
]]
function ReplicatedRegistry.client.to_server(registerKey: any, _sender: Sender_Client?, _changes: TableChanges?, _auto_commit: boolean?)
	assert(IS_CLIENT, MUST_CLIENT)
	
	local sender = _sender or ReplicatedRegistry.client.callbacks.default_send_changes
	assert(sender, "sender not specified")

	local changes = _changes or ReplicatedRegistry.get_changes(registerKey)
	if #changes == 0 then return end
	
	if _auto_commit == nil or _auto_commit == true then
		ReplicatedRegistry.commit_changes(registerKey, changes)
	end
	
	sender(registerKey, changes)
end

--[[
	Returns a viewing interface for a registree's data
	
	@param register_key: The key for the registree whose data you want to view
	@return: A viewing interface which contains functions such as await() and unwrap() depending on how you need to view the data
]]
function ReplicatedRegistry.client.view(register_key: any): View<Table, RegistreeInterface_Client>
	assert(IS_CLIENT, MUST_CLIENT)
	local function get(): Table?
		local registree = registrees[register_key]
		if not registree then
			assert(ReplicatedRegistry.client.callbacks.request_full, "ReplicatedRegistry.request_full_remote_function must be set in order to use client.view for the first time")
			local tbl = ReplicatedRegistry.client.callbacks.request_full(register_key)

			--assert(tbl, `Registree '{register_key}' couldn't be accessed.`)
			if not tbl then return nil end
			local reg: Registree = {
				value = tbl,
				copy = deep_copy(tbl),
				filter = nil,

				onRecievedListeners = {},
				onKeyChangedListeners = {}
			}
			registrees[register_key] = reg

			return tbl
		end

		return registree.value
	end
	
	local view: View
	view = {
		await = function()
			return yield_call(get)
		end,
		unwrap = get,
		expect = function()
			local value = get()
			assert(value, `RegisterKey '{register_key}' is not registered yet`)
			
			return value
		end,
		as_proxy = function()
			local function create_proxy(method: string): any
				local tbl = view[method]()
				if tbl then
					return create_client_proxy(register_key, tbl)
				else
					return nil
				end
			end
			
			return {
				unwrap = function()
					return create_proxy("unwrap")
				end,
				await = function()
					return create_proxy("await")
				end,
				expect = function()
					return create_proxy("expect")
				end,
			}
		end,
	}
	return view
end

--[[
	The reciever function that handles delta changes sent by the server.
	
	@param register_key: The key of the registree being changed
	@param changes: The delta/changes being made to this registree
]]
function ReplicatedRegistry.client.callbacks.remote_event_reciever(register_key: any, changes: TableChanges)
	remote_event_reciever(nil, register_key, changes)
end

--[[
	Replicates deltas of a registree to an array of clients.
	
	@param register_key: The key of the registree being replicated
	@param players: The clients the changes should be replicated to
	@param _sender: An optional sender function, overriding the default one
	@param _changes: An optional array of your own deltas, overriding the default one
	@param _auto_commit: If a commit should be automatically done by this function, default = true
]]
function ReplicatedRegistry.server.to_clients(registerKey: any, players: {Player}, _sender: Sender_Server?, _changes: TableChanges?, _auto_commit: boolean?)
	assert(not IS_CLIENT, MUST_SERVER)

	local sender = _sender or ReplicatedRegistry.server.callbacks.default_send_changes
	assert(sender, "sender not specified")

	local changes = _changes or ReplicatedRegistry.get_changes(registerKey)
	if #changes == 0 then return end
	
	if _auto_commit == nil or _auto_commit == true then
		ReplicatedRegistry.commit_changes(registerKey, changes)
	end
	
	for _, player in players do
		sender(player, registerKey, changes)
	end
end

--[[
	Sets default remote middleware that all the functions will use from Roblox remote instances.
	
	@param request_full: The RemoteFunction that'll be used to handle full data requests from clients
	@param send_changes: The RemoteEvent that'll be used to handle 2-way data sync between server and clients
]]
function ReplicatedRegistry.server.set_remote_instances(request_full: RemoteFunction, send_changes: RemoteEvent)
	ReplicatedRegistry.server.set_remote_callbacks(
		function(handler)
			request_full.OnServerInvoke = handler
		end,
		function(...)
			send_changes:FireClient(...)
		end,
		function(reciever)
			send_changes.OnServerEvent:Connect(reciever)
		end
	)
end

--[[
	Sets default remote middleware that all the functions will use.
	
	@param request_full_init: The callback that should connect the internal full data request handler (passed as an argument to the callback) to a middleware, such as a RemoteFunction
	@param send_changes: The callback that'll be called to send changes to clients
	@param connect_change_reciever: The callback that should connect the internal delta reciever handler (passed as an argument to the callback) to a middleware, such as a RemoteEvent
]]
function ReplicatedRegistry.server.set_remote_callbacks(request_full_init: RequestFullInit, send_changes: Sender_Server, connect_change_reciever: (reciever: (plr: Player, register_key: any, changes: TableChanges) -> ()) -> () )
	assert(not IS_CLIENT, MUST_SERVER)
	ReplicatedRegistry.server.callbacks.default_send_changes = send_changes
	request_full_init(function(...)
		assert(ReplicatedRegistry.server.callbacks.request_full_handler, "request_full_handler not set")
		return ReplicatedRegistry.server.callbacks.request_full_handler(...)
	end)
	connect_change_reciever(function(...)
		assert(ReplicatedRegistry.server.callbacks.remote_event_reciever, "remote_event_reciever not set")
		ReplicatedRegistry.server.callbacks.remote_event_reciever(...)
	end)
end

--[[
	Connects a callback function to be called when changes are received for a specific table.
	
    @param registerKey: The unique identifier for the table
    @param fn: The callback function to call when changes are received
    @return: A ScriptConnection representing the connection.
]]
function ReplicatedRegistry.server.on_receive(register_key: string, fn: (sender: Player, data: Table, changes: TableChanges) -> ())
	assert(not IS_CLIENT, MUST_SERVER)
	
	local registree = assert(registrees[register_key], `Registree '{register_key}' does not exist.`)

	return Signal.connect(registree.onRecievedListeners, fn)
end

--[[
	Connects a callback function to be called when changes are recieved for a specific path in a registree
	
	@behavior: Only gets called when a key is changed via a delta being sent and applied, not changes made on the same run context.
	@param register_key: The registree whose data contains the path
	@param path: The path you want to listen to for changes
	@param fn: The callback to be called
	@return: A ScriptConnection representing the connection.
]]
function ReplicatedRegistry.server.on_key_changed(register_key: string, path: {any}, fn: (sender: Player, old_value: any, new_value: any) -> ())
	assert(not IS_CLIENT, MUST_SERVER)
	
	local registree = registrees[register_key]
	assert(registree)
	
	local k = hash(path)
	return Signal.connect(ensure_tbl(registree.onKeyChangedListeners, k), fn, function(tbl)
		if #tbl == 0 then
			registree.onKeyChangedListeners[k] = nil
		end
	end)
end

--[[
	Returns a viewing interface for a registree's data
	
	@param register_key: The key for the registree whose data you want to view
	@return: A viewing interface which contains functions such as await() and unwrap() depending on how you need to view the data
]]
function ReplicatedRegistry.server.view(register_key: any): View<Table, RegistreeInterface_Server>
	assert(not IS_CLIENT, MUST_SERVER)
	local function get(): Table?
		local registree = registrees[register_key]
		if registree then
			return registree.value
		else
			return nil
		end
	end
	
	local view: View
	view = {
		await = function()
			return yield_call(get)
		end,
		unwrap = get,
		expect = function()
			local value = get()
			assert(value, `RegisterKey '{register_key}' is not registered yet`)

			return value
		end,
		as_proxy = function()
			local function create_proxy(method: string): any
				local tbl = view[method]()
				if tbl then
					return create_server_proxy(register_key, tbl)
				else
					return nil
				end
			end
			
			return {
				unwrap = function()
					return create_proxy("unwrap")
				end,
				await = function()
					return create_proxy("await")
				end,
				expect = function()
					return create_proxy("expect")
				end,
			}
		end,
	}
	return view
end

--[[
	Registers a registree, making it replicable and accessible by both server and clients
	
	@param register_key: The key for the registree to register
	@param registree_value: The data that'll be assigned to this registree, is a table.
	@param filter: An optional replication reciever filter to prevent tampered/invalid deltas
]]
function ReplicatedRegistry.server.register<T>(register_key: any, registree_value: T & Table, filter: Filter?)
	assert(not IS_CLIENT, MUST_SERVER)
	local reg: Registree = {
		value = registree_value,
		copy = deep_copy(registree_value),
		filter = filter,
		
		onRecievedListeners = {},
		onKeyChangedListeners = {}
	}
	
	registrees[register_key] = reg
end

--[[
	Deregisters a registree, making it not replicable nor accessible anymore.
	
	@param register_key: The key for the registree you want to deregisteer
	@param _auto_replicate: If the deregistering should be automatically replicated to all clients by this function
]]
function ReplicatedRegistry.server.deregister<T>(register_key: any, _auto_replicate: boolean?)
	assert(not IS_CLIENT, MUST_SERVER)
	
	local reg = registrees[register_key]
	assert(reg, `Registree '{register_key}' does not exist.`)
	
	if inactiveKeys[register_key] then
		inactiveKeys[register_key] = nil
	end

	table.clear(reg.onRecievedListeners)
	
	if _auto_replicate == nil or _auto_replicate == true then
		local changes = {}
		diff_changes(
			function(v, p)
				table.insert(changes, {v = v, p = p})
			end,
			{},
			reg.value,
			{}
		)
		ReplicatedRegistry.server.to_clients(register_key, Players:GetPlayers(), nil, changes)
	end
	
	registrees[register_key] = nil
end

--[[
	The reciever function that handles delta changes sent by clients.
	
	@param plr: The player sending this registree's delta
	@param register_key: The key of the registree being changed
	@param changes: The delta/changes being made to this registree
]]
function ReplicatedRegistry.server.callbacks.remote_event_reciever(plr: Player, register_key: any, changes: TableChanges)
	remote_event_reciever(plr, register_key, changes)
end

--[[
	The reciever function that handles full registree requests by clients.
	
	@param player: The player requesting this registree's data
	@param register_key: The key of the registree being requested
	@return: The data, if valid
]]
function ReplicatedRegistry.server.callbacks.request_full_handler(player: Player, registerKey: any): Table?
	if registerKey == nil then return nil end
	if not ReplicatedRegistry.server.callbacks.validate_full_request(player, registerKey) then return nil end
	local registree = registrees[registerKey]
	
	if not registree then
		return nil
	end
	return registree.value
end

function ReplicatedRegistry.meta.switch_signal_lib(new_signal_lib: typeof(Signal))
	Signal = new_signal_lib
end

return ReplicatedRegistry