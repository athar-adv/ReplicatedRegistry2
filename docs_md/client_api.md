# Client API

## Accessing Tables

### `client.view(key)`

Requests and returns the registered table from the server.

```lua
local playerData = ReplicatedRegistry.client.view("player_123")
print(playerData.coins) -- 100

-- Modify locally
playerData.coins = 150
```

### `client.view_as_proxy(key)`

Returns a proxy interface with helper methods.

```lua
local proxy = ReplicatedRegistry.client.view_as_proxy("player_123")

-- Set values
proxy.set("coins")(200)
proxy.set("inventory", "sword")(true)

-- Get values
local coins = proxy.get("coins")

-- Increment values
proxy.incr("coins")(50)

-- Replicate changes to server
proxy.replicate()

-- Get full table
local fullTable = proxy.full()
```

## Replication

### `client.to_server(key, sender?, changes?, auto_commit?)`

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

### `on_recieve(key, callback)`

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