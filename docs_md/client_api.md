# Client API

## Accessing Tables

### `client.view(key: any) -> Table?`

Requests and returns the registered table from the server, and nil if not registered yet.

```lua
local playerData = ReplicatedRegistry.client.view("player_123")
assert(playerData, "playerData not registered yet!")
print(playerData.coins) -- 100

-- Modify locally
playerData.coins = 150
```

### `client.await_view(key: any) -> Table`

Yields the calling thread indefinitely until a Registree registered with `key` is created on the server.

```lua
local playerData = ReplicatedRegistry.client.await_view("player_123")
print(playerData.coins) -- 100
```

### `client.view_as_proxy(key: any) -> RegistreeInterface_Client?`

Returns a proxy interface with helper methods.

```lua
local proxy = ReplicatedRegistry.client.view_as_proxy("player_123")
assert(proxy, "proxy not registered yet!")

-- Set values
proxy.set({"coins"}, 200)
proxy.set({"inventory", "sword"}, true)

-- Get values
local coins = proxy.get({"coins"})

-- Increment values
proxy.incr({"coins"}, 50)

-- Replicate changes to server
proxy.replicate()

-- Get full table
local fullTable = proxy.full()
```

### `client.await_view_as_proxy(key: any) -> RegistreeInterface_Client`

The same as `client.view_as_proxy` but yields the calling thread indefinitely until a registree with the key `key` exists.

## Replication

### `client.to_server(key: any, sender: SenderFunction?, changes: TableChanges?, auto_commit: boolean?) -> ()`

Sends changes to the server.

```lua
local data = ReplicatedRegistry.client.view("player_123")
data.coins = 200
data.level = 5

-- Send changes to server
ReplicatedRegistry.client.to_server("player_123")
```

**Manual change tracking:**

```lua
local data = ReplicatedRegistry.client.view("player_123")
data.coins = 200

local changes = ReplicatedRegistry.get_changes("player_123")
ReplicatedRegistry.client.to_server("player_123", nil, changes)
```

## Listening for Changes

### `on_receive(key: any, callback: (sender: Player?, old_table: Table, changes: TableChanges) -> ()) -> ScriptConnection`

Listens for incoming changes from the server.

```lua
local connection = ReplicatedRegistry.on_recieve("player_123", function(sender, table, changes)
    print("Received changes from", sender)
    for _, change in changes do
        print("Path:", table.concat(change.p, "."))
        print("Value:", change.v)
    end
end)

-- Disconnect when done
connection:Disconnect()
```

## Change Management

Same as server API:

- `get_changes(key)` - Get pending changes
- `commit_changes(key)` - Commit changes
- `revert_changes(key)` - Revert changes