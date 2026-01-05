# Client API

## Accessing Tables

### `client.view(key: any) -> View`

Returns a viewing interface for registree data on the server.

```luau
local playerData = ReplicatedRegistry.client.view("player_123")
    .unwrap()
assert(playerData, "playerData not registered yet!")
print(playerData.coins) -- 100

-- Modify locally
playerData.coins = 150
```

```luau
local playerData = ReplicatedRegistry.client.view("player_123")
    .await()
print(playerData.coins) -- 100
```

```luau
local proxy = ReplicatedRegistry.client.view("player_123")
    .as_proxy()
    .await()
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
local fullTable = proxy.data()
```

## Replication

### `client.to_server(key: any, sender: Sender_Client?, changes: TableChanges?, auto_commit: boolean?) -> ()`

Sends changes to the server.

```luau
local data = ReplicatedRegistry.client.view("player_123")
    .await()
data.coins = 200
data.level = 5

-- Send changes to server
ReplicatedRegistry.client.to_server("player_123")
```

**Manual change tracking:**

```luau
local data = ReplicatedRegistry.client.view("player_123")
    .await()
data.coins = 200

local changes = ReplicatedRegistry.get_changes("player_123")
ReplicatedRegistry.client.to_server("player_123", nil, changes)
```

## Listening for Changes

### `on_receive(key: any, callback: (old_table: Table, changes: TableChanges) -> ()) -> ScriptConnection`

Listens for incoming changes from the server.

```luau
local connection = ReplicatedRegistry.client.on_receive("player_123", function(table, changes)
    for _, change in changes do
        print("Path:", table.concat(change.p, "."))
        print("Value:", change.v)
    end
end)

-- Disconnect when done
connection:Disconnect()
```

### `on_key_changed(key: any, path: {any}, callback: (old_value: any, new_value: any) -> ()) -> ScriptConnection`

Listens for incoming changes to a specific path from the server.

```luau
local connection = ReplicatedRegistry.client.on_key_changed("player_123", {"coins"}, function(old_value, new_value)
    print(`{old_value} -> {new_value}`)
end)

-- Disconnect when done
connection:Disconnect()
```

### `on_update(register_key: string, fn: (data: Table) -> ()) -> ScriptConnection`

Listens for applied changes incoming from the server. Differs from on_receive in that the changes are already applied to the data when the callback is called

