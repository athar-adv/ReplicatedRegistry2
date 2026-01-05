# Server API

## Registering Tables

### `server.register(key: any, table: Table, filter: ReplicationFilter?)`

Registers a table on the server for replication.

```luau
local playerData = {
    coins = 100,
    level = 1,
    inventory = {}
}

server.register("player_123", playerData)
```

**With filter:**

```luau
local filter = ReplicatedRegistry.get_filter({
    rate_limit = 10, -- 10 changes per second max
    player_whitelist = {123, 456} -- Only these user IDs
})

server.register("shared_data", sharedTable, filter)
```

### `server.deregister(register_key: any, _auto_replicate: boolean?)`

Deregisters a table on the server, if already registered.
If `_auto_replicate` is set to false, then clients won't know the key has been deregistered until the next time it is replicated.

## Accessing Tables

### `server.view(key: any) -> View`

Returns a viewing interface for registree data.

```lua
local data = server.view("player_123")
    .unwrap()
assert(data, "data not registered!")
data.coins = 150
data.level = 2
```

```luau
local proxy = server.view("player_123")
    .as_proxy()
    .await()

-- Set values
proxy.set({"coins"}, 200)
proxy.set({"inventory", "sword"}, true)

-- Get values
local coins = proxy.get({"coins"})

-- Increment values
proxy.incr({"coins"}, 50)
proxy.incr({"level"}, 1)

-- Replicate to specific players
proxy.replicate({player1, player2})

-- Replicate to all players
proxy.replicate()

-- Get full table
local fullTable = proxy.data()
```

## Replication

### `server.to_clients(key: any, players: {Player}, _sender: Sender_Server?, _changes: TableChanges?, _auto_commit: boolean?) -> ()`

Sends changes to specified clients.

```lua
-- Replicate to specific players
ReplicatedRegistry.server.to_clients(
    "player_123",
    {player1, player2}
)

-- Replicate to all players
ReplicatedRegistry.server.to_clients(
    "global_data",
    game.Players:GetPlayers()
)
```

## Listening for Changes

### `on_receive(key: any, callback: (sender: Player, old_table: Table, changes: TableChanges) -> ()) -> ScriptConnection`

Listens for incoming changes from a client.

```luau
local connection = ReplicatedRegistry.client.on_receive("player_123", function(sender, table, changes)
    print(`From {sender.Name}`)
    for _, change in changes do
        print("Path:", table.concat(change.p, "."))
        print("Value:", change.v)
    end
end)

-- Disconnect when done
connection:Disconnect()
```

### `on_key_changed(key: any, path: {any}, callback: (sender: Player, old_value: any, new_value: any) -> ()) -> ScriptConnection`

Listens for incoming changes to a specific path from a client.

```luau
local connection = ReplicatedRegistry.client.on_key_changed("player_123", {"coins"}, function(sender, old_value, new_value)
    print(`{old_value} -> {new_value} from {sender.Name}`)
end)

-- Disconnect when done
connection:Disconnect()
```

### `on_update(register_key: string, fn: (sender: Player, data: Table) -> ()) -> ScriptConnection`

Listens for applied changes incoming from a client. Differs from on_receive in that the changes are already applied to the data when the callback is called