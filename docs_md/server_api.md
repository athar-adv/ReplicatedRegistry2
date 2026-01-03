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

## Accessing Tables

### `server.view(key: any) -> Table?`

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
local fullTable = proxy.full()
```

## Replication

### `server.to_clients(key: any, players: {Player}, sender: Sender_Server?, changes: TableChanges?, auto_commit: boolean?) -> ()`

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
